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

    // Low-energy caustic at the perimeter; the centre is left clear.
    final edgeBand = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(edge(0.7))
      ..addRRect(edge(3.2));
    canvas.drawPath(
      edgeBand,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.09 : 0.13),
            Colors.transparent,
            Colors.white.withValues(alpha: isDark ? 0.04 : 0.08),
          ],
          stops: const [0, 0.48, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      edge(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.55 : 0.82),
            Colors.white.withValues(alpha: isDark ? 0.10 : 0.24),
            Colors.black.withValues(alpha: isDark ? 0.14 : 0.07),
            Colors.white.withValues(alpha: isDark ? 0.30 : 0.64),
          ],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(rect),
    );
    // A barely visible inner shadow replaces the previous multi-pixel bevel.
    canvas.drawRRect(
      edge(1.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: isDark ? 0.15 : 0.09),
            Colors.transparent,
            Colors.white.withValues(alpha: isDark ? 0.08 : 0.22),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassEdge oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.radius != radius;
}
