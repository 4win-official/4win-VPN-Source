import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/rain_button_surface.dart';

Widget host({
  bool enabled = true,
  bool tickerEnabled = true,
  bool disableAnimations = false,
  Widget child = const SizedBox.expand(),
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: TickerMode(
          enabled: tickerEnabled,
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: SizedBox.square(
              dimension: 200,
              child: RainButtonSurface(
                enabled: enabled,
                child: SizedBox.expand(
                  child: GestureDetector(
                    key: const ValueKey('gesture'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    onLongPress: onLongPress,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder surface() => find.byType(RainButtonSurface);
Finder customPaint() => find.descendant(
      of: surface(),
      matching: find.byType(CustomPaint),
    );

RainButtonPainter painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(customPaint()).painter!
        as RainButtonPainter;

Future<ui.Image> raster(double phase) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  RainButtonPainter(AlwaysStoppedAnimation<double>(phase))
      .paint(canvas, const Size(200, 200));
  return recorder.endRecording().toImage(200, 250);
}

Future<int> alphaPixels(ui.Image image, {int yStart = 0, int yEnd = 250}) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  var count = 0;
  for (var y = yStart; y < yEnd; y++) {
    for (var x = 0; x < image.width; x++) {
      if (data!.getUint8((y * image.width + x) * 4 + 3) != 0) count++;
    }
  }
  return count;
}

void main() {
  testWidgets('disabled is a passthrough and enabled keeps a 200x200 child',
      (tester) async {
    final child = SizedBox(
      key: const ValueKey('child'),
      width: 37,
      height: 43,
      child: const ColoredBox(color: Colors.red),
    );
    await tester.pumpWidget(host(enabled: false, child: child));
    expect(customPaint(), findsNothing);
    expect(find.byKey(const ValueKey('child')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('child'))),
        const Size(200, 200));

    await tester.pumpWidget(host(child: child));
    expect(customPaint(), findsOneWidget);
    expect(tester.getSize(surface()), const Size(200, 200));
    expect(tester.getSize(customPaint()), const Size(200, 272));
    expect(find.byKey(const ValueKey('child')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap and long press pass through the surface', (tester) async {
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(host(
      enabled: false,
      child: const SizedBox(key: ValueKey('child'), width: 37, height: 43),
      onTap: () => taps++,
      onLongPress: () => longPresses++,
    ));
    final target = find.byKey(const ValueKey('gesture'));
    await tester.tap(target);
    await tester.longPress(target);
    expect(taps, 1);
    expect(longPresses, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animation advances, pauses, resumes, and disposes cleanly',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    final initial = painter(tester).progress.value;
    await tester.pump(const Duration(milliseconds: 180));
    final advanced = painter(tester).progress.value;
    expect(advanced, isNot(initial));

    await tester.pumpWidget(host(tickerEnabled: false));
    await tester.pump();
    final tickerStopped = painter(tester).progress.value;
    expect(tickerStopped, 0.45);
    await tester.pump(const Duration(milliseconds: 300));
    expect(painter(tester).progress.value, tickerStopped);

    await tester.pumpWidget(host());
    await tester.pump();
    final resumed = painter(tester).progress.value;
    await tester.pump(const Duration(milliseconds: 180));
    expect(painter(tester).progress.value, isNot(resumed));

    await tester.pumpWidget(host(disableAnimations: true));
    await tester.pump();
    final mediaStopped = painter(tester).progress.value;
    expect(mediaStopped, 0.45);
    await tester.pump(const Duration(milliseconds: 300));
    expect(painter(tester).progress.value, mediaStopped);

    await tester.pumpWidget(host(disableAnimations: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(painter(tester).progress.value, isNot(0.45));

    await tester.pumpWidget(host(enabled: false));
    await tester.pump();
    expect(customPaint(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('raster runoff changes by phase and detaches below the 200px surface',
      () async {
    final early = await raster(0.20);
    final selected = await raster(0.97);
    addTearDown(() {
      early.dispose();
      selected.dispose();
    });

    final earlySurface = await alphaPixels(early, yEnd: 200);
    final selectedSurface = await alphaPixels(selected, yEnd: 200);
    final selectedBelow = await alphaPixels(selected, yStart: 200);
    expect(earlySurface, greaterThan(0));
    expect(selectedSurface, greaterThan(0));
    expect(selectedSurface, isNot(earlySurface));
    expect(selectedBelow, greaterThan(0));
  });

  test('runoff stays on the rim and clear of the power glyph', () {
    for (var i = 0; i < RainButtonPainter.streamCount; i++) {
      for (var step = 0; step < 48; step++) {
        final sample = RainButtonPainter.sampleRunoff(i, step / 100);
        expect(
          (sample.position - const Offset(100, 100)).distance,
          closeTo(96, 0.4),
        );
        expect(sample.detached, isFalse);
      }
    }
  });

  test(
    'water gathers, pinches off continuously, and accelerates downwards',
    () {
      for (var i = 0; i < RainButtonPainter.streamCount; i++) {
        final start = RainButtonPainter.sampleRunoff(i, 0.48);
        final middle = RainButtonPainter.sampleRunoff(i, 0.63);
        final before = RainButtonPainter.sampleRunoff(i, 0.78 - 1e-7);
        final detached = RainButtonPainter.sampleRunoff(i, 0.78);
        final falling = RainButtonPainter.sampleRunoff(i, 0.83);
        final later = RainButtonPainter.sampleRunoff(i, 0.88);
        final end = RainButtonPainter.sampleRunoff(i, 1);
        expect(middle.radius, greaterThan(start.radius));
        expect(before.radius, greaterThan(middle.radius));
        expect(middle.neck, greaterThan(before.neck));
        expect(before.detached, isFalse);
        expect(detached.detached, isTrue);
        expect((detached.position - before.position).distance, lessThan(0.001));
        expect(detached.stretch, closeTo(before.stretch, 0.001));
        expect(
          later.position.dy - falling.position.dy,
          greaterThan(falling.position.dy - detached.position.dy),
        );
        expect(later.stretch, lessThan(detached.stretch));
        expect(end.opacity, closeTo(0, 1e-12));
        expect(end.position.dy, greaterThan(200));
      }
    },
  );

  testWidgets('enabled water does not consume tap or long press', (
    tester,
  ) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      host(onTap: () => taps++, onLongPress: () => holds++),
    );
    final target = find.byKey(const ValueKey('gesture'));
    await tester.tap(target);
    await tester.longPress(target);
    expect(taps, 1);
    expect(holds, 1);
    expect(tester.takeException(), isNull);
  });
}
