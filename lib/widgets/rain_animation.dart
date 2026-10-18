import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class RainAnimation extends StatefulWidget {
  const RainAnimation({super.key, this.obstacleKey});

  /// The solid button blocks airborne rain; its surface paints runoff instead.
  final GlobalKey? obstacleKey;

  @override
  State<RainAnimation> createState() => _RainAnimationState();
}

class _RainAnimationState extends State<RainAnimation>
    with SingleTickerProviderStateMixin {
  late final RainSimulation _rain;
  late final Ticker _ticker;
  Duration? _lastFrame;
  final GlobalKey _canvasKey = GlobalKey();

  Rect? _obstacleBounds() {
    final button = widget.obstacleKey?.currentContext?.findRenderObject();
    final surface = _canvasKey.currentContext?.findRenderObject();
    if (button is! RenderBox ||
        surface is! RenderBox ||
        !button.attached ||
        !surface.attached ||
        !button.hasSize) {
      return null;
    }
    return surface.globalToLocal(button.localToGlobal(Offset.zero)) &
        button.size;
  }

  @override
  void initState() {
    super.initState();
    _rain = RainSimulation();
    _ticker = createTicker((elapsed) {
      final previous = _lastFrame;
      _lastFrame = elapsed;
      if (previous != null) {
        _rain.advance((elapsed - previous).inMicroseconds / 1000000);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep compatibility with the project's Flutter 3.35 / Dart 3.9 baseline.
    // ignore: deprecated_member_use
    final tickerEnabled = TickerMode.of(context);
    final animate = tickerEnabled && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_ticker.isActive) {
      _lastFrame = null;
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
      _lastFrame = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _rain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _rain.resize(constraints.biggest);
          return CustomPaint(
            key: _canvasKey,
            painter: RainPainter(_rain, obstacleBounds: _obstacleBounds),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

/// Positions are integrated in logical pixels/second, not a repeating animation
/// fraction. A completed controller cycle can therefore never rewind the rain.
class RainSimulation extends ChangeNotifier {
  RainSimulation({Random? random, int dropCount = 112})
    : _random = random ?? Random() {
    drops = List.generate(dropCount, (_) {
      final depth = _random.nextDouble();
      return RainDrop(
        depth: depth,
        speed: 310 + depth * 510 + _random.nextDouble() * 90,
        length: 9 + depth * 21 + _random.nextDouble() * 5,
        thickness: 0.8 + depth * 1.2,
        opacity: 0.28 + depth * 0.38,
        phase: _random.nextDouble() * pi * 2,
      );
    });
    _nextLightning = 9 + _random.nextDouble() * 13;
  }

  final Random _random;
  late final List<RainDrop> drops;
  Size _size = Size.zero;
  double time = 0;
  double lightning = 0;
  late double _nextLightning;
  double? _lightningStarted;

  // Predominantly diagonal rain, with slow gusts instead of synchronized zigzags.
  double get wind => 66 + 43 * sin(time * 0.63) + 22 * sin(time * 1.37);

  void resize(Size size) {
    if (size == _size || size.isEmpty || !size.isFinite) return;
    for (final drop in drops) {
      if (_size.isEmpty) {
        drop.x = _random.nextDouble() * (size.width + 96) - 48;
        drop.y = _random.nextDouble() * (size.height + 96) - 48;
        drop.velocityX = wind * (0.55 + drop.depth * 0.65);
      } else {
        drop.x *= size.width / _size.width;
        drop.y *= size.height / _size.height;
      }
    }
    _size = size;
  }

  void advance(double seconds) {
    if (_size.isEmpty || !seconds.isFinite || seconds <= 0) return;
    // Resume gently after a paused/backgrounded frame rather than teleporting.
    final dt = seconds.clamp(0.0, 0.05).toDouble();
    time += dt;
    for (final drop in drops) {
      final target =
          wind * (0.55 + drop.depth * 0.65) +
          sin(time * 1.8 + drop.phase) * (5 + drop.depth * 8);
      final oldVelocity = drop.velocityX;
      // Inertia keeps gusts gradual; each depth layer responds differently.
      drop.velocityX +=
          (target - drop.velocityX) * (1 - exp(-dt * (1.6 + drop.depth)));
      drop.x += (oldVelocity + drop.velocityX) * 0.5 * dt;
      drop.y += drop.speed * dt;

      // Recycle only after the entire tail is out of view. Randomize entry so
      // drops don't repeat the same columns or appear split at opposite edges.
      if (drop.y > _size.height + drop.length + 24) {
        drop.y = -24 - _random.nextDouble() * 64;
        drop.x = _random.nextDouble() * (_size.width + 96) - 48;
      } else if (drop.x > _size.width + 64) {
        drop.x = -32 - _random.nextDouble() * 32;
        drop.y = _random.nextDouble() * _size.height;
      } else if (drop.x < -64) {
        drop.x = _size.width + 32 + _random.nextDouble() * 32;
        drop.y = _random.nextDouble() * _size.height;
      }
    }

    // Keep the storm atmosphere, but use one faint, smooth cloud illumination
    // instead of the old rapid white strobe. No delayed callbacks to leak.
    if (time >= _nextLightning) {
      _lightningStarted = time;
      _nextLightning = time + 10 + _random.nextDouble() * 14;
    }
    final age = time - (_lightningStarted ?? -10);
    lightning = age >= 0 && age < 0.65 ? sin(pi * age / 0.65) * 0.065 : 0;
    notifyListeners();
  }
}

class RainDrop {
  RainDrop({
    required this.depth,
    required this.speed,
    required this.length,
    required this.thickness,
    required this.opacity,
    required this.phase,
  });

  double x = 0;
  double y = 0;
  double velocityX = 0;
  final double depth;
  final double speed;
  final double length;
  final double thickness;
  final double opacity;
  final double phase;
}

class RainPainter extends CustomPainter {
  RainPainter(this.rain, {this.obstacleBounds}) : super(repaint: rain);

  final RainSimulation rain;
  final Rect? Function()? obstacleBounds;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (rain.lightning > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = Colors.blueGrey.shade100.withValues(alpha: rain.lightning),
      );
    }
    final obstacle = obstacleBounds?.call();
    if (obstacle != null && !obstacle.isEmpty) {
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addOval(obstacle),
      );
    }
    final paint = Paint()..isAntiAlias = true;
    // A cool dark rim keeps the water visible over the disconnected button's
    // white surface; the bright core remains visible on the black backdrop.
    final rimPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final drop in rain.drops) {
      final head = Offset(drop.x, drop.y);
      final velocity = Offset(drop.velocityX, drop.speed);
      final direction = velocity / velocity.distance;
      final tail = head - direction * drop.length;
      final normal = Offset(-direction.dy, direction.dx);
      final halfWidth = drop.thickness * 0.5;
      final shoulder = head - direction * (drop.thickness * 1.3);
      // A tapered, translucent trail ending in a small rounded droplet, rather
      // than a long, uniformly blue line. Its angle follows actual velocity.
      final path = Path()
        ..moveTo(tail.dx, tail.dy)
        ..quadraticBezierTo(
          (shoulder + normal * halfWidth).dx,
          (shoulder + normal * halfWidth).dy,
          (head + normal * halfWidth).dx,
          (head + normal * halfWidth).dy,
        )
        ..quadraticBezierTo(
          (head + direction * halfWidth).dx,
          (head + direction * halfWidth).dy,
          (head - normal * halfWidth).dx,
          (head - normal * halfWidth).dy,
        )
        ..quadraticBezierTo(
          (shoulder - normal * halfWidth).dx,
          (shoulder - normal * halfWidth).dy,
          tail.dx,
          tail.dy,
        )
        ..close();
      rimPaint.shader = ui.Gradient.linear(tail, head, [
        const Color(0xFF164E70).withValues(alpha: 0),
        const Color(0xFF164E70).withValues(alpha: drop.opacity * 0.8),
      ]);
      canvas.drawPath(path, rimPaint);
      paint.shader = ui.Gradient.linear(
        tail,
        head,
        [
          const Color(0xFF8CAFC4).withValues(alpha: 0),
          const Color(0xFFADD8F0).withValues(alpha: drop.opacity * 0.75),
          const Color(0xFFE0F4FF).withValues(alpha: drop.opacity),
        ],
        [0, 0.65, 1],
      );
      canvas.drawPath(path, paint);
      paint.shader = null;
      paint.color = const Color(
        0xFFE2EDF2,
      ).withValues(alpha: drop.opacity * 0.7);
      canvas.drawCircle(head, halfWidth * 0.65, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RainPainter oldDelegate) =>
      oldDelegate.rain != rain || oldDelegate.obstacleBounds != obstacleBounds;
}
