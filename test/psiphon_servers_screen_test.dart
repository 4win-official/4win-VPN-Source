import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/psiphon_server.dart';
import 'package:vpn_swift/screens/psiphon_servers_screen.dart';
import 'package:vpn_swift/services/psiphon_service.dart';
import 'package:vpn_swift/widgets/psiphon_server_list_status.dart';

class FakePsiphonService extends PsiphonService {
  final server = const PsiphonServer(
    id: 'one',
    ipAddress: '192.0.2.1',
    region: 'Test',
    port: 443,
  );
  int refreshCalls = 0;
  int pingCalls = 0;
  int activePings = 0;
  int maxActivePings = 0;
  DateTime? updatedAt;

  @override
  Future<PsiphonServerList> getServerList() async => PsiphonServerList(
    servers: [server],
    source: updatedAt == null ? 'bundled' : 'cache',
    updatedAt: updatedAt,
  );

  @override
  Future<PsiphonRefreshResult> refreshServerListNow() async {
    refreshCalls++;
    updatedAt = DateTime(2026, 1, 2, 3, 4, 5);
    return const PsiphonRefreshResult(updated: true);
  }

  @override
  Future<int?> testServerLatency(PsiphonServer server) async {
    pingCalls++;
    activePings++;
    maxActivePings = maxActivePings < activePings
        ? activePings
        : maxActivePings;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    activePings--;
    return 12;
  }
}

class ControlledPsiphonService extends PsiphonService {
  final pending = <Completer<int?>>[];
  int active = 0;
  int maximum = 0;
  bool failRefresh = false;
  bool failRead = false;

  @override
  Future<PsiphonServerList> getServerList() async {
    if (failRead) return const PsiphonServerList(error: 'Metadata unavailable');
    return PsiphonServerList(
      source: 'cache',
      updatedAt: DateTime(2026, 1, 2, 3, 4, 5),
      servers: List.generate(
        8,
        (i) => PsiphonServer(
          id: '$i',
          ipAddress: '192.0.2.${i + 1}',
          region: 'Test',
          port: 443,
        ),
      ),
    );
  }

  @override
  Future<PsiphonRefreshResult> refreshServerListNow() async {
    if (failRefresh) {
      failRead = true;
      return const PsiphonRefreshResult(updated: false);
    }
    return const PsiphonRefreshResult(updated: true);
  }

  @override
  Future<int?> testServerLatency(PsiphonServer server) {
    active++;
    if (active > maximum) maximum = active;
    final result = Completer<int?>();
    pending.add(result);
    return result.future.whenComplete(() => active--);
  }
}

void main() {
  testWidgets('shows metadata and manual signed-list refresh', (tester) async {
    final service = FakePsiphonService();
    await tester.pumpWidget(
      MaterialApp(
        home: PsiphonServerListStatus(service: service, isDark: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Bundled list · No successful online update yet'),
      findsOneWidget,
    );
    await tester.tap(find.text('Refresh signed list'));
    await tester.pumpAndSettle();
    expect(service.refreshCalls, 1);
    expect(
      find.textContaining('Last successful update: 2026-01-02 03:04:05'),
      findsOneWidget,
    );
  });

  testWidgets('tests TCP reachability and displays the result', (tester) async {
    final service = FakePsiphonService();
    await tester.pumpWidget(
      MaterialApp(home: PsiphonServersScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('192.0.2.1'), findsOneWidget);
    await tester.tap(find.byTooltip('Test TCP latency'));
    await tester.pumpAndSettle();
    expect(service.pingCalls, 1);
    expect(find.textContaining('12 ms TCP'), findsOneWidget);
    expect(
      find.textContaining('TCP reachability, not VPN latency'),
      findsOneWidget,
    );
  });

  testWidgets('rapid test-all taps never start more than four probes', (
    tester,
  ) async {
    final service = ControlledPsiphonService();
    await tester.pumpWidget(
      MaterialApp(home: PsiphonServersScreen(service: service)),
    );
    await tester.pumpAndSettle();
    final testAll = find.text('Test all (max 4 at a time)');
    await tester.tap(testAll);
    await tester.tap(testAll);
    await tester.pump();
    expect(service.pending.length, 4);
    expect(service.active, 4);
    for (final result in service.pending.toList()) {
      result.complete(12);
    }
    await tester.pump();
    expect(service.pending.length, 8);
    for (final result in service.pending.skip(4)) {
      result.complete(12);
    }
    await tester.pumpAndSettle();
    expect(service.maximum, 4);
    expect(service.active, 0);
  });

  testWidgets('refresh cancels the next probe batch and clears old spinners', (
    tester,
  ) async {
    final service = ControlledPsiphonService();
    await tester.pumpWidget(
      MaterialApp(home: PsiphonServersScreen(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test all (max 4 at a time)'));
    await tester.pump();
    expect(service.pending.length, 4);
    await tester.tap(find.byTooltip('Refresh signed list'));
    await tester.pump();
    for (final result in service.pending) {
      result.complete(12);
    }
    await tester.pumpAndSettle();
    expect(service.pending.length, 4);
    expect(service.active, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'failed refresh and metadata read preserve the last successful date',
    (tester) async {
      final service = ControlledPsiphonService()..failRefresh = true;
      await tester.pumpWidget(
        MaterialApp(
          home: PsiphonServerListStatus(service: service, isDark: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-01-02 03:04:05'), findsOneWidget);
      await tester.tap(find.text('Refresh signed list'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-01-02 03:04:05'), findsOneWidget);
      expect(find.textContaining('not updated'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
