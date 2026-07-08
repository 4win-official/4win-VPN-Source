import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/vpn_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/loading_screen.dart';
import 'screens/openvpn_configs_screen.dart';
import 'services/ovpn_import_service.dart';

/// Global navigator key so we can route to the OpenVPN import screen from
/// outside the widget tree (e.g. when an .ovpn file is opened/shared).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Set to true by LoadingScreen once it has replaced itself with HomeScreen.
/// Used by the .ovpn cold-start import flow to avoid pushing the import screen
/// before the loading screen's pushReplacement wipes the navigation stack.
bool _homeReady = false;
void markHomeReady() => _homeReady = true;

void main() {
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
    // Listen for .ovpn files shared/opened while the app is already running.
    OvpnImportService.instance.init();
    OvpnImportService.instance.onImportAvailable = _handlePendingImport;
    // Cold start: an .ovpn may have launched the app.
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePendingImport());
  }

  /// Pulls any pending .ovpn from the native side and opens the OpenVPN config
  /// screen pre-loaded with it.
  Future<void> _handlePendingImport() async {
    if (_handlingImport) return;
    _handlingImport = true;
    try {
      // Capture the navigator/context BEFORE any await to avoid using a
      // BuildContext across an async gap.
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      final ctx = nav.context;

      final pending = await OvpnImportService.instance.checkPending();
      if (pending == null) return;

      // CRITICAL FIX: on a cold start the app first shows LoadingScreen and then
      // does Navigator.pushReplacement(HomeScreen). If we push the import screen
      // BEFORE that replacement, the replacement wipes the whole stack and our
      // import screen (and its dialog) vanish in a flash. So we wait until the
      // app has settled on the home screen (i.e. no more pushReplacement is
      // pending) before pushing the import screen on top of it.
      await _waitUntilHomeReady();

      // Switch the active protocol to OpenVPN so the imported config is usable.
      try {
        // ignore: use_build_context_synchronously
        await Provider.of<VpnProvider>(ctx, listen: false)
            .switchProtocol('openvpn');
      } catch (_) {
        // Provider not ready yet; the import screen still works standalone.
      }

      final currentNav = navigatorKey.currentState;
      if (currentNav == null) return;
      currentNav.push(
        MaterialPageRoute(
          builder: (_) => OpenVpnConfigsScreen(
            initialImportName: pending.name,
            initialImportContent: pending.content,
          ),
        ),
      );
    } finally {
      _handlingImport = false;
    }
  }

  /// Waits until the app is no longer on the transient LoadingScreen so the
  /// pushed import screen isn't destroyed by LoadingScreen's pushReplacement.
  Future<void> _waitUntilHomeReady() async {
    for (var i = 0; i < 60; i++) {
      // ~60 * 200ms = 12s max
      if (_homeReady) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => VpnProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: '4win VPN',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode:
                themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const LoadingScreen(), // شروع با Loading Screen
          );
        },
      ),
    );
  }
}
