import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_locale_provider.dart';
import 'providers/vpn_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/language_selection_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/openvpn_configs_screen.dart';
import 'services/ovpn_import_service.dart';
import 'services/connection_logger.dart';
import 'widgets/pixelation_filter.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool _homeReady = false;
void markHomeReady() => _homeReady = true;

void main() {
  // Restore the persisted log tail (events from before a restart/crash) so
  // the log viewer can show them; failures are swallowed inside.
  ConnectionLogger.instance.loadPersisted();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _handlingImport = false;

  @override
  void initState() {
    super.initState();
    OvpnImportService.instance.init();
    OvpnImportService.instance.onImportAvailable = _handlePendingImport;
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingImport());
  }

  Future<void> _handlePendingImport() async {
    if (_handlingImport) return;
    _handlingImport = true;
    try {
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      final ctx = nav.context;
      final pending = await OvpnImportService.instance.checkPending();
      if (pending == null) return;
      await _waitUntilHomeReady();
      try {
        await Provider.of<VpnProvider>(ctx, listen: false)
            .switchProtocol('openvpn');
      } catch (_) {}
      final currentNav = navigatorKey.currentState;
      if (currentNav == null) return;
      currentNav.push(MaterialPageRoute(
        builder: (_) => OpenVpnConfigsScreen(
          initialImportName: pending.name,
          initialImportContent: pending.content,
        ),
      ));
    } finally {
      _handlingImport = false;
    }
  }

  Future<void> _waitUntilHomeReady() async {
    for (var i = 0; i < 60; i++) {
      if (_homeReady) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppLocaleProvider()),
        ChangeNotifierProvider<VpnProvider>(
          create: (_) => VpnProvider(),
        ),
      ],
      child: Consumer2<ThemeProvider, AppLocaleProvider>(
        builder: (context, themeProvider, appLocale, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: context.l10n.text('4win VPN'),
            locale: appLocale.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode:
                themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) {
              final navigator = child ?? const SizedBox.shrink();
              if (themeProvider.selectedTheme == AppTheme.pixel) {
                return PixelationFilter(child: navigator);
              }
              return navigator;
            },
            home: const LanguageGate(child: LoadingScreen()),
          );
        },
      ),
    );
  }
}
