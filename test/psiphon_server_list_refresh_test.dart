import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/services/psiphon_server_list_refresh.dart';

class RefreshTestProvider extends VpnProvider {
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

final _xray = <String, dynamic>{
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const refreshChannel = MethodChannel('com.forwin.vpn/psiphon');
  const xrayChannel = MethodChannel('com.forwin.vpn/xray');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late TargetPlatform? oldPlatform;
  late Completer<void> pendingRefresh;

  setUp(() {
    oldPlatform = debugDefaultTargetPlatformOverride;
    pendingRefresh = Completer<void>();
    SharedPreferences.setMockInitialValues({
      'psiphon_default_v1': true,
      'xray_default_v1': true,
      'selected_protocol': 'xray',
      'selected_xray_server': 'standalone-xray',
      'xray_selected_group': 'standalone-group',
      'connection_mode': 'vpn',
      'xray_servers': <String>[jsonEncode(_xray)],
    });
  });

  tearDown(() async {
    if (!pendingRefresh.isCompleted) pendingRefresh.complete();
    messenger.setMockMethodCallHandler(refreshChannel, null);
    messenger.setMockMethodCallHandler(xrayChannel, null);
    debugDefaultTargetPlatformOverride = oldPlatform;
  });

  test(
    'Android request returns while the refresh platform call is pending',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var calls = 0;
      messenger.setMockMethodCallHandler(refreshChannel, (call) {
        calls++;
        return pendingRefresh.future;
      });

      PsiphonServerListRefresh.request();
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      expect(pendingRefresh.isCompleted, isFalse);
      // If request awaited the channel, this test could not reach this assertion.
    },
  );

  test('refresh request swallows a missing plugin/platform failure', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // No handler is installed, which makes invokeMethod throw MissingPluginException.
    expect(() => PsiphonServerListRefresh.request(), returnsNormally);
    await Future<void>.delayed(Duration.zero);
  });

  test('native scheduling errors never escape the optional refresh', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(refreshChannel, (call) async {
      throw PlatformException(code: 'UNAVAILABLE');
    });
    expect(() => PsiphonServerListRefresh.request(), returnsNormally);
    await Future<void>.delayed(Duration.zero);
  });

  test('non-Android platforms do not invoke the refresh channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var calls = 0;
    messenger.setMockMethodCallHandler(refreshChannel, (call) {
      calls++;
      return null;
    });

    PsiphonServerListRefresh.request();
    await Future<void>.delayed(Duration.zero);

    expect(calls, 0);
  });

  test(
    'Psiphon starts and connects without Dart refresh',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(xrayChannel, (call) async {
        return switch (call.method) {
          'requestXrayPermission' => true,
          'connectMixPlan' => 42,
          'isXrayRunning' => true,
          'isXrayReconnecting' => false,
          _ => null,
        };
      });
      final psiphonCalls = <String>[];
      messenger.setMockMethodCallHandler(refreshChannel, (call) async {
        psiphonCalls.add(call.method);
        return switch (call.method) {
          'prepare' => true,
          'start' => true,
          'isConnected' => true,
          'isKillSwitchActive' => false,
          'getStatus' => '',
          'getPsiphonLogs' => <String>[],
          'queryStats' => <String, int>{'uplink': 0, 'downlink': 0},
          _ => null,
        };
      });

      final provider = RefreshTestProvider();
      await Future<void>.delayed(Duration.zero);
      await provider.switchProtocol('psiphon');
      var connectedNotifications = 0;
      provider.addListener(() {
        if (provider.status == VpnConnectionStatus.connected) {
          connectedNotifications++;
        }
      });

      await provider.connect();
      expect(provider.status, VpnConnectionStatus.connected);
      expect(connectedNotifications, 1);
      await Future<void>.delayed(Duration.zero);
      expect(
        psiphonCalls.where((call) => call == 'refreshServerList').length,
        0,
      );
      provider.notifyListeners();
      provider.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(
        psiphonCalls.where((call) => call == 'refreshServerList').length,
        0,
      );

      provider.dispose();
    },
  );

  test(
    'Mix connects without Dart refresh',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final refreshCalls = <String>[];
      messenger.setMockMethodCallHandler(refreshChannel, (call) async {
        refreshCalls.add(call.method);
        return null;
      });
      messenger.setMockMethodCallHandler(xrayChannel, (call) async {
        return switch (call.method) {
          'requestXrayPermission' => true,
          'connectMixPlan' => 42,
          'disconnectMixPlan' => true,
          'isXrayRunning' => true,
          'isXrayReconnecting' => false,
          _ => null,
        };
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('mix_strategies_v1', [
        jsonEncode({
          'id': 'mix-1',
          'name': 'Native chain',
          'hops': [
            {'protocol': 'psiphon', 'serverId': 'default'},
          ],
        }),
      ]);
      await prefs.setString('mix_selected_strategy_v1', 'mix-1');

      final provider = RefreshTestProvider();
      await Future<void>.delayed(Duration.zero);
      await provider.switchProtocol('mix');
      var connectedNotifications = 0;
      provider.addListener(() {
        if (provider.status == VpnConnectionStatus.connected) {
          connectedNotifications++;
        }
      });

      await provider.connect();
      expect(provider.status, VpnConnectionStatus.connected);
      expect(connectedNotifications, 1);
      expect(refreshCalls, isNot(contains('refreshServerList')));
      provider.notifyListeners();
      provider.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(refreshCalls, isNot(contains('refreshServerList')));

      provider.dispose();
    },
  );
}
