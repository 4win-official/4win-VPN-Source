import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small, sleepy cat mascot that decorates the top of a screen without
/// intercepting interaction or adding semantics.
class CatScene extends StatefulWidget {
  const CatScene({super.key, required this.isDark});

  final bool isDark;

  @override
  State<CatScene> createState() => _CatSceneState();
}

class _CatSceneState extends State<CatScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  bool _animationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final enabled =
        !(media?.disableAnimations ?? false) &&
        TickerMode.valuesOf(context).enabled;
    if (enabled == _animationsEnabled) return;
    _animationsEnabled = enabled;
    if (enabled) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0.2;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_animationsEnabled && !_controller.isAnimating) {
      _controller.repeat();
    }

    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: CatScenePainter(
              isDark: widget.isDark,
              animation: _animation,
              topInset: MediaQuery.paddingOf(context).top,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// Paints the vector artwork used by [CatScene].
class CatScenePainter extends CustomPainter {
  CatScenePainter({
    required this.isDark,
    required this.animation,
    required this.topInset,
  }) : super(repaint: animation);

  final bool isDark;
  final Animation<double> animation;
  final double topInset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final top = _bandTop(size);
    final height = _bandHeight(size);
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xD916233D), Color(0x251E3A40), Color(0x001E3A40)]
            : const [Color(0xBFFFF8EA), Color(0x24F2C8AF), Color(0x00F2C8AF)],
        stops: const [0, 0.62, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    _paintEdgePaws(canvas, size, top, height);
    _paintMascot(canvas, size, top, height);
  }

  /// Conservative bounds including ears, tail, stroke and breathing motion.
  Rect mascotBounds(Size size) {
    final radius = _radius(size);
    final center = Offset(
      size.width - radius - 7,
      _bandTop(size) + _bandHeight(size) * 0.52,
    );
    return Rect.fromLTRB(
      center.dx - radius * 1.52,
      center.dy - radius * 1.1 - 1.8,
      center.dx + radius + 0.8,
      center.dy + radius * 1.05 + 1.8,
    );
  }

  double _radius(Size size) => size.height < 720
      ? math.min(26, size.width * 0.082)
      : math.min(39, math.max(29, size.width * 0.078));

  double _bandTop(Size size) =>
      topInset + kToolbarHeight + (size.height < 720 ? 4 : 14);

  double _bandHeight(Size size) =>
      size.height < 720 ? 36 : math.min(124, math.max(96, size.height * 0.15));

  void _paintEdgePaws(Canvas canvas, Size size, double top, double height) {
    final color = (isDark ? const Color(0xFFB8C9B4) : const Color(0xFFC98167))
        .withValues(alpha: 0.09);
    final paint = Paint()..color = color;
    _drawPaw(canvas, paint, Offset(12, top + height * 0.58), 13, -0.18);
    _drawPaw(
      canvas,
      paint,
      Offset(size.width - 11, top + height * 0.23),
      11,
      0.24,
    );
  }

  void _drawPaw(
    Canvas canvas,
    Paint paint,
    Offset center,
    double scale,
    double rotation,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0, 4),
        width: scale * 1.35,
        height: scale,
      ),
      paint,
    );
    for (var i = -1; i <= 1; i++) {
      canvas.drawCircle(
        Offset(i * scale * 0.4, -scale * 0.48),
        scale * 0.22,
        paint,
      );
    }
    canvas.restore();
  }

  void _paintMascot(Canvas canvas, Size size, double top, double height) {
    final phase = animation.value * math.pi * 2;
    final breathing = math.sin(phase) * 1.15;
    final tailWave = math.sin(phase + 0.9) * 0.035;
    final radius = _radius(size);
    final center = Offset(
      size.width - radius - 7,
      top + height * 0.52 + breathing,
    );

    final tail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * 0.18
      ..color = (isDark ? const Color(0xFFB7C6A6) : const Color(0xFFC96F57))
          .withValues(alpha: 0.96);
    final tailPath = Path()
      ..moveTo(center.dx - radius * 0.65, center.dy + radius * 0.58)
      ..cubicTo(
        center.dx - radius * 1.2,
        center.dy + radius * 0.95,
        center.dx - radius * 1.42,
        center.dy + radius * (0.36 + tailWave),
        center.dx - radius * 1.04,
        center.dy + radius * 0.13,
      )
      ..cubicTo(
        center.dx - radius * 0.76,
        center.dy - radius * 0.06,
        center.dx - radius * 0.56,
        center.dy + radius * 0.12,
        center.dx - radius * 0.7,
        center.dy + radius * 0.3,
      );
    canvas.drawPath(tailPath, tail);

    final body = Rect.fromCenter(
      center: center.translate(0, radius * 0.1),
      width: radius * 1.92,
      height: radius * 1.7,
    );
    final fur = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.6),
        radius: 1.1,
        colors: isDark
            ? const [Color(0xFFE1D3B7), Color(0xFFB7C6A5), Color(0xFF728B7A)]
            : const [Color(0xFFFFE9D1), Color(0xFFE7A982), Color(0xFFC96F57)],
      ).createShader(body);
    canvas.drawOval(body, fur);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..color = (isDark ? const Color(0xFFE2E8D5) : const Color(0xFF9D4F43))
          .withValues(alpha: 0.56);
    canvas.drawOval(body, outline);

    final earPaint = Paint()
      ..color = isDark ? const Color(0xFFB7C6A6) : const Color(0xFFE7A982);
    final innerEar = Paint()
      ..color = (isDark ? const Color(0xFFD58E83) : const Color(0xFFC96562))
          .withValues(alpha: 0.72);
    _drawEar(
      canvas,
      center.translate(-radius * 0.58, -radius * 0.55),
      radius,
      -1,
      earPaint,
      innerEar,
    );
    _drawEar(
      canvas,
      center.translate(radius * 0.58, -radius * 0.55),
      radius,
      1,
      earPaint,
      innerEar,
    );

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.2 : 0.42);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-radius * 0.34, -radius * 0.35),
        width: radius * 0.23,
        height: radius * 0.45,
      ),
      highlight,
    );
    _paintFace(canvas, center.translate(0, radius * 0.03), radius);
    _paintPaws(canvas, center, radius);
  }

  void _drawEar(
    Canvas canvas,
    Offset center,
    double radius,
    int side,
    Paint outer,
    Paint inner,
  ) {
    final path = Path()
      ..moveTo(center.dx - side * radius * 0.45, center.dy + radius * 0.3)
      ..lineTo(center.dx + side * radius * 0.02, center.dy - radius * 0.55)
      ..quadraticBezierTo(
        center.dx + side * radius * 0.58,
        center.dy - radius * 0.1,
        center.dx + side * radius * 0.45,
        center.dy + radius * 0.43,
      )
      ..close();
    canvas.drawPath(path, outer);
    final innerPath = Path()
      ..moveTo(center.dx - side * radius * 0.2, center.dy + radius * 0.2)
      ..lineTo(center.dx + side * radius * 0.03, center.dy - radius * 0.25)
      ..lineTo(center.dx + side * radius * 0.27, center.dy + radius * 0.27)
      ..close();
    canvas.drawPath(innerPath, inner);
  }

  void _paintFace(Canvas canvas, Offset face, double radius) {
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.7, radius * 0.06)
      ..color = isDark ? const Color(0xFF304A49) : const Color(0xFF633E43);
    for (final side in const [-1, 1]) {
      final eye = Path()
        ..moveTo(face.dx + side * radius * 0.54, face.dy - radius * 0.08)
        ..quadraticBezierTo(
          face.dx + side * radius * 0.34,
          face.dy + radius * 0.13,
          face.dx + side * radius * 0.12,
          face.dy - radius * 0.04,
        );
      canvas.drawPath(eye, ink);
    }
    final nose = Paint()
      ..color = isDark ? const Color(0xFFB56E68) : const Color(0xFFA94E4D);
    final nosePath = Path()
      ..moveTo(face.dx, face.dy + radius * 0.14)
      ..quadraticBezierTo(
        face.dx - radius * 0.1,
        face.dy + radius * 0.02,
        face.dx - radius * 0.1,
        face.dy + radius * 0.13,
      )
      ..quadraticBezierTo(
        face.dx,
        face.dy + radius * 0.25,
        face.dx + radius * 0.1,
        face.dy + radius * 0.13,
      )
      ..quadraticBezierTo(
        face.dx + radius * 0.1,
        face.dy + radius * 0.02,
        face.dx,
        face.dy + radius * 0.14,
      )
      ..close();
    canvas.drawPath(nosePath, nose);
    final mouth = Path()
      ..moveTo(face.dx, face.dy + radius * 0.2)
      ..quadraticBezierTo(
        face.dx - radius * 0.12,
        face.dy + radius * 0.36,
        face.dx - radius * 0.23,
        face.dy + radius * 0.29,
      )
      ..moveTo(face.dx, face.dy + radius * 0.2)
      ..quadraticBezierTo(
        face.dx + radius * 0.12,
        face.dy + radius * 0.36,
        face.dx + radius * 0.23,
        face.dy + radius * 0.29,
      );
    canvas.drawPath(mouth, ink);
    final blush = Paint()
      ..color = const Color(0xFFD97B77).withValues(alpha: isDark ? 0.25 : 0.4);
    canvas.drawOval(
      Rect.fromCenter(
        center: face.translate(-radius * 0.48, radius * 0.2),
        width: radius * 0.28,
        height: radius * 0.12,
      ),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: face.translate(radius * 0.48, radius * 0.2),
        width: radius * 0.28,
        height: radius * 0.12,
      ),
      blush,
    );
  }

  void _paintPaws(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = (isDark ? const Color(0xFFD8DEBF) : const Color(0xFFFFE7D0))
          .withValues(alpha: 0.8);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-radius * 0.38, radius * 0.76),
        width: radius * 0.42,
        height: radius * 0.25,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(radius * 0.38, radius * 0.76),
        width: radius * 0.42,
        height: radius * 0.25,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CatScenePainter oldDelegate) =>
      oldDelegate.isDark != isDark ||
      oldDelegate.animation != animation ||
      oldDelegate.topInset != topInset;
}
