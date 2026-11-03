import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/screens/theme_selection_screen.dart';
import 'package:vpn_swift/widgets/black_hole_background.dart';

Future<ThemeProvider> _newProvider() async {
  final provider = ThemeProvider();
  await Future<void>.delayed(Duration.zero);
  return provider;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Black Hole is appended without changing saved theme indices', () {
    expect(AppTheme.liquidGlass.index, 7);
    expect(AppTheme.crying.index, 8);
    expect(AppTheme.cat.index, 9);
    expect(AppTheme.blackHole.index, 10);
  });

  test('Black Hole selects, persists, and stays in dark mode', () async {
    final provider = await _newProvider();
    addTearDown(provider.dispose);

    await provider.setTheme(AppTheme.blackHole);
    expect(provider.selectedTheme, AppTheme.blackHole);
    expect(provider.isDarkMode, isTrue);
    expect(provider.currentTheme.brightness, Brightness.dark);
    expect(
      provider.currentTheme.scaffoldBackgroundColor,
      const Color(0xFF05060B),
    );
    expect(provider.isModeLocked, isTrue);

    await provider.toggleTheme();
    expect(provider.isDarkMode, isTrue);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('selected_theme'), AppTheme.blackHole.index);
    expect(preferences.getBool('is_dark_mode'), isTrue);
  });

  testWidgets('Advanced theme picker offers and selects Black Hole', (
    tester,
  ) async {
    final provider = await _newProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: const MaterialApp(home: ThemeSelectionScreen()),
      ),
    );

    expect(find.text('Black Hole'), findsOneWidget);
    expect(
      find.text('Event-horizon glow · deep-space lensing'),
      findsOneWidget,
    );
    expect(find.byType(BlackHoleEmblem), findsOneWidget);

    final card = find.ancestor(
      of: find.text('Black Hole'),
      matching: find.byType(InkWell),
    );
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pump();

    expect(provider.selectedTheme, AppTheme.blackHole);
    expect(provider.isDarkMode, isTrue);
  });
}
