import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/screens/dns_scanner_screen.dart';
import 'package:vpn_swift/services/dns_vpn_connection.dart';
import 'package:vpn_swift/services/operator_ipv4_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(DnsVpnConnection.platform, null),
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(360, 640),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: DnsScannerScreen()));
    await tester.pump();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final finder = find.bySemanticsLabel(label);
    await reveal(tester, finder);
    await tester.enterText(finder, value);
  }

  Future<void> start(WidgetTester tester) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Start scan'));
    await tester.tap(find.text('Start scan'));
    await tester.pump();
  }

  testWidgets('shows exactly the two primary IPv4 choices on a narrow phone', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(320, 480));
    expect(find.text('Random public IPv4'), findsOneWidget);
    expect(find.textContaining('Supplementary'), findsNothing);
    expect(find.textContaining('optional note'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('operator mode offers From/To and pasted range input', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.bySemanticsLabel('From IPv4'), findsOneWidget);
    expect(find.bySemanticsLabel('To IPv4'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Paste IPv4 addresses or CIDR ranges'),
      findsOneWidget,
    );
    expect(find.text('Import IPv4 ranges'), findsOneWidget);
    expect(find.textContaining('Enter your own IPv4 ranges'), findsOneWidget);
  });

  testWidgets('built-in choices preserve custom range input when switching', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(320, 480));
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '10.1.2.3');
    final choice = find.byType(DropdownButtonFormField<String>);
    await reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    for (final operator in OperatorIpv4Catalog.operators) {
      expect(find.text(operator.label), findsOneWidget);
    }
    await tester.tap(find.text(OperatorIpv4Catalog.operators.first.label));
    await tester.pumpAndSettle();
    expect(find.textContaining('RIPE NCC snapshot:'), findsOneWidget);
    expect(
      find.textContaining('batches do not run automatically'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('From IPv4'), findsNothing);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom IPv4 ranges').last);
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText ==
                'Paste IPv4 addresses or CIDR ranges',
      ),
    );
    expect(input.controller!.text, '10.1.2.3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected operator batch supplies only that batch and can stop', (
    tester,
  ) async {
    await pumpScreen(tester);
    final operator = OperatorIpv4Catalog.operators.last;
    final choice = find.byType(DropdownButtonFormField<String>);
    await reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text(operator.label));
    await tester.pumpAndSettle();
    final batchChoice = find.byType(DropdownButtonFormField<int>);
    await reveal(tester, batchChoice);
    await tester.tap(batchChoice);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        'Batch 2 / ${operator.batchCount} · ${operator.batchSize(1)} IPs',
      ),
    );
    await tester.pumpAndSettle();
    final pending = Completer<String>();
    final queried = <String>[];
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      queried.addAll(List<String>.from((call.arguments as Map)['ips'] as List));
      return pending.future;
    });
    await start(tester);
    expect(queried, operator.targetsForBatch(1).take(64).toList());
    await tester.tap(find.byTooltip('Stop'));
    pending.complete('[]');
    await tester.pumpAndSettle();
    expect(queried, hasLength(64));
    await reveal(tester, find.textContaining('Tested 0 / 200000'));
    expect(
      find.textContaining('Batch 2 of ${operator.batchCount}'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasted IPv4 range is scanned and remains operator mode', (
    tester,
  ) async {
    List<String>? scanned;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      scanned = List<String>.from((call.arguments as Map)['ips'] as List);
      return '[]';
    });
    await pumpScreen(tester);
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '198.51.100.1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(scanned, ['198.51.100.1']);
  });

  testWidgets('random mode generates only public IPv4 targets', (tester) async {
    List<String>? scanned;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      scanned = List<String>.from((call.arguments as Map)['ips'] as List);
      return '[]';
    });
    await pumpScreen(tester);
    await tester.tap(find.text('Random public IPv4'));
    await tester.pump();
    await enter(tester, 'Random public IPv4 count (max 200000)', '3');
    await start(tester);
    await tester.pumpAndSettle();
    expect(scanned, hasLength(3));
    expect(scanned!.toSet(), hasLength(3));
    expect(
      scanned!.every((ip) => !ip.contains(':') && ip.split('.').length == 4),
      isTrue,
    );
  });

  testWidgets('IPv6 input is refused before native scanning', (tester) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') calls++;
      return jsonEncode([]);
    });
    await pumpScreen(tester);
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '2001:db8::1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('IPv6 is not supported'), findsWidgets);
  });

  Map<String, dynamic> safeResult(String ip) => {
    'ip': ip,
    'udpMs': 8,
    'tcpMs': 12,
    'reachable': true,
    'ednsSupported': true,
    'nxdomainSafe': true,
    'nxdomainHijacked': false,
    'tunnelCandidate': true,
  };

  testWidgets('safe UDP candidate returns resolver and retains tested port', (
    tester,
  ) async {
    var scannedPort = 0;
    int? selected;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      scannedPort = (call.arguments as Map)['port'] as int;
      return jsonEncode([safeResult('1.1.1.1')]);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DnsScannerScreen(
          initialPort: 5353,
          onPortSelected: (port) => selected = port,
        ),
      ),
    );
    await tester.pump();
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '1.1.1.1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(scannedPort, 5353);
    await enter(tester, 'Port', '853');
    await tester.tap(find.textContaining('1.1.1.1').last);
    expect(selected, 5353);
  });

  testWidgets('TCP-only or hijacked candidates cannot be selected', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      return jsonEncode([
        {...safeResult('1.1.1.1'), 'udpMs': -1},
        {...safeResult('1.1.1.2'), 'nxdomainHijacked': true},
      ]);
    });
    await pumpScreen(tester);
    await enter(
      tester,
      'Paste IPv4 addresses or CIDR ranges',
      '1.1.1.1 1.1.1.2',
    );
    await start(tester);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('1.1.1.1 · Cloudflare'));
    expect(find.textContaining('Not selectable'), findsNWidgets(2));
    await tester.tap(find.textContaining('1.1.1.1').last);
    expect(find.text('DNS resolver discovery'), findsOneWidget);
  });

  testWidgets(
    'Stop cancels pending native scan without starting later chunks',
    (tester) async {
      final pending = Completer<String>();
      var calls = 0;
      messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (
        call,
      ) async {
        if (call.method != 'scanDns') return null;
        calls++;
        return pending.future;
      });
      await pumpScreen(tester);
      await enter(tester, 'From IPv4', '1.1.1.1');
      await enter(tester, 'To IPv4', '1.1.1.3');
      await enter(tester, 'Workers (1–64)', '1');
      await start(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, 1);
      await tester.tap(find.byTooltip('Stop'));
      pending.complete('[]');
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets('Workers zero is rejected before native scanning', (
    tester,
  ) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') calls++;
      return '[]';
    });
    await pumpScreen(tester);
    await enter(tester, 'Paste IPv4 addresses or CIDR ranges', '1.1.1.1');
    await enter(tester, 'Workers (1–64)', '0');
    await start(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('IPv6 From input is rejected before native scanning', (
    tester,
  ) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method == 'scanDns') calls++;
      return '[]';
    });
    await pumpScreen(tester);
    await enter(tester, 'From IPv4', '2001:db8::1');
    await enter(tester, 'To IPv4', '2001:db8::1');
    await start(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('IPv6 is not supported'), findsWidgets);
  });
}
