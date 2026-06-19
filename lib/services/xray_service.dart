import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/xray_server.dart';

/// Manages persisted Xray servers + the currently selected one.
class XrayServerService {
  static const String _storageKey = 'xray_servers';
  static const String _selectedKey = 'selected_xray_server';

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

  /// Add a server parsed from a share link. Supports multiple links separated
  /// by newlines. Returns number of servers successfully added.
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
        // avoid exact-duplicate links
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

  Future<bool> removeServer(String id) async {
    final servers = await loadServers();
    servers.removeWhere((s) => s.id == id);
    final selected = await getSelectedId();
    if (selected == id) await setSelectedId(null);
    return saveServers(servers);
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
}
