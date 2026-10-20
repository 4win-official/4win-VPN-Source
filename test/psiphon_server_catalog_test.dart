import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/psiphon_server.dart';
import 'package:vpn_swift/services/psiphon_service.dart';
import 'psiphon_provider_test.dart' show PsiphonTestProvider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.forwin.vpn/psiphon');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = PsiphonService();
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    SharedPreferences.setMockInitialValues({
      'psiphon_default_v1': true,
      'xray_default_v1': true,
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'prepare':
        case 'start':
        case 'stop':
        case 'reconnect':
        case 'isConnected':
          return true;
        case 'isKillSwitchActive':
          return false;
        case 'getPsiphonLogs':
          return <String>[];
        case 'getStatus':
          return '';
        default:
          return null;
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'catalog bridge distinguishes signed cache date and public server metadata',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'source': 'cache',
          'updatedAt': 1700000000000,
          'servers': [
            {
              'id': 'id-one',
              'ipAddress': '192.0.2.1',
              'region': 'NL',
              'port': 443,
            },
            {'id': '', 'ipAddress': '192.0.2.2', 'port': 0},
          ],
        },
      );
      final list = await service.getServerList();
      expect(list.source, 'cache');
      expect(list.updatedAt!.millisecondsSinceEpoch, 1700000000000);
      expect(list.servers.single.id, 'id-one');
      expect(list.servers.single.port, 443);
      expect(list.servers.single.region, 'NL');
    },
  );

  test('bundled fallback never fabricates an online update date', () {
    final list = PsiphonServerList.fromMap({
      'source': 'bundled',
      'updatedAt': 1700000000000,
    });
    expect(list.updatedAt, isNull);
    expect(
      PsiphonServer.fromMap({
        'id': 'x',
        'ipAddress': '192.0.2.1',
        'port': 70000,
      }).port,
      isNull,
    );
  });

  test(
    'manual refresh reports update, busy and failure without throwing',
    () async {
      for (final response in [
        {'updated': true},
        {'updated': false, 'busy': true},
        {'updated': false, 'error': 'Refresh unavailable'},
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'refreshServerListNow');
          return response;
        });
        final result = await service.refreshServerListNow();
        expect(result.updated, response['updated']);
        expect(result.busy, response['busy'] == true);
        expect(result.error, response['error']);
      }
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'OFFLINE'),
      );
      expect((await service.refreshServerListNow()).updated, isFalse);
      expect((await service.getServerList()).error, isNotNull);
    },
  );

  test(
    'TCP probe measures a real socket without Psiphon authentication or DNS lookup',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((socket) => socket.destroy());
      try {
        final latency = await service.testServerLatency(
          PsiphonServer(id: 'local', ipAddress: '127.0.0.1', port: server.port),
        );
        expect(latency, isNotNull);
        expect(latency!, greaterThanOrEqualTo(0));
        expect(
          await service.testServerLatency(
            const PsiphonServer(
              id: 'invalid',
              ipAddress: 'not-an-ip',
              port: 443,
            ),
          ),
          isNull,
        );
        expect(
          await service.testServerLatency(
            const PsiphonServer(id: 'udp-only', ipAddress: '192.0.2.1'),
          ),
          isNull,
        );
      } finally {
        await subscription.cancel();
        await server.close();
      }
    },
  );

  test(
    'selected server id persists and is forwarded only for a chosen-server start',
    () async {
      final provider = PsiphonTestProvider();
      await Future<void>.delayed(Duration.zero);
      await provider.switchProtocol('psiphon');
      await provider.selectPsiphonServer('verified-entry-id');
      expect(provider.selectedPsiphonServerId, 'verified-entry-id');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'psiphon_selected_server_id',
        ),
        'verified-entry-id',
      );
      await provider.connect();
      expect(
        calls
            .where((call) => call.method == 'start')
            .single
            .arguments['targetServerId'],
        'verified-entry-id',
      );
      await expectLater(provider.selectPsiphonServer(null), throwsStateError);
      await provider.disconnect();
      await provider.selectPsiphonServer(null);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'psiphon_selected_server_id',
        ),
        isFalse,
      );
      provider.dispose();
    },
  );

  test('automatic start preserves the legacy start arguments', () async {
    await service.start();
    final start = calls.singleWhere((call) => call.method == 'start');
    expect(start.arguments, {'egressRegion': ''});
  });
}
