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
  /// an http(s) subscription URL (stored and merged into the free group on
  /// every refresh) OR one/more raw share links (vless/vmess/trojan/ss),
  /// which are added immediately as locked free-group servers so they show
  /// up in the server list right away. Returns count added (>0 = success).
  Future<int> addSubInput(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return 0;

    // Lines that look like share links go straight into the free group.
    final shareLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.contains('://') && !e.startsWith('http'))
        .toList();

    int added = 0;

    if (shareLines.isNotEmpty) {
      final all = await loadServers();
      for (final line in shareLines) {
        try {
          final s = XrayServer.fromLink(line, group: XrayServer.freeGroup);
          if (all.any((x) => x.link == s.link)) continue;
          all.add(s);
          added++;
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

  /// Fetches the free subscription and rebuilds the locked free group.
  /// User servers and selection are preserved. Returns the number of free
  /// servers loaded (0 on failure, leaving existing data untouched).
  Future<int> refreshFreeGroup({Duration? minInterval}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Optional throttle so we don't hammer the URL on every screen open.
      if (minInterval != null) {
        final last = prefs.getInt(_subUpdatedKey) ?? 0;
        final age = DateTime.now().millisecondsSinceEpoch - last;
        if (age < minInterval.inMilliseconds) {
          // Return current count without refetching.
          final existing = await loadServers();
          return existing.where((s) => s.isLocked).length;
        }
      }

      // Fetch the built-in subscription plus any user-added ones.
      final urls = <String>[subscriptionUrl, ...await getSubUrls()];
      final lines = <String>[];
      for (final u in urls) {
        lines.addAll(await _fetchLinks(u));
      }
      if (lines.isEmpty) return 0;

      final freeServers = <XrayServer>[];
      final seenLinks = <String>{};
      for (final line in lines) {
        try {
          final s = XrayServer.fromLink(line, group: XrayServer.freeGroup);
          if (seenLinks.add(s.link)) freeServers.add(s);
        } catch (_) {/* skip bad line */}
      }
      if (freeServers.isEmpty) return 0;

      // Keep the user's non-free servers, replace the free group entirely.
      final all = await loadServers();
      final userServers = all.where((s) => !s.isLocked).toList();
      // Carry over previously measured pings for unchanged free links.
      final oldPings = <String, int?>{
        for (final s in all.where((s) => s.isLocked)) s.link: s.ping
      };
      for (var i = 0; i < freeServers.length; i++) {
        final p = oldPings[freeServers[i].link];
        if (p != null) freeServers[i] = freeServers[i].copyWith(ping: p);
      }

      await saveServers([...freeServers, ...userServers]);
      await prefs.setInt(
          _subUpdatedKey, DateTime.now().millisecondsSinceEpoch);
      return freeServers.length;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ refreshFreeGroup: $e');
      return 0;
    }
  }

  /// Removes a server by id. Locked (free group) servers cannot be removed.
  /// Returns false if the server is locked or not found.
  Future<bool> removeServer(String id) async {
    final servers = await loadServers();
    final idx = servers.indexWhere((s) => s.id == id);
    if (idx < 0) return false;
    if (servers[idx].isLocked) return false; // protected group
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
