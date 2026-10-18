import 'dart:ui';

import 'package:flutter/material.dart';

/// A translucent lens, not an opaque card with a glow painted in its centre.
///
/// The scene supplies the glass colour through a clipped backdrop blur. Most of
/// the reflection is confined to the bevel so labels remain crisp and the same
/// material works over both the light and dark home screen.
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
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            key: const ValueKey('protocol-glass-tint'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0, 0.32, 0.7, 1],
                colors: isDark
                    ? const [
                        Color(0x38282B30),
                        Color(0x26181B20),
                        Color(0x20181B20),
                        Color(0x30282B30),
                      ]
                    : const [
                        Color(0x60FFFFFF),
                        Color(0x36FFFFFF),
                        Color(0x2CF4F7FA),
                        Color(0x48FFFFFF),
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
    // A very quiet grazing reflection fades out before the list. No artificial
    // central spotlight: the background, not a radial blob, provides depth.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(0.25, 0.1),
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.07 : 0.16),
            Colors.white.withValues(alpha: 0.015),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
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

    // A curved lens catches light at opposing corners. The wide, faint band
    // rolls into a sharper hairline, rather than two uniform concentric borders.
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
            Colors.white.withValues(alpha: 0.015),
            Colors.white.withValues(alpha: isDark ? 0.15 : 0.28),
            Colors.white.withValues(alpha: 0.025),
            Colors.black.withValues(alpha: isDark ? 0.09 : 0.055),
            Colors.white.withValues(alpha: isDark ? 0.22 : 0.42),
            Colors.white.withValues(alpha: 0.015),
          ],
          stops: const [0, 0.18, 0.36, 0.53, 0.68, 1],
        ).createShader(rect),
    );

    canvas.drawRRect(
      _edge(rect, 0.65),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.72 : 0.95),
            Colors.white.withValues(alpha: isDark ? 0.18 : 0.40),
            Colors.white.withValues(alpha: isDark ? 0.045 : 0.12),
            Colors.white.withValues(alpha: isDark ? 0.36 : 0.72),
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
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: isDark ? 0.16 : 0.07),
            Colors.black.withValues(alpha: 0),
            Colors.white.withValues(alpha: isDark ? 0.045 : 0.13),
          ],
          stops: const [0, 0.48, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassBevel oldDelegate) =>
      oldDelegate.isDark != isDark;
}
