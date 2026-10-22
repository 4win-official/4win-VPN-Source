import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/xray_server.dart';
import 'package:vpn_swift/services/xray_config_builder.dart';

const _id = '11111111-2222-3333-4444-555555555555';

XrayServer _server(
  String protocol,
  String transport, {
  String host = 'cdn.example.com',
  String path = '/tunnel%2Fpart?ed=2560',
  String security = 'tls',
  String? mode,
  Object? extra,
}) {
  if (protocol == 'vmess') {
    return XrayServer.fromLink(
      'vmess://${base64Encode(utf8.encode(jsonEncode({'v': '2', 'add': '127.0.0.1', 'port': 443, 'id': _id, 'net': transport, 'tls': security, 'host': host, 'path': path, 'sni': 'tls.example.com', 'alpn': 'h2,http/1.1', 'fp': 'chrome', if (mode != null) 'mode': mode, if (extra != null) 'extra': extra})))}',
    );
  }
  return XrayServer.fromLink(
    Uri(
      scheme: protocol,
      userInfo: protocol == 'trojan' ? 'test-password' : _id,
      host: '127.0.0.1',
      port: 443,
      queryParameters: {
        'type': transport,
        'security': security,
        'host': host,
        'path': path,
        'sni': 'tls.example.com',
        'alpn': 'h2,http/1.1',
        'fp': 'chrome',
        if (mode != null) 'mode': mode,
        if (extra != null) 'extra': extra is String ? extra : jsonEncode(extra),
        if (security == 'reality') ...{
          'pbk': 'test-public-key',
          'sid': '0123456789abcdef',
        },
      },
    ).toString(),
  );
}

Map<String, dynamic> _proxy(String config) =>
    (jsonDecode(config)['outbounds'] as List).first as Map<String, dynamic>;

void main() {
  group('HTTP transports shared by connection and URL ping', () {
    for (final protocol in ['vless', 'vmess', 'trojan']) {
      for (final transport in ['xhttp', 'splithttp', 'httpupgrade']) {
        for (final fragment in [false, true]) {
          test(
            '$protocol/$transport fragment=$fragment preserves settings',
            () {
              final server = _server(protocol, transport);
              final connection = _proxy(
                XrayConfigBuilder.build(server, fragmentEnabled: fragment),
              );
              final ping = _proxy(
                XrayConfigBuilder.buildForDelayTest(
                  server,
                  fragmentEnabled: fragment,
                ),
              );
              expect(connection, ping);
              final stream = connection['streamSettings'] as Map;
              final isXhttp = transport != 'httpupgrade';
              expect(stream['network'], isXhttp ? 'xhttp' : 'httpupgrade');
              expect(
                stream[isXhttp ? 'xhttpSettings' : 'httpupgradeSettings'],
                {
                  'host': 'cdn.example.com',
                  'path': '/tunnel%2Fpart?ed=2560',
                  if (isXhttp) 'mode': 'auto',
                },
              );
              expect(stream.containsKey('wsSettings'), isFalse);
              expect(stream.containsKey('httpSettings'), isFalse);
              expect(stream['security'], 'tls');
              expect(stream['tlsSettings'], {
                'serverName': 'tls.example.com',
                'alpn': ['h2', 'http/1.1'],
                'fingerprint': 'chrome',
                'allowInsecure': false,
              });
              if (fragment) {
                expect(stream['sockopt'], {'dialerProxy': 'fragment'});
              } else {
                expect(stream.containsKey('sockopt'), isFalse);
              }
            },
          );
        }
      }
    }

    for (final transport in ['xhttp', 'splithttp', 'httpupgrade']) {
      test('$transport defaults to root path without an invented host', () {
        final proxy = _proxy(
          XrayConfigBuilder.buildForDelayTest(
            _server('vless', transport, path: '', host: '', security: 'none'),
            fragmentEnabled: false,
          ),
        );
        final stream = proxy['streamSettings'] as Map;
        expect(
          stream[transport == 'httpupgrade'
              ? 'httpupgradeSettings'
              : 'xhttpSettings'],
          {'path': '/', if (transport != 'httpupgrade') 'mode': 'auto'},
        );
        expect(stream.containsKey('security'), isFalse);
      });
    }

    for (final protocol in ['vless', 'vmess', 'trojan']) {
      for (final mode in ['auto', 'packet-up', 'stream-up', 'stream-one']) {
        test('$protocol preserves XHTTP $mode and nested extra', () {
          final extra = {
            'noGRPCHeader': true,
            'xPaddingBytes': '100-200',
            'headers': {'X-Test': '%2F+value'},
            'xmux': {'maxConcurrency': '8-16'},
            'downloadSettings': {
              'address': 'download.example.com',
              'port': 443,
              'network': 'xhttp',
              'xhttpSettings': {'path': '/download', 'mode': 'stream-one'},
              'security': 'tls',
              'tlsSettings': {'serverName': 'download.example.com'},
            },
          };
          final server = _server(protocol, 'xhttp', mode: mode, extra: extra);
          final connection = _proxy(XrayConfigBuilder.build(server));
          final ping = _proxy(XrayConfigBuilder.buildForDelayTest(server));
          expect(connection, ping);
          final settings = connection['streamSettings']['xhttpSettings'];
          expect(settings['mode'], mode);
          expect(settings['extra'], extra);
        });
      }
      test('$protocol accepts JSON-string XHTTP extra', () {
        final server = _server(
          protocol,
          'xhttp',
          extra: jsonEncode({'noGRPCHeader': true}),
        );
        expect(
          _proxy(
            XrayConfigBuilder.build(server),
          )['streamSettings']['xhttpSettings']['extra'],
          {'noGRPCHeader': true},
        );
      });
    }

    for (final extra in ['not-json', '[]', 'null', '42', 'true']) {
      test('rejects invalid XHTTP extra: $extra for connection and ping', () {
        final server = _server('vless', 'xhttp', extra: extra);
        expect(() => XrayConfigBuilder.build(server), throwsFormatException);
        expect(
          () => XrayConfigBuilder.buildForDelayTest(server),
          throwsFormatException,
        );
      });
    }

    for (final protocol in ['vless', 'trojan']) {
      test('$protocol XHTTP retains REALITY authentication for ping too', () {
        final server = _server(protocol, 'xhttp', security: 'reality');
        final connection = _proxy(XrayConfigBuilder.build(server));
        expect(connection, _proxy(XrayConfigBuilder.buildForDelayTest(server)));
        expect(connection['streamSettings']['realitySettings'], {
          'serverName': 'tls.example.com',
          'fingerprint': 'chrome',
          'publicKey': 'test-public-key',
          'shortId': '0123456789abcdef',
          'spiderX': '',
        });
      });
    }

    test('proxy mode uses the same XHTTP outbound as VPN and ping', () {
      final server = _server('vless', 'xhttp');
      expect(
        _proxy(XrayConfigBuilder.build(server, proxyMode: true)),
        _proxy(XrayConfigBuilder.buildForDelayTest(server)),
      );
    });

    test('fragment host override preserves transport host and path', () {
      final server = _server('vless', 'httpupgrade');
      final connection = _proxy(
        XrayConfigBuilder.build(server, fragmentHost: 'fake.example.com'),
      );
      expect(
        connection,
        _proxy(
          XrayConfigBuilder.buildForDelayTest(
            server,
            fragmentHost: 'fake.example.com',
          ),
        ),
      );
      final stream = connection['streamSettings'];
      expect(stream['tlsSettings']['serverName'], 'fake.example.com');
      expect(stream['httpupgradeSettings']['host'], 'cdn.example.com');
      expect(stream['httpupgradeSettings']['path'], '/tunnel%2Fpart?ed=2560');
    });

    for (final protocol in ['vless', 'vmess', 'trojan']) {
      for (final transport in ['xhttp', 'splithttp']) {
        test('$protocol/$transport compression never adds generic Mux', () {
          final server = _server(
            protocol,
            transport,
            extra: {
              'xmux': {'maxConcurrency': '8-16'},
            },
          );
          final connection = _proxy(
            XrayConfigBuilder.build(server, trafficCompression: true),
          );
          expect(connection.containsKey('mux'), isFalse);
          expect(
            connection,
            _proxy(XrayConfigBuilder.buildForDelayTest(server)),
          );
          expect(connection['streamSettings']['xhttpSettings']['extra'], {
            'xmux': {'maxConcurrency': '8-16'},
          });
        });
      }
    }

    for (final transport in ['tcp', 'ws', 'grpc', 'httpupgrade']) {
      test('$transport retains existing compression Mux behavior', () {
        final server = _server('vless', transport);
        final connection = _proxy(
          XrayConfigBuilder.build(server, trafficCompression: true),
        );
        expect(connection['mux'], {
          'enabled': true,
          'concurrency': 8,
          'xudpConcurrency': 8,
          'xudpProxyUDP443': 'reject',
        });
      });
    }

    test('XTLS flow still prevents generic Mux on TCP', () {
      final server = XrayServer.fromLink(
        'vless://$_id@127.0.0.1:443?type=tcp&security=tls&flow=xtls-rprx-vision',
      );
      expect(
        _proxy(
          XrayConfigBuilder.build(server, trafficCompression: true),
        ).containsKey('mux'),
        isFalse,
      );
    });

    for (final transport in ['tcp', 'ws', 'grpc', 'h2', 'http']) {
      test('preserves existing $transport connection and ping behavior', () {
        final server = _server('vless', transport, extra: 'not-json');
        final connection = _proxy(XrayConfigBuilder.build(server));
        expect(connection, _proxy(XrayConfigBuilder.buildForDelayTest(server)));
        final stream = connection['streamSettings'] as Map;
        expect(stream['network'], transport);
        expect(stream.containsKey('xhttpSettings'), isFalse);
        expect(stream.containsKey('httpupgradeSettings'), isFalse);
        if (transport == 'ws') {
          expect(stream['wsSettings'], {
            'path': '/tunnel%2Fpart?ed=2560',
            'headers': {'Host': 'cdn.example.com'},
          });
        }
        if (transport == 'h2' || transport == 'http') {
          expect(stream['httpSettings'], {
            'path': '/tunnel%2Fpart?ed=2560',
            'host': ['cdn.example.com'],
          });
        }
      });
    }
  });
}
