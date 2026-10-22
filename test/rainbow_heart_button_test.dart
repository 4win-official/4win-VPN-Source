import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/rainbow_heart_button.dart';

void main() {
  const calloutKey = ValueKey('support-callout');
  const opacityKey = ValueKey('support-callout-opacity');

  Future<void> waitForCallout(WidgetTester tester) async {
    for (var second = 0; second < 7; second++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byKey(calloutKey).evaluate().isNotEmpty) return;
    }
    fail('Support callout did not appear');
  }

  Future<void> showCallout(WidgetTester tester) async {
    await waitForCallout(tester);
    await tester.pump(const Duration(milliseconds: 450));
  }

  double opacity(WidgetTester tester) =>
      tester.widget<Opacity>(find.byKey(opacityKey)).opacity;

  Widget harness({
    required TextDirection direction,
    VoidCallback? onPressed,
    bool dark = false,
    bool reduceMotion = false,
  }) => MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
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

  testWidgets('bubble fades, slides and scales into its anchored position', (
    tester,
  ) async {
    await tester.pumpWidget(harness(direction: TextDirection.ltr));
    await waitForCallout(tester);
    expect(opacity(tester), 0);
    final start = tester.getTopLeft(find.byKey(calloutKey));
    final transforms = find.ancestor(
      of: find.byKey(calloutKey),
      matching: find.byType(Transform),
    );
    final initialScale = tester.widget<Transform>(transforms.first).transform;
    expect(initialScale.entry(0, 0), closeTo(0.94, 0.001));
    await tester.pump(const Duration(milliseconds: 180));
    expect(opacity(tester), allOf(greaterThan(0), lessThan(1)));
    final duringIntro = tester.getTopLeft(find.byKey(calloutKey));
    await tester.pump(const Duration(milliseconds: 240));
    expect(opacity(tester), 1);
    final end = tester.getTopLeft(find.byKey(calloutKey));
    expect(duringIntro.dy, greaterThan(start.dy));
    expect(end.dy, greaterThan(duringIntro.dy));
    expect(tester.widget<Transform>(transforms.first).transform.entry(0, 0), 1);
    expect(find.text('Support Us'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final tapHeart in [false, true]) {
    testWidgets('tapping ${tapHeart ? 'heart' : 'bubble'} opens support once', (
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
      await tester.tap(
        tapHeart ? find.byType(IconButton) : find.byKey(calloutKey),
      );
      await tester.pump();
      expect(presses, 1);
      // Navigation remains immediate; an overlay must not linger on that page.
      expect(find.byKey(calloutKey), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 60));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('bubble animates out at four seconds without accepting taps', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      harness(direction: TextDirection.ltr, onPressed: () => presses++),
    );
    await waitForCallout(tester);
    await tester.pump(const Duration(milliseconds: 420));
    await tester.pump(const Duration(milliseconds: 3579));
    expect(opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(calloutKey), findsOneWidget);
    final ignoring = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.byKey(calloutKey),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(ignoring.ignoring, isTrue);
    await tester.pump(const Duration(milliseconds: 120));
    expect(opacity(tester), allOf(greaterThan(0), lessThan(1)));
    await tester.tap(find.byKey(calloutKey), warnIfMissed: false);
    expect(presses, 0);
    await tester.pump(const Duration(milliseconds: 136));
    // Overlay removal requested during the final animation frame is rebuilt
    // on the next frame.
    await tester.pump();
    expect(find.byKey(calloutKey), findsNothing);
    // The next random appearance is still scheduled after the original deadline.
    await showCalloutAfterRepeat(tester);
    expect(opacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion skips both transitions, retaining four seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(direction: TextDirection.ltr, reduceMotion: true),
    );
    await waitForCallout(tester);
    expect(opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 3999));
    expect(find.byKey(calloutKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(calloutKey), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final elapsed in [100, 4100]) {
    testWidgets('dispose safely during animation at ${elapsed}ms', (
      tester,
    ) async {
      await tester.pumpWidget(harness(direction: TextDirection.ltr));
      await waitForCallout(tester);
      if (elapsed > 4000) {
        await tester.pump(const Duration(milliseconds: 420));
        await tester.pump(const Duration(milliseconds: 3580));
        await tester.pump(Duration(milliseconds: elapsed - 4000));
      } else {
        await tester.pump(Duration(milliseconds: elapsed));
      }
      expect(find.byKey(calloutKey), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 60));
      expect(find.byKey(calloutKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> showCalloutAfterRepeat(WidgetTester tester) async {
  for (var second = 0; second < 49; second++) {
    await tester.pump(const Duration(seconds: 1));
    if (find.byKey(const ValueKey('support-callout')).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 450));
      return;
    }
  }
  fail('Support callout did not reappear');
}
