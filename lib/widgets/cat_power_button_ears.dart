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
      ..strokeJoin = StrokeJoin.round;
    final inner = Paint()..color = const Color(0xFFD38E86);

    final leftEar = Path()
      ..moveTo(20, 63)
      ..lineTo(30, 5)
      ..quadraticBezierTo(32, -1, 37, 4)
      ..lineTo(79, 63)
      ..close();
    final rightEar = Path()
      ..moveTo(121, 63)
      ..lineTo(163, 4)
      ..quadraticBezierTo(168, -1, 170, 5)
      ..lineTo(180, 63)
      ..close();

    for (final ear in [leftEar, rightEar]) {
      canvas.drawPath(ear, fur);
      canvas.drawPath(ear, outline);
    }

    final leftInnerEar = Path()
      ..moveTo(37, 48)
      ..lineTo(40, 18)
      ..lineTo(61, 49)
      ..close();
    final rightInnerEar = Path()
      ..moveTo(139, 49)
      ..lineTo(160, 18)
      ..lineTo(163, 48)
      ..close();
    canvas.drawPath(leftInnerEar, inner);
    canvas.drawPath(rightInnerEar, inner);
  }

  @override
  bool shouldRepaint(covariant _CatPowerButtonEarsPainter oldDelegate) =>
      oldDelegate.furColor != furColor ||
      oldDelegate.outlineColor != outlineColor;
}
