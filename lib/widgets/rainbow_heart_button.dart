import 'package:flutter/material.dart';

/// An attention-grabbing animated donate button.
/// The heart cycles through a 7-color rainbow gradient while gently
/// pulsing (scale) to draw the user's attention to support the app.
class RainbowHeartButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const RainbowHeartButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Support Us',
  });

  @override
  State<RainbowHeartButton> createState() => _RainbowHeartButtonState();
}

class _RainbowHeartButtonState extends State<RainbowHeartButton>
    with TickerProviderStateMixin {
  late final AnimationController _colorController;
  late final AnimationController _pulseController;

  // The 7 rainbow colors (ROYGBIV) used to tint the heart over time.
  static const List<Color> _rainbow = [
    Color(0xFFFF1744), // red
    Color(0xFFFF9100), // orange
    Color(0xFFFFEA00), // yellow
    Color(0xFF00E676), // green
    Color(0xFF2979FF), // blue
    Color(0xFF651FFF), // indigo
    Color(0xFFD500F9), // violet
  ];

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _colorController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color _currentColor(double t) {
    // t in [0,1) -> interpolate across the rainbow ring.
    final scaled = t * _rainbow.length;
    final index = scaled.floor() % _rainbow.length;
    final next = (index + 1) % _rainbow.length;
    final localT = scaled - scaled.floor();
    return Color.lerp(_rainbow[index], _rainbow[next], localT)!;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_colorController, _pulseController]),
      builder: (context, child) {
        final color = _currentColor(_colorController.value);
        final scale = 1.0 + (_pulseController.value * 0.22);
        final glow = 4.0 + (_pulseController.value * 8.0);
        return IconButton(
          tooltip: widget.tooltip,
          onPressed: widget.onPressed,
          icon: Transform.scale(
            scale: scale,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (Rect bounds) {
                return SweepGradient(
                  colors: const [
                    ..._rainbow,
                    Color(0xFFFF1744),
                  ],
                  transform: GradientRotation(
                    _colorController.value * 6.28318,
                  ),
                ).createShader(bounds);
              },
              child: Icon(
                Icons.favorite,
                color: color,
                shadows: [
                  Shadow(
                    color: color.withValues(alpha: 0.8),
                    blurRadius: glow,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
