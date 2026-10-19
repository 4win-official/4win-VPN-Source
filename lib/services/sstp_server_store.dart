import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sstp_server_group.dart';
import '../models/vpn_server.dart';
import 'server_service.dart';

/// Persists user-defined SSTP groups while keeping the built-in group separate.
class SstpServerStore {
  static const String persistenceKey = 'sstp_custom_groups';
  static const String key = persistenceKey;
  static const Duration _httpTimeout = Duration(seconds: 30);

  final ServerService _serverService;
  final http.Client _client;
  List<VpnServer> _lastDefaultServers = const <VpnServer>[];

  SstpServerStore({ServerService? serverService, http.Client? client})
    : _serverService = serverService ?? ServerService(),
      _client = client ?? http.Client();

  Future<List<SstpServerGroup>> loadGroups({bool forceRefresh = false}) async {
    final defaultServers = await _fetchDefault(forceRefresh: forceRefresh);
    return _withDefault(defaultServers, await _loadCustomGroups());
  }

  Future<List<SstpServerGroup>> refreshGroup(String id) async {
    final groups = await _loadCustomGroups();
    if (id == SstpServerGroup.defaultId) {
      final servers = await _fetchDefault(forceRefresh: true);
      return _withDefault(servers, groups);
    }

    final index = groups.indexWhere((group) => group.id == id);
    if (index < 0) {
      throw ArgumentError.value(id, 'id', 'Unknown server group.');
    }
    final oldGroup = groups[index];
    final url = oldGroup.subscriptionUrl;
    if (url == null || url.isEmpty) {
      return _withDefault(await _fetchDefault(), groups);
    }

    final response = await _client.get(Uri.parse(url)).timeout(_httpTimeout);
    if (response.statusCode != 200) {
      throw StateError(
        'Failed to refresh server group: ${response.statusCode}',
      );
    }
    final existing = oldGroup.servers.first;
    final servers = _parseServers(
      response.body,
      username: existing.username,
      password: existing.password,
    );
    if (servers.isEmpty) {
      throw StateError('The subscription contains no valid servers.');
    }
    groups[index] = oldGroup.copyWith(servers: servers);
    await _saveCustomGroups(groups);
    return _withDefault(await _fetchDefault(), groups);
  }

  Future<List<SstpServerGroup>> addGroup(
    String name,
    String content, {
    String username = 'vpn',
    String password = 'vpn',
  }) async {
    final groupName = name.trim();
    if (groupName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Name cannot be empty.');
    }
    final source = content.trim();
    if (source.isEmpty) {
      throw ArgumentError.value(
        content,
        'content',
        'Server list cannot be empty.',
      );
    }

    String? subscriptionUrl;
    String serverText = source;
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (uri.host.isEmpty) {
        throw FormatException('Subscription URL has no host.');
      }
      subscriptionUrl = uri.toString();
      final response = await _client.get(uri).timeout(_httpTimeout);
      if (response.statusCode != 200) {
        throw StateError('Failed to load subscription: ${response.statusCode}');
      }
      serverText = response.body;
    }

    final servers = _parseServers(
      serverText,
      username: username,
      password: password,
    );
    if (servers.isEmpty) throw FormatException('No valid SSTP servers found.');
    final groups = await _loadCustomGroups();
    groups.add(
      SstpServerGroup(
        id: _newId(),
        name: groupName,
        servers: servers,
        subscriptionUrl: subscriptionUrl,
      ),
    );
    await _saveCustomGroups(groups);
    return _withDefault(await _fetchDefault(), groups);
  }

  Future<List<SstpServerGroup>> deleteGroup(String id) async {
    if (id == SstpServerGroup.defaultId) {
      throw StateError('The built-in server group cannot be deleted.');
    }
    final groups = await _loadCustomGroups();
    final removed = groups.any((group) => group.id == id);
    if (!removed) throw ArgumentError.value(id, 'id', 'Unknown server group.');
    groups.removeWhere((group) => group.id == id);
    await _saveCustomGroups(groups);
    return _withDefault(await _fetchDefault(), groups);
  }

  Future<List<VpnServer>> _fetchDefault({bool forceRefresh = false}) async {
    try {
      final servers = await _serverService.fetchServers(
        forceRefresh: forceRefresh,
      );
      _lastDefaultServers = List<VpnServer>.from(servers);
    } catch (_) {
      // Custom groups must remain usable when the built-in feed is offline.
    }
    return List<VpnServer>.from(_lastDefaultServers);
  }

  SstpServerGroup _defaultGroup(List<VpnServer> servers) => SstpServerGroup(
    id: SstpServerGroup.defaultId,
    name: SstpServerGroup.defaultName,
    servers: servers,
  );

  List<SstpServerGroup> _withDefault(
    List<VpnServer> defaultServers, [
    List<SstpServerGroup>? custom,
  ]) => <SstpServerGroup>[
    _defaultGroup(defaultServers),
    ...(custom ?? const <SstpServerGroup>[]),
  ];

  List<VpnServer> _parseServers(
    String content, {
    String username = 'vpn',
    String password = 'vpn',
  }) {
    final result = <VpnServer>[];
    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parsed = _parseServerLine(line);
      if (parsed == null) continue;
      result.add(
        VpnServer(
          address: parsed.$1,
          port: parsed.$2,
          username: username,
          password: password,
        ),
      );
    }
    return result;
  }

  (String, int)? _parseServerLine(String line) {
    if (line.contains(RegExp(r'\s')) ||
        line.contains('://') ||
        line.contains('/') ||
        line.contains('\\') ||
        line.contains('?') ||
        line.contains('#') ||
        line.contains('@')) {
      return null;
    }
    String host;
    String portText;
    if (line.startsWith('[')) {
      final close = line.indexOf(']');
      if (close <= 1 || close + 1 >= line.length || line[close + 1] != ':') {
        return null;
      }
      host = line.substring(1, close);
      portText = line.substring(close + 2);
      if (host.contains('[') || host.contains(']') || !host.contains(':')) {
        return null;
      }
    } else {
      final separator = line.lastIndexOf(':');
      if (separator <= 0 ||
          separator == line.length - 1 ||
          line.substring(0, separator).contains(':')) {
        return null; // IPv6 must use brackets to avoid ambiguity.
      }
      host = line.substring(0, separator);
      portText = line.substring(separator + 1);
    }
    final port = int.tryParse(portText);
    if (host.isEmpty || port == null || port < 1 || port > 65535) return null;
    return (host, port);
  }

  Future<List<SstpServerGroup>> _loadCustomGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <SstpServerGroup>[];
    for (final raw in prefs.getStringList(persistenceKey) ?? const <String>[]) {
      try {
        final group = SstpServerGroup.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (!group.isDefault &&
            group.name.trim().isNotEmpty &&
            group.servers.isNotEmpty) {
          result.add(group);
        }
      } catch (_) {
        // Ignore a damaged entry without hiding valid groups.
      }
    }
    return result;
  }

  Future<void> _saveCustomGroups(List<SstpServerGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(
      persistenceKey,
      groups.map((group) => jsonEncode(group.toJson())).toList(),
    );
    if (!saved) throw StateError('Could not save SSTP server groups.');
  }

  String _newId() => 'sstp-${DateTime.now().microsecondsSinceEpoch}';
}
