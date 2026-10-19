import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/slowdns_config.dart';
import 'package:vpn_swift/screens/dns_scanner_screen.dart';
import 'package:vpn_swift/screens/slowdns_profile_screen.dart';
import 'package:vpn_swift/services/dns_vpn_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(DnsVpnConnection.platform, null),
  );

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final finder = find.widgetWithText(TextFormField, label);
    await reveal(tester, finder);
    await tester.enterText(finder, value);
  }

  testWidgets(
    'small phone form is scrollable and unsupported options are disabled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SlowDnsProfileScreen()));
      await reveal(tester, find.widgetWithText(ChoiceChip, 'TCP'));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'TCP'))
            .onSelected,
        isNull,
      );
      await reveal(tester, find.text('Connection Method'));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'SSH'))
            .onSelected,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saves supported profile using host:port without changing stored schema',
    (tester) async {
      SlowDnsConfig? returned;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  returned = await Navigator.of(context).push<SlowDnsConfig>(
                    MaterialPageRoute(
                      builder: (_) => const SlowDnsProfileScreen(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await enter(tester, 'Profile Name', 'Fixture');
      await enter(tester, 'Domain', 't.example.com');
      await enter(tester, 'Public Key', List.filled(64, 'a').join());
      await enter(tester, 'DNS Resolver', '127.0.0.1:5353');
      await tester.tap(find.byTooltip('Save profile'));
      await tester.pumpAndSettle();
      expect(returned?.nameServer, '127.0.0.1');
      expect(returned?.effectivePort, 5353);
      expect(returned?.dnsTransport, 'udp');
      expect(returned?.isValid, isTrue);
    },
  );

  testWidgets(
    'resolver scan navigation preserves entered fields and returns selected IP and port',
    (tester) async {
      messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (
        call,
      ) async {
        if (call.method != 'scanDns') return null;
        return jsonEncode([
          {
            'ip': '127.0.0.1',
            'udpMs': 3,
            'tcpMs': 4,
            'reachable': true,
            'ednsSupported': true,
            'nxdomainSafe': true,
            'tunnelCandidate': true,
          },
        ]);
      });
      await tester.pumpWidget(const MaterialApp(home: SlowDnsProfileScreen()));
      await enter(tester, 'Profile Name', 'Keep me');
      await enter(tester, 'Domain', 't.example.com');
      await enter(tester, 'DNS Resolver', '127.0.0.1:5353');
      await tester.tap(find.byTooltip('Scan for Working Resolvers'));
      await tester.pumpAndSettle();
      expect(find.byType(DnsScannerScreen), findsOneWidget);
      final scanner = tester.widget<DnsScannerScreen>(
        find.byType(DnsScannerScreen),
      );
      expect(scanner.probeDomain, 't.example.com');
      expect(scanner.initialPort, 5353);
      // Exercise the same selection contract without launching any network work.
      scanner.onPortSelected?.call(5454);
      Navigator.of(
        tester.element(find.byType(DnsScannerScreen)),
      ).pop('127.0.0.2');
      await tester.pumpAndSettle();
      final resolver = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'DNS Resolver'),
      );
      expect(resolver.controller!.text, '127.0.0.2:5454');
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 2000),
        1000,
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(TextFormField, 'Profile Name'));
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Profile Name'),
            )
            .controller!
            .text,
        'Keep me',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed persistence retains the entered profile for retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SlowDnsProfileScreen(onSave: (_) async => false)),
    );
    await enter(tester, 'Profile Name', 'Duplicate');
    await enter(tester, 'Domain', 't.example.com');
    await enter(tester, 'Public Key', List.filled(64, 'a').join());
    await enter(tester, 'DNS Resolver', '127.0.0.1:5353');
    await tester.tap(find.byTooltip('Save profile'));
    await tester.pumpAndSettle();
    expect(find.byType(SlowDnsProfileScreen), findsOneWidget);
    expect(find.textContaining('Could not save profile.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'DNS Resolver'),
          )
          .controller!
          .text,
      '127.0.0.1:5353',
    );
  });

  testWidgets(
    'DoT defaults port without changing custom ports and disables plaintext scan',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SlowDnsProfileScreen()));
      await enter(tester, 'DNS Resolver', 'dns.example:5353');
      await reveal(tester, find.widgetWithText(ChoiceChip, 'DoT'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'DoT'));
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(TextFormField, 'DNS Resolver'));
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'DNS Resolver'),
            )
            .controller!
            .text,
        'dns.example:5353',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Scanner tests UDP only',
              ),
            )
            .onPressed,
        isNull,
      );
      await enter(tester, 'DNS Resolver', 'dns.example:853');
      await reveal(tester, find.widgetWithText(ChoiceChip, 'UDP'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'UDP'));
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(TextFormField, 'DNS Resolver'));
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'DNS Resolver'),
            )
            .controller!
            .text,
        'dns.example:53',
      );
    },
  );
}
