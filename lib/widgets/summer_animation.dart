import 'dart:math';
import 'package:flutter/material.dart';

/// Summer theme animation — a bright sun in the top corner that gently pulses
/// and casts slowly-rotating warm rays, plus a soft warm glow. Light-mode only.
class SummerAnimation extends StatefulWidget {
  const SummerAnimation({super.key});

  @override
  State<SummerAnimation> createState() => _SummerAnimationState();
}

class _SummerAnimationState extends State<SummerAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _SunPainter(_controller.value),
            child: Container(),
          );
        },
      ),
    );
  }
}

class _SunPainter extends CustomPainter {
  final double t; // 0..1

  _SunPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Sun sits near the top-right corner.
    final center = Offset(size.width * 0.82, size.height * 0.14);
    // Gentle pulse for the sun core.
    final pulse = 1 + sin(t * pi * 2) * 0.05;
    final coreR = size.width * 0.09 * pulse;

    // Warm ambient glow filling the top portion of the screen.
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF3C4).withValues(alpha: 0.55),
          const Color(0xFFFFE082).withValues(alpha: 0.20),
          const Color(0xFFFFE082).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: size.width * 0.9),
      );
    canvas.drawRect(Offset.zero & size, glow);

    // Rotating rays.
    final rayPaint = Paint()
      ..color = const Color(0xFFFFC107).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const rayCount = 16;
    final rot = t * pi * 2; // full slow rotation per cycle
    for (int i = 0; i < rayCount; i++) {
      final angle = rot + (i * (2 * pi / rayCount));
      // Rays alternate length for a nicer sunburst.
      final inner = coreR * 1.25;
      final outer = coreR * (i.isEven ? 2.4 : 1.9);
      final p1 = center + Offset(cos(angle), sin(angle)) * inner;
      final p2 = center + Offset(cos(angle), sin(angle)) * outer;
      canvas.drawLine(p1, p2, rayPaint);
    }

    // Sun core with a soft radial fill.
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF59D),
          const Color(0xFFFFC107),
          const Color(0xFFFF9800),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreR));
    canvas.drawCircle(center, coreR, corePaint);
  }

  @override
  bool shouldRepaint(covariant _SunPainter oldDelegate) => oldDelegate.t != t;
}
