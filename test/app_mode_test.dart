import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/app_locale_provider.dart';
import 'package:vpn_swift/providers/app_mode_provider.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/screens/simple_mode_screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first run asks for a mode and saves the selected choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final mode = AppModeProvider();
    addTearDown(mode.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppModeProvider>.value(
        value: mode,
        child: const MaterialApp(
          home: AppModeGate(child: Text('App content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('How would you like to use the app?'), findsOneWidget);
    expect(find.text('App content'), findsNothing);
    await tester.tap(find.text('Simple'));
    await tester.pumpAndSettle();

    expect(find.text('App content'), findsOneWidget);
    expect(mode.hasSavedChoice, isTrue);
    expect(mode.isSimpleMode, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getString(
        AppModeProvider.preferenceKey,
      ),
      'simple',
    );
  });

  testWidgets('Simple settings contains the switch to Advanced action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeProvider();
    final locale = AppLocaleProvider();
    addTearDown(theme.dispose);
    addTearDown(locale.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AppLocaleProvider>.value(value: locale),
        ],
        child: const MaterialApp(home: SimpleSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch to Advanced'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('mode changes write only the dedicated mode preference', () async {
    SharedPreferences.setMockInitialValues({
      'selected_theme': AppTheme.cat.index,
      'is_dark_mode': true,
      'connection_mode': 'proxy',
      'selected_protocol': 'openvpn',
    });
    final mode = AppModeProvider();
    addTearDown(mode.dispose);

    await mode.load();
    expect(mode.hasSavedChoice, isFalse);
    await mode.setMode(AppExperienceMode.advanced);
    final preferences = await SharedPreferences.getInstance();

    expect(preferences.getString(AppModeProvider.preferenceKey), 'advanced');
    expect(preferences.getInt('selected_theme'), AppTheme.cat.index);
    expect(preferences.getBool('is_dark_mode'), isTrue);
    expect(preferences.getString('connection_mode'), 'proxy');
    expect(preferences.getString('selected_protocol'), 'openvpn');
  });

  testWidgets('Simple brightness is separate from the saved Advanced theme', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'selected_theme': AppTheme.cat.index,
      'is_dark_mode': true,
    });
    final theme = ThemeProvider();
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    theme.setSimpleMode(true);
    expect(theme.selectedTheme, AppTheme.system);
    expect(theme.isDarkMode, isFalse);
    await theme.setSimpleDarkMode(true);
    expect(theme.isDarkMode, isTrue);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('selected_theme'), AppTheme.cat.index);
    expect(preferences.getBool('is_dark_mode'), isTrue);
    expect(preferences.getBool('simple_is_dark_mode'), isTrue);

    theme.setSimpleMode(false);
    expect(theme.selectedTheme, AppTheme.cat);
    expect(theme.isDarkMode, isTrue);
  });
}
