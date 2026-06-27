import 'dart:convert';

import '../models/xray_server.dart';

/// Builds a complete Xray JSON config (the standard Xray config format that
/// libv2ray / v2rayNG's core consumes via `startLoop`).
///
/// The killer feature wired here is **TLS ClientHello fragmentation** (the REAL
/// "fragment"): a `freedom` outbound with
///   "fragment": { "packets": "tlshello", "length": "...", "interval": "..." }
/// is used as the `dialerProxy` for the main proxy outbound. This splits the
/// initial TLS ClientHello packet (which carries the SNI/server address that
/// DPI / filtering inspects) into small chunks sent with tiny time delays, so
/// the censor can't analyse the whole handshake; the pieces reassemble at the
/// server and the connection passes through.
class XrayConfigBuilder {
  /// Build the config JSON string for [server].
  ///
  /// [fragmentEnabled] toggles the TLS ClientHello fragmentation outbound.
  /// [fragmentLength]/[fragmentInterval] are Xray range strings, e.g. "1-3" /
  /// "10-20" (bytes per packet / ms between packets).
  static String build(
    XrayServer server, {
    bool fragmentEnabled = true,
    String fragmentPackets = 'tlshello',
    String fragmentLength = '1-3',
    String fragmentInterval = '10-20',
  }) {
    final outbounds = <Map<String, dynamic>>[];

    // 1) Main proxy outbound parsed from the share link.
    final proxy = _buildProxyOutbound(server);

    // 2) If fragmentation is enabled, route the proxy's transport through a
    //    freedom outbound that performs TLS ClientHello fragmentation.
    if (fragmentEnabled) {
      // Tell the proxy outbound to dial through the fragment outbound.
      // NOTE: rebuild the maps as <String, dynamic> — outbound builders may
      // return map literals that Dart infers as Map<String,String>, which
      // would throw when we insert non-String values (e.g. nested maps).
      final stream = Map<String, dynamic>.from(
          (proxy['streamSettings'] as Map?) ?? const {});
      final sockopt = Map<String, dynamic>.from(
          (stream['sockopt'] as Map?) ?? const {});
      sockopt['dialerProxy'] = 'fragment';
      stream['sockopt'] = sockopt;
      proxy['streamSettings'] = stream;
    }

    // 🔴 IMPORTANT: Xray sends traffic with no matching routing rule to the
    // FIRST outbound in the list. So "proxy" MUST be first, otherwise all
    // traffic would leak through the freedom/fragment outbound (i.e. direct,
    // unprotected). v2rayNG keeps "proxy" as the first outbound for the same
    // reason.
    proxy['tag'] = 'proxy';
    outbounds.add(proxy);

    if (fragmentEnabled) {
      // The freedom "fragment" dialer — referenced by tag via dialerProxy, so
      // its position in the list does not affect default routing.
      outbounds.add({
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': {
          'domainStrategy': 'UseIP',
          'fragment': {
            'packets': fragmentPackets,
            'length': fragmentLength,
            'interval': fragmentInterval,
          },
        },
        'streamSettings': {
          'sockopt': {
            'tcpNoDelay': true,
            'tcpKeepAliveIdle': 100,
          },
        },
      });
    }

    // 3) Direct + block fallbacks.
    outbounds.add({
      'tag': 'direct',
      'protocol': 'freedom',
      'settings': {'domainStrategy': 'UseIP'},
    });
    outbounds.add({
      'tag': 'block',
      'protocol': 'blackhole',
      'settings': {'response': {'type': 'http'}},
    });

    final config = <String, dynamic>{
      'stats': <String, dynamic>{},
      'log': {'loglevel': 'warning'},
      'policy': {
        'levels': {
          '8': {
            'handshake': 4,
            'connIdle': 300,
            'uplinkOnly': 1,
            'downlinkOnly': 1,
          },
        },
        'system': {
          'statsOutboundUplink': true,
          'statsOutboundDownlink': true,
        },
      },
      'dns': {
        'servers': ['1.1.1.1', '8.8.8.8', 'localhost'],
      },
      'inbounds': [
        // SOCKS inbound (kept for proxy-sharing / local apps).
        {
          'tag': 'socks',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {
            'auth': 'noauth',
            'udp': true,
            'userLevel': 8,
          },
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        },
        // 🔴 CRITICAL: the TUN inbound. When startLoop() receives the VpnService
        // TUN file descriptor, the core's built-in tun inbound binds to that fd
        // and pumps ALL device traffic through the routing/outbounds below.
        // Without this inbound the fd is never used and NOTHING is tunnelled —
        // which is exactly why connections used to "succeed" but pass no data.
        // This mirrors v2rayNG's assets/v2ray_config_with_tun.json.
        {
          'tag': 'tun',
          'protocol': 'tun',
          'settings': {
            'name': 'xray0',
            'MTU': 1500,
            'userLevel': 8,
          },
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        },
      ],
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          // Send private / LAN ranges straight out (don't tunnel local traffic).
          // Explicit CIDRs are used instead of "geoip:private" so this never
          // depends on the geoip.dat asset loading correctly.
          {
            'type': 'field',
            'ip': [
              '0.0.0.0/8',
              '10.0.0.0/8',
              '100.64.0.0/10',
              '127.0.0.0/8',
              '169.254.0.0/16',
              '172.16.0.0/12',
              '192.168.0.0/16',
              '::1/128',
              'fc00::/7',
              'fe80::/10',
            ],
            'outboundTag': 'direct',
          },
        ],
      },
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  /// Builds a minimal proxy-only config used by the core's
  /// measureOutboundDelay (the "real delay" test). It has just the proxy
  /// outbound (optionally through the fragment dialer) — no inbounds/tun.
  static String buildForDelayTest(
    XrayServer server, {
    bool fragmentEnabled = true,
    String fragmentPackets = 'tlshello',
    String fragmentLength = '1-3',
    String fragmentInterval = '10-20',
  }) {
    final proxy = _buildProxyOutbound(server);
    final outbounds = <Map<String, dynamic>>[];

    if (fragmentEnabled) {
      final stream = Map<String, dynamic>.from(
          (proxy['streamSettings'] as Map?) ?? const {});
      final sockopt = Map<String, dynamic>.from(
          (stream['sockopt'] as Map?) ?? const {});
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
        'settings': {
          'domainStrategy': 'UseIP',
          'fragment': {
            'packets': fragmentPackets,
            'length': fragmentLength,
            'interval': fragmentInterval,
          },
        },
        'streamSettings': {
          'sockopt': {'tcpNoDelay': true},
        },
      });
    }

    final config = <String, dynamic>{
      'log': {'loglevel': 'none'},
      'outbounds': outbounds,
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  /// Build the main proxy outbound from the server's share link.
  static Map<String, dynamic> _buildProxyOutbound(XrayServer server) {
    switch (server.protocol) {
      case 'vmess':
        return _vmessOutbound(server);
      case 'vless':
        return _vlessOutbound(server);
      case 'trojan':
        return _trojanOutbound(server);
      case 'shadowsocks':
        return _shadowsocksOutbound(server);
      default:
        throw FormatException('Unsupported protocol: ${server.protocol}');
    }
  }

  // ---------------- VMess ----------------
  static Map<String, dynamic> _vmessOutbound(XrayServer server) {
    final b64 = server.link.substring('vmess://'.length).trim();
    final m = jsonDecode(utf8.decode(base64.decode(_pad(b64))))
        as Map<String, dynamic>;
    final net = (m['net'] ?? 'tcp').toString();
    final tls = (m['tls'] ?? '').toString();
    final stream = _streamSettings(
      network: net,
      security: tls,
      sni: (m['sni'] ?? m['host'] ?? '').toString(),
      host: (m['host'] ?? '').toString(),
      path: (m['path'] ?? '').toString(),
      alpn: (m['alpn'] ?? '').toString(),
      fp: (m['fp'] ?? '').toString(),
    );
    return {
      'protocol': 'vmess',
      'settings': {
        'vnext': [
          {
            'address': server.address,
            'port': server.port,
            'users': [
              {
                'id': (m['id'] ?? '').toString(),
                'alterId': int.tryParse('${m['aid'] ?? 0}') ?? 0,
                'security': (m['scy'] ?? 'auto').toString(),
              }
            ],
          }
        ],
      },
      'streamSettings': stream,
    };
  }

  // ---------------- VLESS ----------------
  static Map<String, dynamic> _vlessOutbound(XrayServer server) {
    final uri = Uri.parse(server.link);
    final q = uri.queryParameters;
    final uuid = uri.userInfo;
    final stream = _streamSettings(
      network: q['type'] ?? 'tcp',
      security: q['security'] ?? '',
      sni: q['sni'] ?? q['host'] ?? '',
      host: q['host'] ?? '',
      path: q['path'] ?? '',
      alpn: q['alpn'] ?? '',
      fp: q['fp'] ?? '',
      flow: q['flow'] ?? '',
      pbk: q['pbk'] ?? '',
      sid: q['sid'] ?? '',
      serviceName: q['serviceName'] ?? '',
    );
    return {
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': server.address,
            'port': server.port,
            'users': [
              {
                'id': uuid,
                'encryption': q['encryption'] ?? 'none',
                if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
              }
            ],
          }
        ],
      },
      'streamSettings': stream,
    };
  }

  // ---------------- Trojan ----------------
  static Map<String, dynamic> _trojanOutbound(XrayServer server) {
    final uri = Uri.parse(server.link);
    final q = uri.queryParameters;
    final password = uri.userInfo;
    final stream = _streamSettings(
      network: q['type'] ?? 'tcp',
      security: q['security'] ?? 'tls',
      sni: q['sni'] ?? q['host'] ?? '',
      host: q['host'] ?? '',
      path: q['path'] ?? '',
      alpn: q['alpn'] ?? '',
      fp: q['fp'] ?? '',
    );
    return {
      'protocol': 'trojan',
      'settings': {
        'servers': [
          {
            'address': server.address,
            'port': server.port,
            'password': password,
          }
        ],
      },
      'streamSettings': stream,
    };
  }

  // ---------------- Shadowsocks ----------------
  static Map<String, dynamic> _shadowsocksOutbound(XrayServer server) {
    final hashIdx = server.link.indexOf('#');
    final body = hashIdx >= 0
        ? server.link.substring('ss://'.length, hashIdx)
        : server.link.substring('ss://'.length);
    String method;
    String password;
    if (body.contains('@')) {
      final userinfo = body.split('@').first;
      final decoded = userinfo.contains(':')
          ? userinfo
          : utf8.decode(base64.decode(_pad(userinfo)));
      final mp = decoded.split(':');
      method = mp.first;
      password = mp.sublist(1).join(':');
    } else {
      final decoded = utf8.decode(base64.decode(_pad(body)));
      final at = decoded.lastIndexOf('@');
      final cred = decoded.substring(0, at);
      final mp = cred.split(':');
      method = mp.first;
      password = mp.sublist(1).join(':');
    }
    return {
      'protocol': 'shadowsocks',
      'settings': {
        'servers': [
          {
            'address': server.address,
            'port': server.port,
            'method': method,
            'password': password,
          }
        ],
      },
      'streamSettings': <String, dynamic>{
        'network': 'tcp',
      },
    };
  }

  /// Common transport (streamSettings) builder.
  static Map<String, dynamic> _streamSettings({
    required String network,
    required String security,
    String sni = '',
    String host = '',
    String path = '',
    String alpn = '',
    String fp = '',
    String flow = '',
    String pbk = '',
    String sid = '',
    String serviceName = '',
  }) {
    final net = network.isEmpty ? 'tcp' : network;
    final stream = <String, dynamic>{
      'network': net,
    };

    // Security (tls / reality / none).
    if (security == 'tls') {
      stream['security'] = 'tls';
      stream['tlsSettings'] = {
        if (sni.isNotEmpty) 'serverName': sni,
        if (alpn.isNotEmpty) 'alpn': alpn.split(','),
        if (fp.isNotEmpty) 'fingerprint': fp,
        'allowInsecure': false,
      };
    } else if (security == 'reality') {
      stream['security'] = 'reality';
      stream['realitySettings'] = {
        if (sni.isNotEmpty) 'serverName': sni,
        if (fp.isNotEmpty) 'fingerprint': fp else 'fingerprint': 'chrome',
        if (pbk.isNotEmpty) 'publicKey': pbk,
        if (sid.isNotEmpty) 'shortId': sid,
        'spiderX': '',
      };
    }

    // Transport-specific settings.
    switch (net) {
      case 'ws':
        stream['wsSettings'] = {
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'headers': {'Host': host},
        };
        break;
      case 'grpc':
        stream['grpcSettings'] = {
          'serviceName': serviceName.isNotEmpty ? serviceName : path,
          'multiMode': false,
        };
        break;
      case 'h2':
      case 'http':
        stream['httpSettings'] = {
          'path': path.isEmpty ? '/' : path,
          if (host.isNotEmpty) 'host': host.split(','),
        };
        break;
      case 'tcp':
        if (host.isNotEmpty && (path.isNotEmpty)) {
          stream['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                'path': [path],
                'headers': {
                  'Host': [host],
                },
              },
            },
          };
        }
        break;
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
