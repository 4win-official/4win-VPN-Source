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
    final headerHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
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

    // Leave room for the full sunburst below the status bar and toolbar,
    // including on notched phones. Scale down gracefully in compact layouts.
    final radius = min(
      (size.width * 0.085).clamp(22.0, 46.0),
      min(size.width, size.height) * 0.14,
    );
    final clearance = radius * (isDark ? 1.3 : 2.15);
    final center = Offset(
      min(size.width * 0.80, size.width - clearance),
      min(
        headerHeight + clearance + 12,
        size.height - clearance,
      ),
    );
    final breath = sin(progress * pi * 2);
    _halo(
      canvas,
      center,
      radius * (isDark ? 4.8 : 5.5),
      isDark ? const Color(0xFF7C9DFF) : const Color(0xFFFFC55C),
      isDark ? 0.14 : 0.22,
    );
    if (isDark) {
      _paintStars(canvas, size, center, radius);
      _paintMoon(canvas, center, radius, breath);
    } else {
      _paintSun(canvas, center, radius, breath);
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
    final r = radius * (1 + breath * 0.025);
    _halo(canvas, center, r * 1.65, const Color(0xFFFFD16A), 0.45);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    // Rounded, softly graded rays with generous space around the sun's core.
    canvas.rotate(progress * pi * 2);
    for (var i = 0; i < 12; i++) {
      final angle = i * pi / 6;
      final direction = Offset(cos(angle), sin(angle));
      final start = direction * (r * 1.36);
      final end = direction * (r * (i.isEven ? 1.95 : 1.73));
      canvas.drawLine(
        start,
        end,
        Paint()
          ..shader = LinearGradient(
            colors: const [Color(0xFFF7B744), Color(0xFFFFDC8A)],
          ).createShader(Rect.fromPoints(start, end).inflate(1))
          ..strokeWidth = r * 0.105
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();

    final disk = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center.translate(0, r * 0.10),
      r,
      Paint()
        ..color = const Color(0xFFEFA133).withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.24),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.38, -0.42),
          radius: 1.1,
          colors: [Color(0xFFFFF8CF), Color(0xFFFFDA70), Color(0xFFF5A632)],
          stops: [0, 0.52, 1],
        ).createShader(disk),
    );
    canvas.drawCircle(
      center,
      r - 0.7,
      Paint()
        ..color = const Color(0xFFFFF4C5).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawArc(
      disk.deflate(r * 0.19),
      pi * 1.08,
      pi * 0.42,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round,
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
    final random = Random(42);
    for (var i = 0; i < 42; i++) {
      final point = Offset(
        size.width * (0.05 + random.nextDouble() * 0.90),
        size.height * (0.07 + random.nextDouble() * 0.63),
      );
      final r = 0.6 + random.nextDouble() * 0.9;
      if ((point - moon).distance < radius * 1.7) continue;
      final shimmer = sin(progress * pi * 2 + i * 1.7);
      final paint = Paint()
        ..color = const Color(
          0xFFDFEAFF,
        ).withValues(alpha: 0.28 + (shimmer + 1) * 0.20);
      canvas.drawCircle(point, r, paint);
      if (i % 9 == 0) {
        paint
          ..strokeWidth = 0.8
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(point.translate(-3, 0), point.translate(3, 0), paint);
        canvas.drawLine(point.translate(0, -3), point.translate(0, 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DayNightPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.headerHeight != headerHeight;
}
