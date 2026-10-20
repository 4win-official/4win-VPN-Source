import 'dart:ui';

import 'package:flutter/material.dart';

/// Clear, shallow lens glass: a lightly magnified backdrop, minimal diffusion,
/// and a fine curved edge. Content is painted after the filter and stays crisp.
class ProtocolGlassSurface extends StatelessWidget {
  const ProtocolGlassSurface({
    super.key,
    required this.isDark,
    required this.child,
    this.radius = 28,
  });

  final bool isDark;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.13 : 0.06),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.07),
            blurRadius: 24,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          // A small optical enlargement acts on the actual backdrop, not on
          // labels. This is a shallow-lens approximation, not a frosted fill.
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            inner: ImageFilter.matrix(
              (Matrix4.identity()..scaleByDouble(1.025, 1.025, 1, 1)).storage,
              filterQuality: FilterQuality.medium,
            ),
          ),
          child: DecoratedBox(
            key: const ValueKey('protocol-glass-tint'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.16, 0.78, 1],
                colors: isDark
                    ? const [
                        Color(0x292C3336),
                        Color(0x14202729),
                        Color(0x17202729),
                        Color(0x24333B3D),
                      ]
                    : const [
                        Color(0x36FFFFFF),
                        Color(0x14FFFFFF),
                        Color(0x18F5F8F7),
                        Color(0x36FFFFFF),
                      ],
              ),
            ),
            child: CustomPaint(
              foregroundPainter: _GlassEdge(isDark: isDark, radius: radius),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassEdge extends CustomPainter {
  const _GlassEdge({required this.isDark, required this.radius});

  final bool isDark;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    // Clamp the radius before insetting, so pill edges remain concentric.
    final curve = radius.clamp(0.0, size.shortestSide / 2);
    RRect edge(double inset) => RRect.fromRectAndRadius(
      rect.deflate(inset),
      Radius.circular((curve - inset).clamp(0.0, curve)),
    );

    // Model the rounded cross-section, not a bevel made of concentric lines:
    // a soft shoulder catches light, turns through a narrow shade, then lets
    // a faint inner caustic fade back into the unchanged clear centre.
    // These are optical cues only; no extra blur/filter touches the content.
    final rimWidth = 5.8.clamp(0.0, size.shortestSide / 4);
    const profile = <(double, double, double)>[
      (0, 0.08, 0.025),
      (0.8, 0.25, 0.04),
      (1.5, 0.20, 0.065),
      (2.5, 0.07, 0.11),
      (3.5, 0.015, 0.08),
      (4.5, 0.055, 0.025),
      (5.8, 0, 0),
    ];
    const slices = 24;
    final paint = Paint();
    var segment = 0;
    for (var i = 0; i < slices; i++) {
      final outer = rimWidth * i / slices;
      final inner = rimWidth * (i + 1) / slices;
      final sample = (i + 0.5) * 5.8 / slices;
      while (sample > profile[segment + 1].$1) {
        segment++;
      }
      final a = profile[segment];
      final b = profile[segment + 1];
      final t = (sample - a.$1) / (b.$1 - a.$1);
      final light = (a.$2 + (b.$2 - a.$2) * t) * (isDark ? 0.85 : 1.0);
      final shade = (a.$3 + (b.$3 - a.$3) * t) * (isDark ? 1.0 : 0.7);
      paint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: light),
          Colors.white.withValues(alpha: light * 0.18),
          Colors.black.withValues(alpha: shade),
          Colors.white.withValues(alpha: light * 0.55),
        ],
        stops: const [0, 0.36, 0.67, 1],
      ).createShader(rect);
      // Adjacent subpixel bands share exact boundaries. Disabling AA here
      // avoids seams; the clipped silhouette and final glint remain AA'd.
      paint.isAntiAlias = false;
      canvas.drawDRRect(edge(outer), edge(inner), paint);
    }

    // A single fine glint describes the outside silhouette, never an opaque
    // outline. The broader, fading shoulder above supplies the thickness.
    canvas.drawRRect(
      edge(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.65
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.48 : 0.68),
            Colors.white.withValues(alpha: isDark ? 0.09 : 0.18),
            Colors.black.withValues(alpha: isDark ? 0.12 : 0.06),
            Colors.white.withValues(alpha: isDark ? 0.28 : 0.48),
          ],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassEdge oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.radius != radius;
}
