import 'package:flutter/material.dart';

/// A clear, polished glass sphere that leaves its background visible.
///
/// The surface is decorative only: its child remains the existing power icon
/// or connection loader, and callers keep ownership of the button gesture.
class GlassPowerButtonSurface extends StatelessWidget {
  const GlassPowerButtonSurface({
    super.key,
    required this.isDark,
    required this.tint,
    required this.child,
  });

  final bool isDark;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: RepaintBoundary(
        child: ClipOval(
          child: CustomPaint(
            painter: GlassPowerButtonPainter(isDark: isDark, tint: tint),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Paints controlled, static reflections and a bright glass rim without
/// covering the centre with an opaque fill or adding liquid-like movement.
class GlassPowerButtonPainter extends CustomPainter {
  const GlassPowerButtonPainter({required this.isDark, required this.tint});

  final bool isDark;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2.5;
    if (radius <= 0) return;
    final sphere = Rect.fromCircle(center: center, radius: radius);

    // A subtle translucent body preserves the background through the glass.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.28, -0.34),
          radius: 1.2,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.055),
                  tint.withValues(alpha: 0.035),
                  const Color(0x46384450),
                ]
              : [
                  Colors.white.withValues(alpha: 0.10),
                  tint.withValues(alpha: 0.045),
                  const Color(0x304B5A68),
                ],
          stops: const [0, 0.58, 1],
        ).createShader(sphere),
    );

    // A soft, neutral bloom gives the polished edge a little light spill.
    canvas.drawCircle(
      center,
      radius - 1.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = Colors.white.withValues(alpha: isDark ? 0.16 : 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(
      center,
      radius - 1.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..color = tint.withValues(alpha: isDark ? 0.08 : 0.045)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );

    // A continuous silver base keeps the bevel legible around the whole sphere.
    final rim = Rect.fromCircle(center: center, radius: radius - 2.0);
    canvas.drawCircle(
      center,
      radius - 2.0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..color = Colors.white.withValues(alpha: isDark ? 0.30 : 0.24),
    );
    canvas.drawCircle(
      center,
      radius - 2.0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.92 : 0.82),
            tint.withValues(alpha: isDark ? 0.48 : 0.36),
            Colors.white.withValues(alpha: isDark ? 0.72 : 0.60),
            Colors.white.withValues(alpha: isDark ? 0.38 : 0.30),
            tint.withValues(alpha: isDark ? 0.42 : 0.32),
            Colors.white.withValues(alpha: isDark ? 0.88 : 0.76),
          ],
          stops: const [0, 0.17, 0.34, 0.53, 0.72, 1],
        ).createShader(rim),
    );
    canvas.drawCircle(
      center,
      radius - 7.0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = Colors.white.withValues(alpha: isDark ? 0.22 : 0.17),
    );

    // A small stationary specular patch adds a polished surface reflection.
    canvas.save();
    canvas.translate(center.dx - radius * 0.40, center.dy - radius * 0.48);
    canvas.rotate(-0.72);
    final gloss = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 0.60,
      height: radius * 0.16,
    );
    canvas.drawOval(
      gloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: isDark ? 0.36 : 0.26),
            Colors.white.withValues(alpha: isDark ? 0.20 : 0.14),
            Colors.transparent,
          ],
          stops: const [0, 0.24, 0.66, 1],
        ).createShader(gloss)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.restore();

    // A broad, fixed upper-left reflection gives the glass a glossy highlight.
    final upperLeftReflection = Path()
      ..moveTo(center.dx - radius * 0.73, center.dy - radius * 0.16)
      ..cubicTo(
        center.dx - radius * 0.65,
        center.dy - radius * 0.56,
        center.dx - radius * 0.38,
        center.dy - radius * 0.77,
        center.dx - radius * 0.10,
        center.dy - radius * 0.82,
      );
    canvas.drawPath(
      upperLeftReflection,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 13
        ..color = Colors.white.withValues(alpha: isDark ? 0.46 : 0.34)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      upperLeftReflection,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: isDark ? 0.88 : 0.72),
    );

    // A smaller opposite glint balances the highlight without adding motion.
    canvas.drawArc(
      rim,
      0.62,
      0.52,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4.2
        ..color = Colors.white.withValues(alpha: isDark ? 0.48 : 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant GlassPowerButtonPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.tint != tint;
}
