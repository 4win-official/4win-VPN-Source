import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/services/psiphon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.forwin.vpn/psiphon');
  late List<MethodCall> calls;
  late Map<String, dynamic> responses;

  setUp(() {
    calls = [];
    responses = {
      'prepare': true,
      'start': true,
      'stop': true,
      'reconnect': true,
      'isRunning': true,
      'isConnected': true,
      'getStatus': 'Connecting to Psiphon...',
      'isKillSwitchActive': true,
      'queryStats': <String, dynamic>{'uplink': '12', 'downlink': 34.9},
      'getPsiphonLogs': <String>['connected'],
      'getPsiphonServers': <String, dynamic>{
        'count': 0,
        'regions': <String>['US', 'DE'],
      },
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return responses[call.method];
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start prepares permission and forwards egress region', () async {
    final service = PsiphonService();

    expect(await service.start(egressRegion: 'DE'), isTrue);
    expect(calls.map((call) => call.method), ['prepare', 'start']);
    expect(calls.last.arguments, {'egressRegion': 'DE'});
  });

  test('status, control, logs, stats and servers map native values', () async {
    final service = PsiphonService();

    expect(await service.isRunning, isTrue);
    expect(await service.isConnected, isTrue);
    expect(await service.statusText, 'Connecting to Psiphon...');
    expect(await service.isKillSwitchActive, isTrue);
    expect(await service.reconnect(), isTrue);
    expect(await service.stop(), isTrue);
    expect(await service.queryStats(), {'uplink': 12, 'downlink': 34});
    expect(await service.getNativeLogs(), ['connected']);
    expect(await service.getServers(), {
      'count': 2,
      'regions': ['US', 'DE'],
    });
  });

  test('platform failures degrade to safe defaults', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'unavailable');
        });
    final service = PsiphonService();

    expect(await service.prepare(), isFalse);
    expect(await service.start(), isFalse);
    expect(await service.stop(), isFalse);
    expect(await service.reconnect(), isFalse);
    expect(await service.isRunning, isFalse);
    expect(await service.isConnected, isFalse);
    expect(await service.statusText, isEmpty);
    expect(await service.isKillSwitchActive, isFalse);
    expect(await service.queryStats(), {'uplink': 0, 'downlink': 0});
    expect(await service.getNativeLogs(), isEmpty);
    expect(await service.getServers(), {'count': 0, 'regions': <String>[]});
  });
}
