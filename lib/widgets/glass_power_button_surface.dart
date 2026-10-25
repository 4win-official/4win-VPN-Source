import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// A quiet, translucent glass lens for the System theme's power button.
///
/// The background remains visible through the softened surface. This widget is
/// decorative only: the home screen still owns the button's size, gestures,
/// state icon, and connecting loader.
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -32,
            top: -32,
            right: -32,
            bottom: -32,
            child: CustomPaint(
              painter: GlassPowerButtonGlowPainter(isDark: isDark, tint: tint),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: ClipOval(
              child: BackdropFilter(
                // A restrained blur softens the scene through the curved lens.
                filter: ImageFilter.blur(sigmaX: 1.8, sigmaY: 1.8),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: GlassPowerButtonPainter(
                      isDark: isDark,
                      tint: tint,
                    ),
                    child: Center(child: child),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A restrained status-tinted bloom that sits just beyond the glass edge.
class GlassPowerButtonGlowPainter extends CustomPainter {
  const GlassPowerButtonGlowPainter({required this.isDark, required this.tint});

  final bool isDark;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 32;
    if (radius <= 0) return;
    final haloBounds = Rect.fromCircle(center: center, radius: radius + 10);
    void drawHaloArc({
      required double start,
      required double sweep,
      required double width,
      required Color color,
      required double blur,
    }) {
      canvas.drawArc(
        haloBounds,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    // Broken, low-contrast blooms keep the glass from reading as a neon ring.
    drawHaloArc(
      start: -2.80,
      sweep: 1.18,
      width: 15,
      color: const Color(0xFFCEE8FF).withValues(alpha: isDark ? 0.16 : 0.075),
      blur: 13,
    );
    drawHaloArc(
      start: -0.28,
      sweep: 0.62,
      width: 24,
      color: tint.withValues(alpha: isDark ? 0.10 : 0.045),
      blur: 13,
    );
    drawHaloArc(
      start: 2.24,
      sweep: 0.54,
      width: 12,
      color: const Color(0xFFB9DAF6).withValues(alpha: isDark ? 0.065 : 0.035),
      blur: 12,
    );
  }

  @override
  bool shouldRepaint(covariant GlassPowerButtonGlowPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.tint != tint;
}

/// Paints a translucent sea-glass lens with a curved, refractive edge.
///
/// Volume comes from soft color falloff and edge occlusion rather than a metal
/// bezel. Highlights are small and diffused; there are no hard white streaks,
/// ripples, droplets, caustics, or animation.
class GlassPowerButtonPainter extends CustomPainter {
  const GlassPowerButtonPainter({required this.isDark, required this.tint});

  final bool isDark;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3.5;
    if (radius <= 0) return;
    final disc = Rect.fromCircle(center: center, radius: radius);
    final clip = Path()..addOval(disc);
    canvas.save();
    canvas.clipPath(clip, doAntiAlias: true);

    // A low-opacity body keeps the underlying scene visible through the lens.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.30, -0.38),
          radius: 1.34,
          colors: isDark
              ? [
                  const Color(0xFFD8EDFF).withValues(alpha: 0.075),
                  const Color(0xFF9ECBF1).withValues(alpha: 0.045),
                  const Color(0xFF304967).withValues(alpha: 0.055),
                  const Color(0xFF111D2E).withValues(alpha: 0.13),
                  const Color(0xFF050B14).withValues(alpha: 0.26),
                ]
              : [
                  Colors.white.withValues(alpha: 0.42),
                  const Color(0xFFE6F7FF).withValues(alpha: 0.31),
                  const Color(0xFFA7D3EC).withValues(alpha: 0.23),
                  const Color(0xFF54718D).withValues(alpha: 0.11),
                  const Color(0xFF20364B).withValues(alpha: 0.12),
                ],
          stops: const [0, 0.24, 0.55, 0.82, 1],
        ).createShader(disc),
    );

    // Edge occlusion gives the clear center a convex, thick-glass profile.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: isDark
              ? [
                  Colors.transparent,
                  Colors.transparent,
                  const Color(0xFF081321).withValues(alpha: 0.10),
                  const Color(0xFF020812).withValues(alpha: 0.30),
                  const Color(0xFF020710).withValues(alpha: 0.13),
                ]
              : [
                  Colors.transparent,
                  Colors.transparent,
                  const Color(0xFF53738E).withValues(alpha: 0.045),
                  const Color(0xFF34546E).withValues(alpha: 0.10),
                  const Color(0xFF203B53).withValues(alpha: 0.045),
                ],
          stops: const [0, 0.70, 0.83, 0.93, 1],
        ).createShader(disc),
    );

    // A broad, asymmetric upper-left reflection gives the sphere a real light
    // source without laying a hard stripe across the button face.
    canvas.save();
    canvas.translate(center.dx - radius * 0.36, center.dy - radius * 0.38);
    canvas.rotate(-0.64);
    final reflection = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 1.30,
      height: radius * 0.78,
    );
    canvas.drawOval(
      reflection,
      Paint()
        ..shader = RadialGradient(
          radius: 1.05,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.34 : 0.22),
            const Color(0xFFD9F0FF).withValues(alpha: isDark ? 0.22 : 0.13),
            const Color(0xFFB7DDF8).withValues(alpha: isDark ? 0.085 : 0.05),
            Colors.transparent,
          ],
          stops: const [0, 0.50, 0.82, 1],
        ).createShader(reflection)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.restore();

    // Keep only a few reflected catches; the remaining edge comes from soft
    // refraction and shading, not a complete circular outline.
    final rimBounds = Rect.fromCircle(center: center, radius: radius - 3.4);
    // A diffuse upper-left glint follows the light source without tracing the
    // sphere. Its brief, sharper catch is intentionally discontinuous.
    _drawArc(
      canvas,
      rimBounds,
      start: -2.78,
      sweep: 1.02,
      width: 9.0,
      color: const Color(0xFFD9EEFF).withValues(alpha: isDark ? 0.22 : 0.19),
      blur: 7.0,
    );
    _drawArc(
      canvas,
      rimBounds,
      start: -2.53,
      sweep: 0.31,
      width: 1.55,
      color: Colors.white.withValues(alpha: isDark ? 0.80 : 0.54),
      blur: 0.9,
    );
    _drawArc(
      canvas,
      rimBounds,
      start: 0.42,
      sweep: 0.72,
      width: 5.0,
      color: const Color(0xFFB9E2FF).withValues(alpha: isDark ? 0.15 : 0.11),
      blur: 4.5,
    );
    _drawArc(
      canvas,
      rimBounds,
      start: 2.22,
      sweep: 0.46,
      width: 2.8,
      color: tint.withValues(alpha: isDark ? 0.20 : 0.12),
      blur: 2.8,
    );
    canvas.restore();
  }

  void _drawArc(
    Canvas canvas,
    Rect bounds, {
    required double start,
    required double sweep,
    required double width,
    required Color color,
    double blur = 0,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = color;
    if (blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    canvas.drawArc(bounds, start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant GlassPowerButtonPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.tint != tint;
}
