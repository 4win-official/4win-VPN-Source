import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/mix_diagnostics.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';

class TestVpnProvider extends VpnProvider {
  @override
  Future<void> loadServers({bool forceRefresh = false}) async {}

  @override
  Future<void> loadXrayServers() async {}

  @override
  Future<void> loadProxyServers() async {}

  @override
  Future<void> loadSelectedProtocol() async {}

  @override
  Future<void> loadOpenVpnConfigs() async {}
}

final _xray = {
  'id': 'x1',
  'remark': 'test xray',
  'link': 'vless://uuid@example.com:443?type=tcp#test',
  'protocol': 'vless',
  'address': 'example.com',
  'port': 443,
  'addedAt': '2025-01-01T00:00:00.000Z',
  'group': '',
  'encrypted': false,
};

final _proxy = {
  'id': 'p1',
  'remark': 'test proxy',
  'link': 'socks5://proxy.example.com:1080',
  'protocol': 'socks5',
  'address': 'proxy.example.com',
  'port': 1080,
  'username': '',
  'password': '',
  'addedAt': '2025-01-01T00:00:00.000Z',
  'group': '',
  'encrypted': false,
};

MixStrategy _strategy() => MixStrategy(
  id: 'mix-1',
  name: 'Test chain',
  hops: const [MixHop(protocol: 'xray', serverId: 'x1')],
);

MixStrategy _nativeStrategy() => MixStrategy(
  id: 'mix-native',
  name: 'Native chain',
  hops: const [MixHop(protocol: 'psiphon', serverId: 'default')],
);

Future<void> _prefs({
  String mode = 'vpn',
  List<MixStrategy> strategies = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'psiphon_default_v1': true,
    'xray_default_v1': true,
    'selected_protocol': 'xray',
    'selected_xray_server': 'standalone-xray',
    'xray_selected_group': 'standalone-group',
    'connection_mode': mode,
    'xray_servers': <String>[jsonEncode(_xray)],
    'proxy_servers': <String>[jsonEncode(_proxy)],
    'mix_strategies_v1': strategies
        .map((strategy) => jsonEncode(strategy.toJson()))
        .toList(),
    if (strategies.isNotEmpty) 'mix_selected_strategy_v1': strategies.first.id,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.forwin.vpn/xray');
  late List<String> calls;
  late Map<String, dynamic> responses;

  setUp(() async {
    calls = [];
    responses = {
      'requestXrayPermission': true,
      'measureDelay': 42,
      'connectMix': true,
      'connectMixPlan': 42,
      'disconnectMixPlan': true,
      'isXrayRunning': true,
      'isXrayReconnecting': false,
      'disconnectXray': true,
      'queryXrayStats': <String, int>{'uplink': 0, 'downlink': 0},
    };
    await _prefs();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'connectMixPlan') {
            final plan =
                jsonDecode((call.arguments as Map)['planJson'] as String)
                    as Map;
            final diagnostic = responses['getMixDiagnostics'];
            if (diagnostic is Map) {
              diagnostic['attemptId'] = plan['diagnosticsAttemptId'];
            }
          }
          final response = responses[call.method];
          if (response is Future<dynamic>) return response;
          return response;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<TestVpnProvider> providerWith(MixStrategy? strategy) async {
    await _prefs(strategies: strategy == null ? const [] : [strategy]);
    final provider = TestVpnProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.switchProtocol('mix');
    return provider;
  }

  for (final native in [false, true]) {
    test(
      'home Mix ping is fresh and preserves the chain (native=$native)',
      () async {
        final strategy = MixStrategy(
          id: 'ordered-ping',
          name: 'Ordered ping chain',
          hops: [
            const MixHop(protocol: 'proxy', serverId: 'p1'),
            if (native) const MixHop(protocol: 'psiphon', serverId: 'default'),
            const MixHop(protocol: 'xray', serverId: 'x1'),
          ],
        );
        final provider = await providerWith(strategy);
        await provider.connect();
        final prefs = await SharedPreferences.getInstance();
        final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
        calls.clear();
        final pending = Completer<int>();
        responses['measureMixDelay'] = pending.future;
        final ping = provider.manualXrayPing();
        expect(provider.xrayPinging, isTrue);
        expect(provider.currentPing, isNull);
        await provider
            .manualXrayPing(); // Double taps must not start another probe.
        pending.complete(73);
        await ping;
        expect(calls, ['measureMixDelay']);
        expect(provider.currentPing, 73);
        expect(provider.pingFailed, isFalse);
        expect(provider.xrayPinging, isFalse);
        responses['measureMixDelay'] = 0;
        await provider.manualXrayPing();
        expect(provider.currentPing, 0);
        expect(calls.where((call) => call != 'getMixDiagnostics'), [
          'measureMixDelay',
          'measureMixDelay',
        ]);
        expect(provider.selectedMixStrategy!.toJson(), strategy.toJson());
        expect({
          for (final key in prefs.getKeys()) key: prefs.get(key),
        }, before);
        expect(provider.isConnected, isTrue);
        await provider.disconnect();
        provider.dispose();
      },
    );
  }

  test('Mix ping failure allows retry without disconnecting', () async {
    final provider = await providerWith(_nativeStrategy());
    await provider.connect();
    for (final failure in [-1, null, 'invalid']) {
      responses['measureMixDelay'] = failure;
      await provider.manualXrayPing();
      expect(provider.currentPing, isNull);
      expect(provider.pingFailed, isTrue);
      expect(provider.xrayPinging, isFalse);
      expect(provider.isConnected, isTrue);
    }
    responses['measureMixDelay'] = 91;
    await provider.manualXrayPing();
    expect(provider.currentPing, 91);
    expect(provider.pingFailed, isFalse);
    await provider.disconnect();
    provider.dispose();
  });

  test('disconnected Mix does not start a ping', () async {
    final provider = await providerWith(_strategy());
    calls.clear();
    await provider.manualXrayPing();
    expect(calls, isEmpty);
    expect(provider.xrayPinging, isFalse);
    provider.dispose();
  });

  for (final action in ['disconnect', 'switch', 'reconnect', 'dispose']) {
    test('late Mix ping is ignored after $action', () async {
      final provider = await providerWith(_strategy());
      await provider.connect();
      final pending = Completer<int>();
      responses['measureMixDelay'] = pending.future;
      final ping = provider.manualXrayPing();
      await Future<void>.delayed(Duration.zero);
      if (action == 'dispose') {
        provider.dispose();
      } else if (action == 'switch') {
        await provider.switchProtocol('xray');
      } else {
        await provider.disconnect();
        if (action == 'reconnect') await provider.connect();
      }
      pending.complete(999);
      await ping;
      if (action != 'dispose') {
        expect(provider.currentPing, action == 'reconnect' ? 42 : null);
        expect(provider.xrayPinging, isFalse);
        await provider.disconnect();
        provider.dispose();
      }
    });
  }

  test(
    'does not start native tunnel when no Mix strategy is selected',
    () async {
      final provider = await providerWith(null);
      await provider.connect();

      expect(calls, isNot(contains('connectMix')));
      expect(provider.status, VpnConnectionStatus.error);
      provider.dispose();
    },
  );

  test(
    'native coordinator returns delay and disconnects the complete chain',
    () async {
      final provider = await providerWith(_nativeStrategy());
      await provider.connect();

      expect(calls, contains('connectMixPlan'));
      expect(calls, isNot(contains('connectMix')));
      expect(provider.currentPing, 42);
      expect(provider.status, VpnConnectionStatus.connected);

      await provider.disconnect();
      expect(calls, contains('disconnectMixPlan'));
      expect(provider.status, VpnConnectionStatus.disconnected);
      provider.dispose();
    },
  );

  test('relay on an otherwise Xray-only chain uses the coordinator', () async {
    final strategy = MixStrategy(
      id: 'relay',
      name: 'Relay',
      hops: _strategy().hops,
      udpRelay: const MixUdpRelay(
        host: 'relay.example',
        port: 4433,
        token: '0123456789abcdef0123456789abcdef',
      ),
    );
    final provider = await providerWith(strategy);
    await provider.connect();
    expect(provider.status, VpnConnectionStatus.connected);
    expect(calls, contains('connectMixPlan'));
    expect(calls, isNot(contains('connectMix')));
    await provider.disconnect();
    expect(calls, contains('disconnectMixPlan'));
    provider.dispose();
  });

  test('SOCKS4-only chain uses its real coordinator adapter', () async {
    final strategy = MixStrategy(
      id: 'four',
      name: 'SOCKS4',
      hops: const [MixHop(protocol: 'proxy', serverId: 'p1')],
    );
    final provider = await providerWith(strategy);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('proxy_servers', [
      jsonEncode({
        ..._proxy,
        'protocol': 'socks4',
        'link': 'socks4://proxy.example.com:1080',
      }),
    ]);
    await provider.connect();
    expect(provider.status, VpnConnectionStatus.connected);
    expect(calls, contains('connectMixPlan'));
    expect(calls, isNot(contains('connectMix')));
    await provider.disconnect();
    provider.dispose();
  });

  test(
    'proxy-only mode rejects Mix before permission or native connect',
    () async {
      await _prefs(mode: 'proxy', strategies: [_strategy()]);
      final provider = TestVpnProvider();
      await Future<void>.delayed(Duration.zero);
      await provider.switchProtocol('mix');

      await provider.connect();

      expect(calls, isNot(contains('requestXrayPermission')));
      expect(calls, isNot(contains('connectMix')));
      expect(provider.status, VpnConnectionStatus.error);
      provider.dispose();
    },
  );

  test(
    'successful Mix probes the complete chain before native connect and preserves standalone settings',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final before = {
        'selected_protocol': prefs.getString('selected_protocol'),
        'selected_xray_server': prefs.getString('selected_xray_server'),
        'xray_selected_group': prefs.getString('xray_selected_group'),
        'connection_mode': prefs.getString('connection_mode'),
      };
      final provider = await providerWith(_strategy());

      await provider.connect();

      expect(provider.status, VpnConnectionStatus.connected);
      expect(
        calls.indexOf('measureDelay'),
        lessThan(calls.indexOf('connectMix')),
      );
      expect(calls, contains('requestXrayPermission'));
      final after = {
        'selected_protocol': prefs.getString('selected_protocol'),
        'selected_xray_server': prefs.getString('selected_xray_server'),
        'xray_selected_group': prefs.getString('xray_selected_group'),
        'connection_mode': prefs.getString('connection_mode'),
      };
      expect(after, before);

      await provider.disconnect();
      expect(calls, contains('disconnectXray'));
      expect(provider.status, VpnConnectionStatus.disconnected);
      provider.dispose();
    },
  );

  test('cancelling delayed preflight never starts the tunnel', () async {
    final probe = Completer<int>();
    responses['measureDelay'] = probe.future;
    final provider = await providerWith(_strategy());

    final connecting = provider.connect();
    await Future<void>.delayed(Duration.zero);
    await provider.disconnect();
    probe.complete(42);
    await connecting;

    expect(calls, contains('measureDelay'));
    expect(calls, isNot(contains('connectMix')));
    expect(provider.status, VpnConnectionStatus.disconnected);
    expect(provider.mixDiagnostics!.phase, 'Connection cancelled');
    provider.dispose();
  });

  test(
    'Mix monitor leaves a notification reconnect and its strategy intact',
    () async {
      final provider = await providerWith(_nativeStrategy());
      await provider.connect();
      calls.clear();
      responses['isXrayRunning'] = false;
      responses['isXrayReconnecting'] = true;
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(calls, contains('isXrayReconnecting'));
      expect(calls, isNot(contains('disconnectMixPlan')));
      expect(calls, isNot(contains('disconnectXray')));
      expect(provider.status, VpnConnectionStatus.connected);
      expect(provider.selectedMixStrategy?.id, _nativeStrategy().id);

      responses['isXrayRunning'] = true;
      responses['isXrayReconnecting'] = false;
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(provider.status, VpnConnectionStatus.connected);
      expect(calls, isNot(contains('disconnectMixPlan')));
      provider.dispose();
    },
  );

  test(
    'Mix monitor still reports a terminal failure after reconnect ends',
    () async {
      final provider = await providerWith(_nativeStrategy());
      await provider.connect();
      calls.clear();
      responses['isXrayRunning'] = false;
      responses['isXrayReconnecting'] = false;
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(calls, contains('disconnectMixPlan'));
      expect(provider.status, VpnConnectionStatus.error);
      provider.dispose();
    },
  );

  test(
    'switching protocol during late native connect drains cleanup',
    () async {
      final nativeConnect = Completer<bool>();
      responses['connectMix'] = nativeConnect.future;
      final provider = await providerWith(_strategy());

      final connecting = provider.connect();
      await Future<void>.delayed(Duration.zero);
      while (!calls.contains('connectMix')) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final switching = provider.switchProtocol('xray');
      nativeConnect.complete(true);
      await switching;
      await connecting;

      expect(provider.selectedProtocol, 'xray');
      expect(calls.where((method) => method == 'disconnectXray'), isNotEmpty);
      expect(provider.status, isNot(VpnConnectionStatus.connected));
      provider.dispose();
    },
  );
  test(
    'native failure preserves exact reached/failed/pending positions',
    () async {
      final strategy = MixStrategy(
        id: 'repeat',
        name: 'Repeated',
        hops: const [
          MixHop(protocol: 'psiphon', serverId: 'default'),
          MixHop(protocol: 'psiphon', serverId: 'default'),
          MixHop(protocol: 'psiphon', serverId: 'default'),
        ],
      );
      responses['getMixDiagnostics'] = <String, dynamic>{
        'phase': 'Chain failed',
        'blocks': [
          {'index': 0, 'state': 'ready'},
          {'index': 1, 'state': 'failed'},
          {'index': 2, 'state': 'pending'},
        ],
      };
      responses['connectMixPlan'] = -1;
      final provider = await providerWith(strategy);
      await provider.connect();
      expect(provider.status, VpnConnectionStatus.error);
      expect(
        provider.mixDiagnostics!.hops.map((hop) => hop.toJson()).toList(),
        strategy.hops.map((hop) => hop.toJson()).toList(),
      );
      expect(provider.mixDiagnostics!.states, [
        MixBlockState.ready,
        MixBlockState.failed,
        MixBlockState.pending,
      ]);
      await provider.disconnect();
      expect(provider.mixDiagnostics!.states[1], MixBlockState.failed);
      provider.dispose();
    },
  );

  test(
    'combined-core failed test admits unknown block and starts no tunnel',
    () async {
      responses['measureDelay'] = -1;
      final provider = await providerWith(_strategy());
      await provider.connect();
      expect(provider.mixDiagnostics!.states, [MixBlockState.unverified]);
      expect(
        provider.mixDiagnostics!.message,
        contains('could not be identified'),
      );
      expect(calls, isNot(contains('connectMix')));
      provider.dispose();
    },
  );

  test('missing native telemetry does not invent block progress', () async {
    final provider = await providerWith(_nativeStrategy());
    await provider.connect();
    expect(provider.status, VpnConnectionStatus.connected);
    expect(provider.mixDiagnostics!.states, [MixBlockState.unverified]);
    await provider.disconnect();
    provider.dispose();
  });
}
