import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/protocol_glass_surface.dart';

const _sizes = <Size>[
  Size(300, 180), // dialog-like surface
  Size(176, 72), // compact rounded surface
];

Widget _host({
  required bool isDark,
  required Size size,
  double radius = 28,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: isDark ? Brightness.dark : Brightness.light),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ProtocolGlassSurface(
            isDark: isDark,
            radius: radius,
            child: const Center(child: Text('Sample')),
          ),
        ),
      ),
    ),
  );
}

CustomPainter _extractPainter(WidgetTester tester) {
  final glass = find.byType(ProtocolGlassSurface);
  final customPaint = tester
      .widgetList<CustomPaint>(
        find.descendant(of: glass, matching: find.byType(CustomPaint)),
      )
      .firstWhere((paint) => paint.foregroundPainter != null);
  final painter = customPaint.foregroundPainter;
  expect(painter, isNotNull);
  return painter!;
}

Future<ui.Image> _renderPainter(CustomPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  picture.dispose();
  return image;
}

Future<Uint8List> _rawPixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  return data!.buffer.asUint8List();
}

Future<Uint8List> _renderPixels(CustomPainter painter, Size size) async {
  final image = await _renderPainter(painter, size);
  final pixels = await _rawPixels(image);
  image.dispose();
  return pixels;
}

int _offset(int x, int y, int width) => (y * width + x) * 4;

bool _insideDeflatedRRect(Offset point, Size size, double radius) {
  final curve = radius.clamp(0.0, size.shortestSide / 2);
  final rect = Offset.zero & size;
  final rrect = RRect.fromRectAndRadius(
    rect.deflate(7),
    Radius.circular((curve - 7).clamp(0.0, curve)),
  );
  return rrect.contains(point);
}

void main() {
  for (final isDark in [false, true]) {
    for (final size in _sizes) {
      testWidgets(
        'draws only a variable perimeter rim in ${isDark ? 'dark' : 'light'} theme at ${size.width}x${size.height}',
        (tester) async {
          await tester.pumpWidget(_host(isDark: isDark, size: size));
          final painter = _extractPainter(tester);
          final pixels = await tester.runAsync(
            () => _renderPixels(painter, size),
          );
          expect(pixels, isNotNull);
          final raw = pixels!;
          final width = size.width.ceil();
          final height = size.height.ceil();

          var painted = 0;
          final signatures = <int>{};
          for (var y = 0; y < height; y++) {
            for (var x = 0; x < width; x++) {
              final i = _offset(x, y, width);
              final r = raw[i];
              final g = raw[i + 1];
              final b = raw[i + 2];
              final a = raw[i + 3];
              if (a != 0) {
                painted++;
                // Premultiplied raw-RGBA values make this a stable, relative
                // brightness signature without asserting exact shader bytes.
                signatures.add((r << 24) | (g << 16) | (b << 8) | a);
              }
              if (_insideDeflatedRRect(Offset(x + .5, y + .5), size, 28)) {
                expect(
                  a,
                  0,
                  reason: 'the deep interior must remain untouched at ($x,$y)',
                );
              }
            }
          }

          expect(painted, greaterThan(20), reason: 'rim must not be empty');
          expect(
            signatures.length,
            greaterThan(2),
            reason: 'rim lighting should vary around the perimeter',
          );
        },
      );
    }
  }

  testWidgets('glass edge repaint identity tracks theme and radius', (
    tester,
  ) async {
    await tester.pumpWidget(_host(isDark: false, size: _sizes.first));
    final light28 = _extractPainter(tester);
    await tester.pumpWidget(_host(isDark: false, size: _sizes.first, radius: 20));
    final light20 = _extractPainter(tester);
    await tester.pumpWidget(_host(isDark: true, size: _sizes.first, radius: 20));
    final dark20 = _extractPainter(tester);

    expect(light28.shouldRepaint(light28), isFalse);
    expect(light28.shouldRepaint(light20), isTrue);
    expect(light20.shouldRepaint(dark20), isTrue);
    expect(dark20.shouldRepaint(dark20), isFalse);
  });
}
