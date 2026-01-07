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

    // ایجاد قطرات باران (50 قطره) - توزیع در تمام ارتفاع صفحه
    for (int i = 0; i < 50; i++) {
      _rainDrops.add(RainDrop(
        x: _random.nextDouble(),
        y: _random.nextDouble() * 2.0, // توزیع در 2 برابر ارتفاع برای لوپ نرم
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
      
      // محاسبه موقعیت فعلی قطره با لوپ نرم (از -1 تا 2 برای لوپ بدون جهش)
      var currentY = (drop.y + animation * drop.speed);
      
      // لوپ نرم: وقتی از پایین خارج میشه، از بالا برمی‌گرده
      while (currentY > 2.0) {
        currentY -= 2.0;
      }
      
      // تبدیل به pixel
      final startY = (currentY * size.height) - size.height; // شروع از بالای صفحه
      final endY = startY + drop.length;
      final x = drop.x * size.width;

      // فقط قطراتی که در صفحه هستند رسم شوند
      if (endY > 0 && startY < size.height) {
        canvas.drawLine(
          Offset(x, startY),
          Offset(x, endY),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(RainPainter oldDelegate) => true;
}
