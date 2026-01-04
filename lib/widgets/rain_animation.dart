import 'dart:math';
import 'package:flutter/material.dart';

class RainAnimation extends StatefulWidget {
  const RainAnimation({super.key});

  @override
  State<RainAnimation> createState() => _RainAnimationState();
}

class _RainAnimationState extends State<RainAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<RainDrop> _rainDrops = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    // ایجاد قطرات باران (50 قطره)
    for (int i = 0; i < 50; i++) {
      _rainDrops.add(RainDrop(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        speed: 0.5 + _random.nextDouble() * 0.5,
        length: 20 + _random.nextDouble() * 30,
        thickness: 1 + _random.nextDouble(),
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: RainPainter(
            rainDrops: _rainDrops,
            animation: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class RainDrop {
  double x;
  double y;
  final double speed;
  final double length;
  final double thickness;

  RainDrop({
    required this.x,
    required this.y,
    required this.speed,
    required this.length,
    required this.thickness,
  });
}

class RainPainter extends CustomPainter {
  final List<RainDrop> rainDrops;
  final double animation;

  RainPainter({required this.rainDrops, required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3)
      ..strokeCap = StrokeCap.round;

    for (var drop in rainDrops) {
      paint.strokeWidth = drop.thickness;
      
      // محاسبه موقعیت فعلی قطره
      final currentY = (drop.y + animation * drop.speed) % 1.0;
      
      // موقعیت شروع و پایان قطره
      final startY = currentY * size.height;
      final endY = startY + drop.length;
      final x = drop.x * size.width;

      canvas.drawLine(
        Offset(x, startY),
        Offset(x, endY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(RainPainter oldDelegate) => true;
}
