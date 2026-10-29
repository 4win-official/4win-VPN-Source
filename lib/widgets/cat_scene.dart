import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// A small, sleepy cat mascot that decorates the top of the Cat-theme screen.
class CatScene extends StatefulWidget {
  const CatScene({super.key, required this.isDark, this.onCatTap});

  final bool isDark;
  final VoidCallback? onCatTap;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final painter = CatScenePainter(
          isDark: widget.isDark,
          animation: _animation,
          topInset: MediaQuery.paddingOf(context).top,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: painter, size: Size.infinite),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: painter.mascotBounds(size).inflate(4),
              child: Semantics(
                button: true,
                label: context.l10n.text('Cat mascot'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onCatTap,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        );
      },
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
      center.dy - radius * 1.42 - 1.8,
      center.dx + radius + 0.8,
      center.dy + radius * 1.10 + 1.8,
    );
  }

  double _radius(Size size) => size.height < 720
      ? math.min(24, size.width * 0.075)
      : math.min(39, math.max(29, size.width * 0.078));

  double _bandTop(Size size) => topInset + (size.height < 720 ? 24 : 14);

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

    final furColor = isDark ? const Color(0xFFB9C9AE) : const Color(0xFFE3A37D);
    final lightFur = isDark ? const Color(0xFFE9D9BA) : const Color(0xFFFFE7C9);
    final outlineColor = isDark
        ? const Color(0xFF314A49)
        : const Color(0xFF7D403C);
    final stripeColor = isDark
        ? const Color(0xFF6C8272)
        : const Color(0xFFB96550);

    // A compact curled tail gives the mascot a recognizable silhouette without
    // expanding into the controls below it.
    final tail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * 0.18
      ..color = furColor;
    final tailPath = Path()
      ..moveTo(center.dx - radius * 0.48, center.dy + radius * 0.62)
      ..cubicTo(
        center.dx - radius * 1.16,
        center.dy + radius * 1.0,
        center.dx - radius * 1.42,
        center.dy + radius * (0.34 + tailWave),
        center.dx - radius * 1.0,
        center.dy + radius * 0.12,
      )
      ..cubicTo(
        center.dx - radius * 0.76,
        center.dy - radius * 0.02,
        center.dx - radius * 0.52,
        center.dy + radius * 0.13,
        center.dx - radius * 0.65,
        center.dy + radius * 0.34,
      );
    canvas.drawPath(tailPath, tail);

    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, radius * 0.35),
        width: radius * 1.56,
        height: radius * 1.42,
      ),
      Radius.circular(radius * 0.62),
    );
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          lightFur,
          furColor,
          isDark ? const Color(0xFF819982) : const Color(0xFFC8755D),
        ],
      ).createShader(body.outerRect);
    canvas.drawRRect(body, bodyPaint);

    final head = Rect.fromCenter(
      center: center.translate(0, -radius * 0.22),
      width: radius * 1.78,
      height: radius * 1.48,
    );
    final headPaint = Paint()..color = furColor;
    canvas.drawOval(head, headPaint);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.05, radius * 0.055)
      ..color = outlineColor.withValues(alpha: 0.62);
    canvas.drawRRect(body, outline);
    canvas.drawOval(head, outline);

    _drawEar(
      canvas,
      center.translate(-radius * 0.56, -radius * 0.82),
      radius,
      -1,
      headPaint,
      Paint()
        ..color = (isDark ? const Color(0xFFD38E86) : const Color(0xFFC96562))
            .withValues(alpha: 0.8),
    );
    _drawEar(
      canvas,
      center.translate(radius * 0.56, -radius * 0.82),
      radius,
      1,
      headPaint,
      Paint()
        ..color = (isDark ? const Color(0xFFD38E86) : const Color(0xFFC96562))
            .withValues(alpha: 0.8),
    );

    // Forehead tabby marks and a soft cheek highlight make the head read at
    // the small 320px layout size as a cat rather than a generic blob.
    final stripe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, radius * 0.08)
      ..color = stripeColor.withValues(alpha: 0.7);
    for (final dx in [-0.27, 0.0, 0.27]) {
      canvas.drawLine(
        center.translate(radius * dx, -radius * 0.83),
        center.translate(radius * dx * 0.72, -radius * 0.58),
        stripe,
      );
    }
    canvas.drawLine(
      center.translate(-radius * 0.74, radius * 0.02),
      center.translate(-radius * 0.48, radius * 0.09),
      stripe,
    );
    canvas.drawLine(
      center.translate(radius * 0.74, radius * 0.02),
      center.translate(radius * 0.48, radius * 0.09),
      stripe,
    );

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.18 : 0.38);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-radius * 0.36, -radius * 0.47),
        width: radius * 0.2,
        height: radius * 0.35,
      ),
      highlight,
    );
    _paintFace(
      canvas,
      center.translate(0, -radius * 0.18),
      radius,
      outlineColor,
    );
    _paintPaws(canvas, center, radius, lightFur, outlineColor);
  }

  void _drawEar(
    Canvas canvas,
    Offset center,
    double radius,
    int side,
    Paint outer,
    Paint inner,
  ) {
    final ear = Path()
      ..moveTo(center.dx - side * radius * .38, center.dy + radius * .28)
      ..lineTo(center.dx + side * radius * .18, center.dy - radius * .48)
      ..quadraticBezierTo(
        center.dx + side * radius * .29,
        center.dy - radius * .52,
        center.dx + side * radius * .34,
        center.dy + radius * .30,
      )
      ..close();
    canvas.drawPath(ear, outer);
    canvas.drawPath(
      ear,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, radius * .035)
        ..color = (isDark ? const Color(0xFF314A49) : const Color(0xFF7D403C))
            .withValues(alpha: .55),
    );
    final inset = Path()
      ..moveTo(center.dx - side * radius * .13, center.dy + radius * .17)
      ..lineTo(center.dx + side * radius * .15, center.dy - radius * .27)
      ..lineTo(center.dx + side * radius * .21, center.dy + radius * .20)
      ..close();
    canvas.drawPath(inset, inner);
  }

  void _paintFace(
    Canvas canvas,
    Offset face,
    double radius,
    Color outlineColor,
  ) {
    final eyeWhite = Paint()
      ..color = isDark ? const Color(0xFFE7E7D0) : const Color(0xFFFFF8E7);
    final pupil = Paint()
      ..color = isDark ? const Color(0xFF223B3A) : const Color(0xFF3E3034);
    final eyeHighlight = Paint()..color = Colors.white.withValues(alpha: 0.9);

    for (final side in const [-1, 1]) {
      final eyeCenter = face.translate(side * radius * 0.36, -radius * 0.06);
      canvas.drawOval(
        Rect.fromCenter(
          center: eyeCenter,
          width: radius * 0.34,
          height: radius * 0.39,
        ),
        eyeWhite,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: eyeCenter,
          width: radius * 0.14,
          height: radius * 0.28,
        ),
        pupil,
      );
      canvas.drawCircle(
        eyeCenter.translate(-side * radius * 0.045, -radius * 0.08),
        radius * 0.035,
        eyeHighlight,
      );
    }

    final muzzle = Paint()
      ..color = (isDark ? const Color(0xFFEAD9C0) : const Color(0xFFFFEED8))
          .withValues(alpha: 0.9);
    canvas.drawOval(
      Rect.fromCenter(
        center: face.translate(-radius * 0.16, radius * 0.19),
        width: radius * 0.46,
        height: radius * 0.29,
      ),
      muzzle,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: face.translate(radius * 0.16, radius * 0.19),
        width: radius * 0.46,
        height: radius * 0.29,
      ),
      muzzle,
    );

    final nose = Paint()
      ..color = isDark ? const Color(0xFFC47778) : const Color(0xFFA94E4D);
    final nosePath = Path()
      ..moveTo(face.dx, face.dy + radius * 0.12)
      ..quadraticBezierTo(
        face.dx - radius * 0.11,
        face.dy + radius * 0.02,
        face.dx - radius * 0.11,
        face.dy + radius * 0.13,
      )
      ..quadraticBezierTo(
        face.dx,
        face.dy + radius * 0.25,
        face.dx + radius * 0.11,
        face.dy + radius * 0.13,
      )
      ..quadraticBezierTo(
        face.dx + radius * 0.11,
        face.dy + radius * 0.02,
        face.dx,
        face.dy + radius * 0.12,
      )
      ..close();
    canvas.drawPath(nosePath, nose);
    final mouth = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.1, radius * 0.045);
    final mouthPath = Path()
      ..moveTo(face.dx, face.dy + radius * 0.21)
      ..quadraticBezierTo(
        face.dx - radius * 0.13,
        face.dy + radius * 0.36,
        face.dx - radius * 0.25,
        face.dy + radius * 0.27,
      )
      ..moveTo(face.dx, face.dy + radius * 0.21)
      ..quadraticBezierTo(
        face.dx + radius * 0.13,
        face.dy + radius * 0.36,
        face.dx + radius * 0.25,
        face.dy + radius * 0.27,
      );
    canvas.drawPath(mouthPath, mouth);

    final whisker = Paint()
      ..color = outlineColor.withValues(alpha: 0.72)
      ..strokeWidth = math.max(0.8, radius * 0.035)
      ..strokeCap = StrokeCap.round;
    for (final side in const [-1, 1]) {
      for (var i = 0; i < 2; i++) {
        canvas.drawLine(
          face.translate(side * radius * 0.22, radius * (0.2 + i * 0.1)),
          face.translate(
            side * radius * (0.93 + i * 0.05),
            radius * (0.14 + i * 0.16),
          ),
          whisker,
        );
      }
    }
    final blush = Paint()
      ..color = const Color(0xFFD97B77).withValues(alpha: isDark ? 0.22 : 0.38);
    canvas.drawOval(
      Rect.fromCenter(
        center: face.translate(-radius * 0.5, radius * 0.24),
        width: radius * 0.24,
        height: radius * 0.11,
      ),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: face.translate(radius * 0.5, radius * 0.24),
        width: radius * 0.24,
        height: radius * 0.11,
      ),
      blush,
    );
  }

  void _paintPaws(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    Color outlineColor,
  ) {
    final paint = Paint()..color = color.withValues(alpha: 0.94);
    final pawOutline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, radius * 0.04)
      ..color = outlineColor.withValues(alpha: 0.38);
    for (final side in const [-1, 1]) {
      final paw = Rect.fromCenter(
        center: center.translate(side * radius * 0.31, radius * 0.78),
        width: radius * 0.43,
        height: radius * 0.3,
      );
      canvas.drawOval(paw, paint);
      canvas.drawOval(paw, pawOutline);
      for (var i = -1; i <= 1; i++) {
        canvas.drawCircle(
          Offset(paw.center.dx + i * radius * 0.105, paw.top + radius * 0.08),
          radius * 0.025,
          pawOutline,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CatScenePainter oldDelegate) =>
      oldDelegate.isDark != isDark ||
      oldDelegate.animation != animation ||
      oldDelegate.topInset != topInset;
}
