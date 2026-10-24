import 'package:flutter/material.dart';

/// Paints the Cat theme's button surface behind the existing power control.
///
/// The 200 px layout and hit target are unchanged; the ears paint softly above
/// that footprint, while the face itself stays a round, glossy mint sphere.
class CatPowerButtonSurface extends StatelessWidget {
  const CatPowerButtonSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(200, 200),
    painter: const CatPowerButtonPainter(),
    child: Center(child: child),
  );
}

/// Static glossy artwork used only by the Cat theme's power button.
class CatPowerButtonPainter extends CustomPainter {
  const CatPowerButtonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);

    final mint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-0.75, -1),
        end: Alignment(0.7, 1),
        colors: [Color(0xFFD7F0E2), Color(0xFFB9DECE), Color(0xFF8DBBAA)],
        stops: [0, 0.48, 1],
      ).createShader(const Rect.fromLTWH(0, -34, 200, 240));
    final paleRim = Paint()
      ..color = const Color(0xFFDDF5E8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Rounded ears are painted first, then tucked behind the circular face so
    // their roots flow into the head instead of forming a V-shaped forehead.
    final leftEar = Path()
      ..moveTo(20, 68)
      ..cubicTo(19, 40, 21, 0, 31, -28)
      ..cubicTo(34, -36, 42, -30, 48, -23)
      ..cubicTo(63, -6, 74, 18, 83, 38)
      ..cubicTo(60, 42, 39, 56, 20, 78)
      ..close();
    final rightEar = Path()
      ..moveTo(180, 68)
      ..cubicTo(181, 40, 179, 0, 169, -28)
      ..cubicTo(166, -36, 158, -30, 152, -23)
      ..cubicTo(137, -6, 126, 18, 117, 38)
      ..cubicTo(140, 42, 161, 56, 180, 78)
      ..close();
    canvas
      ..drawPath(leftEar, mint)
      ..drawPath(rightEar, mint);

    final leftInnerEar = Path()
      ..moveTo(29, 43)
      ..cubicTo(30, 19, 32, -6, 36, -21)
      ..cubicTo(44, -12, 52, 5, 64, 24)
      ..cubicTo(51, 28, 39, 35, 29, 48)
      ..close();
    final rightInnerEar = Path()
      ..moveTo(171, 43)
      ..cubicTo(170, 19, 168, -6, 164, -21)
      ..cubicTo(156, -12, 148, 5, 136, 24)
      ..cubicTo(149, 28, 161, 35, 171, 48)
      ..close();
    final blush = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFB5A5), Color(0xFFDF827C)],
      ).createShader(const Rect.fromLTWH(28, -22, 144, 72));
    canvas
      ..drawPath(leftInnerEar, blush)
      ..drawPath(rightInnerEar, blush);

    final earLine = Paint()
      ..color = const Color(0xFFDDF5E8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final leftEarRim = Path()
      ..moveTo(23, 62)
      ..cubicTo(22, 35, 24, -7, 32, -28)
      ..cubicTo(35, -34, 42, -28, 48, -21)
      ..cubicTo(61, -5, 73, 18, 82, 38);
    final rightEarRim = Path()
      ..moveTo(177, 62)
      ..cubicTo(178, 35, 176, -7, 168, -28)
      ..cubicTo(165, -34, 158, -28, 152, -21)
      ..cubicTo(139, -5, 127, 18, 118, 38);
    canvas
      ..drawPath(leftEarRim, earLine)
      ..drawPath(rightEarRim, earLine);

    // The face is a near-circular sphere. It covers the lower ear roots and
    // gives the silhouette one continuous cheek and brow line.
    final face = Path()..addOval(const Rect.fromLTWH(4, 12, 192, 192));
    canvas.drawPath(face, mint);

    // Small pink inner-ear glints remain above the face where the ears show.
    final earGlint = Paint()
      ..color = const Color(0x66FFF4E9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final leftEarGlint = Path()
      ..moveTo(37, 25)
      ..cubicTo(37, 10, 38, -5, 41, -13);
    final rightEarGlint = Path()
      ..moveTo(163, 25)
      ..cubicTo(163, 10, 162, -5, 159, -13);
    canvas
      ..drawPath(leftEarGlint, earGlint)
      ..drawPath(rightEarGlint, earGlint);

    // A soft, tapered catchlight makes the mint face read as polished glass.
    final leftGloss = Path()
      ..moveTo(39, 70)
      ..cubicTo(44, 58, 52, 49, 61, 44)
      ..cubicTo(66, 41, 69, 45, 66, 50)
      ..cubicTo(61, 59, 53, 66, 45, 73)
      ..cubicTo(41, 75, 37, 74, 39, 70)
      ..close();
    canvas.drawPath(leftGloss, Paint()..color = const Color(0x99FFFFFF));
    canvas.drawOval(
      const Rect.fromLTWH(28, 84, 7, 13),
      Paint()..color = const Color(0x66FFFFFF),
    );

    // Continuous rim around the spherical face, plus a quiet lower-edge shade.
    canvas.drawPath(face, paleRim);
    final lowerRim = Path()
      ..moveTo(25, 156)
      ..cubicTo(40, 184, 66, 197, 100, 199)
      ..cubicTo(134, 197, 160, 184, 175, 156);
    canvas.drawPath(
      lowerRim,
      Paint()
        ..color = const Color(0x66759889)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );

    // A thin white catch on the upper face completes the soft, glossy rim.
    final upperFace = Path()
      ..moveTo(31, 53)
      ..cubicTo(42, 32, 66, 18, 92, 16)
      ..cubicTo(101, 15, 109, 15, 118, 16)
      ..cubicTo(144, 18, 166, 32, 177, 53);
    canvas.drawPath(
      upperFace,
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CatPowerButtonPainter oldDelegate) => false;
}
