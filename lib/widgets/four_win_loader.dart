import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// The 4win shield with a travelling mint/cyan highlight instead of a stock ring.
/// Drawn as vectors so the same loader stays crisp in buttons and full pages.
class FourWinLoader extends StatefulWidget {
  const FourWinLoader({
    super.key,
    this.size = 36,
    this.strokeWidth = 2.4,
    this.color,
    this.semanticsLabel,
  }) : assert(size > 0),
       assert(strokeWidth > 0);

  final double size;
  final double strokeWidth;

  /// Optional foreground override for surfaces such as the connection button.
  final Color? color;
  final String? semanticsLabel;

  @override
  State<FourWinLoader> createState() => _FourWinLoaderState();
}

class _FourWinLoaderState extends State<FourWinLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.2;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final start =
        widget.color ??
        (isDark ? const Color(0xFF69E69B) : const Color(0xFF168653));
    final end =
        widget.color ??
        (isDark ? const Color(0xFF22CED0) : const Color(0xFF078799));

    return Semantics(
      label: context.l10n.text(widget.semanticsLabel ?? 'Loading'),
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _ShieldLoaderPainter(
              animation: _controller,
              start: start,
              end: end,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldLoaderPainter extends CustomPainter {
  _ShieldLoaderPainter({
    required this.animation,
    required this.start,
    required this.end,
    required this.strokeWidth,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color start;
  final Color end;
  final double strokeWidth;

  // Cached normalized geometry, shared by every loader (including tiny badges).
  static final Path _shield = Path()
    ..moveTo(50, 8)
    ..cubicTo(61, 17, 75, 21, 88, 22)
    ..lineTo(88, 49)
    ..cubicTo(88, 69, 73, 84, 50, 94)
    ..cubicTo(27, 84, 12, 69, 12, 49)
    ..lineTo(12, 22)
    ..cubicTo(25, 21, 39, 17, 50, 8)
    ..close();
  static final PathMetric _outline = _shield.computeMetrics().first;
  static final Path _four = Path()
    ..moveTo(56, 29)
    ..lineTo(33, 57)
    ..lineTo(66, 57)
    ..moveTo(56, 29)
    ..lineTo(56, 76);

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;
    // Keep strokes proportional in 12px status badges and larger splash marks.
    final width = math.min(strokeWidth, side * 0.065) * 100 / side;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 100);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [start, end],
    ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(_shield, paint..color = end.withValues(alpha: 0.22));
    canvas.drawPath(_four, paint..shader = gradient);

    // A fading tail follows the outline, wrapping seamlessly past the tip.
    // Only this highlight travels: the shield and the '4' remain upright.
    paint.shader = null;
    const segments = 20;
    const trail = 0.38;
    for (var i = 0; i < segments; i++) {
      final from = (animation.value + i * trail / segments) % 1.0;
      final to = from + trail / segments + 0.002;
      final color = Color.lerp(start, end, i / (segments - 1))!;
      paint.color = color.withValues(alpha: 0.12 + 0.88 * i / (segments - 1));
      canvas.drawPath(
        _outline.extractPath(
          from * _outline.length,
          math.min(to, 1.0) * _outline.length,
        ),
        paint,
      );
      if (to > 1.0) {
        canvas.drawPath(
          _outline.extractPath(0, (to - 1.0) * _outline.length),
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShieldLoaderPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.strokeWidth != strokeWidth;
}
