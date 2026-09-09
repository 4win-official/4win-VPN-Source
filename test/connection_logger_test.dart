import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/services/connection_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConnectionLogEntry', () {
    test('json roundtrip preserves all fields', () {
      final entry = ConnectionLogEntry(
        time: DateTime.utc(2026, 1, 2, 3, 4, 5),
        protocol: 'psiphon',
        level: ConnectionLogLevel.warning,
        message: 'hello',
      );
      final restored = ConnectionLogEntry.fromJson(entry.toJson());
      expect(restored.protocol, 'psiphon');
      expect(restored.level, ConnectionLogLevel.warning);
      expect(restored.message, 'hello');
      expect(restored.time.toUtc(), entry.time);
    });

    test('fromJson degrades gracefully on garbage', () {
      final restored = ConnectionLogEntry.fromJson({'l': 99});
      expect(restored.protocol, 'app');
      expect(restored.level, ConnectionLogLevel.info);
      expect(restored.message, '');
    });

    test('timeStamp is zero-padded HH:mm:ss', () {
      final entry = ConnectionLogEntry(
        time: DateTime(2026, 1, 1, 7, 5, 9),
        protocol: 'xray',
        level: ConnectionLogLevel.info,
        message: 'x',
      );
      expect(entry.timeStamp, '07:05:09');
    });
  });

  group('ConnectionLogger', () {
    test('logs entries with level helpers', () {
      final logger = ConnectionLogger.detached();
      logger.info('psiphon', 'a');
      logger.success('psiphon', 'b');
      logger.warning('xray', 'c');
      logger.error('sstp', 'd');

      expect(logger.entries.length, 4);
      expect(logger.entries[0].level, ConnectionLogLevel.info);
      expect(logger.entries[1].level, ConnectionLogLevel.success);
      expect(logger.entries[2].level, ConnectionLogLevel.warning);
      expect(logger.entries[3].level, ConnectionLogLevel.error);
      expect(logger.protocols, ['psiphon', 'sstp', 'xray']);
    });

    test('ring buffer caps at maxEntries, newest survive', () {
      final logger = ConnectionLogger.detached();
      for (var i = 0; i < ConnectionLogger.maxEntries + 50; i++) {
        logger.info('psiphon', 'line $i');
      }
      expect(logger.entries.length, ConnectionLogger.maxEntries);
      expect(logger.entries.first.message, 'line 50');
      expect(logger.entries.last.message,
          'line ${ConnectionLogger.maxEntries + 49}');
    });

    test('long messages are truncated', () {
      final logger = ConnectionLogger.detached();
      logger.info('psiphon', 'x' * (ConnectionLogger.maxMessageLength + 100));
      expect(logger.entries.single.message.length,
          ConnectionLogger.maxMessageLength);
    });

    test('clear empties memory and persisted tail', () async {
      final logger = ConnectionLogger.detached();
      logger.info('psiphon', 'a');
      await logger.clear();
      expect(logger.entries, isEmpty);

      final fresh = ConnectionLogger.detached();
      await fresh.loadPersisted();
      expect(fresh.entries, isEmpty);
    });

    test('persisted tail survives across instances', () async {
      final logger = ConnectionLogger.detached();
      logger.info('psiphon', 'before-restart-1');
      logger.error('xray', 'before-restart-2');
      // Let the fire-and-forget persist complete.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final fresh = ConnectionLogger.detached();
      await fresh.loadPersisted();
      expect(fresh.entries.length, 2);
      expect(fresh.entries[0].message, 'before-restart-1');
      expect(fresh.entries[1].level, ConnectionLogLevel.error);
    });

    test('loadPersisted runs only once', () async {
      final logger = ConnectionLogger.detached();
      logger.info('psiphon', 'x');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await logger.loadPersisted();
      final count = logger.entries.length;
      await logger.loadPersisted();
      expect(logger.entries.length, count);
    });
  });
}
