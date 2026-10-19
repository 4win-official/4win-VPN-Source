import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/day_night_animation.dart';

Finder _dayNightPaint() => find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is DayNightPainter,
    );

DayNightPainter _painter(WidgetTester tester) => tester.widget<CustomPaint>(
      _dayNightPaint().first,
    ).painter! as DayNightPainter;

Widget _host({
  required Brightness brightness,
  bool disableAnimations = false,
  bool tickerEnabled = true,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: TickerMode(
        enabled: tickerEnabled,
        child: const SizedBox(
          width: 240,
          height: 160,
          child: DayNightAnimation(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('derives light/night painter state from Theme brightness',
      (tester) async {
    await tester.pumpWidget(_host(brightness: Brightness.light));
    expect(_painter(tester).isDark, isFalse);

    await tester.pumpWidget(_host(brightness: Brightness.dark));
    expect(_painter(tester).isDark, isTrue);
  });

  testWidgets('is pointer-transparent and honors reduced motion', (tester) async {
    await tester.pumpWidget(
      _host(brightness: Brightness.light, disableAnimations: true),
    );
    final ignore = tester.widget<IgnorePointer>(find.byType(IgnorePointer));
    expect(ignore.ignoring, isTrue);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('honors a disabled TickerMode and disposes cleanly', (tester) async {
    await tester.pumpWidget(
      _host(brightness: Brightness.dark, tickerEnabled: false),
    );
    expect(TickerMode.of(tester.element(find.byType(DayNightAnimation))), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('DayNightPainter exposes state and distinguishes light/night paint state',
      () {
    final light = DayNightPainter(progress: 0.25, isDark: false);
    final night = DayNightPainter(progress: 0.25, isDark: true);
    expect(light.progress, 0.25);
    expect(light.isDark, isFalse);
    expect(night.isDark, isTrue);
    expect(light.shouldRepaint(night), isTrue);
  });
}
