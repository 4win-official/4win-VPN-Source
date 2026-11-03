import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/l10n/app_localizations.dart';
import 'package:vpn_swift/services/ip_geolocation_service.dart';
import 'package:vpn_swift/services/vpn_service.dart';
import 'package:vpn_swift/widgets/simple_mode_world_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const directLocation = IpLocation(
    countryCode: 'IR',
    countryName: 'Iran',
    latitude: 32.0,
    longitude: 53.0,
  );
  const exitLocation = IpLocation(
    countryCode: 'DE',
    countryName: 'Germany',
    latitude: 51.0,
    longitude: 10.0,
  );

  Future<void> pumpMap(
    WidgetTester tester, {
    required VpnConnectionStatus status,
    IpLocationLookup? lookupSourceIpLocation,
    IpLocationLookup? lookupCurrentIpLocation,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 320,
            child: SimpleModeWorldMap(
              status: status,
              connecting: false,
              isDark: true,
              lookupSourceIpLocation: lookupSourceIpLocation,
              lookupCurrentIpLocation: lookupCurrentIpLocation,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('the bundled boundaries contain the two representative countries', () async {
    final decoded =
        jsonDecode(
              await rootBundle.loadString('assets/maps/world_countries.json'),
            )
            as List<dynamic>;
    final countries = decoded.whereType<Map<String, dynamic>>();
    expect(countries.any((country) => country['c'] == 'IR'), isTrue);
    expect(countries.any((country) => country['c'] == 'DE'), isTrue);
  });

  testWidgets('disconnected state focuses the returned direct-IP country', (
    tester,
  ) async {
    var directLookupCalls = 0;
    var currentLookupCalls = 0;
    await pumpMap(
      tester,
      status: VpnConnectionStatus.disconnected,
      lookupSourceIpLocation: () async {
        directLookupCalls++;
        return directLocation;
      },
      lookupCurrentIpLocation: () async {
        currentLookupCalls++;
        return exitLocation;
      },
    );

    expect(directLookupCalls, 1);
    expect(currentLookupCalls, 0);
    expect(find.text('Direct IP · Iran'), findsOneWidget);
    expect(find.textContaining('VPN exit'), findsNothing);
    expect(
      find.byKey(const ValueKey('simple-world-map-location-IR')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('simple-world-map-canvas')),
      findsOneWidget,
    );
  });

  testWidgets('connected state focuses only the measured VPN-exit country', (
    tester,
  ) async {
    var sourceLookupCalls = 0;
    var exitLookupCalls = 0;
    await pumpMap(
      tester,
      status: VpnConnectionStatus.connected,
      lookupSourceIpLocation: () async {
        sourceLookupCalls++;
        return directLocation;
      },
      lookupCurrentIpLocation: () async {
        exitLookupCalls++;
        return exitLocation;
      },
    );

    expect(sourceLookupCalls, 1);
    expect(exitLookupCalls, 1);
    expect(find.text('VPN exit · Germany'), findsOneWidget);
    expect(find.textContaining('Direct IP'), findsNothing);
    expect(
      find.byKey(const ValueKey('simple-world-map-location-DE')),
      findsOneWidget,
    );
  });

  testWidgets('connected state never relabels a VPN exit as the direct IP', (
    tester,
  ) async {
    var exitLookupCalls = 0;
    await pumpMap(
      tester,
      status: VpnConnectionStatus.connected,
      lookupCurrentIpLocation: () async {
        exitLookupCalls++;
        return exitLocation;
      },
    );

    expect(exitLookupCalls, 1);
    expect(find.text('VPN exit · Germany'), findsOneWidget);
    expect(find.textContaining('Direct IP'), findsNothing);
    expect(
      find.byKey(const ValueKey('simple-world-map-location-IR')),
      findsNothing,
    );
  });

  testWidgets('a failed location lookup leaves the map unmarked', (tester) async {
    await pumpMap(
      tester,
      status: VpnConnectionStatus.disconnected,
      lookupSourceIpLocation: () async => null,
    );

    expect(find.byKey(const ValueKey('simple-world-map-canvas')), findsOneWidget);
    expect(find.textContaining('Direct IP'), findsNothing);
    expect(find.textContaining('VPN exit'), findsNothing);
    expect(
      find.byKey(const ValueKey('simple-world-map-location-IR')),
      findsNothing,
    );
  });
}
