import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/xray_server.dart';

/// Payload passed to the background isolate for parsing subscriptions.
class _ParseJob {
  final List<List<String>> bodies; // raw lines per subscription (already fetched)
  final List<String> groups; // group name for each subscription (same order)
  final Map<String, int?> oldPings; // preserve measured latency by link
  final int cap; // max servers per group
  _ParseJob(this.bodies, this.groups, this.oldPings, this.cap);
}

/// Runs on a background isolate (via [compute]) so parsing hundreds/thousands
/// of share links + JSON-encoding them never blocks the UI thread. Returns the
/// list of encoded JSON strings ready to store in SharedPreferences.
List<String> _parseSubscriptionsIsolate(_ParseJob job) {
  final seenLinks = <String>{};
  final encoded = <String>[];
  for (var i = 0; i < job.bodies.length; i++) {
    final lines = job.bodies[i];
    final group = job.groups[i];
    var taken = 0;
    for (final line in lines) {
      if (taken >= job.cap) break;
      try {
        final s = XrayServer.fromLink(line, group: group);
        if (!seenLinks.add(s.link)) continue;
        final p = job.oldPings[s.link];
        if (p != null) s.ping = p;
        encoded.add(jsonEncode(s.toJson()));
        taken++;
      } catch (_) {/* skip bad line */}
    }
  }
  return encoded;
}

/// Decodes a list of stored JSON strings into XrayServer objects on a
/// background isolate so loading a large stored list doesn't jank the UI.
List<XrayServer> _decodeServersIsolate(List<String> raw) {
  final out = <XrayServer>[];
  for (final j in raw) {
    try {
      out.add(XrayServer.fromJson(jsonDecode(j) as Map<String, dynamic>));
    } catch (_) {}
  }
  return out;
}

/// Encodes a list of XrayServer objects into JSON strings on a background
/// isolate for large lists.
List<String> _encodeServersIsolate(List<XrayServer> servers) {
  return servers.map((s) => jsonEncode(s.toJson())).toList();
}

/// Manages persisted Xray servers + the currently selected one, plus the
/// built-in free subscription group ([XrayServer.freeGroup]) that the user
/// cannot delete and that we keep refreshed from our subscription URL.
class XrayServerService {
  static const String _storageKey = 'xray_servers';
  static const String _selectedKey = 'selected_xray_server';
  static const String _subUpdatedKey = 'xray_sub_updated_at';
  static const String _subUrlsKey = 'xray_sub_urls';

  /// Our built-in free subscription (one share link per line).
  static const String subscriptionUrl =
      'https://raw.githubusercontent.com/4win-official/sub/refs/heads/main/config.txt';

  /// Second built-in subscription — the premium "Plus" group (gold framed).
  static const String plusSubscriptionUrl =
      'https://raw.githubusercontent.com/4win-official/sub/refs/heads/main/XPlus.txt';

  /// Built-in subscriptions in display order (always first in the list).
  static const Map<String, String> builtInSubs = {
    subscriptionUrl: XrayServer.freeGroup,
    plusSubscriptionUrl: XrayServer.plusGroup,
  };

  /// User-added subscription links (in addition to the built-in one).
  Future<List<String>> getSubUrls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_subUrlsKey) ?? [];
  }

  /// A stable, human-friendly group name for a user subscription URL. Each
  /// sub link is shown as its OWN group in the server list.
  String groupNameForUrl(String url) {
    try {
      final host = Uri.parse(url).host;
      if (host.isNotEmpty) return host;
    } catch (_) {/* fall through */}
    final u = url.replaceAll(RegExp(r'^https?://'), '');
    return u.length > 24 ? '${u.substring(0, 24)}…' : u;
  }

  /// Add a subscription URL. Returns false if empty/duplicate/invalid.
  Future<bool> addSubUrl(String url) async {
    final u = url.trim();
    if (u.isEmpty || !u.startsWith('http')) return false;
    final prefs = await SharedPreferences.getInstance();
    final urls = prefs.getStringList(_subUrlsKey) ?? [];
    if (urls.contains(u)) return false;
    urls.add(u);
    await prefs.setStringList(_subUrlsKey, urls);
    return true;
  }

  /// Adds whatever the user pasted in the Xray sub-link box. Accepts EITHER
  /// an http(s) subscription URL (stored and shown as its own group in the
  /// server list) OR one/more raw share links (vless/vmess/trojan/ss), which
  /// are added immediately as their own "My Sub Links" group so they show up
  /// right away. Returns count added (>0 = success).
  static const String userLinksGroup = 'My Sub Links';

  /// Max servers stored per subscription group. Parsing/encoding now runs on a
  /// background isolate, so large subscriptions no longer freeze the UI; this
  /// cap only guards against pathological (tens of thousands) storage bloat.
  static const int maxServersPerGroup = 2000;

  Future<int> addSubInput(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return 0;

    // Lines that look like share links become their own user group.
    final shareLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.contains('://') && !e.startsWith('http'))
        .toList();

    int added = 0;

    if (shareLines.isNotEmpty) {
      final all = await loadServers();
      final existingLinks = all.map((s) => s.link).toSet();
      final room =
          maxServersPerGroup - all.where((s) => s.group == userLinksGroup).length;
      if (room > 0) {
        // Parse the pasted links on a BACKGROUND isolate so pasting a huge
        // (1000+) block of raw links never freezes the UI.
        final parsed = await compute(
          _parseSubscriptionsIsolate,
          _ParseJob([shareLines], [userLinksGroup], const <String, int?>{}, room),
        );
        final toAdd = <XrayServer>[];
        for (final j in parsed) {
          try {
            final s = XrayServer.fromJson(jsonDecode(j) as Map<String, dynamic>);
            if (existingLinks.contains(s.link)) continue;
            existingLinks.add(s.link);
            toAdd.add(s);
          } catch (_) {}
        }
        if (toAdd.isNotEmpty) {
          all.addAll(toAdd);
          added += toAdd.length;
          await saveServers(all);
        }
      }
    }

    // Anything that is an http(s) URL is treated as a subscription link.
    final urlLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.startsWith('http'))
        .toList();
    for (final u in urlLines) {
      if (await addSubUrl(u)) added++;
    }

    return added;
  }

  Future<void> removeSubUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final urls = prefs.getStringList(_subUrlsKey) ?? [];
    urls.remove(url);
    await prefs.setStringList(_subUrlsKey, urls);
    // Drop that subscription's group from the stored server list too.
    final group = groupNameForUrl(url);
    final all = await loadServers();
    final remaining = all.where((s) => s.group != group).toList();
    if (remaining.length != all.length) await saveServers(remaining);
  }

  Future<List<String>> _fetchLinks(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return [];
      var body = res.body.trim();
      if (body.isEmpty) return [];
      if (!body.contains('://')) {
        try {
          body = utf8.decode(base64.decode(_padBase64(body)));
        } catch (_) {/* not base64 */}
      }
      return body
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e.contains('://'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<XrayServer>> loadServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_storageKey) ?? [];
      if (list.isEmpty) return [];
      // For large stored lists, decode off the UI isolate to avoid jank.
      if (list.length > 60) {
        return await compute(_decodeServersIsolate, list);
      }
      final out = <XrayServer>[];
      for (final j in list) {
        try {
          out.add(XrayServer.fromJson(jsonDecode(j) as Map<String, dynamic>));
        } catch (_) {}
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ load xray servers: $e');
      return [];
    }
  }

  Future<bool> saveServers(List<XrayServer> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Encode off the UI isolate for large lists.
      final List<String> encoded;
      if (servers.length > 60) {
        encoded = await compute(_encodeServersIsolate, servers);
      } else {
        encoded = servers.map((s) => jsonEncode(s.toJson())).toList();
      }
      await prefs.setStringList(_storageKey, encoded);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ save xray servers: $e');
      return false;
    }
  }

  /// Add servers parsed from one or more share links (newline separated).
  /// User-added servers have no group. Returns count added.
  Future<int> addFromLinks(String raw) async {
    final servers = await loadServers();
    final lines = raw
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    int added = 0;
    for (final line in lines) {
      try {
        final s = XrayServer.fromLink(line);
        if (servers.any((x) => x.link == s.link)) continue;
        servers.add(s);
        added++;
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ skip bad link: $e');
      }
    }
    if (added > 0) await saveServers(servers);
    return added;
  }

  /// Wipes the stored ping value on every server. Called on app launch so
  /// stale (previous-session) ping results are never shown; a fresh test must
  /// be run again this session.
  Future<void> clearAllPings() async {
    try {
      final servers = await loadServers();
      if (servers.isEmpty) return;
      var changed = false;
      for (final s in servers) {
        if (s.ping != null) {
          s.ping = null;
          changed = true;
        }
      }
      if (changed) await saveServers(servers);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ clearAllPings: $e');
    }
  }

  /// Refreshes a SINGLE subscription group: clears that group's servers and
  /// re-downloads + re-parses them from the group's source URL. [groupKey] is
  /// the displayed group name — either [XrayServer.freeGroup] (built-in) or a
  /// user sub URL's host (see [groupNameForUrl]). Returns servers loaded, or
  /// -1 if the group isn't a URL-backed subscription (e.g. user-pasted links).
  Future<int> refreshOneGroup(String groupKey) async {
    try {
      // Resolve the source URL for this group.
      String? url;
      // Built-in groups first (free + plus).
      for (final e in builtInSubs.entries) {
        if (e.value == groupKey) {
          url = e.key;
          break;
        }
      }
      if (url == null) {
        final userUrls = await getSubUrls();
        for (final u in userUrls) {
          if (groupNameForUrl(u) == groupKey) {
            url = u;
            break;
          }
        }
      }
      if (url == null) return -1; // not a URL-backed group

      final lines = await _fetchLinks(url);
      // Fetch failed — keep existing servers untouched (esp. cached built-ins).
      if (lines.isEmpty) return -1;

      final all = await loadServers();
      final oldPings = <String, int?>{for (final s in all) s.link: s.ping};

      // Parse this group's links on a background isolate.
      final encodedGroup = await compute(
        _parseSubscriptionsIsolate,
        _ParseJob([lines], [groupKey], oldPings, maxServersPerGroup),
      );

      // Keep everything EXCEPT this group's old servers, then append fresh ones.
      final keep = all.where((s) => s.group != groupKey).toList();
      final encodedKeep = keep.length > 60
          ? await compute(_encodeServersIsolate, keep)
          : keep.map((s) => jsonEncode(s.toJson())).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey, [...encodedKeep, ...encodedGroup]);
      return encodedGroup.length;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ refreshOneGroup: $e');
      return -1;
    }
  }

  /// Fetches every subscription (built-in + user-added) and rebuilds each as
  /// its OWN group. The built-in one uses [XrayServer.freeGroup]; each user
  /// sub URL becomes its own group named after the URL host. Servers the user
  /// added by pasting raw links ([userLinksGroup]) and individual (group-less)
  /// servers are preserved. Returns total subscription servers loaded.
  Future<int> refreshFreeGroup({Duration? minInterval}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Optional throttle so we don't hammer the URLs on every screen open.
      if (minInterval != null) {
        final last = prefs.getInt(_subUpdatedKey) ?? 0;
        final age = DateTime.now().millisecondsSinceEpoch - last;
        if (age < minInterval.inMilliseconds) {
          final existing = await loadServers();
          return existing.where((s) => s.isLocked).length;
        }
      }

      final all = await loadServers();
      // Preserve old pings by link so re-fetch keeps measured latency.
      final oldPings = <String, int?>{for (final s in all) s.link: s.ping};

      // Build each subscription group. Map keeps insertion order: the two
      // built-in groups first (Free, then Plus), then user subs.
      final userUrls = await getSubUrls();
      final subUrls = <String, String>{
        ...builtInSubs,
        for (final u in userUrls) u: groupNameForUrl(u),
      };

      // 1) Fetch every subscription body (network only). A built-in group whose
      //    fetch FAILS is cached — we re-use its previously stored servers so
      //    the default groups are ALWAYS present, even offline.
      final bodies = <List<String>>[];
      final groups = <String>[];
      final cachedBuiltIn = <XrayServer>[]; // failed built-ins reused from store
      var fetchedAny = false;
      for (final entry in subUrls.entries) {
        final lines = await _fetchLinks(entry.key);
        final groupName = entry.value;
        if (lines.isEmpty && XrayServer.isBuiltInGroup(groupName)) {
          // Keep the last known servers for this built-in group (cache).
          cachedBuiltIn.addAll(all.where((s) => s.group == groupName));
          continue;
        }
        if (lines.isNotEmpty) fetchedAny = true;
        bodies.add(lines);
        groups.add(groupName);
      }

      // If nothing could be fetched at all, leave existing data untouched.
      if (!fetchedAny && cachedBuiltIn.isEmpty) {
        return all.where((s) => s.isLocked).length;
      }

      // 2) Parse + JSON-encode the freshly-fetched links on a BACKGROUND
      //    isolate (the heavy part that used to freeze on big subs).
      final encodedSub = bodies.isEmpty
          ? <String>[]
          : await compute(
              _parseSubscriptionsIsolate,
              _ParseJob(bodies, groups, oldPings, maxServersPerGroup),
            );

      // Encode cached built-in servers (from failed fetches) so they persist.
      final encodedCached = cachedBuiltIn
          .map((s) => jsonEncode(s.toJson()))
          .toList();

      // Keep user-pasted links group + individual user servers as-is.
      final keep = all
          .where((s) => s.group.isEmpty || s.group == userLinksGroup)
          .toList();
      final encodedKeep = keep.length > 60
          ? await compute(_encodeServersIsolate, keep)
          : keep.map((s) => jsonEncode(s.toJson())).toList();

      // 3) Store the merged encoded list directly.
      await prefs.setStringList(
          _storageKey, [...encodedSub, ...encodedCached, ...encodedKeep]);
      await prefs.setInt(
          _subUpdatedKey, DateTime.now().millisecondsSinceEpoch);
      return encodedSub.length + encodedCached.length;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ refreshFreeGroup: $e');
      return 0;
    }
  }

  /// Removes a server by id. Subscription-managed servers cannot be removed
  /// individually (delete the whole subscription instead), except the
  /// user-pasted [userLinksGroup] and group-less individual servers.
  /// Returns false if the server is protected or not found.
  Future<bool> removeServer(String id) async {
    final servers = await loadServers();
    final idx = servers.indexWhere((s) => s.id == id);
    if (idx < 0) return false;
    final g = servers[idx].group;
    final deletable = g.isEmpty || g == userLinksGroup;
    if (!deletable) return false; // protected subscription group
    servers.removeAt(idx);
    final selected = await getSelectedId();
    if (selected == id) await setSelectedId(null);
    await saveServers(servers);
    return true;
  }

  /// Persists a measured ping for a single server (matched by id).
  Future<void> updatePing(String id, int? ping) async {
    final servers = await loadServers();
    final idx = servers.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    servers[idx] = servers[idx].copyWith(ping: ping);
    await saveServers(servers);
  }

  /// Persists measured pings for many servers at once (id -> ping).
  Future<void> updatePings(Map<String, int?> pings) async {
    if (pings.isEmpty) return;
    final servers = await loadServers();
    for (var i = 0; i < servers.length; i++) {
      if (pings.containsKey(servers[i].id)) {
        servers[i] = servers[i].copyWith(ping: pings[servers[i].id]);
      }
    }
    await saveServers(servers);
  }

  Future<String?> getSelectedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedKey);
  }

  Future<void> setSelectedId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_selectedKey);
    } else {
      await prefs.setString(_selectedKey, id);
    }
  }

  Future<XrayServer?> getSelectedServer() async {
    final id = await getSelectedId();
    if (id == null) return null;
    final servers = await loadServers();
    for (final s in servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  static String _padBase64(String s) {
    var v = s.replaceAll('-', '+').replaceAll('_', '/');
    final mod = v.length % 4;
    if (mod > 0) v += '=' * (4 - mod);
    return v;
  }
}
