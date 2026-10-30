import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/app_locale_provider.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/screens/simple_mode_screens.dart';
import 'package:vpn_swift/screens/split_tunnel_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Simple Settings opens the shared Split Tunneling screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeProvider();
    final locale = AppLocaleProvider();
    addTearDown(theme.dispose);
    addTearDown(locale.dispose);

    const appsChannel = MethodChannel('com.forwin.vpn/apps');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(appsChannel, (call) async => []);
    addTearDown(() => messenger.setMockMethodCallHandler(appsChannel, null));

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

    expect(find.text('Split Tunneling'), findsOneWidget);
    await tester.tap(find.text('Choose apps & websites'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump();

    expect(find.byType(SplitTunnelScreen), findsOneWidget);
    expect(find.text('Only selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
