import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// The Liquid theme's backdrop. Its ticker is isolated from the home controls.
class LiquidBackground extends StatefulWidget {
  const LiquidBackground({super.key});

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _updateAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateAnimation();
  }

  void _updateAnimation() {
    if (_foreground && !_reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Periodic curves keep both velocity and position continuous at
              // the loop boundary; the two glows follow different orbits.
              final phase = _controller.value * math.pi * 2;
              final wave = math.sin(phase);
              final drift = math.cos(phase);
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final cyanSize = width * (0.58 + 0.05 * wave);
              final violetSize = width * (0.68 + 0.06 * math.sin(phase + 1.2));
              return Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    key: const ValueKey('liquid-gradient'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-0.85 + 0.35 * wave, -1),
                        end: Alignment(0.85 + 0.35 * drift, 1),
                        stops: [0, 0.5 + 0.12 * math.sin(phase + 0.6), 1],
                        colors: isDark
                            ? const [
                                Color(0xFF1B2A4A),
                                Color(0xFF0B1020),
                                Color(0xFF2A1B4A),
                              ]
                            : const [
                                Color(0xFFBFD4FF),
                                Color(0xFFEAF0FF),
                                Color(0xFFDDCBFF),
                              ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: width * (0.18 + 0.18 * wave) - cyanSize / 2,
                    top: height * (0.23 + 0.10 * drift) - cyanSize / 2,
                    child: _glow(
                      'liquid-cyan-glow',
                      const Color(0xFF4FC3F7),
                      cyanSize,
                    ),
                  ),
                  Positioned(
                    left:
                        width * (0.84 + 0.16 * math.sin(phase + 1.1)) -
                        violetSize / 2,
                    top:
                        height * (0.76 + 0.09 * math.cos(phase + 0.7)) -
                        violetSize / 2,
                    child: _glow(
                      'liquid-violet-glow',
                      const Color(0xFFB388FF),
                      violetSize,
                    ),
                  ),
                  child!,
                ],
              );
            },
            // Keep the frosted sheen stable while its backdrop flows beneath it.
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.06 : 0.35),
                      Colors.white.withValues(alpha: isDark ? 0.02 : 0.12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glow(String key, Color color, double size) => SizedBox(
    key: ValueKey(key),
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.5), color.withValues(alpha: 0)],
        ),
      ),
    ),
  );
}
