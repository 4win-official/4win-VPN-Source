import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/liquid_background.dart';

Widget _app({
  bool dark = false,
  bool reduceMotion = false,
  bool enabled = true,
}) => MaterialApp(
  theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: TickerMode(
      enabled: enabled,
      child: const SizedBox.expand(child: LiquidBackground()),
    ),
  ),
);

Rect _glow(WidgetTester tester, String name) =>
    tester.getRect(find.byKey(ValueKey(name)));

LinearGradient _gradient(WidgetTester tester) =>
    (tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('liquid-gradient')),
                    )
                    .decoration
                as BoxDecoration)
            .gradient!
        as LinearGradient;

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'both glows and the gradient flow in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await tester.pumpWidget(_app(dark: dark));
        await tester.pump();
        final cyan = _glow(tester, 'liquid-cyan-glow');
        final violet = _glow(tester, 'liquid-violet-glow');
        final gradient = _gradient(tester);
        await tester.pump(const Duration(seconds: 3));
        final movedCyan = _glow(tester, 'liquid-cyan-glow');
        final movedViolet = _glow(tester, 'liquid-violet-glow');
        expect((movedCyan.center - cyan.center).distance, greaterThan(40));
        expect((movedViolet.center - violet.center).distance, greaterThan(40));
        expect(movedCyan.size, isNot(cyan.size));
        expect(movedViolet.size, isNot(violet.size));
        expect(_gradient(tester).begin, isNot(gradient.begin));
        expect(_gradient(tester).end, isNot(gradient.end));
        expect(_gradient(tester).stops, isNot(gradient.stops));
        expect(_gradient(tester).colors, gradient.colors);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
        expect(tester.hasRunningAnimations, isFalse);
      },
    );
  }

  testWidgets(
    'the twelve-second loop closes without a position or color jump',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();
      final cyan = _glow(tester, 'liquid-cyan-glow');
      final violet = _glow(tester, 'liquid-violet-glow');
      final gradient = _gradient(tester);
      await tester.pump(const Duration(milliseconds: 11999));
      expect(
        (_glow(tester, 'liquid-cyan-glow').center - cyan.center).distance,
        lessThan(1),
      );
      expect(
        (_glow(tester, 'liquid-violet-glow').center - violet.center).distance,
        lessThan(1),
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(_glow(tester, 'liquid-cyan-glow'), cyan);
      expect(_glow(tester, 'liquid-violet-glow'), violet);
      expect(_gradient(tester), gradient);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reduced motion stops the background and can be toggled off', (
    tester,
  ) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    final initial = _glow(tester, 'liquid-cyan-glow');
    final gradient = _gradient(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_glow(tester, 'liquid-cyan-glow'), initial);
    expect(_gradient(tester), gradient);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(_glow(tester, 'liquid-cyan-glow'), isNot(initial));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background pauses offscreen and when the app is inactive', (
    tester,
  ) async {
    await tester.pumpWidget(_app(enabled: false));
    final initial = _glow(tester, 'liquid-cyan-glow');
    await tester.pump(const Duration(seconds: 3));
    expect(_glow(tester, 'liquid-cyan-glow'), initial);
    await tester.pumpWidget(_app());
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final paused = _glow(tester, 'liquid-cyan-glow');
    final gradient = _gradient(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_glow(tester, 'liquid-cyan-glow'), paused);
    expect(_gradient(tester), gradient);
    expect(tester.hasRunningAnimations, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(_glow(tester, 'liquid-cyan-glow'), isNot(paused));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('decorative background does not intercept foreground controls', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Connect'),
              ),
            ),
            const LiquidBackground(),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Connect'));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
