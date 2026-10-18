import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/rainbow_heart_button.dart';

void main() {
  Future<void> showCallout(WidgetTester tester) async {
    for (var second = 0; second < 7; second++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byKey(const ValueKey('support-callout')).evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 450));
        return;
      }
    }
    fail('Support callout did not appear');
  }

  Widget harness({
    required TextDirection direction,
    VoidCallback? onPressed,
    bool dark = false,
  }) => MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: Directionality(
      textDirection: direction,
      child: Scaffold(
        appBar: AppBar(
          actions: [RainbowHeartButton(onPressed: onPressed ?? () {})],
        ),
      ),
    ),
  );

  for (final direction in TextDirection.values) {
    testWidgets('bubble tip points to heart in $direction', (tester) async {
      await tester.pumpWidget(harness(direction: direction));
      await showCallout(tester);
      final clipFinder = find.byKey(const ValueKey('support-callout-pointer'));
      final clip = tester.widget<ClipPath>(clipFinder);
      final size = tester.getSize(clipFinder);
      final path = clip.clipper!.getClip(size);
      final tipX = direction == TextDirection.ltr ? size.width - 24 : 24.0;
      expect(path.contains(Offset(tipX, 2)), isTrue);
      expect(path.contains(Offset(tipX - 13, 2)), isFalse);
      expect(path.contains(Offset(tipX + 13, 2)), isFalse);
      final heartCentre = tester.getCenter(find.byType(IconButton));
      final tip = tester.getTopLeft(clipFinder) + Offset(tipX, 0);
      expect(tip.dx, closeTo(heartCentre.dx, 1));
      expect(tip.dy, greaterThan(heartCentre.dy));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('dark bubble is tappable and dismisses after opening support', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      harness(
        direction: TextDirection.ltr,
        dark: true,
        onPressed: () => presses++,
      ),
    );
    await showCallout(tester);
    await tester.tap(find.byKey(const ValueKey('support-callout')));
    await tester.pump();
    expect(presses, 1);
    expect(find.byKey(const ValueKey('support-callout')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('bubble disappears automatically and cleans up timers', (
    tester,
  ) async {
    await tester.pumpWidget(harness(direction: TextDirection.ltr));
    await showCallout(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('support-callout')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(tester.takeException(), isNull);
  });
}
