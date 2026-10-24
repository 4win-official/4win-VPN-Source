import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// A clear, reflective glass sphere that leaves its background visible.
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
          child: BackdropFilter(
            // Real glass softens the scene behind it just a little; the icon
            // and the specular reflections painted above it remain crisp.
            filter: ImageFilter.blur(sigmaX: 1.15, sigmaY: 1.15),
            child: CustomPaint(
              painter: GlassPowerButtonPainter(isDark: isDark, tint: tint),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a stationary, transparent glass lens with restrained optical cues.
///
/// The uneven edge reflections and broad upper-left softbox reflection are
/// intentional: unlike water, the glass has no ripples, beads, or caustics.
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
    final rim = Rect.fromCircle(center: center, radius: radius - 2.1);

    // A very light smoked-glass body keeps the background visible while the
    // edge shading gives the sphere a curved, solid-glass silhouette.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.10, -0.12),
          radius: 1.18,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.018),
                  const Color(0xFF8293A2).withValues(alpha: 0.025),
                  const Color(0xFFBBC9D5).withValues(alpha: 0.115),
                  const Color(0xFF17212B).withValues(alpha: 0.17),
                ]
              : [
                  Colors.white.withValues(alpha: 0.035),
                  Colors.white.withValues(alpha: 0.075),
                  const Color(0xFF9EABB6).withValues(alpha: 0.105),
                  const Color(0xFF394651).withValues(alpha: 0.12),
                ],
          stops: const [0, 0.55, 0.88, 1],
        ).createShader(sphere),
    );

    // Subtle internal edge shading makes the surface read as a thick lens,
    // not as a flat circle outlined in white.
    canvas.drawCircle(
      center,
      radius - 5.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = Colors.black.withValues(alpha: isDark ? 0.16 : 0.09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // A dim continuous bevel anchors the segmented highlights. Most of the
    // rim stays quiet; the brightest silver catches are deliberately uneven.
    canvas.drawCircle(
      center,
      radius - 1.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: isDark ? 0.23 : 0.18),
    );
    canvas.drawCircle(
      center,
      radius - 2.0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.2
        ..color = Colors.white.withValues(alpha: isDark ? 0.11 : 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
    );
    canvas.drawCircle(
      center,
      radius - 2.0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.62 : 0.48),
            Colors.white.withValues(alpha: isDark ? 0.30 : 0.24),
            const Color(0xFFB9D8F5).withValues(alpha: isDark ? 0.44 : 0.29),
            Colors.white.withValues(alpha: isDark ? 0.22 : 0.15),
            Colors.white.withValues(alpha: isDark ? 0.78 : 0.59),
            Colors.white.withValues(alpha: isDark ? 0.96 : 0.77),
            Colors.white.withValues(alpha: isDark ? 0.70 : 0.52),
            tint.withValues(alpha: isDark ? 0.12 : 0.08),
            Colors.white.withValues(alpha: isDark ? 0.40 : 0.30),
            Colors.white.withValues(alpha: isDark ? 0.62 : 0.48),
          ],
          stops: const [0, 0.10, 0.20, 0.31, 0.40, 0.52, 0.63, 0.74, 0.86, 1],
        ).createShader(rim),
    );

    // Fine inner Fresnel line: faint enough to feel like a reflection inside
    // the glass rather than a second drawn outline.
    canvas.drawCircle(
      center,
      radius - 8.0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: isDark ? 0.13 : 0.09),
    );

    // Soft reflection from a broad light source at the upper-left. A feathered
    // underlayer and a translucent, tapered core mimic the reference's curved
    // white reflection without turning it into a cartoon stroke.
    final upperLeftReflection = Path()
      ..moveTo(center.dx - radius * 0.70, center.dy - radius * 0.15)
      ..cubicTo(
        center.dx - radius * 0.62,
        center.dy - radius * 0.48,
        center.dx - radius * 0.36,
        center.dy - radius * 0.77,
        center.dx - radius * 0.10,
        center.dy - radius * 0.82,
      )
      ..cubicTo(
        center.dx - radius * 0.02,
        center.dy - radius * 0.82,
        center.dx + radius * 0.01,
        center.dy - radius * 0.75,
        center.dx - radius * 0.07,
        center.dy - radius * 0.70,
      )
      ..cubicTo(
        center.dx - radius * 0.29,
        center.dy - radius * 0.66,
        center.dx - radius * 0.48,
        center.dy - radius * 0.43,
        center.dx - radius * 0.55,
        center.dy - radius * 0.19,
      )
      ..cubicTo(
        center.dx - radius * 0.59,
        center.dy - radius * 0.09,
        center.dx - radius * 0.66,
        center.dy - radius * 0.07,
        center.dx - radius * 0.70,
        center.dy - radius * 0.15,
      )
      ..close();

    canvas.drawPath(
      upperLeftReflection,
      Paint()
        ..color = Colors.white.withValues(alpha: isDark ? 0.24 : 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(
      upperLeftReflection,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.76 : 0.60),
            Colors.white.withValues(alpha: isDark ? 0.52 : 0.38),
            Colors.white.withValues(alpha: isDark ? 0.10 : 0.06),
          ],
          stops: const [0.08, 0.50, 1],
        ).createShader(sphere),
    );

    // Narrow glints on the opposite edge and lower rim give the sphere depth
    // while keeping the center clear and the light direction consistent.
    canvas.drawArc(
      rim,
      -1.12,
      0.62,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.0
        ..color = Colors.white.withValues(alpha: isDark ? 0.58 : 0.42),
    );
    canvas.drawArc(
      rim,
      0.50,
      0.42,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.0
        ..color = Colors.white.withValues(alpha: isDark ? 0.38 : 0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    canvas.drawArc(
      rim,
      2.18,
      0.34,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: isDark ? 0.31 : 0.21)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );
  }

  @override
  bool shouldRepaint(covariant GlassPowerButtonPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.tint != tint;
}
