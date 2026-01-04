import 'dart:math';
import 'package:flutter/material.dart';

class PixelEffect extends StatefulWidget {
  const PixelEffect({super.key});

  @override
  State<PixelEffect> createState() => _PixelEffectState();
}

class _PixelEffectState extends State<PixelEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<PixelParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    
    // ایجاد پیکسل‌های متحرک
    for (int i = 0; i < 40; i++) {
      _particles.add(PixelParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextInt(3) + 2, // 2-4 پیکسل
        speed: _random.nextDouble() * 0.1 + 0.05,
        color: _getRandomPixelColor(),
      ));
    }
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    
    _controller.addListener(() {
      setState(() {
        for (var particle in _particles) {
          particle.move();
        }
      });
    });
  }

  Color _getRandomPixelColor() {
    // رنگ‌های نئون روشن برای هر دو حالت دارک و لایت
    final colors = [
      const Color(0xFF00FF88), // نئون سبز
      const Color(0xFFFF4466), // نئون قرمز
      const Color(0xFF4488FF), // نئون آبی
      const Color(0xFFFF9944), // نئون نارنجی
      const Color(0xFFAA44FF), // نئون بنفش
      const Color(0xFFFFDD44), // نئون زرد
      const Color(0xFF44FFFF), // نئون فیروزه‌ای
      const Color(0xFFFF44FF), // نئون صورتی
    ];
    return colors[_random.nextInt(colors.length)];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PixelPainter(_particles),
      child: Container(),
    );
  }
}

class PixelParticle {
  double x;
  double y;
  final int size;
  final double speed;
  final Color color;
  double direction;

  PixelParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.color,
  }) : direction = Random().nextDouble() * 3.14 * 2;

  void move() {
    // حرکت در جهت تصادفی
    x += speed * 0.01 * cos(direction);
    y += speed * 0.01 * sin(direction);
    
    // تغییر جهت گاهی اوقات
    if (Random().nextDouble() < 0.02) {
      direction = Random().nextDouble() * 3.14 * 2;
    }
    
    // محدود کردن به داخل صفحه
    if (x < 0) x = 1.0;
    if (x > 1.0) x = 0.0;
    if (y < 0) y = 1.0;
    if (y > 1.0) y = 0.0;
  }
}

class PixelPainter extends CustomPainter {
  final List<PixelParticle> particles;

  PixelPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      final x = (particle.x * size.width).floorToDouble();
      final y = (particle.y * size.height).floorToDouble();
      
      final paint = Paint()
        ..color = particle.color.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      
      // رسم پیکسل مربعی
      canvas.drawRect(
        Rect.fromLTWH(x, y, particle.size.toDouble(), particle.size.toDouble()),
        paint,
      );
      
      // گلو پیکسلی
      final glowPaint = Paint()
        ..color = particle.color.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      
      canvas.drawRect(
        Rect.fromLTWH(
          x - particle.size / 2,
          y - particle.size / 2,
          particle.size * 2.0,
          particle.size * 2.0,
        ),
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

double cos(double angle) => angle == 0 ? 1.0 : _cos(angle);
double sin(double angle) => angle == 0 ? 0.0 : _sin(angle);

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
