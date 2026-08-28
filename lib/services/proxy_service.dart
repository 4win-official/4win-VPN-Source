import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/proxy_server.dart';

/// Payload passed to the background isolate for parsing subscriptions.
class _ParseJob {
  final List<List<String>> bodies;
  final List<String> groups;
  final Map<String, int?> oldPings;
  final int cap;
  _ParseJob(this.bodies, this.groups, this.oldPings, this.cap);
}

/// Runs on a background isolate: parse many proxy links → encoded JSON strings.
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
        final s = ProxyServer.fromLink(line, group: group);
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

List<ProxyServer> _decodeServersIsolate(List<String> raw) {
  final out = <ProxyServer>[];
  for (final j in raw) {
    try {
      out.add(ProxyServer.fromJson(jsonDecode(j) as Map<String, dynamic>));
    } catch (_) {}
  }
  return out;
}

/// Manages persisted Proxy servers + the currently selected one, plus user
/// subscription links (each shown as its own group). Mirrors
/// XrayServerService, adapted for the SOCKS/HTTP proxy protocol.
class ProxyServerService {
  static const String _storageKey = 'proxy_servers';
  static const String _selectedKey = 'selected_proxy_server';
  static const String _subUpdatedKey = 'proxy_sub_updated_at';
  static const String _subUrlsKey = 'proxy_sub_urls';
  static const String _subNamesKey = 'proxy_sub_names';

  /// Group name for user-pasted raw links (not a URL subscription).
  static const String userLinksGroup = 'My Sub Links';

  /// Max servers stored per subscription group.
  static const int maxServersPerGroup = 2000;

  Future<List<String>> getSubUrls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_subUrlsKey) ?? [];
  }

  Future<Map<String, String>> getSubNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_subNamesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  String _autoNameForUrl(String url) {
    try {
      final host = Uri.parse(url).host;
      if (host.isNotEmpty) return host;
    } catch (_) {}
    final u = url.replaceAll(RegExp(r'^https?://'), '');
    return u.length > 24 ? '${u.substring(0, 24)}…' : u;
  }

  String groupNameForUrl(String url, [Map<String, String>? names]) {
    final custom = names?[url];
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return _autoNameForUrl(url);
  }

  Future<String> groupNameForUrlAsync(String url) async {
    final names = await getSubNames();
    return groupNameForUrl(url, names);
  }

  Future<void> setSubName(String url, String name) async {
    final prefs = await SharedPreferences.getInstance();
    final names = await getSubNames();
    final oldGroup = groupNameForUrl(url, names);
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      names.remove(url);
    } else {
      names[url] = trimmed;
    }
    await prefs.setString(_subNamesKey, jsonEncode(names));
    final newGroup = groupNameForUrl(url, names);
    if (oldGroup != newGroup) {
      final all = await loadServers();
      var changed = false;
      final migrated = all.map((s) {
        if (s.group == oldGroup) {
          changed = true;
          return s.copyWith(group: newGroup);
        }
        return s;
      }).toList();
      if (changed) await saveServers(migrated);
    }
  }

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

  /// Accepts EITHER an http(s) subscription URL OR one/more raw proxy links.
  /// Returns count added (>0 = success).
  Future<int> addSubInput(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return 0;

    // Lines that look like raw proxy links (not http subscription URLs).
    final shareLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !_isSubUrl(e) && _looksLikeProxy(e))
        .toList();

    int added = 0;

    if (shareLines.isNotEmpty) {
      final all = await loadServers();
      final existingLinks = all.map((s) => s.link).toSet();
      final room =
          maxServersPerGroup - all.where((s) => s.group == userLinksGroup).length;
      if (room > 0) {
        final parsed = await compute(
          _parseSubscriptionsIsolate,
          _ParseJob([shareLines], [userLinksGroup], const <String, int?>{}, room),
        );
        final toAdd = <ProxyServer>[];
        for (final j in parsed) {
          try {
            final s = ProxyServer.fromJson(jsonDecode(j) as Map<String, dynamic>);
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

    // http(s) URLs are treated as subscription links.
    final urlLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where(_isSubUrl)
        .toList();
    for (final u in urlLines) {
      if (await addSubUrl(u)) added++;
    }

    return added;
  }

  /// An http(s) URL is a subscription link ONLY if it isn't itself a proxy
  /// share link (http:// proxies are also valid). We treat a bare `http://host`
  /// with a path or query as a subscription; `http://host:port` (no path) as a
  /// proxy. To keep it simple: URLs containing a path segment beyond '/' are
  /// subscriptions; otherwise they're proxy links.
  bool _isSubUrl(String e) {
    if (!e.startsWith('http://') && !e.startsWith('https://')) return false;
    try {
      final u = Uri.parse(e);
      // A subscription URL usually has a path (raw file) — proxy links are just
      // host:port. If there's a non-empty path or query, treat as subscription.
      final hasPath = u.path.isNotEmpty && u.path != '/';
      return hasPath || u.query.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _looksLikeProxy(String e) {
    final lower = e.toLowerCase();
    if (lower.startsWith('socks5://') ||
        lower.startsWith('socks4://') ||
        lower.startsWith('socks://') ||
        lower.startsWith('socks4a://') ||
        lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('4ws://')) {
      return true;
    }
    // bare host:port
    return RegExp(r'^[^\s:]+:\d+').hasMatch(e);
  }

  Future<void> removeSubUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final urls = prefs.getStringList(_subUrlsKey) ?? [];
    urls.remove(url);
    await prefs.setStringList(_subUrlsKey, urls);
    final names = await getSubNames();
    final group = groupNameForUrl(url, names);
    if (names.remove(url) != null) {
      await prefs.setString(_subNamesKey, jsonEncode(names));
    }
    final all = await loadServers();
    final remaining = all.where((s) => s.group != group).toList();
    if (remaining.length != all.length) await saveServers(remaining);
  }

  Future<bool> changeSubUrl(String oldUrl, String newUrl) async {
    final n = newUrl.trim();
    if (n.isEmpty || !n.startsWith('http')) return false;
    if (n == oldUrl) return true;
    final prefs = await SharedPreferences.getInstance();
    final urls = prefs.getStringList(_subUrlsKey) ?? [];
    if (urls.contains(n)) return false;
    final idx = urls.indexOf(oldUrl);
    if (idx < 0) {
      urls.add(n);
    } else {
      urls[idx] = n;
    }
    await prefs.setStringList(_subUrlsKey, urls);

    final names = await getSubNames();
    final oldName = names[oldUrl];
    if (oldName != null) {
      names.remove(oldUrl);
      names[n] = oldName;
      await prefs.setString(_subNamesKey, jsonEncode(names));
    }

    final oldGroup =
        groupNameForUrl(oldUrl, oldName != null ? {oldUrl: oldName} : null);
    final all = await loadServers();
    final remaining = all.where((s) => s.group != oldGroup).toList();
    if (remaining.length != all.length) await saveServers(remaining);
    return true;
  }

  Future<({bool ok, List<String> links})> _fetchLinksResult(String url) async {
    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return (ok: false, links: <String>[]);
      var body = res.body.trim();
      if (body.isEmpty) return (ok: true, links: <String>[]);
      // Subscriptions are often base64-encoded blobs of one link per line.
      if (!body.contains('\n') && !body.contains('://') && !body.contains(':')) {
        try {
          body = utf8.decode(base64.decode(_padBase64(body)));
        } catch (_) {}
      } else if (!body.contains('://') && !body.contains(RegExp(r':\d+'))) {
        try {
          body = utf8.decode(base64.decode(_padBase64(body)));
        } catch (_) {}
      }
      final links = body
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && _looksLikeProxy(e))
          .toList();
      return (ok: true, links: links);
    } catch (_) {
      return (ok: false, links: <String>[]);
    }
  }

  Future<List<ProxyServer>> loadServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_storageKey) ?? [];
      if (list.isEmpty) return [];
      if (list.length > 60) {
        return await compute(_decodeServersIsolate, list);
      }
      final out = <ProxyServer>[];
      for (final j in list) {
        try {
          out.add(ProxyServer.fromJson(jsonDecode(j) as Map<String, dynamic>));
        } catch (_) {}
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ load proxy servers: $e');
      return [];
    }
  }

  Future<bool> saveServers(List<ProxyServer> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = servers.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(_storageKey, encoded);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ save proxy servers: $e');
      return false;
    }
  }

  /// Add servers parsed from one or more proxy links (newline separated).
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
        final s = ProxyServer.fromLink(line);
        if (servers.any((x) => x.link == s.link)) continue;
        servers.add(s);
        added++;
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ skip bad proxy link: $e');
      }
    }
    if (added > 0) await saveServers(servers);
    return added;
  }

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

  /// Refresh a SINGLE subscription group.
  Future<int> refreshOneGroup(String groupKey) async {
    try {
      String? url;
      final userUrls = await getSubUrls();
      final names = await getSubNames();
      for (final u in userUrls) {
        if (groupNameForUrl(u, names) == groupKey) {
          url = u;
          break;
        }
      }
      if (url == null) return -1;

      final fetched = await _fetchLinksResult(url);
      final lines = fetched.links;
      if (lines.isEmpty) {
        if (!fetched.ok) return -1;
        final all = await loadServers();
        final keep = all.where((s) => s.group != groupKey).toList();
        await saveServers(keep);
        return 0;
      }

      final all = await loadServers();
      final oldPings = <String, int?>{for (final s in all) s.link: s.ping};
      final encodedGroup = await compute(
        _parseSubscriptionsIsolate,
        _ParseJob([lines], [groupKey], oldPings, maxServersPerGroup),
      );
      final keep = all.where((s) => s.group != groupKey).toList();
      final encodedKeep = keep.map((s) => jsonEncode(s.toJson())).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey, [...encodedKeep, ...encodedGroup]);
      return encodedGroup.length;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ proxy refreshOneGroup: $e');
      return -1;
    }
  }

  /// Refresh ALL user subscription groups from their URLs.
  Future<int> refreshAll({Duration? minInterval}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (minInterval != null) {
        final last = prefs.getInt(_subUpdatedKey) ?? 0;
        final age = DateTime.now().millisecondsSinceEpoch - last;
        if (age < minInterval.inMilliseconds) {
          final existing = await loadServers();
          return existing.where((s) => s.isLocked).length;
        }
      }

      final all = await loadServers();
      final oldPings = <String, int?>{for (final s in all) s.link: s.ping};

      final userUrls = await getSubUrls();
      final subNames = await getSubNames();
      final subUrls = <String, String>{
        for (final u in userUrls) u: groupNameForUrl(u, subNames),
      };

      final bodies = <List<String>>[];
      final groups = <String>[];
      final cachedFailed = <ProxyServer>[];
      final emptiedGroups = <String>{};
      var fetchedAny = false;
      for (final entry in subUrls.entries) {
        final fetched = await _fetchLinksResult(entry.key);
        final lines = fetched.links;
        final groupName = entry.value;
        if (lines.isEmpty) {
          if (!fetched.ok) {
            cachedFailed.addAll(all.where((s) => s.group == groupName));
          } else {
            emptiedGroups.add(groupName);
          }
          continue;
        }
        fetchedAny = true;
        bodies.add(lines);
        groups.add(groupName);
      }

      if (!fetchedAny && cachedFailed.isEmpty && emptiedGroups.isEmpty) {
        return all.where((s) => s.isLocked).length;
      }

      final encodedSub = bodies.isEmpty
          ? <String>[]
          : await compute(
              _parseSubscriptionsIsolate,
              _ParseJob(bodies, groups, oldPings, maxServersPerGroup),
            );
      final encodedCached =
          cachedFailed.map((s) => jsonEncode(s.toJson())).toList();

      // Keep user-pasted links group + individual (group-less) servers.
      final keep = all.where((s) {
        return s.group.isEmpty || s.group == userLinksGroup;
      }).toList();
      final encodedKeep = keep.map((s) => jsonEncode(s.toJson())).toList();

      await prefs.setStringList(
          _storageKey, [...encodedSub, ...encodedCached, ...encodedKeep]);
      await prefs.setInt(
          _subUpdatedKey, DateTime.now().millisecondsSinceEpoch);
      return encodedSub.length + encodedCached.length;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ proxy refreshAll: $e');
      return 0;
    }
  }

  /// Removes a server by id. Subscription-managed servers cannot be removed
  /// individually (except the user-pasted group and group-less servers).
  Future<bool> removeServer(String id) async {
    final servers = await loadServers();
    final idx = servers.indexWhere((s) => s.id == id);
    if (idx < 0) return false;
    final g = servers[idx].group;
    final deletable = g.isEmpty || g == userLinksGroup;
    if (!deletable) return false;
    servers.removeAt(idx);
    final selected = await getSelectedId();
    if (selected == id) await setSelectedId(null);
    await saveServers(servers);
    return true;
  }

  Future<void> updatePing(String id, int? ping) async {
    final servers = await loadServers();
    final idx = servers.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    servers[idx] = servers[idx].copyWith(ping: ping);
    await saveServers(servers);
  }

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

  Future<ProxyServer?> getSelectedServer() async {
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
