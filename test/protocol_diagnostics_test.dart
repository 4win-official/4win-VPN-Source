import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/protocol_diagnostics.dart';
import 'package:vpn_swift/widgets/protocol_chain_diagnostics.dart';

void main() {
  group('ProtocolDiagnostics', () {
    test('provides protocol-specific steps for every standalone protocol', () {
      final cases = <(String, bool, String)>[
        ('xray', false, 'Xray'),
        ('xray', true, 'Xray Proxy'),
        ('proxy', false, 'Proxy'),
        ('proxy', true, 'Proxy'),
        ('warp', false, 'WARP'),
        ('openvpn', false, 'OpenVPN'),
        ('sstp', false, 'SSTP'),
        ('psiphon', false, 'Psiphon'),
        ('direct_dns', false, 'DNS changer'),
        ('slowdns', false, 'Slow DNS'),
      ];

      for (final (protocol, proxyMode, expectedName) in cases) {
        final diagnostics = ProtocolDiagnostics.begin(
          protocol: protocol,
          attemptId: 'attempt-$protocol-$proxyMode',
          proxyMode: proxyMode,
        );
        expect(diagnostics.displayName, expectedName);
        expect(diagnostics.steps, isNotEmpty);
        expect(diagnostics.outcome, ConnectionAttemptOutcome.connecting);
      }
    });

    testWidgets('shows the exact failed stage and retains its cause', (
      tester,
    ) async {
      final diagnostics =
          ProtocolDiagnostics.begin(
                protocol: 'psiphon',
                attemptId: 'psiphon-timeout',
                proxyMode: false,
              )
              .updateStep(
                0,
                ConnectionStepState.complete,
                detail: 'Psiphon service accepted the start request.',
              )
              .updateStep(
                1,
                ConnectionStepState.running,
                detail: 'Waiting for the native core and traffic bridge.',
              )
              .failCurrent('Startup timed out after 4 attempts.');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProtocolConnectionGraph(diagnostics: diagnostics),
          ),
        ),
      );

      expect(find.text('1. Psiphon service start'), findsOneWidget);
      expect(find.text('2. Psiphon core and traffic bridge'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Failed here'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Failure detected at step 2'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Failure detected at step 2'), findsOneWidget);
      expect(find.text('Startup timed out after 4 attempts.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps connected but unverified stages visibly unverified', (
      tester,
    ) async {
      final diagnostics =
          ProtocolDiagnostics.begin(
                protocol: 'openvpn',
                attemptId: 'openvpn-connected',
                proxyMode: false,
              )
              .updateStep(
                2,
                ConnectionStepState.complete,
                detail: 'OpenVPN reported the tunnel connected.',
              )
              .updateOutcome(ConnectionAttemptOutcome.connected);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProtocolConnectionGraph(diagnostics: diagnostics),
          ),
        ),
      );

      expect(find.text('3. OpenVPN tunnel connected'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('4. Internet traffic through the tunnel'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(
        find.text('4. Internet traffic through the tunnel'),
        findsOneWidget,
      );
      expect(find.text('Unverified'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Connected (some stages remain unverified)'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(
        find.text('Connected (some stages remain unverified)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
