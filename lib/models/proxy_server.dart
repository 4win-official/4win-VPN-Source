import 'dart:convert';
import '../services/secret_text_cipher.dart';

/// A single proxy server for the dedicated **Proxy** protocol. Unlike the Xray
/// protocol (which tunnels vmess/vless/trojan/ss through the Xray core), the
/// Proxy protocol makes a REAL upstream connection to a plain SOCKS4 / SOCKS5 /
/// HTTP(S) proxy. We reuse the Xray core purely as the SOCKS/HTTP *client*: the
/// server is turned into an Xray `socks`/`http` outbound (see
/// [XrayConfigBuilder.buildForProxyServer]).
///
/// Supported share-link formats (one per line):
///   • socks5://[user:pass@]host:port#remark
///   • socks4://host:port#remark              (SOCKS4 — no auth)
///   • socks://…                              (treated as SOCKS5)
///   • http://[user:pass@]host:port#remark
///   • https://[user:pass@]host:port#remark
///   • host:port                             (bare — defaults to SOCKS5)
///   • host:port:user:pass                   (bare with credentials, SOCKS5)
///   • 4ws://…                               (4win encrypted wrapper of any above)
class ProxyServer {
  final String id; // unique id (derived from link hash)
  final String remark; // display name
  final String link; // original share link
  final String protocol; // socks5 | socks4 | http
  final String address;
  final int port;
  final String username; // may be empty
  final String password; // may be empty
  final DateTime addedAt;
  int? ping;

  /// True when this server was imported from a 4win ENCRYPTED link (`4ws://`).
  final bool encrypted;

  /// Group this server belongs to. Empty for user-added individual servers.
  final String group;

  /// A built-in / bundled proxy subscription group (kept for parity with Xray;
  /// currently the Proxy protocol has no bundled subs, but user sub-links each
  /// get their own group name).
  static const String freeGroup = '4win Free Proxies';

  static bool isBuiltInGroup(String g) => g == freeGroup;

  /// A server is locked (subscription-managed, non-deletable individually) when
  /// it belongs to any named group. Individual user servers have empty group.
  bool get isLocked => group.isNotEmpty;

  ProxyServer({
    required this.id,
    required this.remark,
    required this.link,
    required this.protocol,
    required this.address,
    required this.port,
    this.username = '',
    this.password = '',
    DateTime? addedAt,
    this.ping,
    this.group = '',
    this.encrypted = false,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'remark': remark,
        'link': link,
        'protocol': protocol,
        'address': address,
        'port': port,
        'username': username,
        'password': password,
        'addedAt': addedAt.toIso8601String(),
        'ping': ping,
        'group': group,
        'encrypted': encrypted,
      };

  factory ProxyServer.fromJson(Map<String, dynamic> json) => ProxyServer(
        id: json['id'] as String,
        remark: json['remark'] as String? ?? '',
        link: json['link'] as String,
        protocol: json['protocol'] as String? ?? 'socks5',
        address: json['address'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 1080,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.now(),
        ping: (json['ping'] as num?)?.toInt(),
        group: json['group'] as String? ?? '',
        encrypted: json['encrypted'] as bool? ?? false,
      );

  ProxyServer copyWith({int? ping, String? group}) => ProxyServer(
        id: id,
        remark: remark,
        link: link,
        protocol: protocol,
        address: address,
        port: port,
        username: username,
        password: password,
        addedAt: addedAt,
        ping: ping ?? this.ping,
        group: group ?? this.group,
        encrypted: encrypted,
      );

  String get fullAddress => '$address:$port';

  /// The link to use when EXPORTING / COPYING this server. Encrypted servers
  /// re-encrypt to `4ws://`; normal servers copy the plain link as-is.
  String get exportLink {
    if (!encrypted) return link;
    try {
      return SecretTextCipher.encodeServerLink(link);
    } catch (_) {
      return link;
    }
  }

  /// Parse a proxy share link into a [ProxyServer]. Throws [FormatException] on
  /// unsupported / malformed links.
  factory ProxyServer.fromLink(String raw, {String group = ''}) {
    var link = raw.trim();
    var lower = link.toLowerCase();

    var isEncrypted = false;
    if (lower.startsWith('4ws://')) {
      link = SecretTextCipher.decodeServerLink(link).trim();
      lower = link.toLowerCase();
      isEncrypted = true;
    }

    ProxyServer s;
    if (lower.startsWith('socks5://') || lower.startsWith('socks://')) {
      s = _parseUriStyle(link, 'socks5');
    } else if (lower.startsWith('socks4://') || lower.startsWith('socks4a://')) {
      s = _parseUriStyle(link, 'socks4');
    } else if (lower.startsWith('https://')) {
      s = _parseUriStyle(link, 'http');
    } else if (lower.startsWith('http://')) {
      s = _parseUriStyle(link, 'http');
    } else if (link.contains('://')) {
      throw const FormatException(
          'Unsupported proxy. Use socks5://, socks4://, http:// or host:port');
    } else {
      // Bare form: host:port  OR  host:port:user:pass (defaults to SOCKS5).
      s = _parseBare(link, 'socks5');
    }

    if (isEncrypted || group.isNotEmpty) {
      s = ProxyServer(
        id: s.id,
        remark: s.remark,
        link: s.link,
        protocol: s.protocol,
        address: s.address,
        port: s.port,
        username: s.username,
        password: s.password,
        addedAt: s.addedAt,
        ping: s.ping,
        group: group.isEmpty ? s.group : group,
        encrypted: isEncrypted,
      );
    }
    return s;
  }

  // Deterministic id derived ONLY from the link, so a server keeps the same id
  // across subscription refreshes.
  static String _genId(String link) =>
      'p${link.hashCode.toUnsigned(32).toRadixString(16)}'
      '${link.length.toRadixString(16)}';

  // ---- URI style: scheme://[user:pass@]host:port#remark ----
  static ProxyServer _parseUriStyle(String link, String proto) {
    final uri = Uri.parse(link);
    final addr = uri.host;
    if (addr.isEmpty) throw const FormatException('Missing proxy host');
    final port = uri.hasPort
        ? uri.port
        : (proto == 'http' ? 8080 : 1080);
    var user = '';
    var pass = '';
    if (uri.userInfo.isNotEmpty) {
      final ui = uri.userInfo;
      final ci = ui.indexOf(':');
      if (ci >= 0) {
        user = Uri.decodeComponent(ui.substring(0, ci));
        pass = Uri.decodeComponent(ui.substring(ci + 1));
      } else {
        user = Uri.decodeComponent(ui);
      }
    }
    // Some providers put base64(user:pass) in the userinfo.
    if (user.isNotEmpty && pass.isEmpty && !user.contains(RegExp(r'[^A-Za-z0-9+/=_-]'))) {
      try {
        final dec = utf8.decode(base64.decode(_padBase64(user)));
        if (dec.contains(':')) {
          final ci = dec.indexOf(':');
          user = dec.substring(0, ci);
          pass = dec.substring(ci + 1);
        }
      } catch (_) {/* keep as-is */}
    }
    final remark = uri.fragment.isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : '$addr:$port';
    return ProxyServer(
      id: _genId(link),
      remark: remark,
      link: link,
      protocol: proto,
      address: addr,
      port: port,
      username: user,
      password: pass,
    );
  }

  // ---- Bare form: host:port  or  host:port:user:pass ----
  static ProxyServer _parseBare(String link, String proto) {
    // Strip an optional #remark.
    String remark = '';
    var body = link;
    final hashIdx = link.indexOf('#');
    if (hashIdx >= 0) {
      remark = Uri.decodeComponent(link.substring(hashIdx + 1));
      body = link.substring(0, hashIdx);
    }
    final parts = body.split(':');
    if (parts.length < 2) {
      throw const FormatException('Use host:port');
    }
    final host = parts[0];
    final port = int.tryParse(parts[1]);
    if (host.isEmpty || port == null) {
      throw const FormatException('Invalid host:port');
    }
    var user = '';
    var pass = '';
    if (parts.length >= 4) {
      user = parts[2];
      pass = parts.sublist(3).join(':');
    } else if (parts.length == 3) {
      user = parts[2];
    }
    return ProxyServer(
      id: _genId(link),
      remark: remark.isNotEmpty ? remark : '$host:$port',
      link: link,
      protocol: proto,
      address: host,
      port: port,
      username: user,
      password: pass,
    );
  }

  static String _padBase64(String s) {
    var v = s.replaceAll('-', '+').replaceAll('_', '/');
    final mod = v.length % 4;
    if (mod > 0) v += '=' * (4 - mod);
    return v;
  }
}
