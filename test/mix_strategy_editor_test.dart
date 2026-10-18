import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vpn_swift/screens/mix_strategy_editor_screen.dart';
import 'package:vpn_swift/models/mix_strategy.dart';

Widget _editor() => const MaterialApp(home: MixStrategyEditorScreen());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor renders black route canvas with start and palette', (
    tester,
  ) async {
    await tester.pumpWidget(_editor());

    expect(find.text('START'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('INTERNET'), findsOneWidget);
    expect(find.text('Drop or add a protocol block'), findsOneWidget);
    expect(find.text('ADD PROTOCOL BLOCK  (0/50)'), findsOneWidget);
    expect(find.text('Xray'), findsOneWidget);
    expect(find.text('Proxy'), findsOneWidget);
  });

  testWidgets('all native protocols are available in the palette', (
    tester,
  ) async {
    await tester.pumpWidget(_editor());

    expect(MixStrategy.unavailableReason('warp'), isNull);
    expect(find.text('WARP'), findsOneWidget);
    expect(find.text('Drop or add a protocol block'), findsOneWidget);
  });

  testWidgets('save validates an empty strategy before provider access', (
    tester,
  ) async {
    await tester.pumpWidget(_editor());

    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pump();

    expect(find.text('Enter a strategy name.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor shows the hard 50-block ceiling', (tester) async {
    final hops = List.generate(
      MixStrategy.maxBlocks,
      (i) => MixHop(protocol: 'xray', serverId: 'server-$i'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MixStrategyEditorScreen(
          existingStrategy: MixStrategy(id: 'full', name: 'Full', hops: hops),
        ),
      ),
    );
    expect(find.text('ADD PROTOCOL BLOCK  (50/50)'), findsOneWidget);
    expect(
      find.textContaining(
        'DNS is a resolver at the selected position, not a tunnel:',
      ),
      findsOneWidget,
    );
  });
}
