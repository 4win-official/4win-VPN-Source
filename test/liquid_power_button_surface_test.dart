import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/liquid_power_button_surface.dart';

Finder _liquidPaint() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is LiquidPowerButtonPainter,
);

Finder _liquidGlowPaint() => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && widget.painter is LiquidPowerButtonGlowPainter,
);

Future<Uint8List> _renderPainter(CustomPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.transparent, BlendMode.src);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

int _differentPixelCount(Uint8List first, Uint8List second) {
  var count = 0;
  for (var i = 0; i < first.length; i += 4) {
    if (first[i] != second[i] ||
        first[i + 1] != second[i + 1] ||
        first[i + 2] != second[i + 2] ||
        first[i + 3] != second[i + 3]) {
      count++;
    }
  }
  return count;
}

void main() {
  testWidgets('Liquid power button stays 200×200 and clips to a perfect circle', (
    tester,
  ) async {
    const tint = Color(0xFF8CBDF4);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: LiquidPowerButtonSurface(
                isDark: true,
                tint: tint,
                child: Icon(Icons.power_settings_new, size: 80),
              ),
            ),
          ),
        ),
      ),
    );

    final surface = find.byType(LiquidPowerButtonSurface);
    expect(tester.getSize(surface), const Size(200, 200));
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ClipPath && widget.clipper is LiquidPowerButtonClipper,
      ),
      findsOneWidget,
    );
    expect(_liquidPaint(), findsOneWidget);
    expect(_liquidGlowPaint(), findsOneWidget);

    final painter = tester.widget<CustomPaint>(_liquidPaint()).painter!
        as LiquidPowerButtonPainter;
    expect(painter.isDark, isTrue);
    expect(painter.tint, tint);
    expect(
      painter.shouldRepaint(
        LiquidPowerButtonPainter(
          isDark: true,
          tint: tint,
          phase: painter.phase,
        ),
      ),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        LiquidPowerButtonPainter(
          isDark: false,
          tint: tint,
          phase: painter.phase,
        ),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        LiquidPowerButtonPainter(
          isDark: true,
          tint: const Color(0xFF00FF88),
          phase: painter.phase,
        ),
      ),
      isTrue,
    );
    expect(
      tester
          .widget<CustomPaint>(_liquidGlowPaint())
          .painter!
          .shouldRepaint(
            const LiquidPowerButtonGlowPainter(isDark: true, tint: tint),
          ),
      isFalse,
    );

    final clipPath = const LiquidPowerButtonClipper().getClip(
      const Size(200, 200),
    );
    expect(clipPath.getBounds().width, clipPath.getBounds().height);
    expect(clipPath.contains(const Offset(100, 100)), isTrue);
    expect(clipPath.contains(const Offset(100, 10)), isTrue);
    expect(clipPath.contains(const Offset(4, 100)), isFalse);
    expect(clipPath.contains(const Offset(4, 4)), isFalse);
    expect(
      const LiquidPowerButtonClipper().shouldReclip(
        const LiquidPowerButtonClipper(),
      ),
      isFalse,
    );

    final phaseBefore = painter.phase.value;
    await tester.pump(const Duration(seconds: 1));
    expect(painter.phase.value, isNot(phaseBefore));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the graphic water shapes visibly move inside the circle', (
    tester,
  ) async {
    const size = Size(200, 200);
    const tint = Color(0xFF8CBDF4);
    final firstFrame = await tester.runAsync(
      () => _renderPainter(
        LiquidPowerButtonPainter(
          isDark: true,
          tint: tint,
          phase: const AlwaysStoppedAnimation<double>(0.08),
        ),
        size,
      ),
    );
    final secondFrame = await tester.runAsync(
      () => _renderPainter(
        LiquidPowerButtonPainter(
          isDark: true,
          tint: tint,
          phase: const AlwaysStoppedAnimation<double>(0.61),
        ),
        size,
      ),
    );

    expect(firstFrame, isNotNull);
    expect(secondFrame, isNotNull);
    expect(_differentPixelCount(firstFrame!, secondFrame!), greaterThan(100));

    int alphaAt(Uint8List pixels, int x, int y) =>
        pixels[(y * size.width.toInt() + x) * 4 + 3];
    expect(alphaAt(firstFrame, 100, 100), 255);
    expect(alphaAt(firstFrame, 100, 20), 255);
    expect(alphaAt(firstFrame, 4, 100), 0);
    expect(alphaAt(firstFrame, 4, 4), 0);
  });
}
