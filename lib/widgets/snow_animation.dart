import 'dart:math';
import 'package:flutter/material.dart';

class SnowAnimation extends StatefulWidget {
  const SnowAnimation({super.key});

  @override
  State<SnowAnimation> createState() => _SnowAnimationState();
}

class _SnowAnimationState extends State<SnowAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Snowflake> _snowflakes = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    
    // ایجاد دانه‌های برف با اندازه‌های متنوع
    for (int i = 0; i < 60; i++) {
      _snowflakes.add(Snowflake(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 4 + 3, // 3-7 پیکسل - بزرگتر
        speed: _random.nextDouble() * 0.15 + 0.08, // سرعت متوسط - نه خیلی آهسته
        rotation: _random.nextDouble() * 3.14 * 2,
        rotationSpeed: _random.nextDouble() * 0.03 - 0.015,
      ));
    }
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15), // سرعت متوسط
    )..repeat();
    
    _controller.addListener(() {
      setState(() {
        for (var snowflake in _snowflakes) {
          snowflake.fall();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SnowPainter(_snowflakes),
      child: Container(),
    );
  }
}

class Snowflake {
  double x;
  double y;
  final double size;
  final double speed;
  double rotation;
  final double rotationSpeed;

  Snowflake({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
  });

  void fall() {
    y += speed * 0.01;
    rotation += rotationSpeed;
    
    // کمی حرکت افقی برای طبیعی‌تر بودن
    x += (Random().nextDouble() - 0.5) * 0.0005;
    
    // محدود کردن x به داخل صفحه
    if (x < 0) x = 0;
    if (x > 1.0) x = 1.0;
    
    // وقتی به پایین رسید، دوباره از بالا شروع کن
    if (y > 1.0) {
      y = 0.0;
      x = Random().nextDouble();
      rotation = Random().nextDouble() * 3.14 * 2;
    }
  }
}

class SnowPainter extends CustomPainter {
  final List<Snowflake> snowflakes;

  SnowPainter(this.snowflakes);

  @override
  void paint(Canvas canvas, Size size) {
    for (var snowflake in snowflakes) {
      final x = snowflake.x * size.width;
      final y = snowflake.y * size.height;
      
      // More blue-ish for icy effect
      final alpha = 0.7 + (snowflake.size / 10) * 0.3; // 0.7 - 1.0
      final paint = Paint()
        ..color = const Color(0xFFB3E5FC).withValues(alpha: alpha) // Light blue - icy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(snowflake.rotation);
      
      // رسم دانه برف واقعی‌تر (شش گوش)
      _drawSnowflake(canvas, paint, snowflake.size);
      
      canvas.restore();
    }
  }

  void _drawSnowflake(Canvas canvas, Paint paint, double size) {
    // دایره مرکزی کوچک
    canvas.drawCircle(
      Offset.zero,
      size * 0.15,
      paint..style = PaintingStyle.fill,
    );
    
    paint.style = PaintingStyle.stroke;
    
    // خطوط اصلی شش گانه
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60) * 3.14159 / 180;
      final endX = size * cos(angle);
      final endY = size * sin(angle);
      
      // خط اصلی
      canvas.drawLine(
        Offset.zero,
        Offset(endX, endY),
        paint,
      );
      
      // شاخه‌های کوچک - 3 سطح
      for (double t = 0.4; t < 0.9; t += 0.25) {
        final branchSize = size * (0.25 - t * 0.1);
        final branchAngle1 = angle - 0.6;
        final branchAngle2 = angle + 0.6;
        
        final branchStartX = endX * t;
        final branchStartY = endY * t;
        
        canvas.drawLine(
          Offset(branchStartX, branchStartY),
          Offset(
            branchStartX + branchSize * cos(branchAngle1),
            branchStartY + branchSize * sin(branchAngle1),
          ),
          paint,
        );
        
        canvas.drawLine(
          Offset(branchStartX, branchStartY),
          Offset(
            branchStartX + branchSize * cos(branchAngle2),
            branchStartY + branchSize * sin(branchAngle2),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

double cos(double angle) => angle == 0 ? 1.0 : (angle == 90 ? 0.0 : _cos(angle));
double sin(double angle) => angle == 0 ? 0.0 : (angle == 90 ? 1.0 : _sin(angle));

double _cos(double x) {
  x = x % (2 * 3.14159);
  double result = 1.0;
  double term = 1.0;
  for (int i = 1; i < 10; i++) {
    term *= -x * x / ((2 * i - 1) * (2 * i));
    result += term;
  }
  return result;
}

double _sin(double x) {
  x = x % (2 * 3.14159);
  double result = x;
  double term = x;
  for (int i = 1; i < 10; i++) {
    term *= -x * x / ((2 * i) * (2 * i + 1));
    result += term;
  }
  return result;
}
