import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';

Future<ThemeProvider> _provider() async {
  final provider = ThemeProvider();
  // ThemeProvider loads preferences from its constructor asynchronously.
  await Future<void>.delayed(Duration.zero);
  return provider;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('summer keeps its persisted enum index and restores brightness', () async {
    expect(AppTheme.summer.index, 5);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'selected_theme': AppTheme.summer.index,
      'is_dark_mode': false,
    });

    final first = await _provider();
    expect(first.selectedTheme, AppTheme.summer);
    expect(first.isDarkMode, isFalse);
    await first.toggleTheme();

    final restarted = await _provider();
    expect(restarted.selectedTheme, AppTheme.summer);
    expect(restarted.isDarkMode, isTrue);
  });

  test('Day & Night toggle works in both directions', () async {
    final provider = await _provider();
    await provider.setTheme(AppTheme.summer);

    expect(provider.isDarkMode, isFalse);
    await provider.toggleTheme();
    expect(provider.isDarkMode, isTrue);
    await provider.toggleTheme();
    expect(provider.isDarkMode, isFalse);
  });

  test('selecting summer preserves the current mode', () async {
    final provider = await _provider();

    await provider.toggleTheme();
    expect(provider.isDarkMode, isTrue);
    await provider.setTheme(AppTheme.summer);
    expect(provider.isDarkMode, isTrue);

    await provider.toggleTheme();
    expect(provider.isDarkMode, isFalse);
    await provider.setTheme(AppTheme.summer);
    expect(provider.isDarkMode, isFalse);
  });

  test('rain and snow lock dark mode, while other themes remain toggleable', () async {
    final provider = await _provider();

    await provider.setTheme(AppTheme.rain);
    expect(provider.isModeLocked, isTrue);
    expect(provider.isDarkMode, isTrue);
    await provider.toggleTheme();
    expect(provider.isDarkMode, isTrue);

    await provider.setTheme(AppTheme.snow);
    expect(provider.isModeLocked, isTrue);
    expect(provider.isDarkMode, isTrue);
    await provider.toggleTheme();
    expect(provider.isDarkMode, isTrue);

    for (final theme in <AppTheme>[
      AppTheme.system,
      AppTheme.pixel,
      AppTheme.pink,
      AppTheme.summer,
      AppTheme.autumn,
      AppTheme.liquidGlass,
    ]) {
      await provider.setTheme(theme);
      expect(provider.isModeLocked, isFalse, reason: '$theme should be adaptive');
      final before = provider.isDarkMode;
      await provider.toggleTheme();
      expect(provider.isDarkMode, !before, reason: '$theme should toggle');
    }
  });
}
