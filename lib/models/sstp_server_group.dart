import 'dart:convert';

import 'vpn_server.dart';

/// A named collection of SSTP servers.
class SstpServerGroup {
  static const String defaultId = 'default';
  static const String defaultName = '4win Free Servers';

  final String id;
  final String name;
  final List<VpnServer> servers;
  final String? subscriptionUrl;

  SstpServerGroup({
    required this.id,
    required this.name,
    required this.servers,
    this.subscriptionUrl,
  });

  bool get isDefault => id == defaultId;

  SstpServerGroup copyWith({List<VpnServer>? servers}) => SstpServerGroup(
    id: id,
    name: name,
    servers: servers ?? this.servers,
    subscriptionUrl: subscriptionUrl,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'servers': servers.map((server) => server.toJson()).toList(),
    if (subscriptionUrl != null) 'subscriptionUrl': subscriptionUrl,
  };

  factory SstpServerGroup.fromJson(Map<String, dynamic> json) {
    final rawServers = json['servers'];
    if (rawServers is! List) {
      throw const FormatException('Invalid server group.');
    }
    return SstpServerGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      servers: rawServers
          .map(
            (item) =>
                VpnServer.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      subscriptionUrl: json['subscriptionUrl'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());
}
