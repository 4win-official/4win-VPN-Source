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
      duration: const Duration(milliseconds: 800), // سرعت بهتر
    )..repeat();

    // ایجاد قطرات باران (80 قطره) - توزیع کامل
    for (int i = 0; i < 80; i++) {
      _rainDrops.add(RainDrop(
        x: _random.nextDouble(),
        y: _random.nextDouble(), // توزیع در تمام ارتفاع
        speed: 0.8 + _random.nextDouble() * 0.6, // سرعت مناسب
        length: 20 + _random.nextDouble() * 35,
        thickness: 1 + _random.nextDouble() * 0.8,
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
      ..color = Colors.blue.withValues(alpha: 0.35)
      ..strokeCap = StrokeCap.round;

    for (var drop in rainDrops) {
      paint.strokeWidth = drop.thickness;
      
      // محاسبه موقعیت - لوپ بی‌نهایت بدون غیب شدن
      var progress = (drop.y + (animation * drop.speed)) % 1.0;
      
      // اگر در مرز بالا یا پایین است، از طرف دیگر ظاهر شود
      final startY = progress * size.height;
      final endY = startY + drop.length;
      final x = drop.x * size.width;

      // رسم قطره - همیشه در صفحه
      if (endY > size.height) {
        // قطره از پایین خارج میشه - بخشی از بالا ظاهر شود
        canvas.drawLine(
          Offset(x, startY),
          Offset(x, size.height),
          paint,
        );
        // قسمت باقی‌مانده از بالا
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, endY - size.height),
          paint,
        );
      } else {
        // قطره کاملاً در صفحه است
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
