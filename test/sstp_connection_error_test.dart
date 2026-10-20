import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/vpn_server.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/services/server_service.dart';

class _Servers extends ServerService {
  Completer<List<VpnServer>>? pending;

  @override
  Future<List<VpnServer>> fetchServers({bool forceRefresh = false}) async => [
    VpnServer(
      address: 'test.invalid',
      port: 443,
      username: 'vpn',
      password: 'vpn',
    ),
  ];

  @override
  Future<List<VpnServer>> testServersInParallel(
    List<VpnServer> servers, {
    Function(int tested, int total)? onProgress,
  }) async => pending != null
      ? pending!.future
      : servers.map((server) => server.copyWith(ping: 12)).toList();
}

class _Provider extends VpnProvider {
  _Provider(_Servers service) : super(serverService: service);

  @override
  Future<void> loadServers({bool forceRefresh = false}) async {}
  Future<void> loadSstp() => super.loadServers(forceRefresh: true);
  @override
  Future<void> loadSelectedProtocol() async {}
  @override
  Future<void> loadOpenVpnConfigs() async {}
  @override
  Future<void> loadXrayServers() async {}
  @override
  Future<void> loadProxyServers() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sstp = MethodChannel('sstp_flutter');
  const dns = MethodChannel('com.forwin.vpn/dns');
  const state = MethodChannel('com.forwin.vpn/vpn_state');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Servers service;
  late _Provider provider;

  Future<void> event(String status, {bool error = false}) async {
    messenger.handlePlatformMessage(
      'responseReceiver',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('connectResponse', {'status': status, 'error': error}),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'psiphon_default_v1': true,
      'xray_default_v1': true,
      'connection_mode': 'vpn',
      'xray_servers': <String>[],
      'proxy_servers': <String>[],
    });
    messenger.setMockMethodCallHandler(sstp, (call) async => true);
    messenger.setMockMethodCallHandler(dns, (call) async => true);
    messenger.setMockMethodCallHandler(
      state,
      (call) async => {'running': false, 'reconnecting': false},
    );
    service = _Servers();
    provider = _Provider(service);
    await provider.loadSstp();
    await provider.switchProtocol('sstp');
    await provider.refreshConnectionState();
  });

  tearDown(() {
    provider.dispose();
    messenger.setMockMethodCallHandler(sstp, null);
    messenger.setMockMethodCallHandler(dns, null);
    messenger.setMockMethodCallHandler(state, null);
  });

  test(
    'native disconnected then error survives time, pause and resume',
    () async {
      await provider.connect();
      await event('Disconnected', error: true);
      expect(provider.status, VpnConnectionStatus.error);
      final failure = provider.errorMessage;
      expect(failure, contains('SSTP connection failed'));
      // Exceed the previous 10-second auto-clear interval on the same clock
      // used by the native status stream subscription created in setUp.
      await Future<void>.delayed(const Duration(seconds: 11));
      expect(provider.errorMessage, failure);
      provider.resetState();
      await provider.refreshConnectionState();
      expect(provider.errorMessage, failure);
      expect(provider.status, VpnConnectionStatus.error);
      provider.clearError();
      expect(provider.errorMessage, isNull);
      await provider.disconnect();
    },
  );

  test(
    'disconnection without an error flag still explains failed startup',
    () async {
      await provider.connect();
      await event('Disconnected');
      expect(provider.status, VpnConnectionStatus.error);
      expect(provider.errorMessage, contains('SSTP connection failed'));
      await provider.disconnect();
    },
  );

  test(
    'manual disconnect and late native errors do not create failures',
    () async {
      await provider.connect();
      await provider.disconnect();
      await event('Disconnected', error: true);
      expect(provider.status, VpnConnectionStatus.disconnected);
      expect(provider.errorMessage, isNull);
    },
  );

  test(
    'retry clears the old failure immediately and success stays clear',
    () async {
      await provider.connect();
      await event('Disconnected', error: true);
      expect(provider.errorMessage, isNotNull);
      service.pending = Completer<List<VpnServer>>();
      final retry = provider.connect();
      expect(provider.errorMessage, isNull);
      service.pending!.complete([provider.servers.single.copyWith(ping: 8)]);
      await retry;
      await event('Connected');
      expect(provider.status, VpnConnectionStatus.connected);
      expect(provider.errorMessage, isNull);
      await event('Disconnected'); // also cancels the plugin's periodic timer
      expect(provider.errorMessage, contains('SSTP connection lost'));
      await provider.disconnect();
    },
  );
}
