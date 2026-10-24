import 'package:flutter/material.dart';

/// Draws only the pair of ears that sits on top of the Cat-theme power button.
class CatPowerButtonEars extends StatelessWidget {
  const CatPowerButtonEars({
    super.key,
    required this.furColor,
    required this.outlineColor,
  });

  final Color furColor;
  final Color outlineColor;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: CustomPaint(
          size: const Size(200, 66),
          painter: _CatPowerButtonEarsPainter(
            furColor: furColor,
            outlineColor: outlineColor,
          ),
        ),
      ),
    );
  }
}

class _CatPowerButtonEarsPainter extends CustomPainter {
  const _CatPowerButtonEarsPainter({
    required this.furColor,
    required this.outlineColor,
  });

  final Color furColor;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fur = Paint()..color = furColor;
    final outline = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inner = Paint()..color = const Color(0xFFD38E86);

    // Broad, gently cupped ears with softly rounded tips blend into the button
    // instead of reading as sharp triangular add-ons. Leave their lower edges
    // unoutlined so the button's own circular rim remains continuous.
    final leftEar = Path()
      ..moveTo(14, 65)
      ..cubicTo(22, 53, 22, 34, 28, 23)
      ..cubicTo(31, 15, 35, 9, 40, 9)
      ..cubicTo(46, 9, 49, 17, 53, 26)
      ..cubicTo(61, 43, 73, 56, 86, 65)
      ..close();
    final rightEar = Path()
      ..moveTo(114, 65)
      ..cubicTo(127, 56, 139, 43, 147, 26)
      ..cubicTo(151, 17, 154, 9, 160, 9)
      ..cubicTo(165, 9, 169, 15, 172, 23)
      ..cubicTo(178, 34, 178, 53, 186, 65)
      ..close();
    canvas.drawPath(leftEar, fur);
    canvas.drawPath(rightEar, fur);

    final leftContour = Path()
      ..moveTo(14, 65)
      ..cubicTo(22, 53, 22, 34, 28, 23)
      ..cubicTo(31, 15, 35, 9, 40, 9)
      ..cubicTo(46, 9, 49, 17, 53, 26)
      ..cubicTo(61, 43, 73, 56, 86, 65);
    final rightContour = Path()
      ..moveTo(114, 65)
      ..cubicTo(127, 56, 139, 43, 147, 26)
      ..cubicTo(151, 17, 154, 9, 160, 9)
      ..cubicTo(165, 9, 169, 15, 172, 23)
      ..cubicTo(178, 34, 178, 53, 186, 65);
    canvas.drawPath(leftContour, outline);
    canvas.drawPath(rightContour, outline);

    // Muted, rounded inner patches follow the bent shape of the outer ears.
    final leftInnerEar = Path()
      ..moveTo(31, 51)
      ..cubicTo(34, 42, 35, 31, 39, 24)
      ..cubicTo(45, 31, 52, 43, 62, 53)
      ..cubicTo(51, 50, 40, 49, 31, 51)
      ..close();
    final rightInnerEar = Path()
      ..moveTo(169, 51)
      ..cubicTo(166, 42, 165, 31, 161, 24)
      ..cubicTo(155, 31, 148, 43, 138, 53)
      ..cubicTo(149, 50, 160, 49, 169, 51)
      ..close();
    canvas.drawPath(leftInnerEar, inner);
    canvas.drawPath(rightInnerEar, inner);
  }

  @override
  bool shouldRepaint(covariant _CatPowerButtonEarsPainter oldDelegate) =>
      oldDelegate.furColor != furColor ||
      oldDelegate.outlineColor != outlineColor;
}
