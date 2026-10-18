import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/rain_animation.dart';

void main() {
  group('RainSimulation', () {
    test(
      'seeded simulations have varied depth/speed and deterministic drops',
      () {
        final first = RainSimulation(random: Random(42), dropCount: 24);
        final second = RainSimulation(random: Random(42), dropCount: 24);

        expect(first.drops.length, 24);
        for (var i = 0; i < first.drops.length; i++) {
          expect(first.drops[i].depth, second.drops[i].depth);
          expect(first.drops[i].speed, second.drops[i].speed);
          expect(first.drops[i].length, second.drops[i].length);
          expect(first.drops[i].phase, second.drops[i].phase);
        }
        expect(
          first.drops.map((drop) => drop.depth).toSet().length,
          greaterThan(1),
        );
        expect(
          first.drops.map((drop) => drop.speed).toSet().length,
          greaterThan(1),
        );
        expect(
          first.drops.map((drop) => drop.length).toSet().length,
          greaterThan(1),
        );

        first.dispose();
        second.dispose();
      },
    );

    test(
      'drops move downward and predominantly diagonally with changing wind',
      () {
        final rain = RainSimulation(random: Random(7), dropCount: 8);
        rain.resize(const Size(320, 240));
        for (final drop in rain.drops) {
          drop.x = 100;
          drop.y = 100;
        }
        final before = rain.drops
            .map((drop) => Offset(drop.x, drop.y))
            .toList();
        final initialWind = rain.wind;

        rain.advance(0.04);
        expect(rain.time, closeTo(0.04, 1e-10));
        for (var i = 0; i < rain.drops.length; i++) {
          expect(rain.drops[i].y, greaterThan(before[i].dy));
          expect(rain.drops[i].x, isNot(equals(before[i].dx)));
        }
        rain.advance(1.0);
        expect(rain.time, greaterThan(0.04));
        expect(rain.wind, isNot(equals(initialWind)));
        expect(
          rain.drops.map((drop) => drop.velocityX).toSet().length,
          greaterThan(1),
        );
        rain.dispose();
      },
    );

    test('elapsed time is monotonic and is not reset by an 800ms frame', () {
      final rain = RainSimulation(random: Random(11), dropCount: 2);
      rain.resize(const Size(2000, 4000));
      final drop = rain.drops.first;
      drop.y = 0;
      for (var frame = 0; frame < 60; frame++) {
        final previousY = drop.y;
        rain.advance(1 / 60);
        expect(drop.y, greaterThan(previousY));
      }
      expect(rain.time, closeTo(1, 1e-10));
      expect(drop.y, closeTo(drop.speed, 1e-8));
      // A suspended frame advances gently, never by its full elapsed duration.
      rain.advance(8);
      expect(rain.time, closeTo(1.05, 1e-10));
      rain.dispose();
    });

    test('30fps and 120fps produce equivalent motion', () {
      final slow = RainSimulation(random: Random(12), dropCount: 1);
      final fast = RainSimulation(random: Random(12), dropCount: 1);
      for (final rain in [slow, fast]) {
        rain.resize(const Size(2000, 4000));
        rain.drops.single.x = 100;
        rain.drops.single.y = 0;
      }
      for (var frame = 0; frame < 30; frame++) {
        slow.advance(1 / 30);
      }
      for (var frame = 0; frame < 120; frame++) {
        fast.advance(1 / 120);
      }
      expect(slow.drops.single.y, closeTo(fast.drops.single.y, 1e-8));
      expect(slow.drops.single.x, closeTo(fast.drops.single.x, 1));
      slow.dispose();
      fast.dispose();
    });

    test('recycles drops only after they leave the visible frame', () {
      final rain = RainSimulation(random: Random(3), dropCount: 1);
      rain.resize(const Size(100, 100));
      final drop = rain.drops.single;

      drop.y = 100 + drop.length + 25;
      rain.advance(0.001);
      expect(drop.y, lessThan(0));

      drop.x = 165;
      drop.y = 50;
      rain.advance(0.001);
      expect(drop.x, lessThan(0));
      expect(drop.y, inInclusiveRange(0, 100));

      drop.x = -65;
      drop.y = 50;
      rain.advance(0.001);
      expect(drop.x, greaterThan(100));
      expect(drop.y, inInclusiveRange(0, 100));
      rain.dispose();
    });

    test('ignores invalid time and invalid or empty sizes', () {
      final rain = RainSimulation(random: Random(5), dropCount: 1);
      rain.resize(Size.zero);
      rain.resize(const Size(double.infinity, 100));
      expect(rain.time, 0);
      expect(rain.drops.single.x, 0);
      expect(rain.drops.single.y, 0);

      rain.resize(const Size(100, 80));
      final position = Offset(rain.drops.single.x, rain.drops.single.y);
      rain.advance(double.nan);
      rain.advance(double.infinity);
      rain.advance(-1);
      expect(rain.time, 0);
      expect(Offset(rain.drops.single.x, rain.drops.single.y), position);

      final timeBeforeSameSize = rain.time;
      rain.resize(const Size(100, 80));
      expect(rain.time, timeBeforeSameSize);
      rain.dispose();
    });

    test('resizing a non-empty simulation preserves relative positions', () {
      final rain = RainSimulation(random: Random(9), dropCount: 1);
      rain.resize(const Size(100, 100));
      final drop = rain.drops.single;
      drop.x = 25;
      drop.y = 40;
      rain.resize(const Size(200, 50));
      expect(drop.x, 50);
      expect(drop.y, 20);
      rain.dispose();
    });
  });

  test(
    'rain has visible contrast on both the backdrop and power button',
    () async {
      const size = Size(120, 120);
      final rain = RainSimulation(random: Random(42), dropCount: 1);
      rain.resize(size);
      final drop = rain.drops.single;
      drop.x = 60;
      drop.y = 70;

      for (final background in [Colors.black, Colors.white]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(background, BlendMode.src);
        RainPainter(rain).paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(120, 120);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final baseline = background == Colors.black ? 0 : 255;
        var visiblePixels = 0;
        for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
          if ((pixels.getUint8(offset) - baseline).abs() >= 20 ||
              (pixels.getUint8(offset + 1) - baseline).abs() >= 20 ||
              (pixels.getUint8(offset + 2) - baseline).abs() >= 20) {
            visiblePixels++;
          }
        }
        expect(
          visiblePixels,
          greaterThan(12),
          reason: 'background: $background',
        );
        image.dispose();
        picture.dispose();
      }
      rain.dispose();
    },
  );

  test(
    'solid button masks airborne drops but leaves surrounding rain visible',
    () async {
      final rain = RainSimulation(random: Random(42), dropCount: 2);
      rain.resize(const Size(120, 120));
      rain.drops[0].x = 60;
      rain.drops[0].y = 70;
      rain.drops[1].x = 10;
      rain.drops[1].y = 70;
      final recorder = ui.PictureRecorder();
      RainPainter(
        rain,
        obstacleBounds: () => const Rect.fromLTWH(30, 30, 60, 60),
      ).paint(Canvas(recorder), const Size(120, 120));
      final picture = recorder.endRecording();
      final image = await picture.toImage(120, 120);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var outsidePixels = 0;
      for (var y = 40; y < 80; y++) {
        for (var x = 0; x < 80; x++) {
          final alpha = pixels.getUint8((y * 120 + x) * 4 + 3);
          if (x >= 45 && x <= 75 && y >= 45 && y <= 75) {
            expect(
              alpha,
              0,
              reason: 'airborne rain inside the button at $x,$y',
            );
          }
          if (x < 25 && alpha > 0) outsidePixels++;
        }
      }
      expect(outsidePixels, greaterThan(12));
      image.dispose();
      picture.dispose();
      rain.dispose();
    },
  );

  group('RainAnimation widget', () {
    Future<void> pumpRain(
      WidgetTester tester, {
      bool disableAnimations = false,
      bool tickerEnabled = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: TickerMode(
              enabled: tickerEnabled,
              child: const SizedBox(
                width: 160,
                height: 120,
                child: RainAnimation(),
              ),
            ),
          ),
        ),
      );
    }

    RainSimulation simulation(WidgetTester tester) {
      final customPaint = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is RainPainter,
        ),
      );
      return (customPaint.painter! as RainPainter).rain;
    }

    testWidgets('is wrapped in IgnorePointer', (tester) async {
      await pumpRain(tester);
      final ignore = tester.widget<IgnorePointer>(
        find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.child is LayoutBuilder,
        ),
      );
      expect(ignore.ignoring, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('does not advance while MediaQuery disables animations', (
      tester,
    ) async {
      await pumpRain(tester, disableAnimations: true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(simulation(tester).time, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('does not advance while TickerMode is disabled', (
      tester,
    ) async {
      await pumpRain(tester, tickerEnabled: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(simulation(tester).time, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('advances when animations are enabled and disposes cleanly', (
      tester,
    ) async {
      await pumpRain(tester);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 50));
      expect(simulation(tester).time, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
