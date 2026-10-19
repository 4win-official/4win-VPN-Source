import 'dart:ui';

import 'package:flutter/material.dart';

/// A translucent lens with a blurred scene, broad specular sweeps, and a thick
/// refractive rim. The centre stays comparatively quiet so labels remain crisp.
class ProtocolGlassSurface extends StatelessWidget {
  const ProtocolGlassSurface({
    super.key,
    required this.isDark,
    required this.child,
  });

  final bool isDark;
  final Widget child;

  static const _radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          // Contact shadow and a softer cast shadow separate the lens from the
          // scene without making the glass itself look smoky or metallic.
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.13),
            blurRadius: 36,
            spreadRadius: -6,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            key: const ValueKey('protocol-glass-tint'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0, 0.28, 0.68, 1],
                colors: isDark
                    ? const [
                        Color(0x3D242A32),
                        Color(0x28171C24),
                        Color(0x22141A22),
                        Color(0x382B323B),
                      ]
                    : const [
                        Color(0x66FFFFFF),
                        Color(0x3DFFFFFF),
                        Color(0x30F2F6FA),
                        Color(0x55FFFFFF),
                      ],
              ),
            ),
            child: CustomPaint(
              painter: _GlassReflection(isDark: isDark),
              // The rim is painted above the material's ink, but never above
              // labels: it occupies only the outermost few logical pixels.
              foregroundPainter: _GlassBevel(isDark: isDark),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassReflection extends CustomPainter {
  const _GlassReflection({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // A bowed reflection has its own silhouette: this reads as curved glass,
    // rather than another full-panel tint. It fades before the main list.
    final shoulder = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.09)
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.04,
        size.width * 0.36,
        size.height * 0.30,
        0,
        size.height * 0.23,
      )
      ..close();
    canvas.drawPath(
      shoulder,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.18 : 0.26),
            Colors.white.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.3)),
    );
    // Broad, offset bands imply a curved lens while leaving the content area
    // readable. Each band is clipped by the parent's ClipRRect.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1.15, -0.8),
          end: const Alignment(0.8, 0.15),
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.22 : 0.34),
            Colors.white.withValues(alpha: isDark ? 0.075 : 0.14),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.18, 0.58],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-0.25, -1.2),
          end: const Alignment(0.65, 1.15),
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.13 : 0.22),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: isDark ? 0.045 : 0.09),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.22, 0.45, 0.78],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(1.1, -0.75),
          end: const Alignment(-0.75, 0.9),
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.12 : 0.18),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.33],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassReflection oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _GlassBevel extends CustomPainter {
  const _GlassBevel({required this.isDark});

  final bool isDark;

  RRect _edge(Rect rect, double inset) =>
      RRect.fromRectAndRadius(rect.deflate(inset), Radius.circular(28 - inset));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    // A thick, uneven caustic band gives the panel a curved lens edge instead
    // of a flat uniform outline.
    final bevel = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(_edge(rect, 0.5))
      ..addRRect(_edge(rect, 5));
    canvas.drawPath(
      bevel,
      Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.04 : 0.09),
            Colors.white.withValues(alpha: isDark ? 0.32 : 0.52),
            Colors.white.withValues(alpha: isDark ? 0.06 : 0.12),
            Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
            Colors.white.withValues(alpha: isDark ? 0.40 : 0.62),
            Colors.white.withValues(alpha: isDark ? 0.03 : 0.08),
          ],
          stops: const [0, 0.18, 0.36, 0.53, 0.68, 1],
        ).createShader(rect),
    );

    canvas.drawRRect(
      _edge(rect, 0.65),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.86 : 1.0),
            Colors.white.withValues(alpha: isDark ? 0.25 : 0.52),
            Colors.white.withValues(alpha: isDark ? 0.06 : 0.16),
            Colors.white.withValues(alpha: isDark ? 0.52 : 0.86),
          ],
          stops: const [0, 0.28, 0.62, 1],
        ).createShader(rect),
    );

    // The inner falloff is dark on the lit side and clear on the opposite side,
    // suggesting thickness without outlining the whole panel like a frame.
    canvas.drawRRect(
      _edge(rect, 4.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: isDark ? 0.24 : 0.11),
            Colors.black.withValues(alpha: 0),
            Colors.white.withValues(alpha: isDark ? 0.09 : 0.18),
          ],
          stops: const [0, 0.48, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassBevel oldDelegate) =>
      oldDelegate.isDark != isDark;
}
