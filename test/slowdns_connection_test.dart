import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/slowdns_config.dart';
import 'package:vpn_swift/services/slowdns_connection.dart';

SlowDnsConfig profile() => SlowDnsConfig(
  name: 'fixture',
  domain: 't.example.com',
  nameServer: '127.0.0.1',
  pubKey: List.filled(64, 'a').join(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SlowDnsConnection.detach();
    messenger.setMockMethodCallHandler(SlowDnsConnection.platform, (
      call,
    ) async {
      if (call.method == 'disconnect') return null;
      if (call.method == 'requestPermission') return true;
      return {
        'ready': true,
        'connected': true,
        'resolver': '127.0.0.1:53',
        'error': '',
      };
    });
  });
  tearDown(() async {
    await SlowDnsConnection.disconnect();
    SlowDnsConnection.detach();
    messenger.setMockMethodCallHandler(SlowDnsConnection.platform, null);
  });

  test('rejects invalid configuration before calling native connect', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(SlowDnsConnection.platform, (
      call,
    ) async {
      calls++;
      return null;
    });
    expect(
      await SlowDnsConnection.connect(profile().copyWith(pubKey: 'bad')),
      isFalse,
    );
    expect(calls, 0);
    expect(SlowDnsConnection.isConnected, isFalse);
    expect(SlowDnsConnection.lastError, contains('64'));
  });

  test('local listener or started service alone is not ready', () async {
    messenger.setMockMethodCallHandler(
      SlowDnsConnection.platform,
      (call) async => {
        'ready': false,
        'connected': false,
        'error': 'Authentication failed',
      },
    );
    expect(await SlowDnsConnection.connect(profile()), isFalse);
    expect(SlowDnsConnection.activeResolver, isNull);
    expect(SlowDnsConnection.lastError, contains('Authentication failed'));
  });

  test('only native authenticated readiness marks connected', () async {
    expect(await SlowDnsConnection.requestPermission(), isTrue);
    expect(await SlowDnsConnection.connect(profile()), isTrue);
    expect(SlowDnsConnection.activeResolver, '127.0.0.1:53');
    expect(SlowDnsConnection.activeConfig?.name, 'fixture');
    expect(await SlowDnsConnection.disconnect(), isTrue);
    expect(SlowDnsConnection.isConnected, isFalse);
    expect(SlowDnsConnection.activeConfig, isNull);
    expect(SlowDnsConnection.activeResolver, isNull);
  });

  test('late connect result cannot resurrect a cancelled connection', () async {
    final pending = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(SlowDnsConnection.platform, (
      call,
    ) async {
      if (call.method == 'connect') return pending.future;
      return null;
    });
    final operation = SlowDnsConnection.connect(profile());
    await Future<void>.delayed(Duration.zero);
    await SlowDnsConnection.disconnect();
    pending.complete({
      'ready': true,
      'connected': true,
      'resolver': '127.0.0.1:53',
    });
    expect(await operation, isFalse);
    expect(SlowDnsConnection.isConnected, isFalse);
  });

  testWidgets('native failure clears readiness and notifies the UI', (
    tester,
  ) async {
    var healthy = true;
    final events = <bool>[];
    SlowDnsConnection.onStateChanged = (connected, _) => events.add(connected);
    messenger.setMockMethodCallHandler(
      SlowDnsConnection.platform,
      (call) async => {
        'ready': healthy,
        'connected': healthy,
        'resolver': '127.0.0.1:53',
        'error': healthy ? '' : 'Backend exited; traffic is blocked.',
      },
    );
    expect(await SlowDnsConnection.connect(profile()), isTrue);
    healthy = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(SlowDnsConnection.isConnected, isFalse);
    expect(events, [true, false]);
    expect(SlowDnsConnection.lastError, contains('blocked'));
  });

  testWidgets('notification reconnect preserves config and keeps polling', (
    tester,
  ) async {
    var reconnecting = false;
    var healthy = true;
    final events = <bool>[];
    SlowDnsConnection.onStateChanged = (connected, _) => events.add(connected);
    messenger.setMockMethodCallHandler(
      SlowDnsConnection.platform,
      (call) async => {
        'ready': healthy,
        'connected': healthy,
        'reconnecting': reconnecting,
        'resolver': '127.0.0.1:53',
        'error': healthy ? '' : 'Backend exited; traffic is blocked.',
      },
    );
    expect(await SlowDnsConnection.connect(profile()), isTrue);
    healthy = false;
    reconnecting = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(SlowDnsConnection.isConnected, isTrue);
    expect(SlowDnsConnection.activeConfig?.name, 'fixture');
    expect(SlowDnsConnection.activeResolver, '127.0.0.1:53');
    expect(events, [true]);
    reconnecting = false;
    healthy = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(SlowDnsConnection.isConnected, isTrue);
    healthy = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(SlowDnsConnection.isConnected, isFalse);
    expect(events, [true, false]);
  });

  test('missing native engine never simulates a connection', () async {
    messenger.setMockMethodCallHandler(SlowDnsConnection.platform, (
      call,
    ) async {
      throw MissingPluginException();
    });
    expect(await SlowDnsConnection.connect(profile()), isFalse);
    expect(SlowDnsConnection.lastError, contains('engine'));
  });
}
