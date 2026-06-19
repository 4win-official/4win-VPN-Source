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

  XrayServer({
    required this.id,
    required this.remark,
    required this.link,
    required this.protocol,
    required this.address,
    required this.port,
    DateTime? addedAt,
    this.ping,
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
      );

  String get fullAddress => '$address:$port';

  /// Parse a share link into a [XrayServer]. Throws [FormatException] on
  /// unsupported / malformed links.
  factory XrayServer.fromLink(String raw) {
    final link = raw.trim();
    final lower = link.toLowerCase();
    if (lower.startsWith('vmess://')) {
      return _parseVmess(link);
    } else if (lower.startsWith('vless://')) {
      return _parseUriStyle(link, 'vless');
    } else if (lower.startsWith('trojan://')) {
      return _parseUriStyle(link, 'trojan');
    } else if (lower.startsWith('ss://')) {
      return _parseShadowsocks(link);
    }
    throw const FormatException(
        'Unsupported link. Use vless://, vmess://, trojan:// or ss://');
  }

  static String _genId(String link) =>
      '${link.hashCode.toUnsigned(32).toRadixString(16)}'
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

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
