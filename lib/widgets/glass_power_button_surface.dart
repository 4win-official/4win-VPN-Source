import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// A clear, reflective glass sphere that leaves the scene behind it visible.
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -34,
            top: -34,
            right: -34,
            bottom: -34,
            child: CustomPaint(
              painter: GlassPowerButtonGlowPainter(isDark: isDark, tint: tint),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: ClipOval(
                child: BackdropFilter(
                  // Keep the background legible through the clear lens.
                  filter: ImageFilter.blur(sigmaX: 0.45, sigmaY: 0.45),
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

/// A soft, small studio bloom around the glass edge; the center stays unlit.
class GlassPowerButtonGlowPainter extends CustomPainter {
  const GlassPowerButtonGlowPainter({required this.isDark, required this.tint});

  final bool isDark;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 36.5;
    if (radius <= 0) return;

    final bounds = Rect.fromCircle(center: center, radius: radius + 34);
    canvas.drawCircle(
      center,
      radius + 34,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.transparent,
            Colors.white.withValues(alpha: isDark ? 0.17 : 0.10),
            const Color(0xFFBBD9F4).withValues(alpha: isDark ? 0.12 : 0.065),
            Colors.transparent,
          ],
          stops: const [0, 0.75, 0.84, 0.92, 1],
        ).createShader(bounds),
    );

    // Wide, very faint bloom under the sharper glass reflections.
    canvas.drawCircle(
      center,
      radius + 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..color = Colors.white.withValues(alpha: isDark ? 0.13 : 0.075)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      center,
      radius + 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = tint.withValues(alpha: isDark ? 0.075 : 0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
  }

  @override
  bool shouldRepaint(covariant GlassPowerButtonGlowPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.tint != tint;
}

/// Paints a stationary dark lens with a sculpted silver-white glass rim.
///
/// Reflections are fixed studio highlights. There are no ripples, droplets,
/// caustics, or liquid animation, and the central glass stays transparent.
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
    final outerEdge = radius - 0.8;
    final rim = Rect.fromCircle(center: center, radius: radius - 2.0);

    // A nearly clear graphite lens: a little edge shading gives it volume,
    // while the center remains black on the reference's black background.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.02, -0.02),
          radius: 1,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.004 : 0.010),
            const Color(0xFF8D9BA9).withValues(alpha: isDark ? 0.010 : 0.018),
            const Color(0xFF778694).withValues(alpha: isDark ? 0.024 : 0.036),
            const Color(0xFFAAB8C5).withValues(alpha: isDark ? 0.052 : 0.075),
            const Color(0xFFDAE5EF).withValues(alpha: isDark ? 0.075 : 0.105),
          ],
          stops: const [0, 0.54, 0.78, 0.94, 1],
        ).createShader(sphere),
    );

    // The dark inset bevel separates the lens from its bright metal-like edge.
    canvas.drawCircle(
      center,
      radius - 5.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.black.withValues(alpha: isDark ? 0.55 : 0.34)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Broad low light under the rim, then a quiet steel base all the way round.
    canvas.drawCircle(
      center,
      radius - 1.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = const Color(
          0xFFC8D7E6,
        ).withValues(alpha: isDark ? 0.16 : 0.105)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.2),
    );
    canvas.drawCircle(
      center,
      radius - 1.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.2
        ..shader = SweepGradient(
          transform: GradientRotation(-math.pi / 2),
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.36 : 0.26),
            const Color(0xFFAAB6C2).withValues(alpha: isDark ? 0.17 : 0.12),
            const Color(0xFFECF5FF).withValues(alpha: isDark ? 0.48 : 0.35),
            Colors.white.withValues(alpha: isDark ? 0.10 : 0.07),
            Colors.white.withValues(alpha: isDark ? 0.28 : 0.20),
            const Color(0xFFB7D9FC).withValues(alpha: isDark ? 0.62 : 0.46),
            Colors.white.withValues(alpha: isDark ? 0.13 : 0.09),
            Colors.white.withValues(alpha: isDark ? 0.44 : 0.32),
            const Color(0xFFB8C6D3).withValues(alpha: isDark ? 0.21 : 0.15),
            Colors.white.withValues(alpha: isDark ? 0.36 : 0.26),
          ],
          stops: const [0, 0.09, 0.19, 0.29, 0.40, 0.53, 0.65, 0.76, 0.88, 1],
        ).createShader(rim),
    );

    // Clean, narrow Fresnel lines frame the thicker variable silver bevel.
    canvas.drawCircle(
      center,
      outerEdge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = Colors.white.withValues(alpha: isDark ? 0.48 : 0.34),
    );
    canvas.drawCircle(
      center,
      radius - 7.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(
          0xFFDDEBFA,
        ).withValues(alpha: isDark ? 0.26 : 0.17),
    );

    // Variable-width silver-white catches stay on the glass lip; the lens
    // interior remains clear rather than carrying a broad studio streak.
    _drawArc(
      canvas,
      rim,
      start: -2.66,
      sweep: 0.88,
      width: 8.1,
      color: const Color(0xFFEAF4FF).withValues(alpha: isDark ? 0.93 : 0.70),
      blur: 3.2,
    );
    _drawArc(
      canvas,
      rim,
      start: -2.61,
      sweep: 0.77,
      width: 4.2,
      color: Colors.white.withValues(alpha: isDark ? 0.98 : 0.81),
    );

    // Smaller opposing specular catches: cool-white top/right, a blue-white
    // glint at lower left, and a quiet lower-right reflection.
    _drawArc(
      canvas,
      rim,
      start: -1.47,
      sweep: 0.60,
      width: 8.2,
      color: Colors.white.withValues(alpha: isDark ? 0.80 : 0.60),
      blur: 4.2,
    );
    _drawArc(
      canvas,
      rim,
      start: -1.41,
      sweep: 0.51,
      width: 4.8,
      color: Colors.white.withValues(alpha: isDark ? 0.98 : 0.77),
      blur: 0.9,
    );
    _drawArc(
      canvas,
      rim,
      start: -0.12,
      sweep: 0.25,
      width: 3.0,
      color: const Color(0xFFEAF5FF).withValues(alpha: isDark ? 0.74 : 0.53),
      blur: 1.2,
    );
    _drawArc(
      canvas,
      rim,
      start: 2.66,
      sweep: 0.52,
      width: 9.0,
      color: const Color(0xFFE7F4FF).withValues(alpha: isDark ? 0.68 : 0.49),
      blur: 4.0,
    );
    _drawArc(
      canvas,
      rim,
      start: 2.72,
      sweep: 0.42,
      width: 5.2,
      color: const Color(0xFFF4FAFF).withValues(alpha: isDark ? 0.95 : 0.72),
      blur: 0.8,
    );
    _drawArc(
      canvas,
      rim,
      start: 0.80,
      sweep: 0.44,
      width: 3.1,
      color: Colors.white.withValues(alpha: isDark ? 0.58 : 0.39),
      blur: 1.6,
    );

    // Fine inner glints add lens depth without a second circular ripple.
    final rightReflection = Path()
      ..moveTo(center.dx + radius * 0.69, center.dy - radius * 0.52)
      ..cubicTo(
        center.dx + radius * 0.78,
        center.dy - radius * 0.42,
        center.dx + radius * 0.82,
        center.dy - radius * 0.27,
        center.dx + radius * 0.81,
        center.dy - radius * 0.14,
      );
    canvas.drawPath(
      rightReflection,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.6
        ..color = Colors.white.withValues(alpha: isDark ? 0.40 : 0.26)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );

    final innerLeftReflection = Path()
      ..moveTo(center.dx - radius * 0.76, center.dy - radius * 0.10)
      ..cubicTo(
        center.dx - radius * 0.68,
        center.dy + radius * 0.02,
        center.dx - radius * 0.58,
        center.dy + radius * 0.18,
        center.dx - radius * 0.47,
        center.dy + radius * 0.25,
      );
    canvas.drawPath(
      innerLeftReflection,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4.4
        ..color = const Color(
          0xFFB9D9F8,
        ).withValues(alpha: isDark ? 0.23 : 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.8),
    );
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
