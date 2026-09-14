import 'dart:convert';
import '../models/xray_server.dart';
import '../models/proxy_server.dart';
import '../models/warp_account.dart';

class XrayConfigBuilder {
  static String build(XrayServer server, {bool fragmentEnabled = true, String fragmentPackets = 'tlshello', String fragmentLength = '10-20', String fragmentInterval = '10-20', String fragmentHost = '', bool trafficCompression = false, bool proxyMode = false, int proxyPort = 4444}) {
    final proxy = _buildProxyOutbound(server);
    final outbounds = <Map<String, dynamic>>[];
    if (trafficCompression && !_hasXtlsFlow(proxy)) proxy['mux'] = {'enabled': true, 'concurrency': 8, 'xudpConcurrency': 8, 'xudpProxyUDP443': 'reject'};
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

  /// Cloudflare WARP outbound. Xray-core's bundled native library already
  /// implements the "wireguard" protocol (documented at
  /// https://xtls.github.io/en/config/outbounds/wireguard.html), so WARP
  /// needs no new native code — it is just another outbound config routed
  /// through the exact same core as the `xray`/`proxy` protocols. The
  /// outbound MUST be tagged 'proxy' (not e.g. 'warp') because
  /// XrayVpnService's queryTrafficStats() hardcodes the 'proxy' outbound tag.
  static String buildForWarp(WarpAccount account, {bool proxyMode = false, int proxyPort = 4444}) {
    final outbound = _warpOutbound(account);
    return _encode(proxyMode ? _proxyInbounds(proxyPort) : _vpnInbounds(), [outbound, {'tag': 'direct', 'protocol': 'freedom'}], defaultOutbound: 'proxy');
  }

  /// Real delay-test config for WARP (same pattern as buildProxyServerDelayTest).
  static String buildWarpDelayTest(WarpAccount account) {
    final outbound = _warpOutbound(account);
    return const JsonEncoder.withIndent('  ').convert({'log': {'loglevel': 'none'}, 'dns': {'servers': ['1.1.1.1', '8.8.8.8', 'localhost']}, 'outbounds': [outbound]});
  }

  static Map<String, dynamic> _warpOutbound(WarpAccount account) => {
    'tag': 'proxy',
    'protocol': 'wireguard',
    'settings': {
      'secretKey': account.privateKeyBase64,
      // Xray's `address` field wants bare IPs (no /CIDR suffix) — it is the
      // client's in-tunnel source address, not a route.
      'address': [
        account.addressV4Bare,
        if (account.addressV6.isNotEmpty) account.addressV6Bare,
      ],
      'peers': [
        {
          'endpoint': account.peerEndpoint,
          'publicKey': account.peerPublicKeyBase64,
          'allowedIPs': ['0.0.0.0/0', '::/0'],
          // Keep NAT/firewall mappings alive on mobile networks.
          'keepAlive': 25,
        }
      ],
      'reserved': account.reserved,
      'mtu': 1280,
      'domainStrategy': 'ForceIP',
    },
  };

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
    return {'protocol': 'vmess', 'settings': {'vnext': [{'address': server.address, 'port': server.port, 'users': [{'id': '${m['id'] ?? ''}', 'alterId': int.tryParse('${m['aid'] ?? 0}') ?? 0, 'security': '${m['scy'] ?? 'auto'}'}]}]}, 'streamSettings': _streamSettings(network: '${m['net'] ?? 'tcp'}', security: '${m['tls'] ?? ''}', sni: '${m['sni'] ?? m['host'] ?? ''}', host: '${m['host'] ?? ''}', path: '${m['path'] ?? ''}', alpn: '${m['alpn'] ?? ''}', fp: '${m['fp'] ?? ''}')};
  }

  static Map<String, dynamic> _vlessOutbound(XrayServer server) {
    final uri = Uri.parse(server.link), q = uri.queryParameters;
    return {'protocol': 'vless', 'settings': {'vnext': [{'address': server.address, 'port': server.port, 'users': [{'id': uri.userInfo, 'encryption': q['encryption'] ?? 'none', if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow']}]}]}, 'streamSettings': _streamSettings(network: q['type'] ?? 'tcp', security: q['security'] ?? '', sni: q['sni'] ?? q['host'] ?? '', host: q['host'] ?? '', path: q['path'] ?? '', alpn: q['alpn'] ?? '', fp: q['fp'] ?? '', pbk: q['pbk'] ?? '', sid: q['sid'] ?? '', serviceName: q['serviceName'] ?? '')};
  }

  static Map<String, dynamic> _trojanOutbound(XrayServer server) {
    final uri = Uri.parse(server.link), q = uri.queryParameters;
    return {'protocol': 'trojan', 'settings': {'servers': [{'address': server.address, 'port': server.port, 'password': uri.userInfo}]}, 'streamSettings': _streamSettings(network: q['type'] ?? 'tcp', security: q['security'] ?? 'tls', sni: q['sni'] ?? q['host'] ?? '', host: q['host'] ?? '', path: q['path'] ?? '', alpn: q['alpn'] ?? '', fp: q['fp'] ?? '')};
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

  static Map<String, dynamic> _streamSettings({required String network, required String security, String sni = '', String host = '', String path = '', String alpn = '', String fp = '', String pbk = '', String sid = '', String serviceName = ''}) {
    final stream = <String, dynamic>{'network': network.isEmpty ? 'tcp' : network};
    if (security == 'tls') { stream['security'] = 'tls'; stream['tlsSettings'] = {if (sni.isNotEmpty) 'serverName': sni, if (alpn.isNotEmpty) 'alpn': alpn.split(','), if (fp.isNotEmpty) 'fingerprint': fp, 'allowInsecure': false}; }
    else if (security == 'reality') { stream['security'] = 'reality'; stream['realitySettings'] = {if (sni.isNotEmpty) 'serverName': sni, 'fingerprint': fp.isNotEmpty ? fp : 'chrome', if (pbk.isNotEmpty) 'publicKey': pbk, if (sid.isNotEmpty) 'shortId': sid, 'spiderX': ''}; }
    switch (network) {
      case 'ws': stream['wsSettings'] = {'path': path.isEmpty ? '/' : path, if (host.isNotEmpty) 'headers': {'Host': host}}; break;
      case 'grpc': stream['grpcSettings'] = {'serviceName': serviceName.isNotEmpty ? serviceName : path, 'multiMode': false}; break;
      case 'h2':
      case 'http': stream['httpSettings'] = {'path': path.isEmpty ? '/' : path, if (host.isNotEmpty) 'host': host.split(',')}; break;
      case 'tcp': if (host.isNotEmpty && path.isNotEmpty) stream['tcpSettings'] = {'header': {'type': 'http', 'request': {'path': [path], 'headers': {'Host': [host]}}}}; break;
    }
    return stream;
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
