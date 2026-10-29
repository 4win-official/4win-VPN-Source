import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/l10n/app_localizations.dart';
import 'package:vpn_swift/providers/app_locale_provider.dart';
import 'package:vpn_swift/screens/language_selection_screen.dart';
import 'package:vpn_swift/widgets/app_language_setting.dart';

Widget _app(AppLocaleProvider provider, Widget home) {
  return ChangeNotifierProvider<AppLocaleProvider>.value(
    value: provider,
    child: Consumer<AppLocaleProvider>(
      builder: (context, locale, _) => MaterialApp(
        locale: locale.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first launch asks once and saves the selected language', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppLocaleProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _app(provider, const LanguageGate(child: Text('Main content'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('فارسی'), findsOneWidget);
    expect(find.text('Main content'), findsNothing);

    await tester.tap(find.text('فارسی'));
    await tester.pumpAndSettle();

    expect(find.text('Main content'), findsOneWidget);
    expect(find.text('Choose your language'), findsNothing);
    expect(provider.languageCode, 'fa');
    expect(provider.hasSavedChoice, isTrue);
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection,
      TextDirection.rtl,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        AppLocaleProvider.preferenceKey,
      ),
      'fa',
    );
  });

  testWidgets('first launch can choose English and saves it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppLocaleProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _app(provider, const LanguageGate(child: Text('Main content'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Main content'), findsOneWidget);
    expect(find.text('Choose your language'), findsNothing);
    expect(provider.languageCode, 'en');
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection,
      TextDirection.ltr,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        AppLocaleProvider.preferenceKey,
      ),
      'en',
    );
  });

  testWidgets('a saved language skips the first-run chooser', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'fa'});
    final provider = AppLocaleProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _app(provider, const LanguageGate(child: Text('Main content'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Main content'), findsOneWidget);
    expect(find.text('Choose your language'), findsNothing);
    expect(provider.languageCode, 'fa');
  });

  testWidgets('General Settings can change Persian back to English', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_language': 'fa'});
    final provider = AppLocaleProvider();
    await provider.load();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      _app(provider, const Scaffold(body: AppLanguageSetting())),
    );
    await tester.pumpAndSettle();
    expect(find.text('زبان'), findsOneWidget);
    expect(find.text('فارسی'), findsOneWidget);

    await tester.tap(find.text('زبان'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(provider.languageCode, 'en');
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString(
        AppLocaleProvider.preferenceKey,
      ),
      'en',
    );
  });

  test(
    'catalog translates interface text, interpolates safely, and falls back',
    () {
      final persian = AppLocalizations(const Locale('fa'));
      final english = AppLocalizations(const Locale('en'));

      expect(persian.text('Settings'), 'تنظیمات');
      expect(
        persian.text('Candidate resolvers (3)'),
        'حل‌کننده‌های پیشنهادی (3)',
      );
      expect(
        persian.text('A user-provided server label'),
        'A user-provided server label',
      );
      expect(english.text('Settings'), 'Settings');
    },
  );
}
