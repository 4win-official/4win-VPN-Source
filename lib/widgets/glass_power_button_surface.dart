import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A clear, reflective sphere with a slowly moving liquid-like caustic.
///
/// The surface is decorative only: its child remains the existing power icon
/// or connection loader, and callers keep ownership of the button gesture.
class GlassPowerButtonSurface extends StatefulWidget {
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
  State<GlassPowerButtonSurface> createState() =>
      _GlassPowerButtonSurfaceState();
}

class _GlassPowerButtonSurfaceState extends State<GlassPowerButtonSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _animation
        ..stop()
        ..value = 0;
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: RepaintBoundary(
        child: ClipOval(
          child: CustomPaint(
            painter: GlassPowerButtonPainter(
              animation: _animation,
              isDark: widget.isDark,
              tint: widget.tint,
            ),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Paints the optical cues of a transparent glass sphere without covering its
/// centre with an opaque fill. Repaints directly from the animation controller.
class GlassPowerButtonPainter extends CustomPainter {
  const GlassPowerButtonPainter({
    required this.animation,
    required this.isDark,
    required this.tint,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final bool isDark;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2.5;
    if (radius <= 0) return;
    final sphere = Rect.fromCircle(center: center, radius: radius);
    final phase = animation.value * math.pi * 2;

    // A restrained, translucent body lets the existing home background show
    // through while adding enough shading to read as a curved glass lens.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.24, -0.30),
          radius: 1.18,
          colors: isDark
              ? const [Color(0x101C2A38), Color(0x14222D39), Color(0x52384450)]
              : const [Color(0x12FFFFFF), Color(0x12FFFFFF), Color(0x344B5A68)],
          stops: const [0, 0.62, 1],
        ).createShader(sphere),
    );

    // The softly blurred moving band suggests liquid refracting inside the
    // sphere; its travel is intentionally slow and low-contrast.
    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));
    final wave = Path();
    final baseY = center.dy + radius * (0.18 + math.sin(phase) * 0.045);
    const samples = 48;
    for (var i = 0; i <= samples; i++) {
      final x = size.width * i / samples;
      final t = i / samples * math.pi * 2;
      final y =
          baseY +
          math.sin(t + phase) * radius * 0.045 +
          math.sin(t * 2 - phase * 0.7) * radius * 0.018;
      if (i == 0) {
        wave.moveTo(x, y);
      } else {
        wave.lineTo(x, y);
      }
    }
    wave
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      wave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.105 : 0.07),
            tint.withValues(alpha: isDark ? 0.035 : 0.025),
            Colors.white.withValues(alpha: 0.012),
          ],
          stops: const [0, 0.52, 1],
        ).createShader(sphere)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      wave,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: isDark ? 0.15 : 0.12),
    );

    // A small drifting caustic gives the liquid reflection a little motion.
    final causticCenter = Offset(
      center.dx + math.sin(phase * 0.62) * radius * 0.24,
      center.dy + radius * (0.48 + math.cos(phase * 0.62) * 0.055),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: causticCenter,
        width: radius * 0.58,
        height: radius * 0.15,
      ),
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.17 : 0.12),
                tint.withValues(alpha: 0.035),
                Colors.transparent,
              ],
              stops: const [0, 0.48, 1],
            ).createShader(
              Rect.fromCenter(
                center: causticCenter,
                width: radius * 0.58,
                height: radius * 0.15,
              ),
            )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.restore();

    // A cool silver-blue perimeter catches light like a rounded, thick rim.
    final rim = Rect.fromCircle(center: center, radius: radius - 1.7);
    canvas.drawCircle(
      center,
      radius - 1.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..shader = SweepGradient(
          transform: GradientRotation(phase * 0.035),
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.78 : 0.66),
            tint.withValues(alpha: isDark ? 0.30 : 0.20),
            Colors.white.withValues(alpha: isDark ? 0.14 : 0.10),
            Colors.black.withValues(alpha: isDark ? 0.30 : 0.16),
            Colors.white.withValues(alpha: isDark ? 0.72 : 0.58),
            tint.withValues(alpha: isDark ? 0.22 : 0.14),
            Colors.white.withValues(alpha: isDark ? 0.78 : 0.66),
          ],
          stops: const [0, 0.16, 0.34, 0.50, 0.68, 0.84, 1],
        ).createShader(rim),
    );
    canvas.drawCircle(
      center,
      radius - 6.0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = Colors.white.withValues(alpha: isDark ? 0.17 : 0.13),
    );

    // Broad, feathered upper-left reflection and a quieter opposite glint.
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8
      ..color = Colors.white.withValues(alpha: isDark ? 0.66 : 0.54)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(rim, -2.55, 0.92, false, highlight);
    canvas.drawArc(
      rim,
      0.66 + math.sin(phase) * 0.035,
      0.48,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4.0
        ..color = Colors.white.withValues(alpha: isDark ? 0.42 : 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawArc(
      rim,
      -2.53,
      0.86,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.0
        ..color = Colors.white.withValues(alpha: isDark ? 0.86 : 0.70),
    );

    // A moving soft reflection on the face makes the surface feel wet, not
    // metallic, while leaving the power symbol crisp and fully interactive.
    final glossCenter = Offset(
      center.dx - radius * 0.30 + math.sin(phase * 0.55) * radius * 0.035,
      center.dy - radius * 0.44 + math.cos(phase * 0.55) * radius * 0.025,
    );
    canvas.save();
    canvas.translate(glossCenter.dx, glossCenter.dy);
    canvas.rotate(-0.72);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: radius * 0.78, height: 15),
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.44 : 0.34),
                Colors.white.withValues(alpha: isDark ? 0.12 : 0.09),
                Colors.transparent,
              ],
              stops: const [0, 0.36, 1],
            ).createShader(
              Rect.fromCenter(
                center: Offset.zero,
                width: radius * 0.78,
                height: 15,
              ),
            )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GlassPowerButtonPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.isDark != isDark ||
      oldDelegate.tint != tint;
}
