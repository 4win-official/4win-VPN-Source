import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';

class _RestoreTestProvider extends VpnProvider {
  @override
  Future<void> loadServers({bool forceRefresh = false}) async {}

  @override
  Future<void> loadXrayServers() async {}

  @override
  Future<void> loadProxyServers() async {}

  @override
  Future<void> loadOpenVpnConfigs() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const stateChannel = MethodChannel('com.forwin.vpn/vpn_state');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const protocolChannels = [
    MethodChannel('com.forwin.vpn/xray'),
    MethodChannel('com.forwin.vpn/psiphon'),
    MethodChannel('com.forwin.vpn/dns'),
    MethodChannel('com.forwin.vpn/openvpn'),
    MethodChannel('com.forwin.vpn/slowdns'),
  ];
  late Map<String, dynamic>? snapshot;
  late List<String> serviceCalls;
  late List<MethodCall> stateCalls;

  void prefs(String protocol) {
    SharedPreferences.setMockInitialValues({
      'psiphon_default_v1': true,
      'xray_default_v1': true,
      'xray_defaults_v146': true,
      'selected_protocol': protocol,
      'connection_mode': 'vpn',
    });
  }

  setUp(() {
    prefs('psiphon');
    snapshot = {'running': true, 'reconnecting': false, 'connected': true};
    serviceCalls = [];
    stateCalls = [];
    messenger.setMockMethodCallHandler(stateChannel, (call) async {
      stateCalls.add(call);
      return snapshot;
    });
    for (final channel in protocolChannels) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        serviceCalls.add(call.method);
        if (call.method == 'queryStats' || call.method == 'queryXrayStats') {
          return <String, int>{'uplink': 12, 'downlink': 34};
        }
        if (call.method == 'getPsiphonLogs') return <String>[];
        return true;
      });
    }
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(stateChannel, null);
    for (final channel in protocolChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  Future<_RestoreTestProvider> restore() async {
    final provider = _RestoreTestProvider();
    await provider.refreshConnectionState();
    return provider;
  }

  void expectNoConnectionMutation() {
    expect(
      serviceCalls.where(
        (method) => RegExp(
          r'connect|disconnect|start|stop|prepare|permission',
          caseSensitive: false,
        ).hasMatch(method),
      ),
      isEmpty,
    );
  }

  for (final protocol in [
    'psiphon',
    'xray',
    'proxy',
    'warp',
    'mix',
    'sstp',
    'openvpn',
    'direct_dns',
    'slowdns',
  ]) {
    test('fresh UI adopts live $protocol without connecting', () async {
      prefs(protocol);
      final provider = await restore();
      expect(provider.selectedProtocol, protocol);
      expect(provider.status, VpnConnectionStatus.connected);
      expect(stateCalls, isNotEmpty);
      expect(
        stateCalls.every(
          (call) =>
              call.method == 'getState' &&
              (call.arguments as Map)['protocol'] == protocol,
        ),
        isTrue,
      );
      expectNoConnectionMutation();
      provider.dispose();
    });
  }

  test('startup itself restores live service without needing resume', () async {
    final provider = _RestoreTestProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.status, VpnConnectionStatus.connected);
    expect(stateCalls, hasLength(1));
    expectNoConnectionMutation();
    provider.dispose();
  });

  test('resume can adopt a connection while UI was disconnected', () async {
    snapshot = {'running': false, 'reconnecting': false, 'connected': false};
    final provider = await restore();
    expect(provider.status, VpnConnectionStatus.disconnected);
    snapshot = {'running': true, 'reconnecting': false, 'connected': true};
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(provider.status, VpnConnectionStatus.connected);
    expectNoConnectionMutation();
    provider.dispose();
  });

  testWidgets(
    'restored session observes recovery and traffic without retrying',
    (tester) async {
      snapshot = {'running': true, 'reconnecting': true, 'connected': false};
      final provider = _RestoreTestProvider();
      await tester.pump();
      expect(provider.status, VpnConnectionStatus.connecting);
      await tester.pump(const Duration(seconds: 2));
      expect(provider.status, VpnConnectionStatus.connecting);
      snapshot = {'running': true, 'reconnecting': false, 'connected': true};
      await tester.pump(const Duration(seconds: 2));
      expect(provider.status, VpnConnectionStatus.connected);
      await tester.pump(const Duration(seconds: 2));
      expect(serviceCalls, contains('queryStats'));
      snapshot = {'running': true, 'reconnecting': false, 'connected': false};
      await tester.pump(const Duration(seconds: 2));
      expect(provider.status, VpnConnectionStatus.connecting);
      // Beyond the normal Psiphon monitor period: no recovery command is sent.
      await tester.pump(const Duration(seconds: 45));
      expectNoConnectionMutation();
      provider.dispose();
      final reads = stateCalls.length;
      await tester.pump(const Duration(seconds: 5));
      expect(stateCalls, hasLength(reads));
    },
  );

  test(
    'stopped, missing and incomplete snapshots cannot invent a connection',
    () async {
      for (final value in <Map<String, dynamic>?>[
        null,
        {},
        {'running': false, 'reconnecting': false, 'connected': false},
        {'running': true},
        {'connected': true},
      ]) {
        snapshot = value;
        final provider = await restore();
        expect(provider.status, VpnConnectionStatus.disconnected);
        provider.dispose();
      }
      expectNoConnectionMutation();
    },
  );

  test('unavailable native bridge leaves fresh UI disconnected', () async {
    messenger.setMockMethodCallHandler(stateChannel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    final provider = await restore();
    expect(provider.status, VpnConnectionStatus.disconnected);
    expectNoConnectionMutation();
    provider.dispose();
  });

  test('late live snapshot cannot override a manual stop', () async {
    snapshot = {'running': false, 'reconnecting': false, 'connected': false};
    final provider = await restore();
    final pending = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(stateChannel, (call) => pending.future);
    final refresh = provider.refreshConnectionState();
    await Future<void>.delayed(Duration.zero);
    await provider.disconnect();
    pending.complete({
      'running': true,
      'reconnecting': false,
      'connected': true,
    });
    await refresh;
    expect(provider.status, VpnConnectionStatus.disconnected);
    provider.dispose();
  });

  test('notification stop invalidates a pending startup snapshot', () async {
    final pending = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(stateChannel, (call) => pending.future);
    final provider = _RestoreTestProvider();
    await Future<void>.delayed(Duration.zero);
    final reply = Completer<ByteData?>();
    messenger.handlePlatformMessage(
      stateChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onDisconnected', {'protocol': 'psiphon'}),
      ),
      reply.complete,
    );
    await reply.future;
    pending.complete({
      'running': true,
      'reconnecting': false,
      'connected': true,
    });
    await Future<void>.delayed(Duration.zero);
    expect(provider.status, VpnConnectionStatus.disconnected);
    expectNoConnectionMutation();
    provider.dispose();
  });

  test(
    'late live snapshot cannot override protocol switch or disposal',
    () async {
      snapshot = {'running': false, 'reconnecting': false, 'connected': false};
      final provider = await restore();
      final pending = Completer<Map<String, dynamic>>();
      messenger.setMockMethodCallHandler(
        stateChannel,
        (call) => pending.future,
      );
      final refresh = provider.refreshConnectionState();
      await Future<void>.delayed(Duration.zero);
      await provider.switchProtocol('xray');
      provider.dispose();
      pending.complete({
        'running': true,
        'reconnecting': false,
        'connected': true,
      });
      await refresh;
      expect(provider.selectedProtocol, 'xray');
      expect(provider.status, VpnConnectionStatus.disconnected);
    },
  );
}
