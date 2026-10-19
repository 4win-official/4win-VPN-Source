import 'dart:io';

/// Mix keeps references to existing profiles, never copies credentials or
/// changes the standalone protocol selections. Order is device -> hop 1 -> exit.
class MixHop {
  final String protocol;
  final String? serverId;

  /// For SSTP a server may also carry its owning group, since different
  /// groups can publish the same endpoint with different credentials.
  final String? group;
  const MixHop({required this.protocol, this.serverId, this.group});

  Map<String, dynamic> toJson() => {
    'protocol': protocol,
    if (serverId != null) 'serverId': serverId,
    if (group != null) 'group': group,
  };
  factory MixHop.fromJson(Map<String, dynamic> json) => MixHop(
    protocol: json['protocol'] as String,
    serverId: json['serverId'] as String?,
    group: json['group'] as String?,
  );
}

/// Optional per-strategy UDP-over-TLS relay. It is not a Mix block.
class MixUdpRelay {
  final String host;
  final int port;
  final String token;
  final String serverName;

  const MixUdpRelay({
    required this.host,
    required this.port,
    required this.token,
    String? serverName,
  }) : serverName = serverName ?? host;

  String? get validationError {
    if (!_validHost(host)) {
      return 'Enter a valid relay host (IP address or hostname).';
    }
    if (port < 1 || port > 65535) {
      return 'Relay port must be between 1 and 65535.';
    }
    if (!_validHost(serverName)) return 'Enter a valid TLS server name.';
    if (token.length < 32 ||
        token.length > 256 ||
        !RegExp(r'^[\x21-\x7E]+$').hasMatch(token)) {
      return 'Relay auth token must be 32–256 printable ASCII characters.';
    }
    return null;
  }

  static bool _validHost(String value) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.length > 253 ||
        RegExp(r'[\s\x00-\x1F\x7F/\\@%]').hasMatch(value)) {
      return false;
    }
    if (InternetAddress.tryParse(value) != null) return true;
    if (value.contains(':')) return false;
    final ipv4 = RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}$');
    if (ipv4.hasMatch(value)) {
      return value.split('.').every((p) => int.parse(p) <= 255);
    }
    return RegExp(
      r'^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
    ).hasMatch(value);
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'token': token,
    'serverName': serverName,
  };
  factory MixUdpRelay.fromJson(Map<String, dynamic> json) => MixUdpRelay(
    host: json['host'] as String,
    port: json['port'] as int,
    token: json['token'] as String,
    serverName: json['serverName'] as String? ?? json['host'] as String,
  );
}

class MixStrategy {
  static const maxBlocks = 50;
  final String id;
  final String name;
  final List<MixHop> hops;
  final MixUdpRelay? udpRelay;
  MixStrategy({
    required this.id,
    required this.name,
    required List<MixHop> hops,
    this.udpRelay,
  }) : hops = List.unmodifiable(hops);

  static const protocols = {
    'xray': 'Xray',
    'warp': 'WARP',
    'openvpn': 'OpenVPN',
    'sstp': 'SSTP',
    'direct_dns': 'DNS',
    'proxy': 'Proxy',
    'psiphon': 'Psiphon',
  };
  static const chainable = {
    'xray',
    'proxy',
    'warp',
    'sstp',
    'openvpn',
    'psiphon',
    'direct_dns',
  };
  static String? unavailableReason(String protocol) =>
      chainable.contains(protocol)
      ? null
      : 'Unsupported Mix protocol: $protocol.';

  String? get validationError {
    if (name.trim().isEmpty) return 'Enter a strategy name.';
    if (udpRelay?.validationError != null) return udpRelay!.validationError;
    if (hops.isEmpty) return 'Add at least one block after Start.';
    if (hops.length > maxBlocks) {
      return 'At most $maxBlocks blocks are supported.';
    }
    for (var i = 0; i < hops.length; i++) {
      final hop = hops[i];
      final reason = unavailableReason(hop.protocol);
      if (reason != null) return reason;
      if ((hop.serverId == null || hop.serverId!.isEmpty) &&
          (hop.group == null || hop.group!.isEmpty)) {
        return 'Choose a server or group for block ${i + 1}.';
      }
      if (hop.serverId != null && hop.group != null && hop.protocol != 'sstp') {
        return 'Block ${i + 1} must select a server OR a group.';
      }
      if (hop.protocol == 'direct_dns') {
        if (hop.group != null ||
            hop.serverId == null ||
            hop.serverId!.isEmpty) {
          return 'DNS must use a server IP reference, not a group.';
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'hops': hops.map((hop) => hop.toJson()).toList(),
    if (udpRelay != null) 'udpRelay': udpRelay!.toJson(),
  };
  factory MixStrategy.fromJson(Map<String, dynamic> json) => MixStrategy(
    id: json['id'] as String,
    name: json['name'] as String,
    hops: (json['hops'] as List)
        .map((hop) => MixHop.fromJson(Map<String, dynamic>.from(hop as Map)))
        .toList(),
    udpRelay: json['udpRelay'] == null
        ? null
        : MixUdpRelay.fromJson(
            Map<String, dynamic>.from(json['udpRelay'] as Map),
          ),
  );
}
