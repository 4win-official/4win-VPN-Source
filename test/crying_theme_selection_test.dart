import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/screens/theme_selection_screen.dart';

Future<ThemeProvider> _newProvider() async {
  final provider = ThemeProvider();
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('preserves all persisted theme indices, including Cat at index 9', () {
    expect(AppTheme.system.index, 0);
    expect(AppTheme.snow.index, 1);
    expect(AppTheme.pixel.index, 2);
    expect(AppTheme.pink.index, 3);
    expect(AppTheme.rain.index, 4);
    expect(AppTheme.summer.index, 5);
    expect(AppTheme.autumn.index, 6);
    expect(AppTheme.liquidGlass.index, 7);
    expect(AppTheme.crying.index, 8);
    expect(AppTheme.cat.index, 9);
  });

  test('migrates saved Crying and invalid indices to System Default', () async {
    for (final savedIndex in <int>[AppTheme.crying.index, -1, 999]) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'selected_theme': savedIndex,
      });
      final provider = await _newProvider();
      addTearDown(provider.dispose);
      expect(provider.selectedTheme, AppTheme.system);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('selected_theme'), AppTheme.system.index);
    }
  });

  test('setting legacy Crying normalizes to System Default', () async {
    final provider = await _newProvider();
    addTearDown(provider.dispose);

    await provider.setTheme(AppTheme.crying);

    expect(provider.selectedTheme, AppTheme.system);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('selected_theme'), AppTheme.system.index);
  });

  testWidgets('ThemeSelectionScreen does not offer Crying', (tester) async {
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(_themeApp(provider));
    await tester.pumpAndSettle();

    expect(find.text('Crying'), findsNothing);
    expect(
      find.text('Little tears, soft comfort (Light + Dark)'),
      findsNothing,
    );
    await tester.scrollUntilVisible(find.text('Cat'), 200);
    expect(find.text('Cat'), findsOneWidget);
    expect(find.text('Crying'), findsNothing);
  });
}
