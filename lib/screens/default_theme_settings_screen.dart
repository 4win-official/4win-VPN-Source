import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// Settings that belong ONLY to the default (system) theme. Right now this is
/// where the user sets a custom background image (a separate picture for day
/// and for night). Reached from the gear icon on the "System Default" theme
/// card in the theme selection screen.
class DefaultThemeSettingsScreen extends StatelessWidget {
  const DefaultThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black54;

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
          'Default Theme Settings',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Custom Background',
                  style: TextStyle(
                    color: subColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set your own wallpaper for the default theme. You can pick a '
                  'different image for day and for night — the one shown here '
                  'applies to the current mode.',
                  style: TextStyle(color: subColor, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                _CustomBackgroundCard(
                  isDark: isDark,
                  themeProvider: themeProvider,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Card that lets the user pick (or clear) a custom background image for the
/// DEFAULT theme. A separate image is stored per day/night mode.
class _CustomBackgroundCard extends StatelessWidget {
  final bool isDark;
  final ThemeProvider themeProvider;

  const _CustomBackgroundCard({
    required this.isDark,
    required this.themeProvider,
  });

  Future<void> _pickImage(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final modeTag = themeProvider.isDarkMode ? 'dark' : 'light';
      final ext = picked.path.split('.').last;
      final dest = File('${dir.path}/custom_bg_$modeTag.$ext');
      await File(picked.path).copy(dest.path);

      await themeProvider.setCustomBackground(dest.path);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not set background image')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final modeLabel = themeProvider.isDarkMode ? 'night' : 'day';
    final currentPath = themeProvider.customBackgroundPath;
    final hasBg = currentPath != null &&
        currentPath.isNotEmpty &&
        File(currentPath).existsSync();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: hasBg
                  ? Image.file(File(currentPath), fit: BoxFit.cover)
                  : Container(
                      color: Colors.blueGrey.withValues(alpha: 0.2),
                      child: const Icon(Icons.image_outlined,
                          color: Colors.blueGrey),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom background ($modeLabel)',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasBg
                      ? 'Tap to change your $modeLabel background'
                      : 'Pick an image for the default theme ($modeLabel)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          if (hasBg)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: isDark ? Colors.white54 : Colors.black45),
              tooltip: 'Remove',
              onPressed: () => themeProvider.setCustomBackground(null),
            ),
          IconButton(
            icon: Icon(Icons.add_photo_alternate_outlined,
                color: isDark ? const Color(0xFF00FF88) : Colors.blue),
            tooltip: 'Choose image',
            onPressed: () => _pickImage(context),
          ),
        ],
      ),
    );
  }
}
