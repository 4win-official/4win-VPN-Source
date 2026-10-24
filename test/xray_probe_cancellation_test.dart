import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/services/probe_cancellation.dart';
import 'package:vpn_swift/services/xray_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.forwin.vpn/xray');
  final pending = <String, Completer<Object?>>{};
  final cancelled = <String>[];

  setUp(() {
    pending.clear();
    cancelled.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<dynamic, dynamic>.from(call.arguments as Map);
          if (call.method == 'measureDelay') {
            final requestId = args['requestId'] as String;
            final completer = Completer<Object?>();
            pending[requestId] = completer;
            return completer.future;
          }
          if (call.method == 'cancelMeasureDelay') {
            cancelled.add(args['requestId'] as String);
            return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'stopping an individual Xray probe ignores its late native result',
    () async {
      final cancellation = ProbeCancellation();
      final result = XrayConnection.measureDelay(
        '{}',
        cancellation: cancellation,
      );
      await Future<void>.delayed(Duration.zero);
      final requestId = pending.keys.single;

      cancellation.cancel();
      expect(await result, -1);
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, [requestId]);

      pending[requestId]!.complete(27);
      await Future<void>.delayed(Duration.zero);
      expect(await result, -1);
    },
  );

  test(
    'stopping a bulk Xray run cancels active probes and drops late results',
    () async {
      final bulk = ProbeCancellation();
      final firstToken = ProbeCancellation().linkedTo(bulk);
      final secondToken = ProbeCancellation().linkedTo(bulk);
      final results = <Future<int>>[
        XrayConnection.measureDelay('first', cancellation: firstToken),
        XrayConnection.measureDelay('second', cancellation: secondToken),
      ];
      await Future<void>.delayed(Duration.zero);
      final ids = pending.keys.toList();
      expect(ids, hasLength(2));

      bulk.cancel();
      expect(await Future.wait(results), [-1, -1]);
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, unorderedEquals(ids));

      for (final id in ids) {
        pending[id]!.complete(99);
      }
      await Future<void>.delayed(Duration.zero);
      expect(await Future.wait(results), [-1, -1]);
    },
  );
}
