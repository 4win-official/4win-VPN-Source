import 'dart:math';
import 'package:flutter/material.dart';

/// A decorative sky that follows the app's brightness, not the device clock.
class DayNightAnimation extends StatefulWidget {
  const DayNightAnimation({super.key});

  @override
  State<DayNightAnimation> createState() => _DayNightAnimationState();
}

class _DayNightAnimationState extends State<DayNightAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        !MediaQuery.disableAnimationsOf(context) && TickerMode.of(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate) {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The extended Scaffold body already includes the complete app bar in its
    // top padding. Adding kToolbarHeight again pushes the sun into the controls.
    final headerHeight = max(MediaQuery.paddingOf(context).top, kToolbarHeight);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: DayNightPainter(
              progress: _controller.value,
              isDark: isDark,
              headerHeight: headerHeight,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Pure, deterministic painting keeps stars stable across frames and resizes.
class DayNightPainter extends CustomPainter {
  const DayNightPainter({
    required this.progress,
    required this.isDark,
    this.headerHeight = kToolbarHeight,
  });

  final double progress;
  final bool isDark;
  final double headerHeight;

  // Includes the visible corona, not the very faint atmospheric glow. Keep
  // the whole sun in the upper-right pocket, directly below the app bar.
  @visibleForTesting
  Rect sunBounds(Size size) {
    if (size.isEmpty) return Rect.zero;
    final radius = min(
      (size.width * 0.072).clamp(18.0, 32.0),
      min(size.width * 0.14, size.height * 0.055),
    );
    final top = min(headerHeight + 8, size.height);
    var extent = min(radius * 1.5, (size.height - top) / 2);
    // On narrow portrait screens the central controls start much higher.
    // Fit the full corona into the upper band instead of sliding it down.
    if (size.height > size.width) {
      extent = min(extent, max(0.0, (size.height * 0.22 - top) / 2));
    }
    if (extent <= 0) return Rect.zero;
    final right = max(extent * 2, size.width - min(24.0, size.width * 0.06));
    return Rect.fromLTWH(right - extent * 2, top, extent * 2, extent * 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF101F43), Color(0xFF080F25), Color(0xFF15162E)]
              : const [Color(0xFFDFEFFA), Color(0xFFFFF8E9), Color(0xFFFFFDF7)],
          stops: const [0, 0.55, 1],
        ).createShader(bounds),
    );

    // Keep the moon's existing design; the smaller sun has its own higher anchor
    // so it does not descend into the protocol selector / power-button zone.
    final radius = min(
      (size.width * 0.085).clamp(22.0, 46.0),
      min(size.width, size.height) * 0.14,
    );
    final clearance = radius * (isDark ? 1.3 : 2.15);
    final center = Offset(
      min(size.width * 0.80, size.width - clearance),
      min(headerHeight + clearance + 12, size.height - clearance),
    );
    final breath = sin(progress * pi * 2);
    if (isDark) {
      _halo(canvas, center, radius * 4.8, const Color(0xFF7C9DFF), 0.14);
      _paintStars(canvas, size, center, radius);
      _paintMoon(canvas, center, radius, breath);
    } else {
      final sun = sunBounds(size);
      if (!sun.isEmpty) {
        _paintSun(canvas, sun.center, sun.width / 3, breath);
      }
    }
    canvas.restore();
  }

  void _halo(
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
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
  }

  void _paintSun(Canvas canvas, Offset center, double radius, double breath) {
    // A luminous solar disc rather than a rotating icon: warm limb darkening,
    // a fine corona and diffuse sunlight, without spokes or a glossy highlight.
    _halo(canvas, center, radius * 4, const Color(0xFFFFCD72), 0.14);
    _halo(
      canvas,
      center,
      radius * (1.48 + breath * 0.02),
      const Color(0xFFFFC04F),
      0.42 + breath * 0.025,
    );
    final disk = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.52,
          colors: [
            Color(0xFFFFFCE3),
            Color(0xFFFFEDAB),
            Color(0xFFFFD16A),
            Color(0xFFF6B74B),
          ],
          stops: [0, 0.55, 0.88, 1],
        ).createShader(disk),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFFFE8A0).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
    );
  }

  void _paintMoon(Canvas canvas, Offset center, double radius, double breath) {
    final r = radius * 1.12;
    final disk = Rect.fromCircle(center: center, radius: r);
    // A real cut-out path rather than a sky-coloured disc: the sky and stars
    // remain visible through the crescent's open side.
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(disk),
      Path()..addOval(
        Rect.fromCircle(
          center: center.translate(r * 0.65, -r * 0.34),
          radius: r * 0.92,
        ),
      ),
    );
    canvas.drawPath(
      crescent,
      Paint()
        ..color = const Color(
          0xFFB4D2FF,
        ).withValues(alpha: 0.30 + breath * 0.04)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.30),
    );
    canvas.drawPath(
      crescent,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5FAFF), Color(0xFFD1E2FF), Color(0xFF8CAADD)],
        ).createShader(disk),
    );
    canvas.save();
    canvas.clipPath(crescent);
    for (final crater in const [
      Offset(-0.47, -0.28),
      Offset(-0.34, 0.40),
      Offset(0.04, 0.67),
    ]) {
      final p = center + crater * r;
      canvas.drawCircle(
        p,
        r * (crater.dy < 0 ? 0.13 : 0.09),
        Paint()..color = const Color(0xFF7E9DCA).withValues(alpha: 0.18),
      );
    }
    canvas.restore();
    canvas.drawPath(
      crescent,
      Paint()
        ..color = const Color(0xFFE8F2FF).withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  void _paintStars(Canvas canvas, Size size, Offset moon, double radius) {
    // Cache the seeded sky once: no bitmap, no frame-to-frame random jumps and
    // no decorative cross-shaped stars. Most points are faint and subpixel.
    final count = (size.width * size.height / 3000).round().clamp(60, 180);
    final time = progress * pi * 2;
    final paint = Paint();
    for (final star in _stars.take(count)) {
      final point = Offset(
        size.width * star.position.dx,
        size.height * star.position.dy,
      );
      if ((point - moon).distance < radius * 1.7) continue;

      // Independent overlapping rhythms mimic atmospheric scintillation.
      // Integer harmonics make the 24-second loop continuous at its seam;
      // stars never all blink off, travel, or pulsate in sync.
      final shimmer =
          sin(time * star.frequency + star.phase) * 0.6 +
          sin(time * (star.frequency + 3) + star.phase * 2.3) * 0.3 +
          sin(time * (star.frequency + 7) + star.phase * 0.7) * 0.1;
      final horizon = 1 - pow(star.position.dy, 3) * 0.75;
      final alpha = (star.brightness + shimmer * star.twinkle) * horizon;
      if (star.radius > 0.95) {
        _halo(canvas, point, star.radius * 3.5, star.color, alpha * 0.16);
      }
      paint.color = star.color.withValues(alpha: alpha);
      canvas.drawCircle(point, star.radius * (1 + shimmer * 0.06), paint);
    }
  }

  static final List<_SkyStar> _stars = _createStars();

  static List<_SkyStar> _createStars() {
    final random = Random(42);
    return List.generate(180, (_) {
      final position = Offset(
        0.025 + random.nextDouble() * 0.95,
        0.035 + random.nextDouble() * 0.90,
      );
      // A magnitude-like distribution: many dim stars, a few bright ones.
      final magnitude = pow(random.nextDouble(), 3).toDouble();
      return _SkyStar(
        position: position,
        radius: 0.35 + magnitude * 0.95,
        brightness: 0.22 + magnitude * 0.6,
        twinkle: 0.05 + random.nextDouble() * 0.13,
        phase: random.nextDouble() * pi * 2,
        frequency: 3 + random.nextInt(6),
        color: const [
          Color(0xFFE4EDFF),
          Color(0xFFFFE9CE),
          Color(0xFFF4F6FF),
          Color(0xFFCADCFF),
        ][random.nextInt(4)],
      );
    }, growable: false);
  }

  @override
  bool shouldRepaint(covariant DayNightPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.headerHeight != headerHeight;
}

class _SkyStar {
  const _SkyStar({
    required this.position,
    required this.radius,
    required this.brightness,
    required this.twinkle,
    required this.phase,
    required this.frequency,
    required this.color,
  });

  final Offset position;
  final double radius;
  final double brightness;
  final double twinkle;
  final double phase;
  final int frequency;
  final Color color;
}
