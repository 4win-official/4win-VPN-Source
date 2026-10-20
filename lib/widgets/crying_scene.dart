import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A quiet pastel crying mascot that decorates the top of a screen without
/// intercepting interaction or adding semantics.
class CryingScene extends StatefulWidget {
  const CryingScene({super.key, required this.isDark});

  final bool isDark;

  @override
  State<CryingScene> createState() => _CryingSceneState();
}

class _CryingSceneState extends State<CryingScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  bool _animationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
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
      _controller.value = 0.22;
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
            painter: CryingScenePainter(
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

/// Paints the vector artwork used by [CryingScene].
///
/// The [animation] is supplied as a repaint listenable so animation ticks
/// repaint the canvas directly instead of rebuilding the widget tree.
class CryingScenePainter extends CustomPainter {
  CryingScenePainter({
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
    final bandHeight = _bandHeight(size);
    final colors = isDark
        ? const [Color(0xFF11152F), Color(0xFF232451), Color(0xFF34356A)]
        : const [Color(0xFFFFF9F3), Color(0xFFF6EAF4), Color(0xFFE4F1F5)];

    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          colors[0].withValues(alpha: 0.82),
          colors[1].withValues(alpha: 0.22),
          colors[2].withValues(alpha: 0.04),
        ],
        stops: const [0, 0.58, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    _paintOrnamentalTears(canvas, size, top, bandHeight, isDark);
    _paintMascot(canvas, size, top, bandHeight, isDark);
  }

  /// Returns the approximate body bounds used by the mascot, useful to keep
  /// foreground controls out of the decorative lane.
  Rect mascotBounds(Size size) {
    final height = _bandHeight(size);
    final center = Offset(
      size.width - _radius(size) - 6,
      _bandTop(size) + height * 0.52,
    );
    final radius = _radius(size);
    return Rect.fromCircle(center: center, radius: radius);
  }

  double _radius(Size size) => math.min(36.0, size.width * 0.078);

  double _bandTop(Size size) =>
      topInset + kToolbarHeight + (size.height < 720 ? 4 : 14);

  double _bandHeight(Size size) => size.height < 720
      ? 72
      : math.min(122.0, math.max(92.0, size.height * 0.15));

  void _paintOrnamentalTears(
    Canvas canvas,
    Size size,
    double top,
    double height,
    bool dark,
  ) {
    final color = (dark ? const Color(0xFF9FA8FF) : const Color(0xFFB9DDE6))
        .withValues(alpha: 0.13);
    final paint = Paint()..color = color;
    final left = _tearPath(
      Offset(size.width * 0.075, top + height * 0.54),
      height * 0.22,
    );
    final right = _tearPath(
      Offset(size.width * 0.925, top + height * 0.34),
      height * 0.15,
    );
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
    canvas.drawCircle(
      Offset(size.width * 0.14, top + height * 0.83),
      2.4,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.84, top + height * 0.82),
      3.2,
      paint,
    );
  }

  void _paintMascot(
    Canvas canvas,
    Size size,
    double top,
    double height,
    bool dark,
  ) {
    final t = animation.value;
    final bob = math.sin(t * math.pi * 2) * 1.6;
    final center = Offset(
      size.width - _radius(size) - 6,
      top + height * 0.52 + bob,
    );
    final radius = _radius(size);
    final bodyRect = Rect.fromCircle(center: center, radius: radius);
    final bodyGradient = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.5),
        radius: 1.05,
        colors: dark
            ? const [Color(0xFFC6C9FF), Color(0xFF858BD6), Color(0xFF5E63AC)]
            : const [Color(0xFFFFFDF6), Color(0xFFEFD4EB), Color(0xFFC2DCEB)],
      ).createShader(bodyRect);
    canvas.drawOval(bodyRect, bodyGradient);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..color = (dark ? const Color(0xFFE0E1FF) : const Color(0xFFB995B7))
          .withValues(alpha: 0.52);
    canvas.drawOval(bodyRect, outline);

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: dark ? 0.31 : 0.55);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-radius * 0.27, -radius * 0.42),
        width: radius * 0.26,
        height: radius * 0.42,
      ),
      highlight,
    );

    final face = center.translate(0, radius * 0.04);
    _paintFace(canvas, face, radius, dark);
    _paintTears(canvas, face, radius, dark, t);
  }

  void _paintFace(Canvas canvas, Offset face, double radius, bool dark) {
    final brow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.5, radius * 0.055)
      ..color = dark ? const Color(0xFF45477F) : const Color(0xFF876C91);
    final leftBrow = Path()
      ..moveTo(face.dx - radius * 0.56, face.dy - radius * 0.29)
      ..quadraticBezierTo(
        face.dx - radius * 0.34,
        face.dy - radius * 0.44,
        face.dx - radius * 0.13,
        face.dy - radius * 0.29,
      );
    final rightBrow = Path()
      ..moveTo(face.dx + radius * 0.13, face.dy - radius * 0.29)
      ..quadraticBezierTo(
        face.dx + radius * 0.34,
        face.dy - radius * 0.44,
        face.dx + radius * 0.56,
        face.dy - radius * 0.29,
      );
    canvas.drawPath(leftBrow, brow);
    canvas.drawPath(rightBrow, brow);

    final blush = Paint()
      ..color = const Color(0xFFF29CAD).withValues(alpha: dark ? 0.32 : 0.48);
    canvas.drawOval(
      Rect.fromCenter(
        center: face.translate(-radius * 0.48, radius * 0.2),
        width: radius * 0.32,
        height: radius * 0.14,
      ),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: face.translate(radius * 0.48, radius * 0.2),
        width: radius * 0.32,
        height: radius * 0.14,
      ),
      blush,
    );

    final eye = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.7, radius * 0.06)
      ..strokeCap = StrokeCap.round
      ..color = dark ? const Color(0xFF343663) : const Color(0xFF604C74);
    final leftEye = Path()
      ..moveTo(face.dx - radius * 0.54, face.dy - radius * 0.05)
      ..quadraticBezierTo(
        face.dx - radius * 0.35,
        face.dy + radius * 0.15,
        face.dx - radius * 0.16,
        face.dy - radius * 0.03,
      );
    final rightEye = Path()
      ..moveTo(face.dx + radius * 0.16, face.dy - radius * 0.03)
      ..quadraticBezierTo(
        face.dx + radius * 0.35,
        face.dy + radius * 0.15,
        face.dx + radius * 0.54,
        face.dy - radius * 0.05,
      );
    canvas.drawPath(leftEye, eye);
    canvas.drawPath(rightEye, eye);

    final mouth = Path()
      ..moveTo(face.dx - radius * 0.17, face.dy + radius * 0.43)
      ..quadraticBezierTo(
        face.dx,
        face.dy + radius * 0.27,
        face.dx + radius * 0.17,
        face.dy + radius * 0.43,
      );
    canvas.drawPath(mouth, eye);
  }

  void _paintTears(
    Canvas canvas,
    Offset face,
    double radius,
    bool dark,
    double t,
  ) {
    final tearColor = (dark ? const Color(0xFFBBD8FF) : const Color(0xFF86C9E0))
        .withValues(alpha: 0.9);
    final shine = Paint()..color = Colors.white.withValues(alpha: 0.65);
    final paint = Paint()..color = tearColor;
    final phase = math.sin(t * math.pi * 2);
    for (var side = -1; side <= 1; side += 2) {
      final x = face.dx + side * radius * 0.5;
      final y = face.dy + radius * (0.08 + (phase + 1) * 0.045);
      final drop = _tearPath(Offset(x, y), radius * 0.26);
      canvas.drawPath(drop, paint);
      canvas.drawCircle(
        Offset(x - radius * 0.06, y + radius * 0.07),
        radius * 0.035,
        shine,
      );
    }
  }

  Path _tearPath(Offset tip, double size) {
    return Path()
      ..moveTo(tip.dx, tip.dy - size)
      ..cubicTo(
        tip.dx - size * 0.78,
        tip.dy - size * 0.12,
        tip.dx - size * 0.6,
        tip.dy + size * 0.54,
        tip.dx,
        tip.dy + size * 0.62,
      )
      ..cubicTo(
        tip.dx + size * 0.6,
        tip.dy + size * 0.54,
        tip.dx + size * 0.78,
        tip.dy - size * 0.12,
        tip.dx,
        tip.dy - size,
      )
      ..close();
  }

  @override
  bool shouldRepaint(covariant CryingScenePainter oldDelegate) =>
      oldDelegate.isDark != isDark ||
      oldDelegate.animation != animation ||
      oldDelegate.topInset != topInset;
}
