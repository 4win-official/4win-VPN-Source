import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme {
  system, // دیفالت - دارک/لایت عادی
  snow, // تم برفی (فصلی)
  pixel, // تم پیکسلی
  pink, // تم صورتی کیوت
  rain, // تم بارانی (فصلی)
  summer, // Day & Night; keep this index for existing saved selections.
  autumn, // تم پاییزی - برگ‌ها می‌ریزند (فصلی)
  liquidGlass, // تم لیکویید گلس (دارک + لایت)
  crying, // Append only: preserve all existing persisted theme indices.
  cat, // Append only: Cat keeps every existing saved theme stable.
}

class ThemeProvider with ChangeNotifier {
  static const String _darkModeKey = 'is_dark_mode';
  static const String _themeKey = 'selected_theme';
  // Custom background images for the DEFAULT (system) theme only — one per
  // brightness, so day and night can each have their own picture.
  static const String _customBgLightKey = 'custom_bg_light';
  static const String _customBgDarkKey = 'custom_bg_dark';

  bool _isDarkMode = false;
  AppTheme _selectedTheme = AppTheme.system;
  String? _customBgLightPath;
  String? _customBgDarkPath;

  bool get isDarkMode => _isDarkMode;
  AppTheme get selectedTheme => _selectedTheme;
  bool get isThemeActive => _selectedTheme != AppTheme.system;

  /// The custom background image path for the CURRENT brightness — but ONLY for
  /// the default (system) theme. Other themes have their own fixed visuals, so
  /// this returns null for them. Returns null when the user hasn't set one.
  String? get customBackgroundPath {
    if (_selectedTheme != AppTheme.system) return null;
    return _isDarkMode ? _customBgDarkPath : _customBgLightPath;
  }

  ThemeProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_darkModeKey) ?? false;
    final themeIndex = prefs.getInt(_themeKey) ?? AppTheme.system.index;
    _selectedTheme = _themeFromPersistedIndex(themeIndex);
    // Crying was removed from the picker; old saved values safely fall back to
    // System Default and are rewritten so the migration is one-time.
    if (themeIndex != _selectedTheme.index) {
      await prefs.setInt(_themeKey, _selectedTheme.index);
    }
    _customBgLightPath = prefs.getString(_customBgLightKey);
    _customBgDarkPath = prefs.getString(_customBgDarkKey);
    notifyListeners();
  }

  /// Save a custom background image path for the current brightness (default
  /// theme only). Pass null to clear it.
  Future<void> setCustomBackground(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (_isDarkMode) {
      _customBgDarkPath = path;
      if (path == null) {
        await prefs.remove(_customBgDarkKey);
      } else {
        await prefs.setString(_customBgDarkKey, path);
      }
    } else {
      _customBgLightPath = path;
      if (path == null) {
        await prefs.remove(_customBgLightKey);
      } else {
        await prefs.setString(_customBgLightKey, path);
      }
    }
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    // Only the weather themes have a fixed brightness.
    if (isModeLocked) {
      return;
    }

    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, _isDarkMode);
    notifyListeners();
  }

  /// Whether the day/night toggle is locked for the currently-selected theme.
  bool get isModeLocked =>
      _selectedTheme == AppTheme.snow || _selectedTheme == AppTheme.rain;

  static AppTheme _themeFromPersistedIndex(int index) {
    if (index < 0 || index >= AppTheme.values.length) {
      return AppTheme.system;
    }
    final theme = AppTheme.values[index];
    return theme == AppTheme.crying ? AppTheme.system : theme;
  }

  Future<void> setTheme(AppTheme theme) async {
    final normalizedTheme = theme == AppTheme.crying ? AppTheme.system : theme;
    _selectedTheme = normalizedTheme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, normalizedTheme.index);

    // تم برفی: دارک مود فعال
    if (theme == AppTheme.snow) {
      _isDarkMode = true;
      await prefs.setBool(_darkModeKey, true);
    }

    // تم صورتی: حالا هم نسخه روز و هم نسخه شب دارد. هنگام انتخاب،
    // حالت فعلی دارک/لایت کاربر حفظ می‌شود و با دکمه تعویض قابل تغییر است.

    // تم بارانی: دارک مود فعال
    if (theme == AppTheme.rain) {
      _isDarkMode = true;
      await prefs.setBool(_darkModeKey, true);
    }

    // Day & Night and other adaptive themes preserve the current brightness.

    notifyListeners();
  }

  /// Accent/seed colour that varies by the selected theme so the whole app
  /// (buttons, switches, etc.) matches the chosen mood.
  Color get _seedColor {
    switch (_selectedTheme) {
      case AppTheme.pink:
        return const Color(0xFFFF69B4);
      case AppTheme.rain:
        return const Color(0xFF2196F3);
      case AppTheme.snow:
        return const Color(0xFF4FC3F7);
      case AppTheme.summer:
        return _isDarkMode ? const Color(0xFF9AB8FF) : const Color(0xFFFF9800);
      case AppTheme.autumn:
        return const Color(0xFFD35400);
      case AppTheme.liquidGlass:
        return const Color(0xFF5B8CFF);
      case AppTheme.crying:
        return const Color(0xFF4CAF50);
      case AppTheme.cat:
        return _isDarkMode ? const Color(0xFFAFD5C3) : const Color(0xFFAC6549);
      case AppTheme.pixel:
      case AppTheme.system:
        return const Color(0xFF4CAF50);
    }
  }

  ThemeData get lightTheme => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ),
    fontFamily: _selectedTheme == AppTheme.pixel ? 'monospace' : null,
    useMaterial3: true,
    scaffoldBackgroundColor: _selectedTheme == AppTheme.cat
        ? const Color(0xFFFFF8EE)
        : Colors.white,
    appBarTheme: AppBarTheme(
      backgroundColor: _selectedTheme == AppTheme.cat
          ? const Color(0xFFFFF8EE)
          : Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
    ),
  );

  ThemeData get darkTheme => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
    fontFamily: _selectedTheme == AppTheme.pixel ? 'monospace' : null,
    useMaterial3: true,
    scaffoldBackgroundColor: _selectedTheme == AppTheme.cat
        ? const Color(0xFF15252B)
        : const Color(0xFF121212),
    appBarTheme: AppBarTheme(
      backgroundColor: _selectedTheme == AppTheme.cat
          ? const Color(0xFF15252B)
          : const Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );

  ThemeData get currentTheme => _isDarkMode ? darkTheme : lightTheme;
}
