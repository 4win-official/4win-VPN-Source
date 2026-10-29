import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user's in-app language choice independently of device language.
class AppLocaleProvider extends ChangeNotifier {
  static const String preferenceKey = 'app_language';
  static const MethodChannel _notificationLocaleChannel = MethodChannel(
    'com.forwin.vpn/app_locale',
  );

  Locale _locale = const Locale('en');
  bool _hasSavedChoice = false;
  Future<void>? _loadFuture;

  Locale get locale => _locale;
  bool get hasSavedChoice => _hasSavedChoice;
  String get languageCode => _locale.languageCode;

  Future<void> load() => _loadFuture ??= _loadSavedChoice();

  Future<void> _loadSavedChoice() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(preferenceKey);
      if (saved == 'fa' || saved == 'en') {
        _locale = Locale(saved!);
        _hasSavedChoice = true;
      }
    } catch (_) {
      // Keep the existing English appearance if preferences are unavailable.
    }
    notifyListeners();
  }

  Future<void> setLanguage(String languageCode) async {
    final normalized = languageCode == 'fa' ? 'fa' : 'en';
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferenceKey, normalized);
    _locale = Locale(normalized);
    _hasSavedChoice = true;
    notifyListeners();
    try {
      await _notificationLocaleChannel.invokeMethod<void>(
        'refreshNotifications',
      );
    } catch (_) {
      // Widget tests and non-Android hosts have no native notification channel.
    }
  }
}
