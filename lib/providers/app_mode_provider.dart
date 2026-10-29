import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppExperienceMode { simple, advanced }

/// Persists only which interface the user wants to see. It deliberately does
/// not migrate or modify any protocol, server, theme, or connection settings.
class AppModeProvider extends ChangeNotifier {
  static const String preferenceKey = 'app_experience_mode';

  AppExperienceMode _mode = AppExperienceMode.simple;
  bool _hasSavedChoice = false;
  Future<void>? _loadFuture;

  AppExperienceMode get mode => _mode;
  bool get isSimpleMode => _mode == AppExperienceMode.simple;
  bool get hasSavedChoice => _hasSavedChoice;

  Future<void> load() => _loadFuture ??= _loadSavedChoice();

  Future<void> _loadSavedChoice() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(preferenceKey);
      if (saved == 'simple' || saved == 'advanced') {
        _mode = saved == 'simple'
            ? AppExperienceMode.simple
            : AppExperienceMode.advanced;
        _hasSavedChoice = true;
      }
    } catch (_) {
      // Keep Simple as the effective default, but still show the first-run
      // choice screen so the preference can be saved if storage recovers.
    }
    notifyListeners();
  }

  Future<void> setMode(AppExperienceMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      preferenceKey,
      mode == AppExperienceMode.simple ? 'simple' : 'advanced',
    );
    _mode = mode;
    _hasSavedChoice = true;
    notifyListeners();
  }
}
