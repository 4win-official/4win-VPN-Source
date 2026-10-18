import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// A glassy, softly pulsing support button for the home app bar.
///
/// A short "Support Us" callout appears at random intervals below the heart,
/// then disappears on its own so it can explain the button without staying in
/// the way.
class RainbowHeartButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  const RainbowHeartButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Support Us',
    this.size = 26,
  });

  @override
  State<RainbowHeartButton> createState() => _RainbowHeartButtonState();
}

class _RainbowHeartButtonState extends State<RainbowHeartButton>
    with SingleTickerProviderStateMixin {
  static const _calloutDuration = Duration(seconds: 4);
  static const _maxCalloutWidth = 176.0;
  static const _calloutHeight = 54.0;

  final math.Random _random = math.Random();
  final LayerLink _layerLink = LayerLink();
  late final AnimationController _beat;
  late final Animation<double> _beatCurve;
  Timer? _calloutTimer;
  Timer? _dismissTimer;
  OverlayEntry? _calloutEntry;

  @override
  void initState() {
    super.initState();
    _beat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _beatCurve = CurvedAnimation(parent: _beat, curve: Curves.easeInOut);
    _scheduleCallout(first: true);
  }

  void _scheduleCallout({bool first = false}) {
    _calloutTimer?.cancel();
    final seconds = first ? 2 + _random.nextInt(5) : 18 + _random.nextInt(31);
    _calloutTimer = Timer(Duration(seconds: seconds), _showCallout);
  }

  void _showCallout() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _scheduleCallout();
      return;
    }
    _removeCallout();

    final overlay = Overlay.of(context, rootOverlay: true);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final calloutWidth = math
        .min(
          _maxCalloutWidth,
          math.min(screenWidth - 32, math.max(120.0, screenWidth * 0.44)),
        )
        .toDouble();
    final textDirection = Directionality.of(context);
    final anchor = AlignmentDirectional.bottomEnd.resolve(textDirection);
    final followerAnchor = AlignmentDirectional.topEnd.resolve(textDirection);

    _calloutEntry = OverlayEntry(
      builder: (overlayContext) => Positioned.fill(
        child: Align(
          alignment: Alignment.topLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: anchor,
            followerAnchor: followerAnchor,
            offset: const Offset(0, 2),
            child: Directionality(
              textDirection: textDirection,
              child: SizedBox(
                width: calloutWidth,
                height: _calloutHeight,
                child: _buildCallout(context),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_calloutEntry!);
    _dismissTimer = Timer(_calloutDuration, () {
      _removeCallout();
      if (mounted) _scheduleCallout();
    });
  }

  void _removeCallout() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _calloutEntry?.remove();
    _calloutEntry?.dispose();
    _calloutEntry = null;
  }

  Widget _buildCallout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF281D29);

    final shape = _SupportCalloutBorder(
      pointerOnRight: Directionality.of(context) == TextDirection.ltr,
      side: BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.48)
            : const Color(0xFFE79ABC),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(
          scale: 0.94 + 0.06 * value,
          alignment: Directionality.of(context) == TextDirection.ltr
              ? Alignment.topRight
              : Alignment.topLeft,
          child: child,
        ),
      ),
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _removeCallout();
              _scheduleCallout();
              widget.onPressed();
            },
            // One continuous speech-bubble outline: its tip sits directly
            // beneath the heart's centre, including in RTL layouts.
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape,
                shadows: [
                  BoxShadow(
                    color: const Color(0xFFFF69B4).withValues(alpha: 0.24),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipPath(
                key: const ValueKey('support-callout-pointer'),
                clipper: ShapeBorderClipper(shape: shape),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: DecoratedBox(
                    key: const ValueKey('support-callout'),
                    decoration: ShapeDecoration(
                      color: isDark
                          ? const Color(0xF01B1422)
                          : const Color(0xF5FFF9FD),
                      shape: shape,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            size: 15,
                            color: Color(0xFFFF72B8),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              widget.tooltip,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 10,
                            color: textColor.withValues(alpha: 0.65),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _calloutTimer?.cancel();
    _removeCallout();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: () {
          _removeCallout();
          _scheduleCallout();
          widget.onPressed();
        },
        icon: AnimatedBuilder(
          animation: _beatCurve,
          builder: (context, _) {
            final scale = 1.0 + (_beatCurve.value * 0.08);
            return Transform.scale(
              scale: scale,
              child: CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _LiquidGlassHeartPainter(
                  glow: _beatCurve.value,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A single glass bubble with an integrated upward-pointing tail.
class _SupportCalloutBorder extends ShapeBorder {
  const _SupportCalloutBorder({
    required this.pointerOnRight,
    required this.side,
  });

  final bool pointerOnRight;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.only(top: 10);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final centre = pointerOnRight ? rect.right - 24 : rect.left + 24;
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(rect.left, rect.top + 10, rect.right, rect.bottom),
          const Radius.circular(15),
        ),
      );
    final pointer = Path()
      ..moveTo(centre - 9, rect.top + 11)
      ..lineTo(centre, rect.top)
      ..lineTo(centre + 9, rect.top + 11)
      ..close();
    return Path.combine(PathOperation.union, body, pointer);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(getOuterPath(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => _SupportCalloutBorder(
    pointerOnRight: pointerOnRight,
    side: side.scale(t),
  );
}

class _LiquidGlassHeartPainter extends CustomPainter {
  final double glow;
  final bool isDark;

  const _LiquidGlassHeartPainter({required this.glow, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = _heartPath(size);

    // Pink light blooming from behind the translucent glass heart.
    final glowPaint = Paint()
      ..color = const Color(
        0xFFFF3688,
      ).withValues(alpha: isDark ? 0.48 + glow * 0.18 : 0.28 + glow * 0.12)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 + glow * 5);
    canvas.drawPath(path, glowPaint);

    final fill = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-0.8, -1),
        end: const Alignment(0.8, 1),
        colors: isDark
            ? [
                Colors.white.withValues(alpha: 0.68),
                const Color(0xFFFFA5D8).withValues(alpha: 0.42),
                const Color(0xFFE3C9FF).withValues(alpha: 0.38),
                const Color(0xFFFFF7FC).withValues(alpha: 0.62),
              ]
            : const [
                Color(0xFFFF9BCB),
                Color(0xFFEF4B8C),
                Color(0xFFD91E66),
                Color(0xFFFF78B3),
              ],
        stops: const [0, 0.36, 0.7, 1],
      ).createShader(rect)
      ..isAntiAlias = true;
    canvas.drawPath(path, fill);

    // Glassy reflections stay inside the heart silhouette.
    canvas.save();
    canvas.clipPath(path);
    final sheen = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.78),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.30, size.height * 0.24),
              radius: size.width * 0.45,
            ),
          );
    canvas.drawRect(rect, sheen);

    final glint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.7);
    canvas.save();
    canvas.translate(size.width * 0.31, size.height * 0.28);
    canvas.rotate(-0.48);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * 0.18,
        height: size.height * 0.055,
      ),
      glint,
    );
    canvas.restore();
    canvas.restore();

    // Fine luminous rim gives the heart its liquid-glass edge.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                Colors.white.withValues(alpha: 0.98),
                const Color(0xFFFFB5DF).withValues(alpha: 0.88),
                Colors.white.withValues(alpha: 0.72),
              ]
            : const [Color(0xFFFFE2EF), Color(0xFF9E174D), Color(0xFFFFC1DA)],
      ).createShader(rect)
      ..isAntiAlias = true;
    canvas.drawPath(path, rim);
  }

  Path _heartPath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.5, h * 0.88)
      ..cubicTo(w * -0.08, h * 0.52, w * 0.14, h * 0.04, w * 0.5, h * 0.30)
      ..cubicTo(w * 0.86, h * 0.04, w * 1.08, h * 0.52, w * 0.5, h * 0.88)
      ..close();
  }

  @override
  bool shouldRepaint(_LiquidGlassHeartPainter oldDelegate) =>
      oldDelegate.glow != glow || oldDelegate.isDark != isDark;
}
