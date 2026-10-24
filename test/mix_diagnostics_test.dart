import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/models/mix_diagnostics.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/widgets/mix_chain_diagnostics.dart';

class _GraphProvider extends ChangeNotifier implements VpnProvider {
  _GraphProvider(this.mixDiagnostics);
  @override
  final MixDiagnostics? mixDiagnostics;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MixStrategy chain(int length) => MixStrategy(
  id: 'chain',
  name: 'Exact order',
  hops: List.generate(
    length,
    (i) => MixHop(
      protocol: i.isEven ? 'direct_dns' : 'psiphon',
      serverId: i.isEven ? '1.1.1.1' : 'default',
    ),
  ),
);

void main() {
  test('keeps repeated DNS and self-chain occurrences in all 50 positions', () {
    final strategy = chain(50);
    final diagnostics = MixDiagnostics.begin(strategy, 'attempt');
    final blocks = List.generate(
      50,
      (i) => {
        'index': i,
        'state': i < 26
            ? 'ready'
            : i == 26
            ? 'failed'
            : 'pending',
      },
    );
    final result = diagnostics.applyNative({
      'attemptId': 'attempt',
      'phase': 'Chain failed',
      'blocks': blocks,
    });
    expect(result.hops, strategy.hops);
    expect(result.states[25], MixBlockState.ready);
    expect(result.states[26], MixBlockState.failed);
    expect(result.states[27], MixBlockState.pending);
    expect(result.hops[26].protocol, 'direct_dns');
    expect(
      () => result.states[0] = MixBlockState.failed,
      throwsUnsupportedError,
    );
  });

  test('stale, duplicate, incomplete and unknown native data is ignored', () {
    final diagnostics = MixDiagnostics.begin(chain(2), 'current');
    for (final snapshot in [
      {
        'attemptId': 'old',
        'blocks': [
          {'index': 0, 'state': 'failed'},
          {'index': 1, 'state': 'pending'},
        ],
      },
      {
        'attemptId': 'current',
        'blocks': [
          {'index': 0, 'state': 'failed'},
        ],
      },
      {
        'attemptId': 'current',
        'blocks': [
          {'index': 0, 'state': 'failed'},
          {'index': 0, 'state': 'ready'},
        ],
      },
      {
        'attemptId': 'current',
        'blocks': [
          {'index': 0, 'state': 'invented'},
          {'index': 1, 'state': 'ready'},
        ],
      },
    ]) {
      expect(identical(diagnostics.applyNative(snapshot), diagnostics), isTrue);
    }
  });

  test('keeps the verified public WARP exit IP on the original block', () {
    final diagnostics = MixDiagnostics.begin(chain(2), 'attempt');
    final result = diagnostics.applyNative({
      'attemptId': 'attempt',
      'phase': 'Verifying WARP egress',
      'blocks': [
        {
          'index': 0,
          'state': 'verified',
          'detail': 'WARP reachable · exit IP 104.16.132.229',
        },
        {'index': 1, 'state': 'ready'},
      ],
    });
    expect(result.states, [MixBlockState.verified, MixBlockState.ready]);
    expect(result.details, [
      'WARP reachable · exit IP 104.16.132.229',
      null,
    ]);
  });

  test('global failure does not invent a failed final block', () {
    final result = MixDiagnostics.begin(chain(2), 'a').applyNative({
      'attemptId': 'a',
      'phase': 'Chain failed',
      'message': 'secret endpoint',
      'blocks': [
        {'index': 0, 'state': 'ready'},
        {'index': 1, 'state': 'ready'},
      ],
    });
    expect(result.states, everyElement(MixBlockState.ready));
    expect(result.message, isNot(contains('secret endpoint')));
  });

  testWidgets(
    'graph contains exact numbered connected blocks through block 50',
    (tester) async {
      final diagnostics = MixDiagnostics.begin(chain(50), 'a');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixChainGraph(diagnostics: diagnostics)),
        ),
      );
      expect(find.byKey(const ValueKey('mix-graph-block-0')), findsOneWidget);
      expect(find.text('1. DNS'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsWidgets);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mix-graph-block-49')),
        450,
        scrollable: find.byType(Scrollable),
        maxScrolls: 40,
      );
      expect(find.text('50. Psiphon'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'only a button appears after failure, graph is not opened automatically',
    (tester) async {
      final pending = MixDiagnostics.begin(chain(3), 'a');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixChainDiagnostics(diagnostics: pending)),
        ),
      );
      expect(find.text('View failed chain'), findsNothing);
      final failed = pending.update(
        phase: 'Chain failed',
        states: [
          MixBlockState.ready,
          MixBlockState.failed,
          MixBlockState.pending,
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixChainDiagnostics(diagnostics: failed)),
        ),
      );
      expect(find.text('View failed chain'), findsOneWidget);
      expect(find.byType(MixChainGraph), findsNothing);
      expect(find.text('1. DNS'), findsNothing);
    },
  );

  testWidgets(
    'unknown failure is a graph endpoint, never a guessed failed block',
    (tester) async {
      final diagnostics = MixDiagnostics.begin(chain(2), 'a').update(
        phase: 'Chain failed',
        states: [MixBlockState.unverified, MixBlockState.unverified],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixChainGraph(diagnostics: diagnostics)),
        ),
      );
      expect(find.text('Failure location unknown'), findsOneWidget);
      expect(find.text('Failed here'), findsNothing);
      expect(find.text('Unknown'), findsNWidgets(2));
    },
  );
  testWidgets('failure button opens connected graphical blocks on tap', (
    tester,
  ) async {
    final failed = MixDiagnostics.begin(chain(3), 'tap').update(
      phase: 'Chain failed',
      states: [
        MixBlockState.ready,
        MixBlockState.failed,
        MixBlockState.pending,
      ],
    );
    final provider = _GraphProvider(failed);
    await tester.pumpWidget(
      ChangeNotifierProvider<VpnProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(body: MixChainDiagnostics(diagnostics: failed)),
        ),
      ),
    );
    await tester.tap(find.text('View failed chain'));
    await tester.pumpAndSettle();
    expect(find.byType(MixChainGraph), findsOneWidget);
    expect(find.byKey(const ValueKey('mix-graph-block-1')), findsOneWidget);
    expect(find.text('Failed here'), findsOneWidget);
    expect(find.text('Failure detected at block 2'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsWidgets);
    await tester.tap(find.byTooltip('Close chain graph'));
    await tester.pumpAndSettle();
    expect(find.byType(MixChainGraph), findsNothing);
    provider.dispose();
  });

  testWidgets(
    'successful Mix shows its chain graph with verified WARP egress',
    (tester) async {
      final strategy = MixStrategy(
        id: 'warp-chain',
        name: 'Verified WARP chain',
        hops: const [
          MixHop(protocol: 'xray', serverId: 'first'),
          MixHop(protocol: 'warp', serverId: 'default'),
        ],
      );
      final connected = MixDiagnostics.begin(strategy, 'connected').applyNative(
        {
          'attemptId': 'connected',
          'phase': 'Connected — complete-chain test passed',
          'blocks': [
            {'index': 0, 'state': 'ready'},
            {
              'index': 1,
              'state': 'verified',
              'detail': 'WARP reachable · exit IP 104.16.132.229',
            },
          ],
        },
      );
      final provider = _GraphProvider(connected);
      await tester.pumpWidget(
        ChangeNotifierProvider<VpnProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(body: MixChainDiagnostics(diagnostics: connected)),
          ),
        ),
      );

      expect(find.text('View Mix chain'), findsOneWidget);
      expect(find.text('View failed chain'), findsNothing);
      expect(find.byType(MixChainGraph), findsNothing);
      await tester.tap(find.text('View Mix chain'));
      await tester.pumpAndSettle();
      expect(find.byType(MixChainGraph), findsOneWidget);
      expect(find.text('1. Xray'), findsOneWidget);
      expect(find.text('2. WARP'), findsOneWidget);
      expect(find.text('WARP verified'), findsOneWidget);
      expect(
        find.text('WARP reachable · exit IP 104.16.132.229'),
        findsOneWidget,
      );
      expect(find.text('Connected'), findsOneWidget);
      expect(tester.takeException(), isNull);
      provider.dispose();
    },
  );
}
