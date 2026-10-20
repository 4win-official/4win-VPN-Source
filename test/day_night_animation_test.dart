import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/day_night_animation.dart';

Finder _dayNightPaint() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is DayNightPainter,
);

DayNightPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_dayNightPaint().first).painter!
        as DayNightPainter;

Widget _host({
  required Brightness brightness,
  bool disableAnimations = false,
  bool tickerEnabled = true,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    themeAnimationDuration: Duration.zero,
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

Future<Uint8List> _renderNight(double progress) async {
  final recorder = ui.PictureRecorder();
  DayNightPainter(
    progress: progress,
    isDark: true,
  ).paint(Canvas(recorder), const Size(390, 844));
  final picture = recorder.endRecording();
  final image = await picture.toImage(390, 844);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = Uint8List.fromList(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return pixels;
}

void main() {
  testWidgets('derives light/night painter state from Theme brightness', (
    tester,
  ) async {
    await tester.pumpWidget(_host(brightness: Brightness.light));
    expect(_painter(tester).isDark, isFalse);

    await tester.pumpWidget(_host(brightness: Brightness.dark));
    expect(_painter(tester).isDark, isTrue);
  });

  testWidgets('is pointer-transparent and honors reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(brightness: Brightness.light, disableAnimations: true),
    );
    final ignore = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(DayNightAnimation),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignore.ignoring, isTrue);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('honors a disabled TickerMode and disposes cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(brightness: Brightness.dark, tickerEnabled: false),
    );
    expect(
      TickerMode.of(tester.element(find.byType(DayNightAnimation))),
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test(
    'DayNightPainter exposes state and distinguishes light/night paint state',
    () {
      final light = DayNightPainter(progress: 0.25, isDark: false);
      final night = DayNightPainter(progress: 0.25, isDark: true);
      expect(light.progress, 0.25);
      expect(light.isDark, isFalse);
      expect(night.isDark, isTrue);
      expect(light.shouldRepaint(night), isTrue);
    },
  );

  test('sun stays below the header in a compact upper-right pocket', () {
    for (final size in [
      const Size(320, 640),
      const Size(390, 844),
      const Size(430, 932),
      const Size(844, 390),
      const Size(240, 160),
    ]) {
      for (final header in [56.0, 100.0]) {
        final sun = DayNightPainter(
          progress: 0,
          isDark: false,
          headerHeight: header,
        ).sunBounds(size);
        expect(sun.top, greaterThanOrEqualTo(header + 8));
        expect(sun.right, lessThanOrEqualTo(size.width));
        expect(sun.bottom, lessThanOrEqualTo(size.height));
        expect(sun.center.dx, greaterThan(size.width * 0.65));
        // Keep the full corona within 104px of the header, clear of controls.
        expect(sun.bottom - header, lessThanOrEqualTo(104));
      }
    }
  });

  testWidgets(
    'procedural stars brighten and dim independently, with a seamless loop',
    (tester) async {
      final frames = (await tester.runAsync(
        () async => [
          await _renderNight(0),
          await _renderNight(0.073),
          await _renderNight(0),
          await _renderNight(1),
        ],
      ))!;
      final [start, later, repeat, loopEnd] = frames;
      expect(repeat, orderedEquals(start));
      expect(loopEnd, orderedEquals(start));

      var brightening = 0;
      var dimming = 0;
      // The left half excludes the moon and its changing glow. The gradient is
      // static, so changes here must come from the procedurally painted stars.
      for (var y = 80; y < 700; y++) {
        for (var x = 0; x < 190; x++) {
          final pixel = (y * 390 + x) * 4;
          final delta = later[pixel] - start[pixel];
          if (delta > 2) brightening++;
          if (delta < -2) dimming++;
        }
      }
      expect(brightening, greaterThan(15));
      expect(dimming, greaterThan(15));
    },
  );

  testWidgets(
    'night twinkle advances and freezes when reduced motion is enabled',
    (tester) async {
      await tester.pumpWidget(_host(brightness: Brightness.dark));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      final moving = _painter(tester).progress;
      expect(moving, greaterThan(0));
      await tester.pumpWidget(
        _host(brightness: Brightness.dark, disableAnimations: true),
      );
      final frozen = _painter(tester).progress;
      await tester.pump(const Duration(seconds: 2));
      expect(_painter(tester).progress, frozen);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(_host(brightness: Brightness.dark));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(_painter(tester).progress, greaterThan(frozen));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
