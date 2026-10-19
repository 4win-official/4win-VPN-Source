import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/screens/dns_scanner_screen.dart';
import 'package:vpn_swift/services/dns_vpn_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, null);
  });

  Map<String, dynamic> result(
    String ip, {
    bool safe = false,
    bool tcpOnly = false,
  }) => {
    'ip': ip,
    'udpMs': tcpOnly ? -1 : 8,
    'tcpMs': 12,
    'reachable': true,
    'ednsSupported': true,
    'ednsPayload': 1232,
    'txtSupported': true,
    'responseBytes': 145,
    'tunnelVerified': false,
    'nxdomainSafe': safe,
    'nxdomainHijacked': !safe,
    'tunnelCandidate': safe,
  };

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(360, 640),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: DnsScannerScreen()));
    await tester.pump();
  }

  testWidgets('fits small phone layouts without a render exception', (
    tester,
  ) async {
    await pumpScreen(tester, size: const Size(320, 480));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Scan controls'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'safe resolver tap returns its IP while unsafe and TCP-only do not',
    (tester) async {
      messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (
        call,
      ) async {
        if (call.method != 'scanDns') return null;
        final ips = (call.arguments as Map)['ips'] as List;
        return jsonEncode(
          [
            result('1.1.1.1', safe: true),
            result('1.0.0.1', safe: false),
            result('8.8.8.8', safe: true, tcpOnly: true),
          ].where((r) => ips.contains(r['ip'])).toList(),
        );
      });
      String? returned;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Column(
                children: [
                  Text(returned ?? 'none'),
                  ElevatedButton(
                    onPressed: () async {
                      final value = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => const DnsScannerScreen(),
                        ),
                      );
                      setState(() => returned = value);
                    },
                    child: const Text('Open scanner'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open scanner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      expect(find.text('1.1.1.1 · Cloudflare'), findsOneWidget);
      expect(find.byTooltip('Copy resolver'), findsNWidgets(1));
      await tester.scrollUntilVisible(
        find.text('1.0.0.1 · Cloudflare'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('1.0.0.1 · Cloudflare'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('8.8.8.8 · Google'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('8.8.8.8 · Google'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('1.0.0.1 · Cloudflare'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('1.0.0.1 · Cloudflare'));
      await tester.pump();
      expect(find.byType(DnsScannerScreen), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('1.1.1.1 · Cloudflare'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('1.1.1.1 · Cloudflare'));
      await tester.pumpAndSettle();
      expect(find.byType(DnsScannerScreen), findsNothing);
      expect(find.text('1.1.1.1'), findsOneWidget);
    },
  );

  testWidgets('stop prevents later chunks', (tester) async {
    var calls = 0;
    final pending = Completer<String>();
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      calls++;
      if (calls == 1) return pending.future;
      return jsonEncode([result('1.2.3.4', safe: true)]);
    });
    await pumpScreen(tester);
    await tester.tap(find.text('Start scan'));
    await tester.pump();
    await tester.tap(find.byTooltip('Stop'));
    pending.complete(jsonEncode([result('1.1.1.1', safe: true)]));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('invalid custom IP shows an error', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField).first, 'not-an-ip');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Start scan'));
    await tester.pump();
    expect(find.textContaining('Invalid IP or CIDR'), findsOneWidget);
  });
}
