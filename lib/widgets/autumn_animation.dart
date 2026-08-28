import 'dart:math';
import 'package:flutter/material.dart';

/// Falling autumn leaves animation — a full-screen overlay of leaves gently
/// drifting and swaying downward in warm autumn colours.
class AutumnAnimation extends StatefulWidget {
  const AutumnAnimation({super.key});

  @override
  State<AutumnAnimation> createState() => _AutumnAnimationState();
}

class _AutumnAnimationState extends State<AutumnAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Leaf> _leaves = [];
  final Random _random = Random();

  // Warm autumn palette.
  static const List<Color> _colors = [
    Color(0xFFD35400), // pumpkin
    Color(0xFFE67E22), // carrot orange
    Color(0xFFC0392B), // brick red
    Color(0xFFF39C12), // amber
    Color(0xFFB9770E), // dark gold
    Color(0xFF8E4B10), // brown
  ];

  @override
  void initState() {
    super.initState();

    for (int i = 0; i < 32; i++) {
      _leaves.add(_makeLeaf(startAnywhere: true));
    }

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _controller.addListener(() {
      setState(() {
        for (final leaf in _leaves) {
          leaf.update();
        }
      });
    });
  }

  _Leaf _makeLeaf({bool startAnywhere = false}) {
    return _Leaf(
      x: _random.nextDouble(),
      y: startAnywhere ? _random.nextDouble() : -0.05,
      size: _random.nextDouble() * 10 + 10, // 10-20 px
      speed: _random.nextDouble() * 0.12 + 0.06,
      swayAmp: _random.nextDouble() * 0.04 + 0.02,
      swayFreq: _random.nextDouble() * 2 + 1,
      phase: _random.nextDouble() * pi * 2,
      rotation: _random.nextDouble() * pi * 2,
      rotationSpeed: (_random.nextDouble() - 0.5) * 0.05,
      color: _colors[_random.nextInt(_colors.length)],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LeafPainter(_leaves),
      child: Container(),
    );
  }
}

class _Leaf {
  double x;
  double y;
  final double size;
  final double speed;
  final double swayAmp;
  final double swayFreq;
  double phase;
  double rotation;
  final double rotationSpeed;
  final Color color;

  _Leaf({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.swayAmp,
    required this.swayFreq,
    required this.phase,
    required this.rotation,
    required this.rotationSpeed,
    required this.color,
  });

  void update() {
    y += speed * 0.01;
    phase += 0.03;
    rotation += rotationSpeed;
    if (y > 1.05) {
      y = -0.05;
      phase = Random().nextDouble() * pi * 2;
    }
  }

  double get drawX => (x + sin(phase * swayFreq) * swayAmp).clamp(-0.05, 1.05);
}

class _LeafPainter extends CustomPainter {
  final List<_Leaf> leaves;

  _LeafPainter(this.leaves);

  @override
  void paint(Canvas canvas, Size size) {
    for (final leaf in leaves) {
      final cx = leaf.drawX * size.width;
      final cy = leaf.y * size.height;
      final paint = Paint()
        ..color = leaf.color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(leaf.rotation);
      _drawLeaf(canvas, paint, leaf.size);
      canvas.restore();
    }
  }

  // A simple maple-ish leaf: two mirrored teardrop lobes + a stem vein.
  void _drawLeaf(Canvas canvas, Paint paint, double s) {
    final path = Path();
    path.moveTo(0, -s * 0.5);
    path.cubicTo(s * 0.5, -s * 0.4, s * 0.5, s * 0.3, 0, s * 0.5);
    path.cubicTo(-s * 0.5, s * 0.3, -s * 0.5, -s * 0.4, 0, -s * 0.5);
    path.close();
    canvas.drawPath(path, paint);

    // central vein
    final vein = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, -s * 0.45), Offset(0, s * 0.45), vein);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
