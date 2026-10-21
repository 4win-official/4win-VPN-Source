import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';

class PsiphonTestProvider extends VpnProvider {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.forwin.vpn/psiphon');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  late bool nativeConnected;
  late bool killSwitch;
  late String nativeStatus;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'psiphon_default_v1': true,
      'xray_default_v1': true,
    });
    calls = [];
    nativeConnected = true;
    killSwitch = false;
    nativeStatus = '';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'prepare':
          return true;
        case 'start':
        case 'reconnect':
          return true;
        case 'stop':
          // App-origin cleanup does not emit onDisconnected. Native teardown
          // may still replace its status text after the cause was consumed.
          nativeStatus = 'Disconnected';
          return true;
        case 'isConnected':
          return nativeConnected;
        case 'isKillSwitchActive':
          return killSwitch;
        case 'getStatus':
          return nativeStatus;
        case 'getPsiphonLogs':
          return <String>[];
        case 'queryStats':
          return <String, int>{'uplink': 0, 'downlink': 0};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<PsiphonTestProvider> makeProvider() async {
    final provider = PsiphonTestProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.switchProtocol('psiphon');
    return provider;
  }

  test(
    'switching away during delayed native start cannot resurrect Psiphon',
    () async {
      final started = Completer<bool>();
      nativeConnected = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'prepare') return true;
        if (call.method == 'start') return started.future;
        if (call.method == 'stop') return true;
        if (call.method == 'isConnected') return nativeConnected;
        if (call.method == 'isKillSwitchActive') return false;
        if (call.method == 'getStatus') return '';
        if (call.method == 'getPsiphonLogs') return <String>[];
        return null;
      });
      final provider = await makeProvider();
      final operation = provider.connect();
      while (!calls.contains('start')) {
        await Future<void>.delayed(Duration.zero);
      }

      await provider.switchProtocol('xray');
      started.complete(true);
      await operation;

      expect(provider.selectedProtocol, 'xray');
      expect(provider.isConnected, isFalse);
      expect(provider.status, VpnConnectionStatus.disconnected);
      expect(calls, contains('stop'));
      provider.dispose();
    },
  );

  test(
    'late isConnected from cancelled attempt cannot stop newer Psiphon attempt',
    () async {
      final connected = Completer<bool>();
      var starts = 0;
      var stops = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'prepare') return true;
        if (call.method == 'start') {
          starts++;
          return true;
        }
        if (call.method == 'stop') {
          stops++;
          return true;
        }
        if (call.method == 'isConnected') {
          if (starts == 1) return connected.future;
          return true;
        }
        if (call.method == 'isKillSwitchActive') return false;
        if (call.method == 'getStatus') return '';
        if (call.method == 'getPsiphonLogs') return <String>[];
        return null;
      });
      final provider = await makeProvider();
      final first = provider.connect();
      while (starts < 1) {
        await Future<void>.delayed(Duration.zero);
      }
      await provider.disconnect();
      final second = provider.connect();
      while (starts < 2) {
        await Future<void>.delayed(Duration.zero);
      }

      connected.complete(true);
      await first;
      expect(stops, 1);
      await second;
      expect(provider.status, VpnConnectionStatus.connected);
      expect(stops, 1);
      provider.dispose();
    },
  );

  test(
    'terminal native Psiphon status surfaces without waiting for timeout',
    () async {
      nativeConnected = false;
      nativeStatus = 'Psiphon failed: fixture';
      final provider = await makeProvider();

      await provider.connect();

      expect(provider.status, VpnConnectionStatus.error);
      expect(provider.errorMessage, contains('Psiphon failed: fixture'));
      provider.dispose();
    },
  );

  test(
    'failed-start cleanup stops native service without erasing its cause',
    () async {
      nativeConnected = false;
      nativeStatus = 'Psiphon failed: traffic bridge failed to start';
      final provider = await makeProvider();
      await provider.connect();
      expect(calls.where((call) => call == 'stop'), hasLength(1));
      expect(nativeStatus, 'Disconnected');
      expect(provider.status, VpnConnectionStatus.error);
      expect(provider.errorMessage, contains('traffic bridge failed'));
      provider.dispose();
    },
  );

  test(
    'notification Psiphon disconnect still cancels an in-flight connect',
    () async {
      nativeConnected = false;
      // A real notification action must not be ignored because a previous
      // failure is still in the cross-process status cache.
      nativeStatus = 'Psiphon failed: previous startup failure';
      final provider = await makeProvider();
      final operation = provider.connect();
      while (!calls.contains('start')) {
        await Future<void>.delayed(Duration.zero);
      }

      await messenger.handlePlatformMessage(
        'com.forwin.vpn/vpn_state',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onDisconnected', {'protocol': 'psiphon'}),
        ),
        (_) {},
      );
      await operation;
      expect(provider.status, VpnConnectionStatus.disconnected);
      expect(calls, contains('stop'));
      provider.dispose();
    },
  );

  test(
    'native kill-switch failure remains error after the auto-clear window',
    () async {
      nativeConnected = false;
      killSwitch = true;
      nativeStatus = 'Psiphon failed: fixture';
      final provider = await makeProvider();

      await provider.connect();
      expect(provider.status, VpnConnectionStatus.error);
      await Future<void>.delayed(const Duration(seconds: 11));
      expect(provider.status, VpnConnectionStatus.error);
      expect(provider.errorMessage, isNotEmpty);
      provider.dispose();
    },
  );

  test(
    'switching away from Psiphon error always stops native service',
    () async {
      nativeConnected = false;
      killSwitch = true;
      nativeStatus = 'Psiphon failed: fixture';
      final provider = await makeProvider();

      await provider.connect();
      expect(provider.status, VpnConnectionStatus.error);
      await provider.switchProtocol('xray');

      expect(calls, contains('stop'));
      expect(provider.selectedProtocol, 'xray');
      expect(provider.status, VpnConnectionStatus.disconnected);
      provider.dispose();
    },
  );

  testWidgets('kill-switch protection does not exhaust a live startup', (
    tester,
  ) async {
    final provider = PsiphonTestProvider();
    await tester.pump();
    await provider.switchProtocol('psiphon');
    nativeConnected = false;
    killSwitch = true;
    nativeStatus = 'Connecting to Psiphon...';
    final operation = provider.connect();
    await tester.pump();
    for (var second = 0; second < 20; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(provider.status, VpnConnectionStatus.connecting);
    expect(calls.where((call) => call == 'reconnect'), isEmpty);
    expect(provider.errorMessage, contains('protecting traffic'));
    nativeConnected = true;
    killSwitch = false;
    await tester.pump(const Duration(seconds: 1));
    await operation;
    expect(provider.status, VpnConnectionStatus.connected);
    expect(provider.errorMessage, isNull);
    await provider.disconnect();
    provider.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('four exhausted attempts leave an explicit persistent error', (
    tester,
  ) async {
    final provider = PsiphonTestProvider();
    await tester.pump();
    await provider.switchProtocol('psiphon');
    nativeConnected = false;
    nativeStatus = 'Waiting for network...';
    final operation = provider.connect();
    await tester.pump();
    for (var second = 0; second < 740; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await operation;
    expect(calls.where((call) => call == 'start'), hasLength(1));
    expect(calls.where((call) => call == 'reconnect'), hasLength(3));
    expect(provider.status, VpnConnectionStatus.error);
    expect(provider.errorMessage, contains('4/4 attempts'));
    expect(provider.errorMessage, contains('Waiting for network'));
    await tester.pump(const Duration(seconds: 11));
    expect(provider.status, VpnConnectionStatus.error);
    expect(provider.errorMessage, isNotEmpty);
    provider.dispose();
  });

  test(
    'failed startup cause survives reset and stopped-state reconciliation',
    () async {
      nativeConnected = false;
      nativeStatus = 'Psiphon failed: selected server is no longer available';
      const stateChannel = MethodChannel('com.forwin.vpn/vpn_state');
      messenger.setMockMethodCallHandler(
        stateChannel,
        (call) async => {'running': false, 'reconnecting': false},
      );
      final provider = await makeProvider();
      try {
        await provider.connect();
        final error = provider.errorMessage;
        provider.resetState();
        await provider.refreshConnectionState();
        expect(provider.status, VpnConnectionStatus.error);
        expect(provider.errorMessage, error);
        expect(provider.errorMessage, contains('selected server'));
        await provider.disconnect();
        expect(provider.errorMessage, isNull);
      } finally {
        provider.dispose();
        messenger.setMockMethodCallHandler(stateChannel, null);
      }
    },
  );

  test(
    'terminal native failure keeps protection and exposes its cause',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('kill_switch', true);
      nativeConnected = false;
      killSwitch = true;
      nativeStatus =
          'Psiphon failed: traffic bridge failed to start — traffic blocked by kill switch';
      final provider = await makeProvider();
      await provider.connect();
      expect(provider.status, VpnConnectionStatus.error);
      expect(provider.errorMessage, contains('traffic bridge failed to start'));
      expect(provider.errorMessage, contains('kill switch active'));
      expect(calls.where((call) => call == 'reconnect'), isEmpty);
      expect(calls.where((call) => call == 'stop'), isEmpty);
      await provider.disconnect();
      expect(calls, contains('stop'));
      provider.dispose();
    },
  );
}
