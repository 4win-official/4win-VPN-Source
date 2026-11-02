import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/l10n/app_localizations.dart';
import 'package:vpn_swift/services/ip_geolocation_service.dart';
import 'package:vpn_swift/services/vpn_service.dart';
import 'package:vpn_swift/widgets/simple_mode_world_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'connected-on-start looks up direct source and tunnel destination separately',
    (tester) async {
      var sourceLookupCalls = 0;
      var tunnelLookupCalls = 0;
      const source = IpLocation(
        countryCode: 'IR',
        countryName: 'Iran',
        latitude: 32.0,
        longitude: 53.0,
      );
      const destination = IpLocation(
        countryCode: 'DE',
        countryName: 'Germany',
        latitude: 51.0,
        longitude: 10.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 320,
              child: SimpleModeWorldMap(
                status: VpnConnectionStatus.connected,
                connecting: false,
                isDark: true,
                lookupSourceIpLocation: () async {
                  sourceLookupCalls++;
                  return source;
                },
                lookupCurrentIpLocation: () async {
                  tunnelLookupCalls++;
                  return destination;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sourceLookupCalls, 1);
      expect(tunnelLookupCalls, 1);
      expect(find.text('Your location'), findsOneWidget);
      expect(find.text('VPN location'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('simple-world-map-canvas')),
        findsOneWidget,
      );
    },
  );
}
