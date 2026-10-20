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
    test(
      '$protocol restores native session time and cumulative bytes',
      () async {
        prefs(protocol);
        snapshot = {
          'running': true,
          'reconnecting': false,
          'connected': true,
          'sessionId': 'existing-session',
          'elapsedMillis': 11000,
          'downlink': 2048,
          'uplink': 1024,
        };
        final provider = await restore();
        expect(provider.connectionDuration, const Duration(seconds: 11));
        expect(provider.dataUsage, '↓ 2.0 KB  ↑ 1.0 KB');
        provider.dispose();
        // Recreating Flutter must query the service, not persist a UI baseline.
        snapshot!['elapsedMillis'] = 75000;
        snapshot!['downlink'] = 8192;
        snapshot!['uplink'] = 4096;
        final reopened = await restore();
        expect(reopened.connectionDuration, const Duration(seconds: 75));
        expect(reopened.dataUsage, '↓ 8.0 KB  ↑ 4.0 KB');
        expectNoConnectionMutation();
        reopened.dispose();
      },
    );
  }

  testWidgets(
    'native polling updates bytes without legacy counters overwriting',
    (tester) async {
      snapshot = {
        'running': true,
        'reconnecting': false,
        'connected': true,
        'sessionId': 'same',
        'elapsedMillis': 60000,
        'downlink': 2048,
        'uplink': 1024,
      };
      final provider = _RestoreTestProvider();
      await tester.pump();
      snapshot!['elapsedMillis'] = 65000;
      snapshot!['downlink'] = 8192;
      snapshot!['uplink'] = 4096;
      await tester.pump(const Duration(seconds: 2));
      expect(provider.connectionDuration.inSeconds, 65);
      expect(provider.dataUsage, '↓ 8.0 KB  ↑ 4.0 KB');
      expect(serviceCalls, isNot(contains('queryStats')));
      // An incomplete measurement must not erase previously measured totals.
      snapshot!.remove('uplink');
      snapshot!.remove('downlink');
      await tester.pump(const Duration(seconds: 2));
      expect(provider.dataUsage, '↓ 8.0 KB  ↑ 4.0 KB');
      expectNoConnectionMutation();
      provider.dispose();
    },
  );

  test(
    'resume catches up elapsed time and real new session resets totals',
    () async {
      snapshot = {
        'running': true,
        'reconnecting': false,
        'connected': true,
        'sessionId': 'old',
        'elapsedMillis': 120000,
        'downlink': 8192,
        'uplink': 4096,
      };
      final provider = await restore();
      snapshot!['elapsedMillis'] = 240000;
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(provider.connectionDuration.inSeconds, 240);
      expect(provider.dataUsage, '↓ 8.0 KB  ↑ 4.0 KB');
      snapshot!['sessionId'] = 'new';
      snapshot!['elapsedMillis'] = 1000;
      snapshot!['downlink'] = 512;
      snapshot!['uplink'] = 256;
      await provider.refreshConnectionState();
      expect(provider.connectionDuration.inSeconds, 1);
      expect(provider.dataUsage, '↓ 512 B  ↑ 256 B');
      snapshot = {'running': false, 'reconnecting': false, 'connected': false};
      await provider.refreshConnectionState();
      expect(provider.status, VpnConnectionStatus.disconnected);
      expect(provider.connectionDuration, Duration.zero);
      expect(provider.dataUsage, '↓ 0 B  ↑ 0 B');
      snapshot = {
        'running': true,
        'reconnecting': false,
        'connected': true,
        'sessionId': 'third',
        'elapsedMillis': 2000,
        'downlink': 128,
        'uplink': 64,
      };
      await provider.refreshConnectionState();
      expect(provider.connectionDuration.inSeconds, 2);
      expect(provider.dataUsage, '↓ 128 B  ↑ 64 B');
      provider.dispose();
    },
  );

  test(
    'older concurrent snapshot cannot roll back live measurements',
    () async {
      snapshot = {
        'running': true,
        'reconnecting': false,
        'connected': true,
        'sessionId': 'same',
        'elapsedMillis': 1000,
        'downlink': 1024,
        'uplink': 1024,
      };
      final provider = await restore();
      final older = Completer<Map<String, dynamic>>();
      var calls = 0;
      messenger.setMockMethodCallHandler(stateChannel, (_) async {
        if (calls++ == 0) return older.future;
        return {...snapshot!, 'elapsedMillis': 5000, 'downlink': 8192};
      });
      final pending = provider.refreshConnectionState();
      await Future<void>.delayed(Duration.zero);
      await provider.refreshConnectionState();
      older.complete(snapshot!);
      await pending;
      expect(provider.connectionDuration.inSeconds, 5);
      expect(provider.dataUsage, '↓ 8.0 KB  ↑ 1.0 KB');
      provider.dispose();
    },
  );

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

  testWidgets('late Psiphon heartbeat restores original session after reopen', (
    tester,
  ) async {
    snapshot = {'running': false, 'reconnecting': false, 'connected': false};
    final provider = _RestoreTestProvider();
    await tester.pump();
    expect(provider.status, VpnConnectionStatus.disconnected);
    snapshot = {
      'running': true,
      'reconnecting': false,
      'connected': true,
      'sessionId': 'service-in-other-process',
      'elapsedMillis': 125000,
      'downlink': 8192,
      'uplink': 4096,
    };
    await tester.pump(const Duration(seconds: 2));
    expect(provider.status, VpnConnectionStatus.connected);
    expect(provider.connectionDuration.inSeconds, 125);
    expect(provider.dataUsage, '↓ 8.0 KB  ↑ 4.0 KB');
    expectNoConnectionMutation();
    provider.dispose();
    final reads = stateCalls.length;
    await tester.pump(const Duration(seconds: 10));
    expect(stateCalls, hasLength(reads));
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
