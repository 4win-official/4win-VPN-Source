import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';

class _WarpTestProvider extends VpnProvider {
  @override
  Future<void> loadServers({bool forceRefresh = false}) async {}

  @override
  Future<void> loadXrayServers() async {}

  @override
  Future<void> loadProxyServers() async {}

  @override
  Future<void> loadOpenVpnConfigs() async {}
}

const _warpAccount = <String, dynamic>{
  'id': 'device-id',
  'accountId': 'account-id',
  'token': 'token',
  'privateKeyBase64': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  'publicKeyBase64': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  'peerPublicKeyBase64': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  'peerEndpoint': '162.159.192.1:2408',
  'addressV4': '172.16.0.2/32',
  'addressV6': '',
  'reserved': <int>[1, 2, 3],
  'warpEnabled': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const xrayChannel = MethodChannel('com.forwin.vpn/xray');
  const stateChannel = MethodChannel('com.forwin.vpn/vpn_state');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> xrayCalls;
  late Map<String, dynamic> nativeState;
  late Future<Object?> Function(MethodCall) xrayBehavior;

  Future<void> setPrefs() async {
    SharedPreferences.setMockInitialValues({
      'psiphon_default_v1': true,
      'xray_default_v1': true,
      'selected_protocol': 'warp',
      'connection_mode': 'vpn',
      'warp_account': jsonEncode(_warpAccount),
    });
  }

  setUp(() async {
    await setPrefs();
    xrayCalls = [];
    nativeState = {'running': false, 'connected': false, 'reconnecting': false};
    xrayBehavior = (call) async {
      xrayCalls.add(call.method);
      switch (call.method) {
        case 'requestXrayPermission':
          return true;
        case 'connectXray':
          return true;
        case 'disconnectXray':
          return true;
        default:
          return null;
      }
    };
    messenger.setMockMethodCallHandler(
      xrayChannel,
      (call) => xrayBehavior(call),
    );
    messenger.setMockMethodCallHandler(stateChannel, (call) async {
      if (call.method == 'getState') return nativeState;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(xrayChannel, null);
    messenger.setMockMethodCallHandler(stateChannel, null);
  });

  Future<_WarpTestProvider> makeProvider() async {
    final provider = _WarpTestProvider();
    // Let constructor startup restoration and saved account loading finish.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return provider;
  }

  test('native PlatformException is surfaced verbatim as WARP error', () async {
    xrayBehavior = (call) async {
      xrayCalls.add(call.method);
      if (call.method == 'requestXrayPermission') return true;
      if (call.method == 'connectXray') {
        throw PlatformException(
          code: 'WARP_MODE',
          message: 'WARP handshake timed out after 15 seconds.',
        );
      }
      return true;
    };
    final provider = await makeProvider();

    await provider.connect();

    expect(provider.status, VpnConnectionStatus.error);
    expect(provider.warpError, 'WARP handshake timed out after 15 seconds.');
    expect(provider.errorMessage, provider.warpError);
    provider.dispose();
  });

  testWidgets('WARP error remains visible beyond ten seconds', (tester) async {
    xrayBehavior = (call) async {
      xrayCalls.add(call.method);
      if (call.method == 'requestXrayPermission') return true;
      if (call.method == 'connectXray') {
        throw PlatformException(code: 'WARP_MODE', message: 'WARP failed.');
      }
      return true;
    };
    final provider = _WarpTestProvider();
    await tester.pump(const Duration(milliseconds: 100));
    await provider.connect();
    await tester.pump(const Duration(seconds: 11));

    expect(provider.status, VpnConnectionStatus.error);
    expect(provider.errorMessage, 'WARP failed.');
    expect(provider.warpError, 'WARP failed.');
    provider.dispose();
  });

  test(
    'stopped native refresh and resetState do not erase WARP error',
    () async {
      xrayBehavior = (call) async {
        xrayCalls.add(call.method);
        if (call.method == 'requestXrayPermission') return true;
        if (call.method == 'connectXray') {
          throw PlatformException(code: 'WARP_MODE', message: 'WARP stopped.');
        }
        return true;
      };
      final provider = await makeProvider();
      await provider.connect();
      xrayCalls.clear();

      nativeState = {
        'running': false,
        'connected': false,
        'reconnecting': false,
      };
      await provider.refreshConnectionState();
      provider.resetState();

      expect(provider.status, VpnConnectionStatus.error);
      expect(provider.warpError, 'WARP stopped.');
      expect(provider.errorMessage, 'WARP stopped.');
      expect(xrayCalls, isNot(contains('disconnectXray')));
      provider.dispose();
    },
  );

  test(
    'WARP_CONNECT native failure retries once, then connects successfully',
    () async {
      var attempts = 0;
      xrayBehavior = (call) async {
        if (call.method == 'requestXrayPermission') return true;
        if (call.method == 'connectXray') {
          attempts++;
          if (attempts == 1) {
            throw PlatformException(
              code: 'WARP_CONNECT',
              message: 'WARP first handshake failed.',
            );
          }
          return true;
        }
        return true;
      };
      final provider = await makeProvider();

      await provider.connect();

      expect(attempts, 2);
      expect(provider.status, VpnConnectionStatus.connected);
      expect(provider.warpError, isNull);
      provider.dispose();
    },
  );

  test(
    'late connect error after explicit disconnect cannot resurrect WARP error',
    () async {
      final connectResult = Completer<bool>();
      xrayBehavior = (call) async {
        xrayCalls.add(call.method);
        if (call.method == 'requestXrayPermission') return true;
        if (call.method == 'connectXray') return connectResult.future;
        if (call.method == 'disconnectXray') return true;
        return null;
      };
      final provider = await makeProvider();

      final connecting = provider.connect();
      await Future<void>.delayed(Duration.zero);
      while (!xrayCalls.contains('connectXray')) {
        await Future<void>.delayed(Duration.zero);
      }
      final disconnecting = provider.disconnect();
      connectResult.completeError(
        PlatformException(code: 'WARP_MODE', message: 'late WARP error'),
      );
      await disconnecting;
      await connecting;

      expect(provider.status, VpnConnectionStatus.disconnected);
      expect(provider.warpError, isNull);
      expect(provider.errorMessage, isNull);
      provider.dispose();
    },
  );

  test('exhausted native retries retain the final specific cause', () async {
    var attempts = 0;
    xrayBehavior = (call) async {
      if (call.method == 'requestXrayPermission') return true;
      if (call.method == 'connectXray') {
        attempts++;
        throw PlatformException(
          code: 'WARP_CONNECT',
          message: 'WARP endpoint validation failed on attempt $attempts.',
        );
      }
      return true;
    };
    final provider = await makeProvider();
    await provider.connect();
    expect(attempts, 2);
    expect(provider.status, VpnConnectionStatus.error);
    expect(
      provider.errorMessage,
      'WARP endpoint validation failed on attempt 2.',
    );
    expect(provider.warpError, provider.errorMessage);
    provider.dispose();
  });

  test('late cancelled success cannot send a second native stop', () async {
    final result = Completer<bool>();
    xrayBehavior = (call) async {
      xrayCalls.add(call.method);
      if (call.method == 'connectXray') return result.future;
      return true;
    };
    final provider = await makeProvider();
    final connecting = provider.connect();
    for (var i = 0; i < 20 && !xrayCalls.contains('connectXray'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(xrayCalls, contains('connectXray'));
    await provider.disconnect();
    final stops = xrayCalls
        .where((method) => method == 'disconnectXray')
        .length;
    result.complete(true);
    await connecting;
    expect(provider.status, VpnConnectionStatus.disconnected);
    expect(
      xrayCalls.where((method) => method == 'disconnectXray'),
      hasLength(stops),
    );
    provider.dispose();
  });

  test(
    'native WARP error snapshot restores on reopen without stop/start',
    () async {
      nativeState = {
        'running': false,
        'connected': false,
        'reconnecting': false,
        'error': 'WARP native failure persisted.',
      };
      final provider = await makeProvider();
      await provider.refreshConnectionState();

      expect(provider.status, VpnConnectionStatus.error);
      expect(provider.warpError, 'WARP native failure persisted.');
      expect(provider.errorMessage, 'WARP native failure persisted.');
      expect(xrayCalls, isNot(contains('connectXray')));
      expect(xrayCalls, isNot(contains('disconnectXray')));
      provider.dispose();
    },
  );

  test(
    'successful WARP connect uses saved account and supports cancellation',
    () async {
      final provider = await makeProvider();
      await provider.connect();

      expect(provider.status, VpnConnectionStatus.connected);
      expect(provider.warpError, isNull);
      expect(xrayCalls, contains('requestXrayPermission'));
      expect(xrayCalls, contains('connectXray'));
      await provider.disconnect();
      expect(provider.status, VpnConnectionStatus.disconnected);
      expect(xrayCalls, contains('disconnectXray'));
      provider.dispose();
    },
  );
}
