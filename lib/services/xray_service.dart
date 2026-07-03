import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/xray_server.dart';

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

  /// Max servers stored per subscription group. Prevents a giant subscription
  /// (thousands of configs) from freezing the app / bloating storage.
  static const int maxServersPerGroup = 500;

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
      var inGroup = all.where((s) => s.group == userLinksGroup).length;
      for (final line in shareLines) {
        if (inGroup >= maxServersPerGroup) break;
        try {
          final s = XrayServer.fromLink(line, group: userLinksGroup);
          if (all.any((x) => x.link == s.link)) continue;
          all.add(s);
          added++;
          inGroup++;
        } catch (_) {/* skip bad link */}
      }
      if (added > 0) await saveServers(all);
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
      return list
          .map((j) {
            try {
              return XrayServer.fromJson(jsonDecode(j) as Map<String, dynamic>);
            } catch (e) {
              return null;
            }
          })
          .whereType<XrayServer>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ load xray servers: $e');
      return [];
    }
  }

  Future<bool> saveServers(List<XrayServer> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _storageKey,
        servers.map((s) => jsonEncode(s.toJson())).toList(),
      );
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

      // Build each subscription group. Map keeps insertion order (built-in
      // first, then user subs in their stored order).
      final userUrls = await getSubUrls();
      final subUrls = <String, String>{
        subscriptionUrl: XrayServer.freeGroup,
        for (final u in userUrls) u: groupNameForUrl(u),
      };

      final subServers = <XrayServer>[];
      final seenLinks = <String>{};
      var fetchedAny = false;
      for (final entry in subUrls.entries) {
        final lines = await _fetchLinks(entry.key);
        if (lines.isNotEmpty) fetchedAny = true;
        // Cap servers PER subscription so a huge (1000s) list can't freeze the
        // UI or bloat SharedPreferences.
        var takenForGroup = 0;
        for (final line in lines) {
          if (takenForGroup >= maxServersPerGroup) break;
          try {
            final s = XrayServer.fromLink(line, group: entry.value);
            if (!seenLinks.add(s.link)) continue;
            final p = oldPings[s.link];
            subServers.add(p != null ? s.copyWith(ping: p) : s);
            takenForGroup++;
          } catch (_) {/* skip bad line */}
        }
        // Yield to the event loop between subscriptions so the UI stays
        // responsive while parsing many links.
        await Future<void>.delayed(Duration.zero);
      }

      // If nothing could be fetched at all, leave existing data untouched.
      if (!fetchedAny) return all.where((s) => s.isLocked).length;

      // Keep user-pasted links group + individual user servers as-is.
      final keep = all
          .where((s) => s.group.isEmpty || s.group == userLinksGroup)
          .toList();

      await saveServers([...subServers, ...keep]);
      await prefs.setInt(
          _subUpdatedKey, DateTime.now().millisecondsSinceEpoch);
      return subServers.length;
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
