import 'dart:math';
import 'package:flutter/material.dart';

/// A one-shot burst of colourful hearts that fly outward and fade away.
///
/// Used by the Pink theme: when the VPN connects, a shower of hearts erupts
/// from behind the power button and disappears after a few seconds.
///
/// Drive it by flipping [trigger] to a new value (e.g. an incrementing counter
/// or a bool that becomes true on connect). Each time [trigger] changes, a fresh
/// burst plays. The widget paints within its own bounds, so place it in a Stack
/// sized to (and centred on) the power button.
class HeartBurst extends StatefulWidget {
  /// Change this value to launch a new burst.
  final Object? trigger;

  /// Diameter of the area the hearts spread across.
  final double size;

  const HeartBurst({
    super.key,
    required this.trigger,
    this.size = 320,
  });

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Random _random = Random();
  List<_Heart> _hearts = [];

  static const List<Color> _colors = [
    Color(0xFFFF3B6B),
    Color(0xFFFF69B4),
    Color(0xFFFF9AD5),
    Color(0xFFFFC1E3),
    Color(0xFFFF7AA2),
    Color(0xFFE05299),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    // Play once if a trigger is already set on first build.
    if (widget.trigger != null) _launch();
  }

  @override
  void didUpdateWidget(covariant HeartBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != null && widget.trigger != oldWidget.trigger) {
      _launch();
    }
  }

  void _launch() {
    _hearts = List.generate(18, (_) {
      final angle = _random.nextDouble() * pi * 2;
      final distance = _random.nextDouble() * 0.5 + 0.5; // 0.5..1.0 of radius
      return _Heart(
        angle: angle,
        distance: distance,
        size: _random.nextDouble() * 14 + 14, // 14..28
        color: _colors[_random.nextInt(_colors.length)],
        delay: _random.nextDouble() * 0.25,
        sway: (_random.nextDouble() - 0.5) * 0.4,
        spin: (_random.nextDouble() - 0.5) * 1.2,
      );
    });
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.isDismissed || _hearts.isEmpty) {
              return const SizedBox.shrink();
            }
            return CustomPaint(
              painter: _HeartBurstPainter(
                t: _controller.value,
                hearts: _hearts,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Heart {
  final double angle;
  final double distance;
  final double size;
  final Color color;
  final double delay;
  final double sway;
  final double spin;

  _Heart({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
    required this.delay,
    required this.sway,
    required this.spin,
  });
}

class _HeartBurstPainter extends CustomPainter {
  final double t; // 0..1 overall progress
  final List<_Heart> hearts;

  _HeartBurstPainter({required this.t, required this.hearts});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    for (final h in hearts) {
      // Per-heart eased progress with its own delay.
      final span = 1.0 - h.delay;
      double p = ((t - h.delay) / span).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final eased = Curves.easeOut.transform(p);

      // Fly outward, then keep drifting slightly while fading.
      final r = maxR * h.distance * eased;
      final swayOffset = sin(p * pi * 2) * h.sway * maxR * 0.2;
      final dir = Offset(cos(h.angle), sin(h.angle));
      final perp = Offset(-dir.dy, dir.dx);
      final pos = center + dir * r + perp * swayOffset;

      // Fade: appear fast, linger, then fade out in the last 40%.
      double alpha;
      if (p < 0.15) {
        alpha = p / 0.15;
      } else if (p < 0.6) {
        alpha = 1.0;
      } else {
        alpha = (1.0 - (p - 0.6) / 0.4).clamp(0.0, 1.0);
      }

      // Grow a touch then settle.
      final scale = 0.6 + eased * 0.7;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(h.spin * eased);
      canvas.scale(scale);

      final paint = Paint()
        ..color = h.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      _drawHeart(canvas, paint, h.size);

      // subtle glossy highlight
      final hl = Paint()
        ..color = Colors.white.withValues(alpha: alpha * 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(-h.size * 0.16, -h.size * 0.16),
        h.size * 0.12,
        hl,
      );

      canvas.restore();
    }
  }

  void _drawHeart(Canvas canvas, Paint paint, double s) {
    final path = Path();
    final w = s;
    final ht = s;
    path.moveTo(0, ht * 0.35);
    path.cubicTo(-w * 0.6, -ht * 0.1, -w * 0.35, -ht * 0.55, 0, -ht * 0.2);
    path.cubicTo(w * 0.35, -ht * 0.55, w * 0.6, -ht * 0.1, 0, ht * 0.35);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeartBurstPainter old) =>
      old.t != t || old.hearts != hearts;
}
