import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme {
  system,  // دیفالت - دارک/لایت عادی
  snow,    // تم برفی
  pixel,   // تم پیکسلی
  pink,    // تم صورتی کیوت (فقط لایت مود)
  rain,    // تم بارانی
}

class ThemeProvider with ChangeNotifier {
  static const String _darkModeKey = 'is_dark_mode';
  static const String _themeKey = 'selected_theme';
  
  bool _isDarkMode = false;
  AppTheme _selectedTheme = AppTheme.system;

  bool get isDarkMode => _isDarkMode;
  AppTheme get selectedTheme => _selectedTheme;
  bool get isThemeActive => _selectedTheme != AppTheme.system;

  ThemeProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_darkModeKey) ?? false;
    final themeIndex = prefs.getInt(_themeKey) ?? 0;
    _selectedTheme = AppTheme.values[themeIndex];
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    // تم برفی، صورتی و بارانی قفل هستند
    if (_selectedTheme == AppTheme.snow || _selectedTheme == AppTheme.pink || _selectedTheme == AppTheme.rain) return;
    
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, _isDarkMode);
    notifyListeners();
  }

  Future<void> setTheme(AppTheme theme) async {
    _selectedTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, theme.index);
    
    // تم برفی: دارک مود فعال
    if (theme == AppTheme.snow) {
      _isDarkMode = true;
      await prefs.setBool(_darkModeKey, true);
    }
    
    // تم صورتی: فقط لایت مود
    if (theme == AppTheme.pink) {
      _isDarkMode = false;
      await prefs.setBool(_darkModeKey, false);
    }
    
    // تم بارانی: دارک مود فعال
    if (theme == AppTheme.rain) {
      _isDarkMode = true;
      await prefs.setBool(_darkModeKey, true);
    }
    
    notifyListeners();
  }

  ThemeData get lightTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
      );

  ThemeData get darkTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      );

  ThemeData get currentTheme => _isDarkMode ? darkTheme : lightTheme;
}
