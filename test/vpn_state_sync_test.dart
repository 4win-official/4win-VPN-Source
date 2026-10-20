import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/dns_server.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';

class _TestVpnProvider extends VpnProvider {
  @override
  Future<void> loadServers({bool forceRefresh = false}) async {}

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

final _nativeMix = MixStrategy(
  id: 'native',
  name: 'Native chain',
  hops: const [MixHop(protocol: 'psiphon', serverId: 'default')],
);

Future<void> _setPrefs({List<MixStrategy> strategies = const []}) async {
  SharedPreferences.setMockInitialValues({
    'psiphon_default_v1': true,
    'xray_default_v1': true,
    'selected_protocol': 'xray',
    'selected_xray_server': 'x1',
    'xray_servers': <String>[jsonEncode(_xray)],
    'proxy_servers': <String>[],
    'connection_mode': 'vpn',
    'mix_strategies_v1': strategies
        .map((strategy) => jsonEncode(strategy.toJson()))
        .toList(),
    if (strategies.isNotEmpty) 'mix_selected_strategy_v1': strategies.first.id,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const stateChannel = MethodChannel('com.forwin.vpn/vpn_state');
  const xrayChannel = MethodChannel('com.forwin.vpn/xray');
  const dnsChannel = MethodChannel('com.forwin.vpn/dns');
  late Map<String, dynamic> xrayResponses;
  late List<MethodCall> stateCalls;
  late List<String> xrayCalls;

  setUp(() async {
    await _setPrefs();
    stateCalls = [];
    xrayCalls = [];
    xrayResponses = {
      'requestXrayPermission': true,
      'connectXray': true,
      'disconnectXray': true,
      'isXrayRunning': true,
      'isXrayReconnecting': false,
      'connectMixPlan': 42,
      'disconnectMixPlan': true,
      'queryXrayStats': <String, int>{'uplink': 0, 'downlink': 0},
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(stateChannel, (call) async {
          stateCalls.add(call);
          return <String, dynamic>{'running': true, 'reconnecting': false};
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(xrayChannel, (call) async {
          xrayCalls.add(call.method);
          return xrayResponses[call.method];
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dnsChannel, (call) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(stateChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(xrayChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dnsChannel, null);
  });

  Future<_TestVpnProvider> mixProvider() async {
    await _setPrefs(strategies: [_nativeMix]);
    final provider = _TestVpnProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.switchProtocol('mix');
    return provider;
  }

  Future<_TestVpnProvider> xrayProvider() async {
    final provider = _TestVpnProvider();
    await Future<void>.delayed(Duration.zero);
    return provider;
  }

  Future<void> notifyDisconnected(String protocol) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final reply = Completer<ByteData?>();
    messenger.handlePlatformMessage(
      stateChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onDisconnected', {'protocol': protocol}),
      ),
      reply.complete,
    );
    await reply.future;
  }

  test(
    'onDisconnected filters protocols and stops a connected Mix chain',
    () async {
      final provider = await mixProvider();
      await provider.connect();
      expect(provider.status, VpnConnectionStatus.connected);
      xrayCalls.clear();

      await notifyDisconnected('unrelated');
      expect(provider.status, VpnConnectionStatus.connected);
      expect(xrayCalls, isEmpty);

      await notifyDisconnected('xray');
      expect(provider.status, VpnConnectionStatus.disconnected);
      expect(xrayCalls, contains('disconnectXray'));
      expect(provider.currentPing, isNull);
      expect(provider.dataUsage, contains('0 B'));
      provider.dispose();
    },
  );

  test('xray-only native disconnect notification is idempotent', () async {
    final provider = await xrayProvider();
    await provider.connect();
    expect(provider.status, VpnConnectionStatus.connected);
    xrayCalls.clear();

    await notifyDisconnected('xray');
    await notifyDisconnected('xray');
    expect(provider.status, VpnConnectionStatus.disconnected);
    expect(
      xrayCalls.where((method) => method == 'disconnectXray'),
      hasLength(1),
    );
    provider.dispose();
  });

  test(
    'resume reconciles stopped state but preserves reconnecting gap',
    () async {
      final provider = await mixProvider();
      await provider.connect();

      stateCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(stateChannel, (call) async {
            stateCalls.add(call);
            return <String, dynamic>{'running': false, 'reconnecting': true};
          });
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(stateCalls.single.arguments, {'protocol': 'mix'});
      expect(provider.status, VpnConnectionStatus.connected);

      xrayCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(stateChannel, (call) async {
            stateCalls.add(call);
            return <String, dynamic>{'running': false, 'reconnecting': false};
          });
      await provider.refreshConnectionState();
      expect(provider.status, VpnConnectionStatus.disconnected);
      expect(xrayCalls, contains('disconnectXray'));
      provider.dispose();
    },
  );

  test(
    'resume reads disconnected state, skips local connect and ignores errors',
    () async {
      final provider = await mixProvider();
      stateCalls.clear();
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(stateCalls.single.arguments, {'protocol': 'mix'});

      final connecting = Completer<int>();
      xrayResponses['connectMixPlan'] = connecting.future;
      final pendingConnect = provider.connect();
      await Future<void>.delayed(Duration.zero);
      // The native coordinator is now connecting; a resume must not query it.
      stateCalls.clear();
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(stateCalls, isEmpty);
      final stopping = provider.disconnect();
      await Future<void>.delayed(Duration.zero);
      connecting.complete(42);
      await stopping;
      await pendingConnect;

      await provider.connect();
      expect(provider.status, VpnConnectionStatus.connected);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(stateChannel, (call) async => null);
      await provider.refreshConnectionState();
      expect(provider.status, VpnConnectionStatus.connected);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(stateChannel, (call) async {
            throw PlatformException(code: 'unavailable');
          });
      await provider.refreshConnectionState();
      expect(provider.status, VpnConnectionStatus.connected);
      provider.dispose();
    },
  );

  test('late state query cannot disconnect after a protocol switch', () async {
    final provider = await mixProvider();
    await provider.connect();
    final result = Completer<Map<String, dynamic>?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(stateChannel, (call) async => result.future);

    final refresh = provider.refreshConnectionState();
    await Future<void>.delayed(Duration.zero);
    await provider.switchProtocol('xray');
    final disconnects = xrayCalls
        .where((method) => method == 'disconnectXray')
        .length;
    result.complete({'running': false, 'reconnecting': false});
    await refresh;
    expect(provider.selectedProtocol, 'xray');
    expect(provider.status, VpnConnectionStatus.disconnected);
    expect(
      xrayCalls.where((method) => method == 'disconnectXray').length,
      disconnects,
    );
    provider.dispose();
  });

  test(
    'late Direct DNS connect cannot restore state after native disconnect',
    () async {
      final provider = await xrayProvider();
      await provider.switchProtocol('direct_dns');
      final dnsConnect = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(dnsChannel, (call) async {
            if (call.method == 'connectDns') return dnsConnect.future;
            return true;
          });

      final connecting = provider.selectDnsServerAndConnect(
        DnsServer(
          name: 'Test DNS',
          primaryDns: '1.1.1.1',
          secondaryDns: '1.0.0.1',
          description: 'test',
          country: 'test',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.status, VpnConnectionStatus.connecting);

      await notifyDisconnected('direct_dns');
      expect(provider.status, VpnConnectionStatus.disconnected);
      dnsConnect.complete(true);
      await connecting;
      expect(provider.status, VpnConnectionStatus.disconnected);
      provider.dispose();
    },
  );

  test(
    'disposed provider no longer handles native state notifications',
    () async {
      final provider = await mixProvider();
      provider.dispose();
      await notifyDisconnected('xray');
      expect(xrayCalls, isEmpty);
    },
  );
}
