import 'dart:convert';

import '../models/xray_server.dart';
import '../models/proxy_server.dart';

/// Builds a complete Xray JSON config (the standard Xray config format that
/// libv2ray / v2rayNG's core consumes via `startLoop`).
class XrayConfigBuilder {
  static String build(
    XrayServer server, {
    bool fragmentEnabled = true,
    String fragmentPackets = 'tlshello',
    String fragmentLength = '10-20',
    String fragmentInterval = '10-20',
    String fragmentHost = '',
    bool trafficCompression = false,
    bool proxyMode = false,
    int proxyPort = 4444,
  }) {
    final outbounds = <Map<String, dynamic>>[];
    final proxy = _buildProxyOutbound(server);
    if (trafficCompression && !_hasXtlsFlow(proxy)) {
      proxy['mux'] = <String, dynamic>{
        'enabled': true,
        'concurrency': 8,
        'xudpConcurrency': 8,
        'xudpProxyUDP443': 'reject',
      };
    }
    if (fragmentEnabled && fragmentHost.trim().isNotEmpty) {
      _applyFakeHost(proxy, fragmentHost.trim());
    }
    if (fragmentEnabled) {
      final stream = Map<String, dynamic>.from((proxy['streamSettings'] as Map?) ?? const {});
      final sockopt = Map<String, dynamic>.from((stream['sockopt'] as Map?) ?? const {});
      sockopt['dialerProxy'] = 'fragment';
      stream['sockopt'] = sockopt;
      proxy['streamSettings'] = stream;
    }
    proxy['tag'] = 'proxy';
    outbounds.add(proxy);
    if (fragmentEnabled) {
      outbounds.add({
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': {'fragment': {'packets': fragmentPackets, 'length': fragmentLength, 'interval': fragmentInterval}},
        'streamSettings': {'sockopt': {'tcpNoDelay': true, 'tcpKeepAliveIdle': 100}},
      });
    }
    outbounds.add({'tag': 'direct', 'protocol': 'freedom', 'settings': {'domainStrategy': 'UseIP'}});
    outbounds.add({'tag': 'block', 'protocol': 'blackhole', 'settings': {'response': {'type': 'http'}}});

    final List<Map<String, dynamic>> inbounds = proxyMode
        ? [
            {'tag': 'socks', 'port': proxyPort, 'listen': '127.0.0.1', 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8}, 'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']}},
            {'tag': 'http', 'port': proxyPort + 1, 'listen': '127.0.0.1', 'protocol': 'http', 'settings': {'userLevel': 8}, 'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']}},
          ]
        : [
            {'tag': 'socks', 'port': 10808, 'listen': '127.0.0.1', 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8}, 'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']}},
            {'tag': 'tun', 'protocol': 'tun', 'settings': {'name': 'xray0', 'MTU': 1500, 'userLevel': 8}, 'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']}},
          ];

    return const JsonEncoder.withIndent('  ').convert({
      'stats': <String, dynamic>{},
      'log': {'loglevel': 'warning'},
      'policy': {'levels': {'8': {'handshake': 4, 'connIdle': 300, 'uplinkOnly': 1, 'downlinkOnly': 1}}, 'system': {'statsOutboundUplink': true, 'statsOutboundDownlink': true}},
      'dns': {'servers': ['1.1.1.1', '8.8.8.8', 'localhost']},
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {'type': 'field', 'ip': ['0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10'], 'outboundTag': 'direct'},
        ],
      },
    });
  }

  /// Psiphon itself discovers and rotates its upstream servers. Its local SOCKS
  /// endpoint is used as the single upstream of the existing Xray TUN, which
  /// keeps split-tunnel and the Android VPN interface in one place.
  static String buildForPsiphon(int socksPort, {bool proxyMode = false, int proxyPort = 4444}) {
    if (socksPort <= 0 || socksPort > 65535) {
      throw ArgumentError('Invalid Psiphon SOCKS port: $socksPort');
    }
    final inbounds = proxyMode
        ? [
            {'tag': 'socks', 'port': proxyPort, 'listen': '127.0.0.1', 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8}},
            {'tag': 'http', 'port': proxyPort + 1, 'listen': '127.0.0.1', 'protocol': 'http', 'settings': {'userLevel': 8}},
          ]
        : [
            {'tag': 'socks', 'port': 10808, 'listen': '127.0.0.1', 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8}},
            {'tag': 'tun', 'protocol': 'tun', 'settings': {'name': 'xray0', 'MTU': 1500, 'userLevel': 8}, 'sniffing': {'enabled': true, 'destOverride': ['http', 'tls', 'quic']}},
          ];
    return const JsonEncoder.withIndent('  ').convert({
      'log': {'loglevel': 'warning'},
      'dns': {'servers': ['1.1.1.1', '8.8.8.8', 'localhost']},
      'inbounds': inbounds,
      'outbounds': [
        {'tag': 'psiphon', 'protocol': 'socks', 'settings': {'servers': [{'address': '127.0.0.1', 'port': socksPort, 'level': 8}]}},
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {'type': 'field', 'ip': ['10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10'], 'outboundTag': 'direct'},
        ],
      },
    });
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
    if (fragmentEnabled) {
      outbounds.add({'tag': 'fragment', 'protocol': 'freedom', 'settings': {'fragment': {'packets': fragmentPackets, 'length': fragmentLength, 'interval': fragmentInterval}}, 'streamSettings': {'sockopt': {'tcpNoDelay': true}}});
    }
    return const JsonEncoder.withIndent('  ').convert({'log': {'loglevel': 'none'}, 'dns': {'servers': ['1.1.1.1', '8.8.8.8', 'localhost']}, 'outbounds': outbounds});
  }

  static void _applyFakeHost(Map<String, dynamic> proxy, String host) {
    final stream = Map<String, dynamic>.from((proxy['streamSettings'] as Map?) ?? const {});
    final security = (stream['security'] ?? '').toString();
    if (security == 'tls') {
      final tls = Map<String, dynamic>.from((stream['tlsSettings'] as Map?) ?? const {});
      tls['serverName'] = host;
      stream['tlsSettings'] = tls;
    } else if (security == 'reality') {
      final r = Map<String, dynamic>.from((stream['realitySettings'] as Map?) ?? const {});
      r['serverName'] = host;
      stream['realitySettings'] = r;
    } else {
      stream['security'] = 'tls';
      stream['tlsSettings'] = <String, dynamic>{'serverName': host, 'allowInsecure': true};
    }
    proxy['streamSettings'] = stream;
  }

  static bool _hasXtlsFlow(Map<String, dynamic> proxy) {
    try {
      final settings = proxy['settings'];
      if (settings is! Map) return false;
      final vnext = settings['vnext'];
      if (vnext is! List) return false;
      for (final node in vnext) {
        if (node is! Map) continue;
        final users = node['users'];
        if (users is! List) continue;
        for (final u in users) {
          if (u is Map) {
            final flow = (u['flow'] ?? '').toString();
            if (flow.contains('xtls') || flow.contains('vision')) return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

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
    final b64 = server.link.substring('vmess://'.length).trim();
    final m = jsonDecode(utf8.decode(base64.decode(_pad(b64)))) as Map<String, dynamic>;
    final stream = _streamSettings(network: (m['net'] ?? 'tcp').toString(), security: (m['tls'] ?? '').toString(), sni: (m['sni'] ?? m['host'] ?? '').toString(), host: (m['host'] ?? '').toString(), path: (m['path'] ?? '').toString(), alpn: (m['alpn'] ?? '').toString(), fp: (m['fp'] ?? '').toString());
    return {'protocol': 'vmess', 'settings': {'vnext': [{'address': server.address, 'port': server.port, 'users': [{'id': (m['id'] ?? '').toString(), 'alterId': int.tryParse('${m['aid'] ?? 0}') ?? 0, 'security': (m['scy'] ?? 'auto').toString()}]}]}, 'streamSettings': stream};
  }

  static Map<String, dynamic> _vlessOutbound(XrayServer server) {
    final uri = Uri.parse(server.link);
    final q = uri.queryParameters;
    final stream = _streamSettings(network: q['type'] ?? 'tcp', security: q['security'] ?? '', sni: q['sni'] ?? q['host'] ?? '', host: q['host'] ?? '', path: q['path'] ?? '', alpn: q['alpn'] ?? '', fp: q['fp'] ?? '', pbk: q['pbk'] ?? '', sid: q['sid'] ?? '', serviceName: q['serviceName'] ?? '');
    return {'protocol': 'vless', 'settings': {'vnext': [{'address': server.address, 'port': server.port, 'users': [{'id': uri.userInfo, 'encryption': q['encryption'] ?? 'none', if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow']}]}]}, 'streamSettings': stream};
  }

  static Map<String, dynamic> _trojanOutbound(XrayServer server) {
    final uri = Uri.parse(server.link);
    final q = uri.queryParameters;
    return {'protocol': 'trojan', 'settings': {'servers': [{'address': server.address, 'port': server.port, 'password': uri.userInfo}]}, 'streamSettings': _streamSettings(network: q['type'] ?? 'tcp', security: q['security'] ?? 'tls', sni: q['sni'] ?? q['host'] ?? '', host: q['host'] ?? '', path: q['path'] ?? '', alpn: q['alpn'] ?? '', fp: q['fp'] ?? '')};
  }

  static Map<String, dynamic> _shadowsocksOutbound(XrayServer server) {
    final hashIdx = server.link.indexOf('#');
    final body = hashIdx >= 0 ? server.link.substring('ss://'.length, hashIdx) : server.link.substring('ss://'.length);
    String method;
    String password;
    if (body.contains('@')) {
      final userinfo = body.split('@').first;
      final decoded = userinfo.contains(':') ? userinfo : utf8.decode(base64.decode(_pad(userinfo)));
      final mp = decoded.split(':');
      method = mp.first;
      password = mp.sublist(1).join(':');
    } else {
      final decoded = utf8.decode(base64.decode(_pad(body)));
      final at = decoded.lastIndexOf('@');
      final mp = decoded.substring(0, at).split(':');
      method = mp.first;
      password = mp.sublist(1).join(':');
    }
    return {'protocol': 'shadowsocks', 'settings': {'servers': [{'address': server.address, 'port': server.port, 'method': method, 'password': password}]}, 'streamSettings': {'network': 'tcp'}};
  }

  static Map<String, dynamic> _streamSettings({required String network, required String security, String sni = '', String host = '', String path = '', String alpn = '', String fp = '', String pbk = '', String sid = '', String serviceName = ''}) {
    final stream = <String, dynamic>{'network': network.isEmpty ? 'tcp' : network};
    if (security == 'tls') {
      stream['security'] = 'tls';
      stream['tlsSettings'] = {if (sni.isNotEmpty) 'serverName': sni, if (alpn.isNotEmpty) 'alpn': alpn.split(','), if (fp.isNotEmpty) 'fingerprint': fp, 'allowInsecure': false};
    } else if (security == 'reality') {
      stream['security'] = 'reality';
      stream['realitySettings'] = {if (sni.isNotEmpty) 'serverName': sni, 'fingerprint': fp.isNotEmpty ? fp : 'chrome', if (pbk.isNotEmpty) 'publicKey': pbk, if (sid.isNotEmpty) 'shortId': sid, 'spiderX': ''};
    }
    switch (network) {
      case 'ws': stream['wsSettings'] = {'path': path.isEmpty ? '/' : path, if (host.isNotEmpty) 'headers': {'Host': host}}; break;
      case 'grpc': stream['grpcSettings'] = {'serviceName': serviceName.isNotEmpty ? serviceName : path, 'multiMode': false}; break;
      case 'h2':
      case 'http': stream['httpSettings'] = {'path': path.isEmpty ? '/' : path, if (host.isNotEmpty) 'host': host.split(',')}; break;
      case 'tcp': if (host.isNotEmpty && path.isNotEmpty) stream['tcpSettings'] = {'header': {'type': 'http', 'request': {'path': [path], 'headers': {'Host': [host]}}}}; break;
    }
    return stream;
  }

  static String _pad(String s) {
    var v = s.replaceAll('-', '+').replaceAll('_', '/');
    final mod = v.length % 4;
    if (mod > 0) v += '=' * (4 - mod);
    return v;
  }
}
