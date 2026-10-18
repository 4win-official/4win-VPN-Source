import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Static, resolution-independent winter material. It adds no ticker or hit
/// target: the existing button owns gestures, size, status colour and content.
class SnowButtonSurface extends StatelessWidget {
  const SnowButtonSurface({
    super.key,
    required this.enabled,
    required this.tint,
    required this.child,
  });

  final bool enabled;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _IcePainter(tint),
        foregroundPainter: const _SnowCapPainter(),
        child: child,
      ),
    );
  }
}

class _IcePainter extends CustomPainter {
  const _IcePainter(this.tint);
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    // Work in the button's original 200px space, scaling with its constraints.
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);
    const bounds = Rect.fromLTWH(0, 0, 200, 200);
    final circle = Path()..addOval(bounds);
    canvas.clipPath(circle);
    Color ice(Color color, double alpha) =>
        Color.alphaBlend(color.withValues(alpha: alpha), tint);
    canvas.drawCircle(
      const Offset(100, 100),
      100,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ice(const Color(0xFFF3FDFF), 0.78),
            ice(const Color(0xFFBDEBFA), 0.42),
            ice(const Color(0xFF6FBBD9), 0.48),
            ice(const Color(0xFFE5FAFF), 0.65),
          ],
          stops: const [0, 0.4, 0.78, 1],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      const Offset(100, 100),
      98,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFEAFCFF).withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      const Offset(100, 100),
      94,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF74BFD9).withValues(alpha: 0.55),
    );

    // Translucent facets and fine frost stay near the rim, leaving the power
    // glyph / connecting loader unobstructed in the middle.
    final facets = Path()
      ..moveTo(7, 76)
      ..lineTo(28, 48)
      ..lineTo(38, 82)
      ..lineTo(21, 134)
      ..close()
      ..moveTo(155, 143)
      ..lineTo(190, 105)
      ..lineTo(177, 157)
      ..lineTo(133, 188)
      ..close();
    canvas.drawPath(
      facets,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    final random = math.Random(41);
    final grain = Paint();
    for (var i = 0; i < 180; i++) {
      final angle = random.nextDouble() * math.pi * 2;
      final radius = 73 + random.nextDouble() * 26;
      grain.color = Colors.white.withValues(
        alpha: 0.15 + random.nextDouble() * 0.4,
      );
      canvas.drawCircle(
        Offset(100 + math.cos(angle) * radius, 100 + math.sin(angle) * radius),
        0.35 + random.nextDouble() * 0.8,
        grain,
      );
    }
    final vein = Paint()
      ..color = const Color(0xFFF0FCFF).withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 0.8;
    for (final angle in [0.22, 0.79, 1.4, 2.25, 2.85, 3.55]) {
      canvas.save();
      canvas.translate(100, 100);
      canvas.rotate(angle);
      final branch = Path()
        ..moveTo(98, 0)
        ..lineTo(83, 3)
        ..lineTo(72, -2)
        ..moveTo(88, 2)
        ..lineTo(84, -7)
        ..lineTo(78, -10)
        ..moveTo(82, 3)
        ..lineTo(78, 10)
        ..lineTo(71, 12);
      canvas.drawPath(branch, vein);
      canvas.restore();
    }
    // A soft reflected highlight gives the ice volume, rather than a flat fill.
    canvas.drawArc(
      const Rect.fromLTWH(9, 9, 182, 182),
      math.pi * 0.78,
      math.pi * 0.5,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IcePainter oldDelegate) =>
      oldDelegate.tint != tint;
}

class _SnowCapPainter extends CustomPainter {
  const _SnowCapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);
    // Follow the upper circular shoulder, with irregular powder pillows and a
    // scalloped underside. The snow is attached to the rim, not floating above.
    final cap = Path()
      ..moveTo(4, 72)
      ..cubicTo(8, 49, 23, 28, 40, 18)
      ..cubicTo(45, 11, 53, 11, 59, 10)
      ..cubicTo(69, 1, 80, 3, 87, 0)
      ..cubicTo(97, -5, 108, -3, 116, 0)
      ..cubicTo(124, -1, 137, 5, 142, 10)
      ..cubicTo(152, 11, 159, 18, 165, 23)
      ..cubicTo(181, 34, 191, 53, 196, 72)
      ..cubicTo(191, 78, 183, 72, 180, 65)
      ..cubicTo(175, 60, 170, 62, 166, 55)
      ..cubicTo(161, 49, 157, 51, 152, 46)
      ..cubicTo(148, 43, 149, 54, 144, 54)
      ..cubicTo(138, 54, 141, 39, 133, 37)
      ..cubicTo(123, 33, 116, 39, 108, 34)
      ..cubicTo(97, 29, 89, 35, 81, 32)
      ..cubicTo(71, 29, 66, 38, 59, 38)
      ..cubicTo(51, 37, 55, 50, 49, 51)
      ..cubicTo(43, 52, 46, 44, 40, 46)
      ..cubicTo(31, 48, 29, 58, 23, 60)
      ..cubicTo(17, 60, 17, 73, 10, 75)
      ..quadraticBezierTo(6, 77, 4, 72)
      ..close();
    canvas.drawShadow(cap, const Color(0xFF1F698C), 4, false);

    // Short translucent icicles hang from the outer shoulders only.
    final icicles = Path()
      ..moveTo(20, 59)
      ..quadraticBezierTo(23, 96, 27, 59)
      ..close()
      ..moveTo(39, 46)
      ..quadraticBezierTo(42, 76, 46, 46)
      ..close()
      ..moveTo(159, 48)
      ..quadraticBezierTo(163, 81, 166, 52)
      ..close()
      ..moveTo(178, 62)
      ..quadraticBezierTo(184, 98, 186, 67)
      ..close();
    canvas.drawPath(
      icicles,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE6FAFF), Color(0x887CCBE8)],
        ).createShader(const Rect.fromLTWH(0, 45, 200, 48)),
    );
    canvas.drawPath(
      cap,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFF5FCFF), Color(0xFFBBDDEB)],
          stops: [0, 0.55, 1],
        ).createShader(const Rect.fromLTWH(0, -4, 200, 82)),
    );
    final powder = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final dot in const [
      Offset(40, 31),
      Offset(59, 22),
      Offset(77, 13),
      Offset(104, 10),
      Offset(128, 17),
      Offset(147, 25),
      Offset(166, 40),
      Offset(24, 49),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: dot, width: 5, height: 2),
        powder,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SnowCapPainter oldDelegate) => false;
}
