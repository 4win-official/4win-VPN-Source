import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white, // Pure black
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'VPN Themes',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            // Day/Night toggle now lives here (moved off the home screen).
            // Disabled when the active theme forces a fixed mode (snow/rain).
            final bool toggleLocked =
                themeProvider.selectedTheme == AppTheme.snow ||
                    themeProvider.selectedTheme == AppTheme.rain;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Day / Night mode switch ──────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          themeProvider.isDarkMode
                              ? Icons.dark_mode
                              : Icons.light_mode,
                          color: Colors.amber,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              themeProvider.isDarkMode
                                  ? 'Night mode'
                                  : 'Day mode',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              toggleLocked
                                  ? 'This theme uses a fixed mode'
                                  : 'Switch between light and dark',
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: themeProvider.isDarkMode,
                        onChanged: toggleLocked
                            ? null
                            : (_) => themeProvider.toggleTheme(),
                        activeThumbColor: Colors.amber,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // تم سیستم (دیفالت)
                _ThemeCard(
                  title: 'System Default',
                  description: 'Use light/dark mode',
                  icon: Icons.brightness_auto,
                  color: Colors.grey,
                  isSelected: themeProvider.selectedTheme == AppTheme.system,
                  onTap: () => themeProvider.setTheme(AppTheme.system),
                ),

                // Custom background picker — ONLY for the default theme. The
                // user can set a different image for day and for night.
                if (themeProvider.selectedTheme == AppTheme.system) ...[
                  const SizedBox(height: 12),
                  _CustomBackgroundCard(
                    isDark: isDark,
                    themeProvider: themeProvider,
                  ),
                ],

                const SizedBox(height: 16),
                
                // تم برفی
                _ThemeCard(
                  title: 'Snow Theme ❄️',
                  description: 'Dark mode with falling snow',
                  icon: Icons.ac_unit,
                  color: Colors.lightBlue,
                  isSelected: themeProvider.selectedTheme == AppTheme.snow,
                  onTap: () => themeProvider.setTheme(AppTheme.snow),
                  warning: '⚠️ High battery usage',
                  warningColor: Colors.orange,
                ),
                
                const SizedBox(height: 16),
                
                // تم پیکسلی
                _ThemeCard(
                  title: 'Pixel Theme 🎮',
                  description: 'Retro 8-bit pixelated style (Light + Dark)',
                  icon: Icons.grid_4x4,
                  color: Colors.purple,
                  isSelected: themeProvider.selectedTheme == AppTheme.pixel,
                  onTap: () => themeProvider.setTheme(AppTheme.pixel),
                ),
                
                const SizedBox(height: 16),
                
                // تم صورتی
                _ThemeCard(
                  title: 'Pink Theme 💕',
                  description: 'Cute pink theme with day & night versions',
                  icon: Icons.favorite,
                  color: const Color(0xFFFF69B4), // Hot pink
                  warningColor: const Color(0xFFFF1493), // Deep pink
                  isSelected: themeProvider.selectedTheme == AppTheme.pink,
                  onTap: () => themeProvider.setTheme(AppTheme.pink),
                ),
                
                const SizedBox(height: 16),
                
                // تم بارانی
                _ThemeCard(
                  title: 'Rain Theme 🌧️',
                  description: 'Rainy day atmosphere (Dark mode only)',
                  icon: Icons.water_drop,
                  color: Colors.blue,
                  warningColor: Colors.lightBlue,
                  isSelected: themeProvider.selectedTheme == AppTheme.rain,
                  onTap: () => themeProvider.setTheme(AppTheme.rain),
                ),
                
                const SizedBox(height: 24),
                
                // توضیحات
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: isDark ? Colors.white54 : Colors.black54,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'When a theme is active, dark mode toggle is disabled',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final String? warning;
  final Color? warningColor;

  const _ThemeCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.warning,
    this.warningColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected 
                  ? color
                  : (isDark ? Colors.white12 : Colors.black12),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // آیکون
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
              
              const SizedBox(width: 16),
              
              // متن
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                    if (warning != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        warning!,
                        style: TextStyle(
                          fontSize: 11,
                          color: warningColor ?? Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // چک مارک
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: color,
                  size: 28,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card that lets the user pick (or clear) a custom background image for the
/// DEFAULT theme. A separate image is stored per day/night mode, so the label
/// reflects which one is being edited.
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

      // Copy the picked image into the app's private storage so it survives even
      // if the original is deleted/moved, and store a per-mode filename.
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
