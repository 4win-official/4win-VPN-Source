import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A polished, eye-catching animated donate button.
///
/// The heart is filled with a smoothly rotating rainbow sweep gradient and
/// performs a gentle "heartbeat" pulse. Kept subtle and graphical rather than
/// flashy so it looks premium in the app bar.
class RainbowHeartButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  const RainbowHeartButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Support Us',
    this.size = 26,
  });

  @override
  State<RainbowHeartButton> createState() => _RainbowHeartButtonState();
}

class _RainbowHeartButtonState extends State<RainbowHeartButton>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _beat;
  late final Animation<double> _beatCurve;

  static const List<Color> _rainbow = [
    Color(0xFFFF3B6B), // pink-red
    Color(0xFFFF9A3D), // orange
    Color(0xFFFFE14D), // yellow
    Color(0xFF4DE38A), // green
    Color(0xFF38B6FF), // sky blue
    Color(0xFF7C5CFF), // violet
    Color(0xFFFF3B6B), // back to start (seamless loop)
  ];

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _beat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _beatCurve = CurvedAnimation(parent: _beat, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _spin.dispose();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      icon: AnimatedBuilder(
        animation: Listenable.merge([_spin, _beatCurve]),
        builder: (context, _) {
          final scale = 1.0 + (_beatCurve.value * 0.14);
          return Transform.scale(
            scale: scale,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RainbowHeartPainter(
                angle: _spin.value * 2 * math.pi,
                colors: _rainbow,
                glow: _beatCurve.value,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RainbowHeartPainter extends CustomPainter {
  final double angle;
  final List<Color> colors;
  final double glow;

  _RainbowHeartPainter({
    required this.angle,
    required this.colors,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = _heartPath(size);

    // Soft glow halo behind the heart.
    final glowPaint = Paint()
      ..color = colors.first.withValues(alpha: 0.18 + glow * 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + glow * 3);
    canvas.drawPath(path, glowPaint);

    // Rotating rainbow sweep fill.
    final shader = SweepGradient(
      colors: colors,
      transform: GradientRotation(angle),
    ).createShader(rect);
    final fillPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, fillPaint);

    // Subtle top highlight for a glossy, graphical look.
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    final hlPath = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(size.width * 0.34, size.height * 0.32),
        radius: size.width * 0.12,
      ));
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(hlPath, highlight);
    canvas.restore();
  }

  /// Classic heart shape scaled to [size].
  Path _heartPath(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w * 0.5, h * 0.88);
    // left half
    path.cubicTo(w * -0.08, h * 0.52, w * 0.14, h * 0.04, w * 0.5, h * 0.30);
    // right half
    path.cubicTo(w * 0.86, h * 0.04, w * 1.08, h * 0.52, w * 0.5, h * 0.88);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_RainbowHeartPainter old) =>
      old.angle != angle || old.glow != glow;
}
