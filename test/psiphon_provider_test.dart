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
        case 'stop':
        case 'reconnect':
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
}
