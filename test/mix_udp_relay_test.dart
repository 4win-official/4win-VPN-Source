import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/screens/mix_strategy_editor_screen.dart';
import 'package:vpn_swift/services/mix_plan_builder.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  const relay = MixUdpRelay(
    host: 'relay.example.com',
    port: 4433,
    token: token,
  );
  MixStrategy strategy({MixUdpRelay? udpRelay}) => MixStrategy(
    id: 'relay-test',
    name: 'Relay test',
    hops: const [MixHop(protocol: 'proxy', serverId: 'proxy')],
    udpRelay: udpRelay,
  );
  final proxy = ProxyServer(
    id: 'proxy',
    remark: 'Proxy',
    link: 'http://127.0.0.1:8080',
    protocol: 'http',
    address: '127.0.0.1',
    port: 8080,
  );

  test('old strategies remain relay-free and new settings roundtrip', () {
    final old = strategy();
    expect(old.toJson().containsKey('udpRelay'), isFalse);
    expect(MixStrategy.fromJson(old.toJson()).udpRelay, isNull);
    final current = strategy(udpRelay: relay);
    final restored = MixStrategy.fromJson(current.toJson());
    expect(restored.udpRelay!.toJson(), relay.toJson());
    expect(restored.udpRelay!.serverName, relay.host);
    expect(restored.hops.length, 1);
    expect(restored.validationError, isNull);
  });

  test('relay validates IPv4 IPv6 hostname port and exact token contract', () {
    for (final host in ['127.0.0.1', '2001:db8::1', 'relay.example.com']) {
      expect(
        MixUdpRelay(host: host, port: 443, token: token).validationError,
        isNull,
        reason: host,
      );
    }
    for (final host in [
      '',
      '1.2.3.999',
      '::::',
      'host:443',
      'https://host',
      'a/b',
      'a b',
      'user@host',
      'a\\b',
      'fe80::1%eth0',
    ]) {
      expect(
        MixUdpRelay(host: host, port: 443, token: token).validationError,
        isNotNull,
        reason: host,
      );
    }
    for (final port in [0, -1, 65536]) {
      expect(
        MixUdpRelay(
          host: 'relay.test',
          port: port,
          token: token,
        ).validationError,
        isNotNull,
      );
    }
    for (final badToken in [
      'x' * 31,
      'x' * 257,
      '$token ',
      '$token\n',
      '$token\u00e9',
    ]) {
      final error = MixUdpRelay(
        host: 'relay.test',
        port: 443,
        token: badToken,
      ).validationError;
      expect(error, isNotNull);
      expect(error, isNot(contains(badToken)));
    }
    expect(
      MixUdpRelay(
        host: 'relay.test',
        port: 443,
        token: 'x' * 256,
      ).validationError,
      isNull,
    );
  });

  test('TLS identity may differ from dial address but must remain valid', () {
    const custom = MixUdpRelay(
      host: '192.0.2.1',
      port: 4433,
      token: token,
      serverName: 'relay.example.com',
    );
    expect(custom.validationError, isNull);
    expect(
      MixUdpRelay.fromJson(custom.toJson()).serverName,
      'relay.example.com',
    );
    expect(
      const MixUdpRelay(
        host: '192.0.2.1',
        port: 4433,
        token: token,
        serverName: 'invalid/name',
      ).validationError,
      isNotNull,
    );
    expect(
      () => MixUdpRelay.fromJson({...custom.toJson(), 'port': 443.5}),
      throwsA(isA<TypeError>()),
    );
  });

  test('plan contains optional relay metadata without modifying profiles', () {
    final old = MixPlanBuilder.build(
      strategy: strategy(),
      proxyServers: [proxy],
    );
    final original = proxy.toJson();
    final input = strategy(udpRelay: relay);
    final plan = MixPlanBuilder.build(strategy: input, proxyServers: [proxy]);
    expect(old.containsKey('udpRelay'), isFalse);
    expect(plan['udpRelay'], relay.toJson());
    expect(plan['hops'], old['hops']);
    expect(proxy.toJson(), original);
    expect(input.hops.length, 1);
    final copy = plan['udpRelay'] as Map<String, dynamic>;
    copy['token'] = 'changed';
    expect(input.udpRelay!.token, token);
    final fifty = MixStrategy(
      id: '50',
      name: 'Fifty',
      hops: List.filled(50, input.hops.single),
      udpRelay: relay,
    );
    expect(fifty.validationError, isNull);
    expect(
      MixPlanBuilder.build(strategy: fifty, proxyServers: [proxy])['hops'],
      hasLength(50),
    );
  });

  testWidgets('editor restores relay fields and obscures its token', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MixStrategyEditorScreen(
          existingStrategy: strategy(udpRelay: relay),
        ),
      ),
    );
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    final tokenField = fields.singleWhere((f) => f.controller?.text == token);
    expect(tokenField.obscureText, isTrue);
    expect(fields.any((f) => f.controller?.text == relay.host), isTrue);
    expect(fields.any((f) => f.controller?.text == '4433'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
