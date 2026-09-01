import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/vpn_provider.dart';
import 'providers/psiphon_vpn_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/loading_screen.dart';
import 'screens/openvpn_configs_screen.dart';
import 'services/ovpn_import_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
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
        ChangeNotifierProvider<VpnProvider>(
          create: (_) => PsiphonVpnProvider(),
        ),
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
            home: const LoadingScreen(),
          );
        },
      ),
    );
  }
}
