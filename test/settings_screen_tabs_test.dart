import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/app_locale_provider.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/settings_screen.dart';

class _TestVpnProvider extends ChangeNotifier implements VpnProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('settings has General and one tab for each protocol', (
    tester,
  ) async {
    final vpnProvider = _TestVpnProvider();
    final localeProvider = AppLocaleProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<VpnProvider>.value(
        value: vpnProvider,
        child: ChangeNotifierProvider<AppLocaleProvider>.value(
          value: localeProvider,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in const [
      'General',
      'Mix',
      'Xray',
      'Psiphon',
      'WARP',
      'OpenVPN',
      'SSTP',
      'DNS changer',
      'Proxy',
      'Slow DNS',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Security'), findsOneWidget);

    await tester.ensureVisible(find.text('OpenVPN'));
    await tester.tap(find.text('OpenVPN'));
    await tester.pumpAndSettle();
    expect(find.text('OpenVPN Settings'), findsOneWidget);
    expect(find.text('Security'), findsNothing);

    await tester.ensureVisible(find.text('General'));
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Split Tunneling'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    vpnProvider.dispose();
    localeProvider.dispose();
  });
}
