import 'dart:convert';
import '../models/xray_server.dart';
import '../models/proxy_server.dart';
import '../models/warp_account.dart';

class XrayConfigBuilder {
  static String build(XrayServer server, {bool fragmentEnabled = true, String fragmentPackets = 'tlshello', String fragmentLength = '10-20', String fragmentInterval = '10-20', String fragmentHost = '', bool trafficCompression = false, bool proxyMode = false, int proxyPort = 4444}) {
    final proxy = _buildProxyOutbound(server);
    final outbounds = <Map<String, dynamic>>[];
    // XHTTP manages multiplexing itself (including extra.xmux). Generic Mux
    // breaks its data path even though the core accepts the JSON config.
    if (trafficCompression && !_hasXtlsFlow(proxy) &&
        (proxy['streamSettings'] as Map?)?['network'] != 'xhttp') {
      proxy['mux'] = {'enabled': true, 'concurrency': 8, 'xudpConcurrency': 8, 'xudpProxyUDP443': 'reject'};
    }
    if (fragmentEnabled && fragmentHost.trim().isNotEmpty) _applyFakeHost(proxy, fragmentHost.trim());
    if (fragmentEnabled) {
      final stream = Map<String, dynamic>.from((proxy['streamSettings'] as Map?) ?? const {});
      final sockopt = Map<String, dynamic>.from((stream['sockopt'] as Map?) ?? const {});
      sockopt['dialerProxy'] = 'fragment';
      stream['sockopt'] = sockopt;
      proxy['streamSettings'] = stream;
    }
    proxy['tag'] = 'proxy';
    outbounds.add(proxy);
    if (fragmentEnabled) outbounds.add({'tag': 'fragment', 'protocol': 'freedom', 'settings': {'fragment': {'packets': fragmentPackets, 'length': fragmentLength, 'interval': fragmentInterval}}, 'streamSettings': {'sockopt': {'tcpNoDelay': true, 'tcpKeepAliveIdle': 100}}});
    outbounds.add({'tag': 'direct', 'protocol': 'freedom', 'settings': {'domainStrategy': 'UseIP'}});
    outbounds.add({'tag': 'block', 'protocol': 'blackhole', 'settings': {'response': {'type': 'http'}}});
    return _encode(proxyMode ? _proxyInbounds(proxyPort) : _vpnInbounds(), outbounds);
  }

  static String buildForPsiphon(int socksPort, {bool proxyMode = false, int proxyPort = 4444}) {
    if (socksPort < 1 || socksPort > 65535) throw ArgumentError('Invalid Psiphon SOCKS port');
    final outbounds = [
      {'tag': 'psiphon', 'protocol': 'socks', 'settings': {'servers': [{'address': '127.0.0.1', 'port': socksPort}]}},
      {'tag': 'direct', 'protocol': 'freedom'},
      {'tag': 'block', 'protocol': 'blackhole'},
    ];
    return _encode(proxyMode ? _proxyInbounds(proxyPort) : _vpnInbounds(), outbounds, defaultOutbound: 'psiphon');
  }

  static String buildForProxyServer(ProxyServer server, {bool proxyMode = false, int proxyPort = 4444}) {
    final user = <Map<String, dynamic>>[];
    if (server.username.isNotEmpty) user.add({'user': server.username, 'pass': server.password});
    final settings = {'servers': [{'address': server.address, 'port': server.port, if (user.isNotEmpty) 'users': user}]};
    final outbound = {'tag': 'proxy', 'protocol': server.protocol == 'http' ? 'http' : 'socks', 'settings': settings};
    return _encode(proxyMode ? _proxyInbounds(proxyPort) : _vpnInbounds(), [outbound, {'tag': 'direct', 'protocol': 'freedom'}], defaultOutbound: 'proxy');
  }

  /// Cloudflare WARP configuration for the Aether native core. Unlike the old
  /// Xray outbound, Aether owns the Cloudflare registration, endpoint scan,
  /// WireGuard reserved/client-id framing and data-plane validation.
  static String buildForWarp(WarpAccount account, {bool proxyMode = false, int proxyPort = 4444}) {
    _validateWarpAccount(account);
    return const JsonEncoder.withIndent('  ').convert({
      'config_path': '__APP_FILES__/aether-warp.toml',
      'wireguard_config_path': '__APP_FILES__/aether-warp.toml',
      'protocol': 'wg',
      'listen': '127.0.0.1:1819',
      'scan_mode': 'balanced',
      'ip_scan': 'v4',
      'endpoint_discovery': 'cache',
      'wireguard_data_check': true,
      'retry_obfuscation_profiles': true,
      'tls_curve_preset': 'chrome',
      'log_level': 'info',
    });
  }

  /// Real delay-test config for WARP (same pattern as buildProxyServerDelayTest).
  static String buildWarpDelayTest(WarpAccount account) {
    return buildForWarp(account);
  }

  /// Reject malformed persisted identities before they reach the native
  /// Xray/Go runtime. A corrupt or partially-written WARP account used to
  /// make the native wireguard handler terminate the whole app instead of
  /// returning a normal connection error.
  static void _validateWarpAccount(WarpAccount account) {
    for (final key in [
      account.privateKeyBase64,
      account.publicKeyBase64,
      account.peerPublicKeyBase64,
    ]) {
      try {
        if (base64.decode(key).length != 32) {
          throw const FormatException('WARP key must decode to 32 bytes');
        }
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('Invalid WARP key encoding');
      }
    }
    if (account.addressV4Bare.isEmpty || account.peerEndpoint.trim().isEmpty) {
      throw const FormatException('WARP account is missing an address or peer');
    }
    if (account.reserved.length != 3 ||
        account.reserved.any((value) => value < 0 || value > 255)) {
      throw const FormatException('WARP reserved bytes must contain 3 bytes');
    }
  }

  static String buildProxyServerDelayTest(ProxyServer server) {
    final user = <Map<String, dynamic>>[];
    if (server.username.isNotEmpty) user.add({'user': server.username, 'pass': server.password});
    final outbound = {'tag': 'proxy', 'protocol': server.protocol == 'http' ? 'http' : 'socks', 'settings': {'servers': [{'address': server.address, 'port': server.port, if (user.isNotEmpty) 'users': user}]}};
    return const JsonEncoder.withIndent('  ').convert({'log': {'loglevel': 'none'}, 'dns': {'servers': ['1.1.1.1', '8.8.8.8', 'localhost']}, 'outbounds': [outbound]});
  }

  static String buildForDelayTest(XrayServer server, {bool fragmentEnabled = true, String fragmentPackets = 'tlshello', String fragmentLength = '10-20', String fragmentInterval = '10-20', String fragmentHost = ''}) {
    final proxy = _buildProxyOutbound(server);
    if (fragmentEnabled && fragmentHost.trim().isNotEmpty) _applyFakeHost(proxy, fragmentHost.trim());
    final outbounds = <Map<String, dynamic>>[];
    if (fragmentEnabled) {
      final stream = Map<String, dynamic>.from((proxy['streamSettings'] as Map?) ?? const {});
      final sockopt = Map<String, dynamic>.from((stream['sockopt'] as Map?) ?? const {});
      sockopt['dialerProxy'] = 'fragment';
      stream['sockopt'] = sockopt;
      proxy['streamSettings'] = stream;
    }
    proxy['tag'] = 'proxy';
    outbounds.add(proxy);
    if (fragmentEnabled) outbounds.add({'tag': 'fragment', 'protocol': 'freedom', 'settings': {'fragment': {'packets': fragmentPackets, 'length': fragmentLength, 'interval': fragmentInterval}}});
    return const JsonEncoder.withIndent('  ').convert({'log': {'loglevel': 'none'}, 'dns': {'servers': ['1.1.1.1', '8.8.8.8', 'localhost']}, 'outbounds': outbounds});
  }

  static List<Map<String, dynamic>> _vpnInbounds() => [
    {'tag': 'socks', 'port': 10808, 'listen': '127.0.0.1', 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8}, 'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']}},
    {'tag': 'tun', 'protocol': 'tun', 'settings': {'name': 'xray0', 'MTU': 1500, 'userLevel': 8}, 'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']}},
  ];

  static List<Map<String, dynamic>> _proxyInbounds(int port) => [
    {'tag': 'socks', 'port': port, 'listen': '127.0.0.1', 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8}, 'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']}},
    {'tag': 'http', 'port': port + 1, 'listen': '127.0.0.1', 'protocol': 'http', 'settings': {'userLevel': 8}, 'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']}},
  ];

  static String _encode(List<Map<String, dynamic>> inbounds, List<Map<String, dynamic>> outbounds, {String defaultOutbound = 'proxy'}) => const JsonEncoder.withIndent('  ').convert({'stats': {}, 'log': {'loglevel': 'warning'}, 'policy': {'levels': {'8': {'handshake': 4, 'connIdle': 300, 'uplinkOnly': 1, 'downlinkOnly': 1}}, 'system': {'statsOutboundUplink': true, 'statsOutboundDownlink': true}}, 'dns': {'servers': ['1.1.1.1', '8.8.8.8', 'localhost']}, 'inbounds': inbounds, 'outbounds': outbounds, 'routing': {'domainStrategy': 'AsIs', 'rules': [{'type': 'field', 'ip': ['0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10'], 'outboundTag': 'direct'}]}});

  static Map<String, dynamic> _buildProxyOutbound(XrayServer server) {
    switch (server.protocol) {
      case 'vmess': return _vmessOutbound(server);
      case 'vless': return _vlessOutbound(server);
      case 'trojan': return _trojanOutbound(server);
      case 'shadowsocks': return _shadowsocksOutbound(server);
      default: throw FormatException('Unsupported protocol: ${server.protocol}');
    }
  }

  static Map<String, dynamic> _vmessOutbound(XrayServer server) {
    final m = jsonDecode(utf8.decode(base64.decode(_pad(server.link.substring(8))))) as Map<String, dynamic>;
    return {'protocol': 'vmess', 'settings': {'vnext': [{'address': server.address, 'port': server.port, 'users': [{'id': '${m['id'] ?? ''}', 'alterId': int.tryParse('${m['aid'] ?? 0}') ?? 0, 'security': '${m['scy'] ?? 'auto'}'}]}]}, 'streamSettings': _streamSettings(network: '${m['net'] ?? 'tcp'}', security: '${m['tls'] ?? ''}', sni: '${m['sni'] ?? m['host'] ?? ''}', host: '${m['host'] ?? ''}', path: '${m['path'] ?? ''}', alpn: '${m['alpn'] ?? ''}', fp: '${m['fp'] ?? ''}', mode: '${m['mode'] ?? ''}', extra: m['extra'])};
  }

  static Map<String, dynamic> _vlessOutbound(XrayServer server) {
    final uri = Uri.parse(server.link), q = uri.queryParameters;
    return {'protocol': 'vless', 'settings': {'vnext': [{'address': server.address, 'port': server.port, 'users': [{'id': uri.userInfo, 'encryption': q['encryption'] ?? 'none', if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow']}]}]}, 'streamSettings': _streamSettings(network: q['type'] ?? 'tcp', security: q['security'] ?? '', sni: q['sni'] ?? q['host'] ?? '', host: q['host'] ?? '', path: q['path'] ?? '', alpn: q['alpn'] ?? '', fp: q['fp'] ?? '', pbk: q['pbk'] ?? '', sid: q['sid'] ?? '', serviceName: q['serviceName'] ?? '', mode: q['mode'] ?? '', extra: q['extra'])};
  }

  static Map<String, dynamic> _trojanOutbound(XrayServer server) {
    final uri = Uri.parse(server.link), q = uri.queryParameters;
    return {'protocol': 'trojan', 'settings': {'servers': [{'address': server.address, 'port': server.port, 'password': uri.userInfo}]}, 'streamSettings': _streamSettings(network: q['type'] ?? 'tcp', security: q['security'] ?? 'tls', sni: q['sni'] ?? q['host'] ?? '', host: q['host'] ?? '', path: q['path'] ?? '', alpn: q['alpn'] ?? '', fp: q['fp'] ?? '', pbk: q['pbk'] ?? '', sid: q['sid'] ?? '', serviceName: q['serviceName'] ?? '', mode: q['mode'] ?? '', extra: q['extra'])};
  }

  static Map<String, dynamic> _shadowsocksOutbound(XrayServer server) {
    final body = server.link.substring(5).split('#').first;
    String method, password;
    if (body.contains('@')) {
      final u = body.split('@').first;
      final d = u.contains(':') ? u : utf8.decode(base64.decode(_pad(u)));
      final p = d.split(':'); method = p.first; password = p.sublist(1).join(':');
    } else {
      final d = utf8.decode(base64.decode(_pad(body))); final at = d.lastIndexOf('@'); final p = d.substring(0, at).split(':'); method = p.first; password = p.sublist(1).join(':');
    }
    return {'protocol': 'shadowsocks', 'settings': {'servers': [{'address': server.address, 'port': server.port, 'method': method, 'password': password}]}, 'streamSettings': {'network': 'tcp'}};
  }

  static Map<String, dynamic> _streamSettings({required String network, required String security, String sni = '', String host = '', String path = '', String alpn = '', String fp = '', String pbk = '', String sid = '', String serviceName = '', String mode = '', Object? extra}) {
    // SplitHTTP is the legacy share-link name for XHTTP. Both use the same
    // core settings; do not route them through the removed HTTP/H2 transport.
    final transport = network == 'splithttp' ? 'xhttp' : network;
    final stream = <String, dynamic>{'network': transport.isEmpty ? 'tcp' : transport};
    if (security == 'tls') { stream['security'] = 'tls'; stream['tlsSettings'] = {if (sni.isNotEmpty) 'serverName': sni, if (alpn.isNotEmpty) 'alpn': alpn.split(','), if (fp.isNotEmpty) 'fingerprint': fp, 'allowInsecure': false}; }
    else if (security == 'reality') { stream['security'] = 'reality'; stream['realitySettings'] = {if (sni.isNotEmpty) 'serverName': sni, 'fingerprint': fp.isNotEmpty ? fp : 'chrome', if (pbk.isNotEmpty) 'publicKey': pbk, if (sid.isNotEmpty) 'shortId': sid, 'spiderX': ''}; }
    switch (transport) {
      case 'xhttp':
        stream['xhttpSettings'] = {
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'host': host,
          'mode': mode.isEmpty ? 'auto' : mode,
          if (extra != null && extra != '') 'extra': _xhttpExtra(extra),
        };
        break;
      case 'httpupgrade':
        stream['httpupgradeSettings'] = {
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'host': host,
        };
        break;
      case 'ws': stream['wsSettings'] = {'path': path.isEmpty ? '/' : path, if (host.isNotEmpty) 'headers': {'Host': host}}; break;
      case 'grpc': stream['grpcSettings'] = {'serviceName': serviceName.isNotEmpty ? serviceName : path, 'multiMode': false}; break;
      case 'h2':
      case 'http': stream['httpSettings'] = {'path': path.isEmpty ? '/' : path, if (host.isNotEmpty) 'host': host.split(',')}; break;
      case 'tcp': if (host.isNotEmpty && path.isNotEmpty) stream['tcpSettings'] = {'header': {'type': 'http', 'request': {'path': [path], 'headers': {'Host': [host]}}}}; break;
    }
    return stream;
  }

  // URI query parameters have already been percent-decoded by Uri. Decode
  // JSON only once so encoded paths/headers inside extra remain intact.
  static Map<String, dynamic> _xhttpExtra(Object value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('XHTTP extra must be a JSON object');
    }
    return decoded;
  }

  static void _applyFakeHost(Map<String, dynamic> proxy, String host) {
    final stream = Map<String, dynamic>.from((proxy['streamSettings'] as Map?) ?? const {});
    if (stream['security'] == 'tls') { final tls = Map<String, dynamic>.from((stream['tlsSettings'] as Map?) ?? const {}); tls['serverName'] = host; stream['tlsSettings'] = tls; }
    else if (stream['security'] == 'reality') { final r = Map<String, dynamic>.from((stream['realitySettings'] as Map?) ?? const {}); r['serverName'] = host; stream['realitySettings'] = r; }
    else { stream['security'] = 'tls'; stream['tlsSettings'] = {'serverName': host, 'allowInsecure': true}; }
    proxy['streamSettings'] = stream;
  }

  static bool _hasXtlsFlow(Map<String, dynamic> proxy) {
    try { final v = (proxy['settings'] as Map?)?['vnext']; if (v is List) for (final n in v) { final u = (n as Map)['users']; if (u is List) for (final x in u) { final flow = '${(x as Map)['flow'] ?? ''}'; if (flow.contains('xtls') || flow.contains('vision')) return true; } } } catch (_) {}
    return false;
  }

  static String _pad(String s) { var v = s.replaceAll('-', '+').replaceAll('_', '/'); final m = v.length % 4; if (m > 0) v += '=' * (4 - m); return v; }
}
