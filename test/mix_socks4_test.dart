import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/services/mix_plan_builder.dart';
import 'package:vpn_swift/services/xray_config_builder.dart';

void main() {
  test('SOCKS4 and SOCKS4a receive real adapter metadata only in Mix', () {
    for (final scheme in ['socks4', 'socks4a']) {
      final server = ProxyServer.fromLink('$scheme://user@192.0.2.1:1080');
      final saved = jsonEncode(server.toJson());
      final standalone = XrayConfigBuilder.buildForProxyServer(server);
      final strategy = MixStrategy(
        id: scheme,
        name: scheme,
        hops: [MixHop(protocol: 'proxy', serverId: server.id)],
      );
      final plan = MixPlanBuilder.build(
        strategy: strategy,
        proxyServers: [server],
      );
      final hop = (plan['hops'] as List).single as Map<String, dynamic>;
      expect(hop['protocol'], 'proxy');
      expect(hop['socks4'], {
        'host': '192.0.2.1',
        'port': 1080,
        'userId': 'user',
      });
      expect(jsonEncode(server.toJson()), saved);
      expect(XrayConfigBuilder.buildForProxyServer(server), standalone);
      final group = MixStrategy(
        id: 'repeat',
        name: 'Repeat',
        hops: List.filled(50, strategy.hops.single),
      );
      final repeated = MixPlanBuilder.build(
        strategy: group,
        proxyServers: [server],
      );
      expect(repeated['hops'], hasLength(50));
      expect(
        (repeated['hops'] as List).every((hop) => hop['socks4'] != null),
        isTrue,
      );
    }
  });

  test('SOCKS5 and HTTP profiles never request the SOCKS4 adapter', () {
    for (final scheme in ['socks5', 'http', 'https']) {
      final server = ProxyServer.fromLink('$scheme://192.0.2.1:1080');
      final strategy = MixStrategy(
        id: scheme,
        name: scheme,
        hops: [MixHop(protocol: 'proxy', serverId: server.id)],
      );
      final plan = MixPlanBuilder.build(
        strategy: strategy,
        proxyServers: [server],
      );
      expect((plan['hops'] as List).single.containsKey('socks4'), isFalse);
    }
  });
}
