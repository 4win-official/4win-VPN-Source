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
      duration: const Duration(seconds: 2), // کاهش سرعت برای لوپ نرم‌تر
    )..repeat();

    // ایجاد قطرات باران (100 قطره) - توزیع کامل در صفحه
    for (int i = 0; i < 100; i++) {
      _rainDrops.add(RainDrop(
        x: _random.nextDouble(),
        y: _random.nextDouble(), // شروع از موقعیت‌های تصادفی
        speed: 0.3 + _random.nextDouble() * 0.4, // سرعت متنوع
        length: 15 + _random.nextDouble() * 25,
        thickness: 0.8 + _random.nextDouble() * 0.5,
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
      
      // محاسبه موقعیت فعلی قطره - لوپ بی‌نهایت
      var currentY = drop.y + (animation * drop.speed);
      
      // وقتی از پایین خارج شد، از بالا برگرد (لوپ نرم)
      if (currentY > 1.0) {
        currentY = currentY % 1.0; // reset به بالای صفحه
      }
      
      // تبدیل به pixel
      final startY = currentY * size.height;
      final endY = startY + drop.length;
      final x = drop.x * size.width;

      // رسم قطره
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
