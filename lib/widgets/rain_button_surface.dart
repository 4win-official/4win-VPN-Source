import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Button-local water: incoming drops hit its upper edge, run down its curved
/// face, then detach at the lower edge. The child retains layout and gestures.
class RainButtonSurface extends StatefulWidget {
  const RainButtonSurface({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<RainButtonSurface> createState() => _RainButtonSurfaceState();
}

class _RainButtonSurfaceState extends State<RainButtonSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _water;
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    _water = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  void _syncAnimation() {
    // ignore: deprecated_member_use
    final tickerEnabled = TickerMode.of(context);
    _animate = tickerEnabled && !MediaQuery.disableAnimationsOf(context);
    if (widget.enabled && _animate) {
      if (!_water.isAnimating) _water.repeat();
    } else {
      _water.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant RainButtonSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _water.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        // Give airborne splashes and detached drops real paint bounds, while
        // keeping the button's layout and hit target exactly the same size.
        Positioned(
          top: -24,
          bottom: -48,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: RainButtonPainter(
                  _animate
                      ? _water
                      : const AlwaysStoppedAnimation<double>(0.45),
                  topInset: 24,
                  bottomInset: 48,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RainButtonPainter extends CustomPainter {
  RainButtonPainter(this.progress, {this.topInset = 0, this.bottomInset = 0})
    : super(repaint: progress);

  final Animation<double> progress;
  final double topInset;
  final double bottomInset;

  // Geometry is cached, not rebuilt on every frame. Each path starts on the
  // upper circumference and finishes exactly on the lower circumference.
  static final List<ui.PathMetric> _tracks = [
    for (final x in [-0.82, -0.58, -0.31, 0.12, 0.4, 0.67, 0.86])
      _track(x).computeMetrics().single,
  ];

  static Path _track(double x) {
    final endX = x * 0.68;
    final side = x.sign;
    return Path()
      ..moveTo(100 + x * 98, 100 - math.sqrt(1 - x * x) * 98)
      ..cubicTo(
        100 + (x + side * 0.19) * 98,
        83,
        100 + (endX + side * 0.26) * 98,
        151,
        100 + endX * 98,
        100 + math.sqrt(1 - endX * endX) * 98,
      );
  }

  void _bead(
    Canvas canvas,
    Offset point,
    double radius,
    double stretch, {
    double opacity = 1,
  }) {
    final rect = Rect.fromCenter(
      center: point,
      width: radius * 2,
      height: radius * 2 * stretch,
    );
    canvas.drawOval(
      rect.inflate(0.55),
      Paint()..color = Color.fromRGBO(22, 78, 112, 0.65 * opacity),
    );
    canvas.drawOval(
      rect,
      Paint()..color = Color.fromRGBO(157, 223, 255, 0.72 * opacity),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: point + Offset(-radius * 0.25, -radius * 0.35),
        width: radius * 0.75,
        height: radius * stretch,
      ),
      Paint()..color = Color.fromRGBO(238, 251, 255, 0.9 * opacity),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || size.height <= topInset + bottomInset) return;
    canvas.save();
    canvas.translate(0, topInset);
    canvas.scale(
      size.width / 200,
      (size.height - topInset - bottomInset) / 200,
    );
    // A restrained wet highlight, not an opaque layer over the power glyph.
    canvas.drawArc(
      const Rect.fromLTWH(3, 3, 194, 194),
      math.pi * 1.13,
      math.pi * 0.74,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x709EDFFF),
    );
    for (var i = 0; i < _tracks.length; i++) {
      final phase = (progress.value + i * 0.137) % 1;
      final track = _tracks[i];
      final impact = track.getTangentForOffset(0)!.position;
      final radius = 1.6 + (i % 3) * 0.35;

      if (phase < 0.1) {
        // The incoming bead meets the upper edge before turning into runoff.
        final approach = phase / 0.1;
        _bead(
          canvas,
          impact - Offset(2 * (1 - approach), 20 * (1 - approach)),
          radius,
          1.8,
        );
      }
      if (phase >= 0.1 && phase < 0.23) {
        final splash = (phase - 0.1) / 0.13;
        final paint = Paint()
          ..color = Color.fromRGBO(194, 235, 255, (1 - splash) * 0.8)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round;
        for (final side in [-1.0, 1.0]) {
          final tip =
              impact +
              Offset(side * (3 + splash * 8), -math.sin(splash * math.pi) * 7);
          canvas.drawLine(tip, tip + Offset(side * 2, -2), paint);
        }
      }
      if (phase >= 0.1 && phase < 0.8) {
        final slide = (phase - 0.1) / 0.7;
        // Water accelerates down the face, with a short trailing rivulet.
        final distance = track.length * math.pow(slide, 1.35).toDouble();
        final trail = track.extractPath(math.max(0, distance - 24), distance);
        canvas.drawPath(
          trail,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.8
            ..color = const Color(0x70164E70),
        );
        canvas.drawPath(
          trail,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 1.25
            ..color = const Color(0xA6C7EDFF),
        );
        _bead(
          canvas,
          track.getTangentForOffset(distance)!.position,
          radius,
          1.35,
        );
      } else if (phase >= 0.8) {
        final fall = (phase - 0.8) / 0.2;
        final edge = track.getTangentForOffset(track.length)!.position;
        _bead(
          canvas,
          edge + Offset(fall * 3, 44 * fall * fall),
          radius,
          1.4 + fall,
          opacity: 1 - fall,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RainButtonPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.topInset != topInset ||
      oldDelegate.bottomInset != bottomInset;
}
