/// Mix keeps references to existing profiles, never copies credentials or
/// changes the standalone protocol selections. Order is device -> hop 1 -> exit.
class MixHop {
  final String protocol;
  final String? serverId;
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

class MixStrategy {
  static const maxBlocks = 50;
  final String id;
  final String name;
  final List<MixHop> hops;
  MixStrategy({
    required this.id,
    required this.name,
    required List<MixHop> hops,
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
    if (hops.isEmpty) return 'Add at least one tunnel block after Start.';
    if (hops.length > maxBlocks) {
      return 'At most $maxBlocks blocks are supported.';
    }
    var tunnels = 0;
    for (var i = 0; i < hops.length; i++) {
      final hop = hops[i];
      final reason = unavailableReason(hop.protocol);
      if (reason != null) return reason;
      if ((hop.serverId == null || hop.serverId!.isEmpty) &&
          (hop.group == null || hop.group!.isEmpty)) {
        return 'Choose a server or group for block ${i + 1}.';
      }
      if (hop.serverId != null && hop.group != null) {
        return 'Block ${i + 1} must select a server OR a group.';
      }
      if (hop.protocol == 'direct_dns') {
        if (hop.group != null ||
            hop.serverId == null ||
            hop.serverId!.isEmpty) {
          return 'DNS must use a server IP reference, not a group.';
        }
      } else {
        tunnels++;
      }
    }
    if (tunnels == 0) {
      return 'Add at least one tunnel block; DNS is a resolver, not a VPN hop.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'hops': hops.map((hop) => hop.toJson()).toList(),
  };
  factory MixStrategy.fromJson(Map<String, dynamic> json) => MixStrategy(
    id: json['id'] as String,
    name: json['name'] as String,
    hops: (json['hops'] as List)
        .map((hop) => MixHop.fromJson(Map<String, dynamic>.from(hop as Map)))
        .toList(),
  );
}
