import 'dart:convert';

/// A single Xray server, parsed from a share link (vless:// / vmess:// /
/// trojan:// / ss://). Stores the raw link plus the decoded fields needed to
/// build an Xray JSON config for the real core (libv2ray / v2rayNG).
class XrayServer {
  final String id; // unique id (uuid-ish, derived from link hash + time)
  final String remark; // display name
  final String link; // original share link
  final String protocol; // vless | vmess | trojan | shadowsocks
  final String address;
  final int port;
  final DateTime addedAt;
  int? ping;

  /// Group this server belongs to. Empty for user-added servers. The built-in
  /// subscription group uses [freeGroup]; servers in a locked group cannot be
  /// deleted by the user.
  final String group;

  /// The free, auto-updated subscription group bundled with the app.
  static const String freeGroup = '4win Free Servers';

  bool get isLocked => group == freeGroup;

  XrayServer({
    required this.id,
    required this.remark,
    required this.link,
    required this.protocol,
    required this.address,
    required this.port,
    DateTime? addedAt,
    this.ping,
    this.group = '',
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'remark': remark,
        'link': link,
        'protocol': protocol,
        'address': address,
        'port': port,
        'addedAt': addedAt.toIso8601String(),
        'ping': ping,
        'group': group,
      };

  factory XrayServer.fromJson(Map<String, dynamic> json) => XrayServer(
        id: json['id'] as String,
        remark: json['remark'] as String? ?? '',
        link: json['link'] as String,
        protocol: json['protocol'] as String? ?? 'vless',
        address: json['address'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 443,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.now(),
        ping: (json['ping'] as num?)?.toInt(),
        group: json['group'] as String? ?? '',
      );

  XrayServer copyWith({int? ping, String? group}) => XrayServer(
        id: id,
        remark: remark,
        link: link,
        protocol: protocol,
        address: address,
        port: port,
        addedAt: addedAt,
        ping: ping ?? this.ping,
        group: group ?? this.group,
      );

  String get fullAddress => '$address:$port';

  /// Parse a share link into a [XrayServer]. Throws [FormatException] on
  /// unsupported / malformed links.
  factory XrayServer.fromLink(String raw, {String group = ''}) {
    final link = raw.trim();
    final lower = link.toLowerCase();
    XrayServer s;
    if (lower.startsWith('vmess://')) {
      s = _parseVmess(link);
    } else if (lower.startsWith('vless://')) {
      s = _parseUriStyle(link, 'vless');
    } else if (lower.startsWith('trojan://')) {
      s = _parseUriStyle(link, 'trojan');
    } else if (lower.startsWith('ss://')) {
      s = _parseShadowsocks(link);
    } else {
      throw const FormatException(
          'Unsupported link. Use vless://, vmess://, trojan:// or ss://');
    }
    return group.isEmpty ? s : s.copyWith(group: group);
  }

  // Deterministic id derived ONLY from the link, so a server keeps the same id
  // across subscription refreshes (otherwise the user's selection would be lost
  // every time the free group is re-fetched).
  static String _genId(String link) =>
      'x${link.hashCode.toUnsigned(32).toRadixString(16)}'
      '${link.length.toRadixString(16)}';

  // ---- VMess (base64 JSON payload) ----
  static XrayServer _parseVmess(String link) {
    final b64 = link.substring('vmess://'.length).trim();
    final jsonStr = utf8.decode(base64.decode(_padBase64(b64)));
    final m = jsonDecode(jsonStr) as Map<String, dynamic>;
    final addr = (m['add'] ?? '').toString();
    final port = int.tryParse('${m['port']}') ?? 443;
    final remark = (m['ps'] ?? addr).toString();
    return XrayServer(
      id: _genId(link),
      remark: remark,
      link: link,
      protocol: 'vmess',
      address: addr,
      port: port,
    );
  }

  // ---- VLESS / Trojan (URI style with userinfo@host:port?params#remark) ----
  static XrayServer _parseUriStyle(String link, String proto) {
    final uri = Uri.parse(link);
    final addr = uri.host;
    final port = uri.hasPort ? uri.port : 443;
    final remark = uri.fragment.isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : addr;
    if (addr.isEmpty) {
      throw const FormatException('Missing server address');
    }
    return XrayServer(
      id: _genId(link),
      remark: remark,
      link: link,
      protocol: proto,
      address: addr,
      port: port,
    );
  }

  // ---- Shadowsocks (ss://) ----
  static XrayServer _parseShadowsocks(String link) {
    // ss://base64(method:password)@host:port#remark
    // or ss://base64(method:password@host:port)#remark
    final hashIdx = link.indexOf('#');
    final remark = hashIdx >= 0
        ? Uri.decodeComponent(link.substring(hashIdx + 1))
        : '';
    final body = hashIdx >= 0
        ? link.substring('ss://'.length, hashIdx)
        : link.substring('ss://'.length);
    String host;
    int port;
    if (body.contains('@')) {
      final parts = body.split('@');
      final hostPort = parts.last;
      final hp = hostPort.split(':');
      host = hp[0];
      port = int.tryParse(hp.length > 1 ? hp[1] : '') ?? 443;
    } else {
      final decoded = utf8.decode(base64.decode(_padBase64(body)));
      // method:password@host:port
      final at = decoded.lastIndexOf('@');
      final hostPort = decoded.substring(at + 1);
      final hp = hostPort.split(':');
      host = hp[0];
      port = int.tryParse(hp.length > 1 ? hp[1] : '') ?? 443;
    }
    return XrayServer(
      id: _genId(link),
      remark: remark.isNotEmpty ? remark : host,
      link: link,
      protocol: 'shadowsocks',
      address: host,
      port: port,
    );
  }

  static String _padBase64(String s) {
    var v = s.replaceAll('-', '+').replaceAll('_', '/');
    final mod = v.length % 4;
    if (mod > 0) v += '=' * (4 - mod);
    return v;
  }
}
