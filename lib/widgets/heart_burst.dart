import 'dart:math';
import 'package:flutter/material.dart';

/// A one-shot burst of colourful hearts that fly outward and fade away.
///
/// Used by the Pink theme: when the VPN connects, a shower of hearts erupts
/// from behind the power button and disappears after a few seconds.
///
/// The visual burst may be larger than the power button, but its layout footprint
/// stays at [layoutSize]. This is important because it is placed beside the
/// power button in a centered Stack: the animation must overflow visually
/// without making the whole center column taller and shifting the controls.
class HeartBurst extends StatefulWidget {
  final Object? trigger;
  final double size;
  final double layoutSize;

  const HeartBurst({
    super.key,
    required this.trigger,
    this.size = 320,
    this.layoutSize = 200,
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
      final distance = _random.nextDouble() * 0.5 + 0.5;
      return _Heart(
        angle: angle,
        distance: distance,
        size: _random.nextDouble() * 14 + 14,
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
    // Keep the Stack's layout footprint equal to the power button while letting
    // the actual animation paint outside it. Previously the 340px HeartBurst
    // made the center Stack 340px tall, which shifted the protocol selector and
    // power button upward only in the Pink theme.
    return IgnorePointer(
      child: SizedBox(
        width: widget.layoutSize,
        height: widget.layoutSize,
        child: OverflowBox(
          minWidth: widget.size,
          maxWidth: widget.size,
          minHeight: widget.size,
          maxHeight: widget.size,
          alignment: Alignment.center,
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
  final double t;
  final List<_Heart> hearts;

  _HeartBurstPainter({required this.t, required this.hearts});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    for (final h in hearts) {
      final span = 1.0 - h.delay;
      double p = ((t - h.delay) / span).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final eased = Curves.easeOut.transform(p);
      final r = maxR * h.distance * eased;
      final swayOffset = sin(p * pi * 2) * h.sway * maxR * 0.2;
      final dir = Offset(cos(h.angle), sin(h.angle));
      final perp = Offset(-dir.dy, dir.dx);
      final pos = center + dir * r + perp * swayOffset;

      double alpha;
      if (p < 0.15) {
        alpha = p / 0.15;
      } else if (p < 0.6) {
        alpha = 1.0;
      } else {
        alpha = (1.0 - (p - 0.6) / 0.4).clamp(0.0, 1.0);
      }

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
