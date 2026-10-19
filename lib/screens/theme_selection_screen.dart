import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'default_theme_settings_screen.dart';

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
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
            final bool toggleLocked = themeProvider.isModeLocked;
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

                // ── System default theme (with its OWN settings gear) ──────
                _ThemeCard(
                  title: 'System Default',
                  description: 'Use light/dark mode',
                  icon: Icons.brightness_auto,
                  color: Colors.grey,
                  isSelected:
                      themeProvider.selectedTheme == AppTheme.system,
                  onTap: () => themeProvider.setTheme(AppTheme.system),
                  // Gear -> dedicated default-theme settings (background picker).
                  onSettings: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DefaultThemeSettingsScreen(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Liquid Glass (highlighted, new premium theme) ──────────
                _ThemeCard(
                  title: 'Liquid Glass 🫧',
                  description:
                      'Modern frosted-glass look (Light + Dark)',
                  icon: Icons.blur_on,
                  color: const Color(0xFF5B8CFF),
                  isSelected:
                      themeProvider.selectedTheme == AppTheme.liquidGlass,
                  onTap: () =>
                      themeProvider.setTheme(AppTheme.liquidGlass),
                ),

                const SizedBox(height: 16),

                // ── Pixel theme ────────────────────────────────────────────
                _ThemeCard(
                  title: 'Pixel Theme 🎮',
                  description: 'Retro 8-bit pixelated style (Light + Dark)',
                  icon: Icons.grid_4x4,
                  color: Colors.purple,
                  isSelected: themeProvider.selectedTheme == AppTheme.pixel,
                  onTap: () => themeProvider.setTheme(AppTheme.pixel),
                ),

                const SizedBox(height: 16),

                // ── Pink theme ─────────────────────────────────────────────
                _ThemeCard(
                  title: 'Pink Theme 💕',
                  description: 'Cute pink theme with day & night versions',
                  icon: Icons.favorite,
                  color: const Color(0xFFFF69B4),
                  warningColor: const Color(0xFFFF1493),
                  isSelected: themeProvider.selectedTheme == AppTheme.pink,
                  onTap: () => themeProvider.setTheme(AppTheme.pink),
                ),

                const SizedBox(height: 24),

                // ── Seasonal Themes group ──────────────────────────────────
                _GroupHeader(
                  title: 'Seasonal Themes',
                  subtitle: 'Rain · Snow · Day & Night · Autumn',
                  icon: Icons.calendar_today,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _SeasonalGroup(
                  isDark: isDark,
                  themeProvider: themeProvider,
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
                          'Some themes use a fixed day/night mode, so the toggle '
                          'above is disabled while they are active.',
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

/// Header shown above a group of related themes (e.g. seasonal themes).
class _GroupHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isDark;

  const _GroupHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: isDark ? Colors.white70 : Colors.black54),
        const SizedBox(width: 8),
        Column(
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
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The visually-grouped container that holds the four seasonal themes so they
/// clearly read as one "Seasonal Themes" group with sub-items.
class _SeasonalGroup extends StatelessWidget {
  final bool isDark;
  final ThemeProvider themeProvider;

  const _SeasonalGroup({
    required this.isDark,
    required this.themeProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Column(
        children: [
          _ThemeCard(
            title: 'Rain Theme 🌧️',
            description: 'Rainy day atmosphere (Dark mode only)',
            icon: Icons.water_drop,
            color: Colors.blue,
            warningColor: Colors.lightBlue,
            isSelected: themeProvider.selectedTheme == AppTheme.rain,
            onTap: () => themeProvider.setTheme(AppTheme.rain),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          _ThemeCard(
            title: 'Day & Night',
            description: 'Golden sun by day, moonlit sky by night',
            icon: isDark ? Icons.nightlight_round : Icons.wb_sunny,
            color: isDark ? const Color(0xFF9AB8FF) : const Color(0xFFFF9800),
            warningColor: const Color(0xFFFFB300),
            isSelected: themeProvider.selectedTheme == AppTheme.summer,
            onTap: () => themeProvider.setTheme(AppTheme.summer),
          ),
          const SizedBox(height: 10),
          _ThemeCard(
            title: 'Autumn Theme 🍂',
            description: 'Falling leaves (Light + Dark)',
            icon: Icons.park,
            color: const Color(0xFFD35400),
            warningColor: const Color(0xFFE67E22),
            isSelected: themeProvider.selectedTheme == AppTheme.autumn,
            onTap: () => themeProvider.setTheme(AppTheme.autumn),
          ),
        ],
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

  /// Optional settings gear (only the default theme uses it for now).
  final VoidCallback? onSettings;

  const _ThemeCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.warning,
    this.warningColor,
    this.onSettings,
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

              // Settings gear (default theme only)
              if (onSettings != null)
                IconButton(
                  icon: Icon(
                    Icons.settings,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  tooltip: 'Theme settings',
                  onPressed: onSettings,
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
