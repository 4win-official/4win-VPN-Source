import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A dimensional, animated water circle used only by the Liquid theme.
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
      duration: const Duration(milliseconds: 5200),
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

/// Paints a recessed, spherical button with gently moving water.
///
/// Depth comes from broad color gradients and the shaded inner rim rather than
/// bright reflections, glass streaks, cartoon bubbles, or decorative glints.
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
    final center = bounds.center;
    final radius = bounds.width / 2;

    // Modulo makes the endpoint exactly the starting phase. The wave's temporal
    // harmonics are whole cycles, so repeat() cannot expose a reset discontinuity.
    final cycle = phase.value % 1.0;
    final phaseRadians = cycle * math.pi * 2;

    canvas.save();
    canvas.clipPath(circle, doAntiAlias: true);

    canvas.drawPath(
      circle,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.34, -0.42),
          radius: 1.18,
          colors: isDark
              ? const [
                  Color(0xFF345263),
                  Color(0xFF183343),
                  Color(0xFF091824),
                ]
              : const [
                  Color(0xFFE6F0F1),
                  Color(0xFFB7CDD1),
                  Color(0xFF78949C),
                ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(bounds),
    );

    // A recessed dark well gives the water a clear, physical container.
    final wellRadius = radius * 0.855;
    final wellBounds = Rect.fromCircle(center: center, radius: wellRadius);
    final wellPath = Path()..addOval(wellBounds);
    canvas.drawPath(
      wellPath,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.12, -0.25),
          radius: 1.12,
          colors: isDark
              ? const [
                  Color(0xFF102B3B),
                  Color(0xFF091E2B),
                  Color(0xFF06141F),
                ]
              : const [
                  Color(0xFF355965),
                  Color(0xFF1E3E4A),
                  Color(0xFF122B36),
                ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(wellBounds),
    );

    canvas.save();
    canvas.clipPath(wellPath, doAntiAlias: true);

    final waterPath = _waterPath(
      wellBounds,
      level: 0.585,
      amplitude: 0.027,
      phase: phaseRadians,
    );
    canvas.drawPath(
      waterPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [
                  Color(0xFF32C3C9),
                  Color(0xFF168EAE),
                  Color(0xFF10538A),
                ]
              : const [
                  Color(0xFF43CED0),
                  Color(0xFF1499BC),
                  Color(0xFF2459A0),
                ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(wellBounds),
    );

    // A low-contrast radial falloff models the curved water volume without
    // adding any bright streaks or specular marks to its surface.
    canvas.save();
    canvas.clipPath(waterPath, doAntiAlias: true);
    canvas.drawRect(
      wellBounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, -0.16),
          radius: 1.02,
          colors: [
            Colors.transparent,
            (isDark ? const Color(0xFF031923) : const Color(0xFF123744))
                .withValues(alpha: isDark ? 0.27 : 0.22),
          ],
          stops: const [0.46, 1.0],
        ).createShader(wellBounds),
    );
    canvas.restore();
    canvas.restore();

    // Muted structural edges create a machined, inset look; neither ring is a
    // highlight, and both remain subdued in light and dark themes.
    canvas.drawCircle(
      center,
      wellRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, radius * 0.022)
        ..color = (isDark ? const Color(0xFF06131D) : const Color(0xFF34545E))
            .withValues(alpha: 0.72),
    );
    canvas.drawCircle(
      center,
      radius * 0.972,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, radius * 0.018)
        ..color = Color.lerp(
          tint,
          isDark ? const Color(0xFF315A6A) : const Color(0xFF66848B),
          0.58,
        )!.withValues(alpha: 0.76),
    );

    canvas.restore();
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

Path _waterPath(
  Rect bounds, {
  required double level,
  required double amplitude,
  required double phase,
}) {
  const segmentCount = 96;
  const primaryWavelengths = 1.18;
  const secondaryWavelengths = 2.36;
  final path = Path();

  for (var i = 0; i <= segmentCount; i++) {
    final progress = i / segmentCount;
    final x = bounds.left + bounds.width * progress;
    final primary = math.sin(
      progress * primaryWavelengths * math.pi * 2 + phase,
    );
    final secondary = math.sin(
      progress * secondaryWavelengths * math.pi * 2 - phase * 2 + 0.72,
    );
    final y = bounds.top +
        bounds.height * (level + amplitude * (primary * 0.76 + secondary * 0.24));

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
