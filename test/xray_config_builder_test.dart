import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/models/warp_account.dart';
import 'package:vpn_swift/models/xray_server.dart';
import 'package:vpn_swift/services/xray_config_builder.dart';

void main() {
  group('XrayConfigBuilder.buildForPsiphon', () {
    test('builds a valid socks-routed config', () {
      final config =
          jsonDecode(XrayConfigBuilder.buildForPsiphon(1080)) as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      expect(outbounds.first['tag'], 'psiphon');
      expect(outbounds.first['protocol'], 'socks');
      final servers =
          (outbounds.first['settings'] as Map)['servers'] as List;
      expect(servers.single['address'], '127.0.0.1');
      expect(servers.single['port'], 1080);

      final inbounds = config['inbounds'] as List;
      expect(inbounds.any((i) => (i as Map)['protocol'] == 'tun'), isTrue);
    });

    test('rejects invalid ports', () {
      expect(() => XrayConfigBuilder.buildForPsiphon(0), throwsArgumentError);
      expect(() => XrayConfigBuilder.buildForPsiphon(70000),
          throwsArgumentError);
    });
  });

  group('XrayConfigBuilder.buildForProxyServer', () {
    test('builds socks outbound with credentials', () {
      final server = ProxyServer.fromLink('socks5://bob:s3cret@1.2.3.4:1080');
      final config = jsonDecode(XrayConfigBuilder.buildForProxyServer(server))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      expect(outbounds.first['tag'], 'proxy');
      expect(outbounds.first['protocol'], 'socks');
      final target =
          ((outbounds.first['settings'] as Map)['servers'] as List).single
              as Map;
      expect(target['address'], '1.2.3.4');
      expect(target['port'], 1080);
      final users = target['users'] as List;
      expect(users.single['user'], 'bob');
      expect(users.single['pass'], 's3cret');
    });

    test('builds http outbound without credentials', () {
      final server = ProxyServer.fromLink('http://2.3.4.5:8080');
      final config = jsonDecode(XrayConfigBuilder.buildForProxyServer(server))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      expect(outbounds.first['protocol'], 'http');
      final target =
          ((outbounds.first['settings'] as Map)['servers'] as List).single
              as Map;
      expect(target.containsKey('users'), isFalse);
    });
  });

  group('XrayConfigBuilder.build (vless)', () {
    XrayServer vlessServer() => XrayServer(
          id: 'x1',
          remark: 't',
          link: 'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443'
              '?security=tls&sni=example.com&type=tcp#T',
          protocol: 'vless',
          address: '1.2.3.4',
          port: 443,
        );

    test('includes proxy + direct + block outbounds without fragment', () {
      final config = jsonDecode(
              XrayConfigBuilder.build(vlessServer(), fragmentEnabled: false))
          as Map<String, dynamic>;
      final tags = (config['outbounds'] as List)
          .map((o) => (o as Map)['tag'])
          .toList();
      expect(tags, ['proxy', 'direct', 'block']);

      final proxy =
          (config['outbounds'] as List).first as Map<String, dynamic>;
      expect(proxy['protocol'], 'vless');
      final stream = proxy['streamSettings'] as Map;
      expect(stream['security'], 'tls');
      expect((stream['tlsSettings'] as Map)['serverName'], 'example.com');
    });

    test('adds fragment outbound and dialerProxy when enabled', () {
      final config = jsonDecode(
              XrayConfigBuilder.build(vlessServer(), fragmentEnabled: true))
          as Map<String, dynamic>;
      final tags = (config['outbounds'] as List)
          .map((o) => (o as Map)['tag'])
          .toList();
      expect(tags, contains('fragment'));

      final proxy =
          (config['outbounds'] as List).first as Map<String, dynamic>;
      final stream = proxy['streamSettings'] as Map;
      expect((stream['sockopt'] as Map)['dialerProxy'], 'fragment');
    });

    test('leaves Fragment off unless the setting is explicitly enabled', () {
      final config = jsonDecode(XrayConfigBuilder.build(vlessServer()))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      expect(outbounds.any((outbound) => outbound['tag'] == 'fragment'), isFalse);
      expect(
        (outbounds.first['streamSettings'] as Map).containsKey('sockopt'),
        isFalse,
      );
    });

    test('rejects TLS ClientHello fragments shorter than 6 bytes', () {
      expect(
        () => XrayConfigBuilder.build(
          vlessServer(),
          fragmentEnabled: true,
          fragmentLength: '1-5',
        ),
        throwsFormatException,
      );
    });

    test('rejects unsupported protocols', () {
      final bad = XrayServer(
        id: 'x9',
        remark: 't',
        link: 'unknown://x',
        protocol: 'wireguard',
        address: '1.1.1.1',
        port: 443,
      );
      expect(() => XrayConfigBuilder.build(bad), throwsFormatException);
    });

    test('buildForWarp selects the Aether WireGuard data-plane', () {
      final account = WarpAccount(
        id: 'id',
        accountId: 'account',
        token: 'token',
        privateKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        publicKeyBase64: base64Encode(List<int>.filled(32, 1)),
        peerPublicKeyBase64: base64Encode(List<int>.filled(32, 2)),
        peerEndpoint: '162.159.192.1:2408',
        addressV4: '172.16.0.2/32',
        addressV6: '',
        reserved: [0, 0, 0],
      );

      final config = jsonDecode(XrayConfigBuilder.buildForWarp(account))
          as Map<String, dynamic>;

      expect(config['protocol'], 'wg');
      expect(config['wireguard_data_check'], isTrue);
      expect(config['endpoint_discovery'], 'cache');
      expect(config['quick_reconnect'], isTrue);
      expect(config['config_path'], contains('__APP_FILES__'));
    });
  });
}
