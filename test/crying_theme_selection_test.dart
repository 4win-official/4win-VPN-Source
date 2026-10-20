import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/screens/theme_selection_screen.dart';

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

  test('keeps the existing AppTheme indices and appends crying', () {
    expect(AppTheme.system.index, 0);
    expect(AppTheme.snow.index, 1);
    expect(AppTheme.pixel.index, 2);
    expect(AppTheme.pink.index, 3);
    expect(AppTheme.rain.index, 4);
    expect(AppTheme.summer.index, 5);
    expect(AppTheme.autumn.index, 6);
    expect(AppTheme.liquidGlass.index, 7);
    expect(AppTheme.crying.index, 8);
  });

  test(
    'crying selection preserves brightness in light and dark modes',
    () async {
      for (final brightness in Brightness.values) {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final provider = await _newProvider();
        addTearDown(provider.dispose);

        if (brightness == Brightness.dark) {
          await provider.toggleTheme();
        }
        await provider.setTheme(AppTheme.crying);

        expect(provider.selectedTheme, AppTheme.crying);
        expect(provider.isDarkMode, brightness == Brightness.dark);
        expect(provider.currentTheme.brightness, brightness);
        expect(provider.isModeLocked, isFalse);
      }
    },
  );

  test(
    'crying toggles both ways and restores persisted theme and brightness',
    () async {
      final provider = await _newProvider();
      await provider.setTheme(AppTheme.crying);
      expect(provider.isDarkMode, isFalse);
      await provider.toggleTheme();
      expect(provider.isDarkMode, isTrue);
      await provider.toggleTheme();
      expect(provider.isDarkMode, isFalse);
      await provider.toggleTheme();
      expect(provider.isDarkMode, isTrue);
      provider.dispose();

      final restored = await _newProvider();
      addTearDown(restored.dispose);
      expect(restored.selectedTheme, AppTheme.crying);
      expect(restored.isDarkMode, isTrue);
      expect(restored.currentTheme.brightness, Brightness.dark);
    },
  );

  test(
    'crying has pastel-purple seeds and distinct light and dark surfaces',
    () async {
      final provider = await _newProvider();
      addTearDown(provider.dispose);
      await provider.setTheme(AppTheme.crying);

      final light = provider.currentTheme;
      final expectedLight = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7863B5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFF6FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFF6FB),
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
      );
      expect(light.brightness, Brightness.light);
      expect(light.colorScheme.primary, expectedLight.colorScheme.primary);
      expect(light.scaffoldBackgroundColor, const Color(0xFFFFF6FB));

      await provider.toggleTheme();
      final dark = provider.currentTheme;
      final expectedDark = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB9AEFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF17172F),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF17172F),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      );
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.primary, expectedDark.colorScheme.primary);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF17172F));
      expect(light.colorScheme.surface, isNot(dark.colorScheme.surface));
      expect(
        light.scaffoldBackgroundColor,
        isNot(dark.scaffoldBackgroundColor),
      );
      expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
    },
  );

  testWidgets(
    'ThemeSelectionScreen selects crying and toggles day and night both ways',
    (tester) async {
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(_themeApp(provider));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Crying'), 250);
      expect(find.text('Crying'), findsOneWidget);
      expect(
        find.text('Little tears, soft comfort (Light + Dark)'),
        findsOneWidget,
      );
      final cryingCard = _card('Crying');
      expect(cryingCard, findsOneWidget);
      await tester.ensureVisible(cryingCard);
      await tester.tap(cryingCard);
      await tester.pumpAndSettle();
      expect(provider.selectedTheme, AppTheme.crying);
      expect(provider.isDarkMode, isFalse);

      await tester.scrollUntilVisible(find.byType(Switch), -400);
      final toggle = find.byType(Switch);
      expect(toggle, findsOneWidget);
      expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
      expect(tester.widget<Switch>(toggle).value, isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(provider.isDarkMode, isTrue);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(tester.widget<Switch>(toggle).onChanged, isNotNull);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(provider.isDarkMode, isFalse);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(tester.widget<Switch>(toggle).onChanged, isNotNull);

      // A reactive rebuild must retain both the selected card and enabled switch.
      expect(provider.selectedTheme, AppTheme.crying);
      expect(
        find.text('Little tears, soft comfort (Light + Dark)'),
        findsOneWidget,
      );
    },
  );
}
