import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/screens/theme_selection_screen.dart';

const _themePersistenceKey = 'selected_theme';

Future<ThemeProvider> _newProvider() async {
  final provider = ThemeProvider();
  // ThemeProvider loads SharedPreferences from its constructor asynchronously.
  await Future<void>.delayed(Duration.zero);
  return provider;
}

Widget _themeApp(ThemeProvider provider) {
  return ChangeNotifierProvider<ThemeProvider>.value(
    value: provider,
    child: AnimatedBuilder(
      animation: provider,
      builder: (context, _) => MaterialApp(
        theme: provider.currentTheme,
        home: const ThemeSelectionScreen(),
      ),
    ),
  );
}

Finder _card(String title) {
  return find.ancestor(of: find.text(title), matching: find.byType(InkWell));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'preserves Liquid enum index 7 and restores an existing saved ID',
    () async {
      expect(AppTheme.liquidGlass.index, 7);

      SharedPreferences.setMockInitialValues(<String, Object>{
        _themePersistenceKey: AppTheme.liquidGlass.index,
      });
      final provider = await _newProvider();
      addTearDown(provider.dispose);

      expect(provider.selectedTheme, AppTheme.liquidGlass);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_themePersistenceKey), AppTheme.liquidGlass.index);
    },
  );

  testWidgets('ThemeSelectionScreen offers and selects Liquid', (tester) async {
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(_themeApp(provider));
    await tester.pumpAndSettle();

    expect(find.text('Liquid'), findsOneWidget);
    expect(find.text('Liquid Glass 🫧'), findsNothing);
    expect(
      find.text('Modern frosted-glass look (Light + Dark)'),
      findsOneWidget,
    );

    final liquidCard = _card('Liquid');
    expect(liquidCard, findsOneWidget);
    await tester.tap(liquidCard);
    await tester.pumpAndSettle();

    expect(provider.selectedTheme, AppTheme.liquidGlass);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(_themePersistenceKey), AppTheme.liquidGlass.index);
  });

  test(
    'Liquid preserves light and dark brightness and persists selection',
    () async {
      for (final brightness in Brightness.values) {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final provider = await _newProvider();
        addTearDown(provider.dispose);

        if (brightness == Brightness.dark) {
          await provider.toggleTheme();
        }
        await provider.setTheme(AppTheme.liquidGlass);

        expect(provider.selectedTheme, AppTheme.liquidGlass);
        expect(provider.isDarkMode, brightness == Brightness.dark);
        expect(provider.currentTheme.brightness, brightness);
        expect(provider.isModeLocked, isFalse);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(_themePersistenceKey), AppTheme.liquidGlass.index);
      }
    },
  );

  test(
    'Liquid toggles both ways without changing the selected theme',
    () async {
      final provider = await _newProvider();
      addTearDown(provider.dispose);
      await provider.setTheme(AppTheme.liquidGlass);

      expect(provider.isDarkMode, isFalse);
      await provider.toggleTheme();
      expect(provider.isDarkMode, isTrue);
      expect(provider.currentTheme.brightness, Brightness.dark);
      await provider.toggleTheme();
      expect(provider.isDarkMode, isFalse);
      expect(provider.currentTheme.brightness, Brightness.light);
      expect(provider.selectedTheme, AppTheme.liquidGlass);
    },
  );
}
