import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Clear water clings to the rim, gathers under it and falls under gravity.
/// The child retains its original layout, semantics and gestures.
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
      duration: const Duration(seconds: 12),
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
        // Real paint bounds for detached drops, without enlarging the hit area.
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

/// One small stream follows the circumference, not a stripe across the glyph.
/// Integer cycle counts make every stream continuous at the controller wrap.
class _RimStream {
  _RimStream(this.start, this.end, this.cycles, this.offset, this.radius)
    : track =
          (Path()..addArc(
                const Rect.fromLTWH(4, 4, 192, 192),
                start,
                end - start,
              ))
              .computeMetrics()
              .single;

  final double start;
  final double end;
  final int cycles;
  final double offset;
  final double radius;
  final ui.PathMetric track;

  Offset get lip => track.getTangentForOffset(track.length)!.position;
}

/// Exposed as geometry so detachment and gravity can be regression-tested
/// without relying on device-specific antialiasing in a golden image.
@immutable
class RainRunoffSample {
  const RainRunoffSample({
    required this.phase,
    required this.position,
    required this.radius,
    required this.stretch,
    required this.opacity,
    required this.detached,
    required this.neck,
  });

  final double phase;
  final Offset position;
  final double radius;
  final double stretch;
  final double opacity;
  final bool detached;
  final double neck;
}

class RainButtonPainter extends CustomPainter {
  RainButtonPainter(this.progress, {this.topInset = 0, this.bottomInset = 0})
    : super(repaint: progress);

  final Animation<double> progress;
  final double topInset;
  final double bottomInset;

  static final _streams = [
    _RimStream(-2.27, -4.48, 3, 0.03, 2.8),
    _RimStream(-0.91, 1.39, 2, 0.43, 3.4),
    _RimStream(-2.85, -4.20, 4, 0.67, 2.1),
    _RimStream(-0.30, 1.13, 3, 0.27, 2.5),
    _RimStream(1.85, 1.59, 2, 0.81, 3.1),
  ];

  @visibleForTesting
  static int get streamCount => _streams.length;

  // Fixed seeds: no random allocations or jittering positions during paint.
  static const _dew = <(double, double, double)>[
    (38, 49, 1.35),
    (63, 23, 1.05),
    (94, 12, 1.15),
    (132, 24, 1.6),
    (161, 48, 1.1),
    (17, 83, 1.45),
    (182, 91, 1.2),
    (25, 126, 1.0),
    (172, 140, 1.5),
    (49, 165, 1.1),
    (145, 169, 1.25),
    (87, 183, 0.9),
  ];

  @visibleForTesting
  static RainRunoffSample sampleRunoff(int index, double phase) {
    final stream = _streams[index];
    final p = phase.clamp(0.0, 1.0);
    if (p < 0.48) {
      final slide = p / 0.48;
      // Slow adhesion at first, then a faster slip around the curved edge.
      final distance = stream.track.length * math.pow(slide, 1.7);
      return RainRunoffSample(
        phase: p,
        position: stream.track
            .getTangentForOffset(distance.toDouble())!
            .position,
        radius: stream.radius * (0.38 + 0.22 * slide),
        stretch: 1.15 - 0.15 * slide,
        opacity: (slide / 0.12).clamp(0.0, 0.65),
        detached: false,
        neck: 0,
      );
    }
    if (p < 0.78) {
      final gather = (p - 0.48) / 0.30;
      final radius = stream.radius * (0.60 + 0.40 * gather);
      // Surface tension holds the drop until its neck becomes too thin.
      final stretch = 1.0 + 0.50 * gather * gather;
      return RainRunoffSample(
        phase: p,
        position: stream.lip + Offset(0, gather * radius * 1.5),
        radius: radius,
        stretch: stretch,
        opacity: 0.65,
        detached: false,
        neck: math.sin(gather * math.pi) * radius * 0.48,
      );
    }
    final fall = (p - 0.78) / 0.22;
    return RainRunoffSample(
      phase: p,
      position:
          stream.lip +
          Offset(
            (index.isEven ? -1 : 1) * 1.7 * fall,
            stream.radius * 1.5 + 4 * fall + 40 * fall * fall,
          ),
      radius: stream.radius,
      // A falling water drop rounds off after the initial neck recoil.
      stretch: 1.0 + 0.50 * math.exp(-fall * 7),
      opacity: 0.65 * (1 - ((fall - 0.55) / 0.45).clamp(0.0, 1.0)),
      detached: true,
      neck: 0,
    );
  }

  /// A transparent lens: subdued refracted shadow, clear centre and a narrow
  /// off-axis glint. No solid blue fill, glow or cartoon teardrop silhouette.
  void _lens(
    Canvas canvas,
    Offset point,
    double radius,
    double stretch, {
    double opacity = 1,
  }) {
    if (opacity <= 0 || radius <= 0) return;
    final rect = Rect.fromCenter(
      center: point,
      width: radius * 2,
      height: radius * 2 * stretch,
    );
    canvas.drawOval(
      rect.shift(const Offset(0.25, 0.6)).inflate(0.3),
      Paint()..color = Color.fromRGBO(8, 29, 40, 0.22 * opacity),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          point + Offset(-radius * 0.35, -radius * 0.45),
          radius * 2.2,
          [
            Color.fromRGBO(239, 252, 255, 0.35 * opacity),
            Color.fromRGBO(200, 232, 240, 0.035 * opacity),
            Color.fromRGBO(22, 62, 76, 0.34 * opacity),
            Color.fromRGBO(222, 248, 255, 0.62 * opacity),
          ],
          const [0, 0.40, 0.79, 1],
        ),
    );
    canvas.drawArc(
      rect.deflate(radius * 0.20),
      math.pi * 1.03,
      math.pi * 0.46,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.65
        ..color = Color.fromRGBO(246, 254, 255, 0.85 * opacity),
    );
    canvas.drawArc(
      rect.deflate(0.15),
      0.14,
      0.78,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.4
        ..color = Color.fromRGBO(211, 240, 248, 0.40 * opacity),
    );
  }

  void _drawStream(Canvas canvas, int index, double phase) {
    final stream = _streams[index];
    final drop = sampleRunoff(index, phase);
    if (phase < 0.48) {
      final distance = stream.track.length * math.pow(phase / 0.48, 1.7);
      final trail = stream.track.extractPath(
        math.max(0, distance - 9).toDouble(),
        distance.toDouble(),
      );
      canvas.drawPath(
        trail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.65
          ..strokeCap = StrokeCap.round
          ..color = Color.fromRGBO(225, 248, 255, 0.25 * drop.opacity),
      );
    } else if (!drop.detached && drop.neck > 0.02) {
      final lip = stream.lip;
      final shoulderY = drop.position.dy - drop.radius * 0.45;
      final neck = Path()
        ..moveTo(lip.dx - drop.neck, lip.dy - 0.5)
        ..cubicTo(
          lip.dx - drop.neck * 0.45,
          shoulderY,
          drop.position.dx - drop.radius * 0.7,
          shoulderY,
          drop.position.dx - drop.radius * 0.7,
          drop.position.dy,
        )
        ..lineTo(drop.position.dx + drop.radius * 0.7, drop.position.dy)
        ..cubicTo(
          drop.position.dx + drop.radius * 0.7,
          shoulderY,
          lip.dx + drop.neck * 0.45,
          shoulderY,
          lip.dx + drop.neck,
          lip.dy - 0.5,
        )
        ..close();
      canvas.drawPath(
        neck,
        Paint()..color = const Color.fromRGBO(216, 242, 250, 0.20),
      );
    }
    _lens(
      canvas,
      drop.position,
      drop.radius,
      drop.stretch,
      opacity: drop.opacity,
    );
    if (drop.detached) {
      // A shrinking meniscus remains on the rim after the main bead releases.
      final recoil = (1 - (phase - 0.78) / 0.10).clamp(0.0, 1.0);
      _lens(
        canvas,
        stream.lip,
        stream.radius * 0.52 * recoil,
        0.65,
        opacity: 0.45 * recoil,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        size.width <= 0 ||
        size.height <= topInset + bottomInset) {
      return;
    }
    canvas.save();
    canvas.translate(0, topInset);
    canvas.scale(
      size.width / 200,
      (size.height - topInset - bottomInset) / 200,
    );

    // Discontinuous hairline reflections read as a wet surface, not a neon ring.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.75;
    for (final arc in <(double, double, double)>[
      (-2.52, 0.46, 0.30),
      (-1.82, 0.29, 0.18),
      (-1.22, 0.34, 0.24),
      (0.32, 0.26, 0.15),
      (1.29, 0.42, 0.25),
      (2.47, 0.23, 0.16),
    ]) {
      canvas.drawArc(
        const Rect.fromLTWH(3.4, 3.4, 193.2, 193.2),
        arc.$1,
        arc.$2,
        false,
        rim..color = Color.fromRGBO(232, 250, 255, arc.$3),
      );
    }
    for (var i = 0; i < _dew.length; i++) {
      final bead = _dew[i];
      // Barely perceptible changing reflections, never blinking water beads.
      final reflection =
          0.48 + 0.08 * math.sin(progress.value * math.pi * 2 + i * 2.4);
      _lens(
        canvas,
        Offset(bead.$1, bead.$2),
        bead.$3,
        1.08,
        opacity: reflection,
      );
    }
    for (var i = 0; i < _streams.length; i++) {
      final stream = _streams[i];
      _drawStream(
        canvas,
        i,
        (progress.value * stream.cycles + stream.offset) % 1,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RainButtonPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.topInset != topInset ||
      oldDelegate.bottomInset != bottomInset;
}
