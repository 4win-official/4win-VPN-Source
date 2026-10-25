import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/glass_power_button_surface.dart';

Finder _glassPaint() => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && widget.painter is GlassPowerButtonPainter,
);

Finder _glowPaint() => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && widget.painter is GlassPowerButtonGlowPainter,
);

Future<Uint8List> _renderPainter(CustomPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.black, BlendMode.src);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

Widget _host() => const MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: GlassPowerButtonSurface(
          isDark: true,
          tint: Color(0xFF8CBDF4),
          child: Icon(Icons.power_settings_new, size: 80),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('polished glass stays still and preserves the power control', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    final surface = find.byType(GlassPowerButtonSurface);
    expect(tester.getSize(surface), const Size(200, 200));
    expect(
      tester.getRect(find.byIcon(Icons.power_settings_new)).center,
      tester.getRect(surface).center,
      reason: 'the decorative lens must not move the power control',
    );
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    expect(_glassPaint(), findsOneWidget);
    expect(_glowPaint(), findsOneWidget);
    expect(
      find.descendant(of: surface, matching: find.byType(ClipOval)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: surface, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );

    final painter =
        tester.widget<CustomPaint>(_glassPaint()).painter!
            as GlassPowerButtonPainter;
    expect(painter.isDark, isTrue);
    expect(painter.tint, const Color(0xFF8CBDF4));
    expect(
      painter.shouldRepaint(
        const GlassPowerButtonPainter(isDark: true, tint: Color(0xFF8CBDF4)),
      ),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        const GlassPowerButtonPainter(isDark: false, tint: Color(0xFF8CBDF4)),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        const GlassPowerButtonPainter(isDark: true, tint: Color(0xFF00FF88)),
      ),
      isTrue,
    );
    final glowPainter =
        tester.widget<CustomPaint>(_glowPaint()).painter!
            as GlassPowerButtonGlowPainter;
    expect(
      glowPainter.shouldRepaint(
        const GlassPowerButtonGlowPainter(
          isDark: true,
          tint: Color(0xFF8CBDF4),
        ),
      ),
      isFalse,
    );

    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dark sphere stays translucent with a soft, readable glass rim', (
    tester,
  ) async {
    const size = Size(200, 200);
    const painter = GlassPowerButtonPainter(
      isDark: true,
      tint: Color(0xFF8CBDF4),
    );
    final rendered = await tester.runAsync(() => _renderPainter(painter, size));
    expect(rendered, isNotNull);

    final pixels = rendered!;
    int brightnessAt(int x, int y) {
      final offset = (y * size.width.toInt() + x) * 4;
      final red = pixels[offset];
      final green = pixels[offset + 1];
      final blue = pixels[offset + 2];
      return red > green
          ? (red > blue ? red : blue)
          : (green > blue ? green : blue);
    }

    expect(
      brightnessAt(100, 100),
      inInclusiveRange(12, 125),
      reason: 'the center should read as shaded glass, not an opaque face',
    );

    expect(
      brightnessAt(55, 50),
      lessThan(110),
      reason: 'diffuse light must not become a hard white interior streak',
    );

    var brightestUpperLeftRim = 0;
    var brightRimPixels = 0;
    var rimPixels = 0;
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 200; x++) {
        final dx = x - 100;
        final dy = y - 100;
        final distance = (dx * dx + dy * dy).toDouble();
        if (distance < 86 * 86 || distance > 100 * 100) continue;
        rimPixels++;
        final value = brightnessAt(x, y);
        if (value >= 110) brightRimPixels++;
        if (x < 100 && y < 100 && value > brightestUpperLeftRim) {
          brightestUpperLeftRim = value;
        }
      }
    }
    expect(
      brightestUpperLeftRim,
      greaterThan(130),
      reason:
          'a small upper-left reflection should make the glass edge readable',
    );
    expect(
      brightRimPixels / rimPixels,
      lessThan(0.40),
      reason: 'the rim should not become a uniformly bright circular outline',
    );
  });

  test('outer halo falls off before the expanded paint bounds', () async {
    const size = Size(264, 264);
    const painter = GlassPowerButtonGlowPainter(
      isDark: true,
      tint: Color(0xFF8CBDF4),
    );
    final rendered = await _renderPainter(painter, size);
    int brightnessAt(int x, int y) {
      final offset = (y * size.width.toInt() + x) * 4;
      final red = rendered[offset];
      final green = rendered[offset + 1];
      final blue = rendered[offset + 2];
      return red > green
          ? (red > blue ? red : blue)
          : (green > blue ? green : blue);
    }

    expect(
      brightnessAt(252, 132),
      greaterThanOrEqualTo(12),
      reason: 'the halo should remain visible beyond the glass lip',
    );
    expect(
      brightnessAt(132, 132),
      lessThan(12),
      reason: 'the glow painter should leave the center transparent',
    );
  });
}
