import 'dart:math';

import 'package:flutter/material.dart';

/// A dark-space scene for Advanced mode. The slow accretion-disk drift is
/// decorative only and automatically stops when reduced motion is requested.
class BlackHoleBackground extends StatefulWidget {
  const BlackHoleBackground({super.key});

  @override
  State<BlackHoleBackground> createState() => _BlackHoleBackgroundState();
}

class _BlackHoleBackgroundState extends State<BlackHoleBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 48),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate =
        !MediaQuery.disableAnimationsOf(context) && TickerMode.of(context);
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final headerHeight = max(
      MediaQuery.paddingOf(context).top,
      kToolbarHeight,
    );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: BlackHolePainter(
              progress: _controller.value,
              headerHeight: headerHeight,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Deterministic painter for a deep-space field, gravitational halo, and
/// luminous accretion disk. Stars remain in fixed positions while twinkling.
class BlackHolePainter extends CustomPainter {
  const BlackHolePainter({required this.progress, this.headerHeight = 0});

  final double progress;
  final double headerHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF070914),
            Color(0xFF0C0A18),
            Color(0xFF100914),
            Color(0xFF05060B),
          ],
          stops: [0, 0.42, 0.72, 1],
        ).createShader(bounds),
    );

    _paintGlow(
      canvas,
      Offset(size.width * 0.10, size.height * 0.24),
      size.width * 0.66,
      const Color(0xFF3B4C99),
      0.20,
    );
    _paintGlow(
      canvas,
      Offset(size.width * 0.93, size.height * 0.43),
      size.width * 0.62,
      const Color(0xFF9A3F38),
      0.14,
    );
    _paintGlow(
      canvas,
      Offset(size.width * 0.49, size.height * 0.88),
      size.width * 0.78,
      const Color(0xFF342252),
      0.12,
    );
    _paintStars(canvas, size);

    final center = Offset(
      size.width * 0.70,
      min(
        max(headerHeight + size.height * 0.19, size.height * 0.24),
        size.height * 0.37,
      ),
    );
    final radius = min(size.width * 0.142, size.height * 0.082).clamp(
      34.0,
      64.0,
    ).toDouble();
    _paintBlackHole(canvas, center, radius);
    _paintOrbitingDust(canvas, size, center, radius);

    // A very subtle bottom atmosphere helps the connection controls sit within
    // the scene rather than appearing pasted onto a flat black sheet.
    final lowerGlow = Rect.fromLTWH(
      0,
      size.height * 0.58,
      size.width,
      size.height * 0.42,
    );
    canvas.drawRect(
      lowerGlow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF5D2C35).withValues(alpha: 0.00),
            const Color(0xFF5D2C35).withValues(alpha: 0.08),
            const Color(0xFF171225).withValues(alpha: 0.18),
          ],
        ).createShader(lowerGlow),
    );
  }

  void _paintGlow(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double opacity,
  ) {
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
        ).createShader(bounds),
    );
  }

  void _paintStars(Canvas canvas, Size size) {
    for (var i = 0; i < 112; i++) {
      final x = ((i * 73 + 29) % 997) / 997 * size.width;
      final y = ((i * 193 + 47) % 991) / 991 * size.height;
      final twinkle = 0.5 + 0.5 * sin(progress * pi * 2 + i * 1.73);
      final radius = i % 13 == 0 ? 1.25 : (i % 4 == 0 ? 0.85 : 0.55);
      final tint = i % 9 == 0
          ? const Color(0xFFFFD5A2)
          : (i % 5 == 0 ? const Color(0xFFAFC6FF) : Colors.white);
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = tint.withValues(alpha: 0.20 + twinkle * 0.48),
      );
      if (i % 19 == 0) {
        final sparkle = Paint()
          ..color = tint.withValues(alpha: 0.14 + twinkle * 0.25)
          ..strokeWidth = 0.65
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), sparkle);
        canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), sparkle);
      }
    }
  }

  void _paintBlackHole(Canvas canvas, Offset center, double radius) {
    final glowBounds = Rect.fromCenter(
      center: center,
      width: radius * 5.2,
      height: radius * 2.0,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.16 + sin(progress * pi * 2) * 0.018);
    canvas.translate(-center.dx, -center.dy);

    // Diffuse plasma around the disk.
    canvas.drawOval(
      glowBounds,
      Paint()
        ..color = const Color(0xFFFF7138).withValues(alpha: 0.24)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.55),
    );

    final disk = Rect.fromCenter(
      center: center,
      width: radius * 4.05,
      height: radius * 0.78,
    );
    canvas.drawOval(
      disk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.30
        ..color = const Color(0xFFFF6A32).withValues(alpha: 0.44)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.22),
    );
    canvas.drawOval(
      disk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.16
        ..shader = const LinearGradient(
          colors: [
            Color(0xFF8C2637),
            Color(0xFFFF7137),
            Color(0xFFFFD78A),
            Color(0xFFFF873B),
            Color(0xFF7E2536),
          ],
          stops: [0, 0.25, 0.49, 0.73, 1],
        ).createShader(disk),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, -radius * 0.04),
        width: radius * 3.40,
        height: radius * 0.34,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, radius * 0.035)
        ..color = const Color(0xFFFFE5B0).withValues(alpha: 0.80),
    );

    // The event horizon masks the center of the glowing disk.
    final horizon = Rect.fromCircle(center: center, radius: radius * 0.84);
    canvas.drawCircle(
      center,
      radius * 1.09,
      Paint()
        ..color = const Color(0xFFFFB45E).withValues(alpha: 0.34)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.16),
    );
    canvas.drawCircle(
      center,
      radius * 0.98,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.4, radius * 0.055)
        ..shader = const SweepGradient(
          colors: [
            Color(0xFFFF9A4D),
            Color(0xFFFFE4A4),
            Color(0xFFFF8B3E),
            Color(0xFFFFC879),
            Color(0xFFFF9A4D),
          ],
        ).createShader(horizon),
    );
    canvas.drawCircle(
      center,
      radius * 0.83,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF000000),
            const Color(0xFF020207),
            const Color(0xFF090A12).withValues(alpha: 0.96),
          ],
          stops: const [0.56, 0.86, 1],
        ).createShader(horizon),
    );

    // A thin lensing arc gives the silhouette its characteristic warped ring.
    final lens = Rect.fromCircle(center: center, radius: radius * 1.22);
    canvas.drawArc(
      lens,
      pi * 1.08,
      pi * 0.84,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, radius * 0.025)
        ..color = const Color(0xFFFFD08A).withValues(alpha: 0.54),
    );
    canvas.restore();
  }

  void _paintOrbitingDust(Canvas canvas, Size size, Offset center, double radius) {
    for (var i = 0; i < 13; i++) {
      final angle = (i / 13) * pi * 2 + progress * pi * 2;
      final orbit = radius * (1.9 + (i % 4) * 0.28);
      final point = Offset(
        center.dx + cos(angle) * orbit,
        center.dy + sin(angle) * orbit * 0.40,
      );
      if (point.dx < 0 || point.dx > size.width || point.dy < 0 || point.dy > size.height) {
        continue;
      }
      canvas.drawCircle(
        point,
        i % 4 == 0 ? 1.35 : 0.8,
        Paint()
          ..color = const Color(0xFFFFBD77).withValues(
            alpha: 0.30 + 0.35 * sin(angle).abs(),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BlackHolePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.headerHeight != headerHeight;
}

/// Compact icon-scale rendering used by the theme picker card.
class BlackHoleEmblem extends StatelessWidget {
  const BlackHoleEmblem({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(
    painter: _BlackHoleEmblemPainter(),
    child: SizedBox.expand(),
  );
}

class _BlackHoleEmblemPainter extends CustomPainter {
  const _BlackHoleEmblemPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = min(size.width, size.height) * 0.21;
    final disk = Rect.fromCenter(
      center: center,
      width: radius * 4.3,
      height: radius * 1.15,
    );
    canvas.drawOval(
      disk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.55
        ..color = const Color(0xFFFF7138).withValues(alpha: 0.78)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.32),
    );
    canvas.drawOval(
      disk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.24
        ..shader = const LinearGradient(
          colors: [Color(0xFFFF7138), Color(0xFFFFE0A0), Color(0xFFFF783A)],
        ).createShader(disk),
    );
    canvas.drawCircle(
      center,
      radius * 0.88,
      Paint()..color = const Color(0xFF03040A),
    );
    canvas.drawCircle(
      center,
      radius * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, radius * 0.16)
        ..color = const Color(0xFFFFD18A),
    );
  }

  @override
  bool shouldRepaint(covariant _BlackHoleEmblemPainter oldDelegate) => false;
}

/// Adds a quiet event-horizon orbit line inside the existing tappable button.
class BlackHolePowerButtonSurface extends StatelessWidget {
  const BlackHolePowerButtonSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _BlackHolePowerButtonPainter(),
    child: SizedBox.expand(child: Center(child: child)),
  );
}

class _BlackHolePowerButtonPainter extends CustomPainter {
  const _BlackHolePowerButtonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = min(size.width, size.height) * 0.445;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFD29A).withValues(alpha: 0.15),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.91),
      pi * 1.08,
      pi * 0.58,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFB56B).withValues(alpha: 0.34),
    );
  }

  @override
  bool shouldRepaint(covariant _BlackHolePowerButtonPainter oldDelegate) =>
      false;
}
