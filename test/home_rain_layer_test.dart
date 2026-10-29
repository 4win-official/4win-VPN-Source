import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/vpn_server.dart';
import 'package:vpn_swift/models/openvpn_config.dart';
import 'package:vpn_swift/providers/app_mode_provider.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/home_screen.dart';
import 'package:vpn_swift/widgets/glass_power_button_surface.dart';
import 'package:vpn_swift/widgets/rain_animation.dart';
import 'package:vpn_swift/widgets/rain_button_surface.dart';
import 'package:vpn_swift/widgets/snow_button_surface.dart';

class FakeVpnProvider implements VpnProvider {
  int connectCalls = 0;
  int disconnectCalls = 0;
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  @override
  Future<({String username, String password})?> Function(OpenVpnConfig config)?
  onOpenVpnCredentialsRequired;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  bool get isConnected => false;

  @override
  bool get isConnecting => false;

  @override
  bool get isLoadingServers => false;

  @override
  String get selectedProtocol => 'xray';

  @override
  List<VpnServer> get servers => const <VpnServer>[];

  @override
  VpnConnectionStatus get status => VpnConnectionStatus.disconnected;

  @override
  Duration get connectionDuration => Duration.zero;

  @override
  String get dataUsage => '0 B';

  @override
  String get downloadDataUsage => '0 B';

  @override
  String get uploadDataUsage => '0 B';

  @override
  Future<void> connect({bool forceBypassCert = false}) async => connectCalls++;

  @override
  Future<void> disconnect({bool preserveSimpleAttempt = false}) async =>
      disconnectCalls++;

  @override
  noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #errorMessage || name == #protocolDiagnostics) return null;
    if (name == #activeProxyServer ||
        name == #activeXrayServer ||
        name == #selectedProxyServer ||
        name == #selectedXrayServer ||
        name == #warpAccount) {
      return null;
    }
    if (name == #proxyGroupSelected ||
        name == #xrayFreeGroupSelected ||
        name == #warpRegistering ||
        name == #xrayPinging ||
        name == #xrayPingAwaitingFirstTap ||
        name == #pingFailed) {
      return false;
    }
    return super.noSuchMethod(invocation);
  }
}

Future<void> pumpHome(
  WidgetTester tester,
  FakeVpnProvider provider, {
  TextDirection? textDirection,
}) async {
  final appMode = AppModeProvider();
  await appMode.setMode(AppExperienceMode.advanced);
  final themeProvider = ThemeProvider();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppModeProvider>.value(value: appMode),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<VpnProvider>.value(value: provider),
      ],
      child: MaterialApp(
        home: textDirection == null
            ? const HomeScreen()
            : Directionality(
                textDirection: textDirection,
                child: const HomeScreen(),
              ),
      ),
    ),
  );
  // ThemeProvider loads its persisted selection asynchronously. The extra
  // frame also lets HomeScreen install its post-frame callbacks.
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'guide_seen': true,
      'selected_theme': AppTheme.rain.index,
      'is_dark_mode': true,
    });
  });

  testWidgets(
    'rain overlay is last, ignores gestures, and follows theme changes',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      final provider = FakeVpnProvider();
      await pumpHome(tester, provider);

      expect(find.byType(GlassPowerButtonSurface), findsNothing);
      final rain = find.byType(RainAnimation);
      expect(rain, findsOneWidget);
      final mainStack = tester.widget<Stack>(
        find.ancestor(of: rain, matching: find.byType(Stack)).first,
      );
      final lastChild = mainStack.children.last;
      expect(lastChild, isA<Positioned>());
      expect(
        find.descendant(of: find.byWidget(lastChild), matching: rain),
        findsOneWidget,
      );

      final ignoringWrapper = find.descendant(
        of: rain,
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      );
      expect(ignoringWrapper, findsOneWidget);

      final power = find.byIcon(Icons.power_settings_new);
      expect(power, findsOneWidget);
      await tester.tap(power);
      expect(provider.connectCalls, 1);

      await tester.longPress(power);
      await tester.pump();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(RainButtonSurface), findsOneWidget);
      expect(
        tester
            .widget<RainButtonSurface>(find.byType(RainButtonSurface))
            .enabled,
        isTrue,
      );

      final themes = Provider.of<ThemeProvider>(
        tester.element(find.byType(HomeScreen)),
        listen: false,
      );
      await themes.setTheme(AppTheme.snow);
      await tester.pump();
      expect(find.byType(SnowButtonSurface), findsOneWidget);
      expect(
        tester
            .widget<SnowButtonSurface>(find.byType(SnowButtonSurface))
            .enabled,
        isTrue,
      );
      expect(find.byType(GlassPowerButtonSurface), findsNothing);
      expect(find.byType(RainButtonSurface), findsOneWidget);
      expect(
        tester
            .widget<RainButtonSurface>(find.byType(RainButtonSurface))
            .enabled,
        isFalse,
      );
      expect(find.byType(RainAnimation), findsNothing);

      await themes.setTheme(AppTheme.system);
      await tester.pump();
      expect(find.byType(RainAnimation), findsNothing);
      expect(find.byType(GlassPowerButtonSurface), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('power-button'))).size,
        const Size(200, 200),
      );
      expect(find.byType(SnowButtonSurface), findsOneWidget);
      expect(
        tester
            .widget<SnowButtonSurface>(find.byType(SnowButtonSurface))
            .enabled,
        isFalse,
      );
      expect(find.byType(RainButtonSurface), findsOneWidget);
      expect(
        tester
            .widget<RainButtonSurface>(find.byType(RainButtonSurface))
            .enabled,
        isFalse,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
