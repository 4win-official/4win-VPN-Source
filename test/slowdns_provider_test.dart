import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/slowdns_config.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/services/slowdns_connection.dart';

class SlowDnsTestProvider extends VpnProvider {
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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'psiphon_default_v1': true,
      'xray_default_v1': true,
      'connection_mode': 'vpn',
    });
    calls = [];
    messenger.setMockMethodCallHandler(SlowDnsConnection.platform, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'requestPermission') return true;
      if (call.method == 'connect')
        throw PlatformException(
          code: 'SLOWDNS_CONNECTION',
          message: 'Traffic remains blocked until you disconnect or retry.',
        );
      return null;
    });
  });
  tearDown(() async {
    await SlowDnsConnection.disconnect();
    SlowDnsConnection.detach();
    messenger.setMockMethodCallHandler(SlowDnsConnection.platform, null);
  });
  Future<SlowDnsTestProvider> makeProvider() async {
    final provider = SlowDnsTestProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.switchProtocol('slowdns');
    await provider.selectSlowDnsConfig(
      SlowDnsConfig(
        name: 'fixture',
        domain: 't.example.com',
        nameServer: '1.1.1.1',
        pubKey: List.filled(64, 'a').join(),
      ),
    );
    return provider;
  }

  testWidgets('blocked-tunnel error does not auto-clear to disconnected', (
    tester,
  ) async {
    late SlowDnsTestProvider provider;
    await tester.runAsync(() async {
      provider = await makeProvider();
      await provider.connect();
    });
    expect(provider.status, VpnConnectionStatus.error);
    await tester.pump(const Duration(seconds: 11));
    expect(provider.status, VpnConnectionStatus.error);
    expect(provider.errorMessage, contains('blocked'));
    await tester.runAsync(() async => provider.disconnect());
    provider.dispose();
  });

  test('switching protocol releases a failed Slow DNS blackhole', () async {
    final provider = await makeProvider();
    await provider.connect();
    expect(provider.status, VpnConnectionStatus.error);
    await provider.switchProtocol('xray');
    expect(calls, contains('disconnect'));
    expect(provider.selectedProtocol, 'xray');
    provider.dispose();
  });

  test(
    'switching during late native connect cannot resurrect Slow DNS',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      messenger.setMockMethodCallHandler(SlowDnsConnection.platform, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'requestPermission') return true;
        if (call.method == 'connect') return pending.future;
        return null;
      });
      final provider = await makeProvider();
      final operation = provider.connect();
      while (!calls.contains('connect')) {
        await Future<void>.delayed(Duration.zero);
      }
      await provider.switchProtocol('xray');
      pending.complete({
        'ready': true,
        'connected': true,
        'resolver': '1.1.1.1:53',
      });
      await operation;
      expect(provider.selectedProtocol, 'xray');
      expect(provider.isConnected, isFalse);
      expect(calls, contains('disconnect'));
      provider.dispose();
    },
  );
}
