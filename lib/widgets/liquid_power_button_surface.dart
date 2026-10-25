import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A graphic, animated water circle used only by the Liquid theme.
///
/// This is decorative: the supplied icon or loader remains centered, while the
/// home screen continues to own the power button's size and gesture handling.
class LiquidPowerButtonSurface extends StatefulWidget {
  const LiquidPowerButtonSurface({
    super.key,
    required this.isDark,
    required this.tint,
    required this.child,
  });

  final bool isDark;
  final Color tint;
  final Widget child;

  @override
  State<LiquidPowerButtonSurface> createState() =>
      _LiquidPowerButtonSurfaceState();
}

class _LiquidPowerButtonSurfaceState extends State<LiquidPowerButtonSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase;

  @override
  void initState() {
    super.initState();
    _phase = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: LiquidPowerButtonGlowPainter(
                isDark: widget.isDark,
                tint: widget.tint,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: ClipPath(
              clipper: const LiquidPowerButtonClipper(),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: LiquidPowerButtonPainter(
                    isDark: widget.isDark,
                    tint: widget.tint,
                    phase: _phase,
                  ),
                  child: Center(child: widget.child),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips the artwork to a centered, perfect circle inside the square hit area.
class LiquidPowerButtonClipper extends CustomClipper<Path> {
  const LiquidPowerButtonClipper();

  @override
  Path getClip(Size size) => _circlePath(size);

  @override
  bool shouldReclip(covariant LiquidPowerButtonClipper oldClipper) => false;
}

/// Paints bold, moving water shapes without glass reflections or light streaks.
class LiquidPowerButtonPainter extends CustomPainter {
  LiquidPowerButtonPainter({
    required this.isDark,
    required this.tint,
    required this.phase,
  }) : super(repaint: phase);

  final bool isDark;
  final Color tint;
  final Animation<double> phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final circle = _circlePath(size);
    final bounds = circle.getBounds();
    final angle = phase.value * math.pi * 2;
    final center = bounds.center;
    final radius = bounds.width / 2;

    canvas.save();
    canvas.clipPath(circle, doAntiAlias: true);

    canvas.drawPath(
      circle,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF082443), Color(0xFF0A3855)]
              : const [Color(0xFFBDEEF0), Color(0xFF8BDCE8)],
        ).createShader(bounds),
    );

    // The rear wave sits higher; the bright foreground wave moves at a
    // different speed so the water reads as layered graphic shapes.
    final rearWave = _wavePath(
      bounds,
      level: 0.655,
      amplitude: 0.042,
      angle: angle * 0.78 + 1.1,
    );
    canvas.drawPath(
      rearWave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF2785FF), Color(0xFF344CC7)]
              : const [Color(0xFF2386F4), Color(0xFF3858D4)],
        ).createShader(bounds),
    );

    final frontWave = _wavePath(
      bounds,
      level: 0.595,
      amplitude: 0.052,
      angle: angle * 1.18,
    );
    canvas.drawPath(
      frontWave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF08D9C5), Color(0xFF078BCB)]
              : const [Color(0xFF05CDB7), Color(0xFF087FC5)],
        ).createShader(bounds),
    );

    _drawBubbles(canvas, bounds, angle);

    // A simple colored outline keeps the vector badge crisp; it is not a
    // highlight or reflective rim.
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, radius * 0.045)
        ..color = isDark
            ? Color.lerp(tint, const Color(0xFF2DD8DC), 0.32)!
                .withValues(alpha: 0.88)
            : Color.lerp(tint, const Color(0xFF11698D), 0.22)!
                .withValues(alpha: 0.9),
    );

    canvas.restore();
  }

  void _drawBubbles(Canvas canvas, Rect bounds, double angle) {
    const bubbles = <(double, double, double, double)>[
      (0.31, 0.91, 0.035, 0.00),
      (0.68, 0.84, 0.024, 0.34),
      (0.48, 0.96, 0.020, 0.66),
      (0.78, 0.98, 0.031, 0.82),
    ];
    final color = isDark ? const Color(0xFF8EF5E8) : const Color(0xFFDBFFFA);
    for (final (x, y, relativeRadius, offset) in bubbles) {
      final bob = math.sin(angle + offset * math.pi * 2) * 0.025;
      final bubbleCenter = Offset(
        bounds.left + bounds.width * x,
        bounds.top + bounds.height * (y + bob),
      );
      canvas.drawCircle(
        bubbleCenter,
        bounds.width * relativeRadius,
        Paint()..color = color.withValues(alpha: isDark ? 0.62 : 0.72),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LiquidPowerButtonPainter oldDelegate) =>
      oldDelegate.isDark != isDark ||
      oldDelegate.tint != tint ||
      oldDelegate.phase != phase;
}

/// Adds only a restrained, status-tinted shadow beyond the circular badge.
/// No white shine, specular glint, or reflection is painted here.
class LiquidPowerButtonGlowPainter extends CustomPainter {
  const LiquidPowerButtonGlowPainter({
    required this.isDark,
    required this.tint,
  });

  final bool isDark;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final circle = _circlePath(size);
    canvas.drawShadow(
      circle,
      tint.withValues(alpha: isDark ? 0.22 : 0.14),
      size.shortestSide * 0.055,
      true,
    );
  }

  @override
  bool shouldRepaint(covariant LiquidPowerButtonGlowPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.tint != tint;
}

Path _circlePath(Size size) {
  final diameter = size.shortestSide - math.min(14, size.shortestSide * 0.07);
  return Path()
    ..addOval(
      Rect.fromCircle(center: size.center(Offset.zero), radius: diameter / 2),
    );
}

Path _wavePath(
  Rect bounds, {
  required double level,
  required double amplitude,
  required double angle,
}) {
  const segmentCount = 64;
  const wavelengthCount = 1.32;
  final path = Path();
  for (var i = 0; i <= segmentCount; i++) {
    final progress = i / segmentCount;
    final x = bounds.left + bounds.width * progress;
    final y = bounds.top +
        bounds.height *
            (level +
                amplitude *
                    math.sin(
                      progress * wavelengthCount * math.pi * 2 + angle,
                    ));
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path
    ..lineTo(bounds.right, bounds.bottom)
    ..lineTo(bounds.left, bounds.bottom)
    ..close();
  return path;
}
