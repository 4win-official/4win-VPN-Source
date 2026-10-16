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
  static const _calloutWidth = 136.0;

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
    final seconds = first
        ? 2 + _random.nextInt(5)
        : 18 + _random.nextInt(31);
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

    _calloutEntry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomCenter,
        followerAnchor: Alignment.topRight,
        offset: const Offset(10, 8),
        child: _buildCallout(context),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_calloutEntry!);
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

    return Semantics(
      button: true,
      label: 'Support Us',
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _removeCallout();
            _scheduleCallout();
            widget.onPressed();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: _calloutWidth,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xD91B1422)
                      : const Color(0xE6FFF9FD),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.34 : 0.78),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF69B4).withValues(alpha: 0.36),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.favorite_rounded,
                      size: 15,
                      color: Color(0xFFFF72B8),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Support Us',
                      maxLines: 1,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
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
                painter: _LiquidGlassHeartPainter(glow: _beatCurve.value),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LiquidGlassHeartPainter extends CustomPainter {
  final double glow;

  const _LiquidGlassHeartPainter({required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = _heartPath(size);

    // Pink light blooming from behind the translucent glass heart.
    final glowPaint = Paint()
      ..color = const Color(0xFFFF54AE).withValues(alpha: 0.48 + glow * 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 + glow * 5);
    canvas.drawPath(path, glowPaint);

    final fill = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-0.8, -1),
        end: const Alignment(0.8, 1),
        colors: [
          Colors.white.withValues(alpha: 0.68),
          const Color(0xFFFFA5D8).withValues(alpha: 0.42),
          const Color(0xFFE3C9FF).withValues(alpha: 0.38),
          const Color(0xFFFFF7FC).withValues(alpha: 0.62),
        ],
        stops: const [0, 0.36, 0.7, 1],
      ).createShader(rect)
      ..isAntiAlias = true;
    canvas.drawPath(path, fill);

    // Glassy reflections stay inside the heart silhouette.
    canvas.save();
    canvas.clipPath(path);
    final sheen = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.78),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.30, size.height * 0.24),
        radius: size.width * 0.45,
      ));
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
        colors: [
          Colors.white.withValues(alpha: 0.98),
          const Color(0xFFFFB5DF).withValues(alpha: 0.88),
          Colors.white.withValues(alpha: 0.72),
        ],
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
      oldDelegate.glow != glow;
}
