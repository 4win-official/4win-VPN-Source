import 'package:flutter/material.dart';

/// A simple visual guide that teaches new users two key interactions:
///   1. How to change the app theme  -> the palette icon at the top of the screen.
///   2. How to open Settings         -> long-press the power (on/off) button.
///
/// Each step is illustrated with a mock of the relevant UI element plus a short
/// caption so users can understand it visually without reading much.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF00FF88) : const Color(0xFF4CAF50);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Quick Guide',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
            Icon(Icons.lightbulb_outline, size: 56, color: accent),
            const SizedBox(height: 12),
            Text(
              'Welcome to 4win VPN',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Two quick things to know before you start',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 14),
            ),
            const SizedBox(height: 28),

            // STEP 1 — Change theme (palette icon at the top)
            _GuideCard(
              isDark: isDark,
              accent: accent,
              stepNumber: '1',
              title: 'Change the theme',
              description:
                  'Tap the palette icon at the top of the home screen to switch '
                  'between themes (Snow, Pixel, Rain, Pink…) and day / night mode.',
              illustration: _TopBarIllustration(isDark: isDark, accent: accent),
            ),
            const SizedBox(height: 20),

            // STEP 2 — Open settings (long-press the power button)
            _GuideCard(
              isDark: isDark,
              accent: accent,
              stepNumber: '2',
              title: 'Open Settings',
              description:
                  'Press and HOLD the power (on/off) button in the middle of the '
                  'screen. A spinning gear appears and takes you to Settings — '
                  'this works in every protocol.',
              illustration: _PowerButtonIllustration(isDark: isDark, accent: accent),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Got it!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// A card containing a numbered step: an illustration, a title and a description.
class _GuideCard extends StatelessWidget {
  final bool isDark;
  final Color accent;
  final String stepNumber;
  final String title;
  final String description;
  final Widget illustration;

  const _GuideCard({
    required this.isDark,
    required this.accent,
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  stepNumber,
                  style: TextStyle(
                    color: isDark ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(child: illustration),
          const SizedBox(height: 16),
          Text(
            description,
            style: TextStyle(color: subColor, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Mock of the home-screen top bar, highlighting the palette (theme) icon.
class _TopBarIllustration extends StatelessWidget {
  final bool isDark;
  final Color accent;
  const _TopBarIllustration({required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) {
    final faded = isDark ? Colors.white38 : Colors.black38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: faded.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '4win VPN',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Highlighted palette icon (the theme button)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
            ),
            child: Icon(Icons.palette_outlined, color: accent, size: 22),
          ),
          const SizedBox(width: 10),
          Icon(Icons.dark_mode, color: faded, size: 22),
          const SizedBox(width: 10),
          Icon(Icons.favorite_border, color: faded, size: 22),
        ],
      ),
    );
  }
}

/// Mock of the round power button with a "hold" hint and a gear overlay,
/// illustrating the long-press-to-settings gesture.
class _PowerButtonIllustration extends StatelessWidget {
  final bool isDark;
  final Color accent;
  const _PowerButtonIllustration({required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                Icons.power_settings_new,
                size: 48,
                color: isDark ? Colors.black87 : Colors.white,
              ),
            ),
            // Small gear badge indicating long-press -> settings
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.settings, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 18, color: accent),
            const SizedBox(width: 6),
            Text(
              'Press & hold',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
