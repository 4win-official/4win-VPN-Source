import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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

  test(
    'the bundled boundaries contain the two representative countries',
    () async {
      final decoded =
          jsonDecode(
                await rootBundle.loadString('assets/maps/world_countries.json'),
              )
              as List<dynamic>;
      final countries = decoded.whereType<Map<String, dynamic>>();
      expect(countries.any((country) => country['c'] == 'IR'), isTrue);
      expect(countries.any((country) => country['c'] == 'DE'), isTrue);
    },
  );

  test('frames Ireland less tightly without changing Iran zoom', () async {
    final decoded =
        jsonDecode(
              await rootBundle.loadString('assets/maps/world_countries.json'),
            )
            as List<dynamic>;
    final countries = decoded.cast<Map<String, dynamic>>();
    final ireland = countries.firstWhere((country) => country['c'] == 'IE');
    final iran = countries.firstWhere((country) => country['c'] == 'IR');
    const size = Size(400, 320);
    const irelandLocation = IpLocation(
      countryCode: 'IE',
      countryName: 'Ireland',
      latitude: 53.4,
      longitude: -8.0,
    );

    final irelandFrame = simpleModeMapFocusedCameraFrameForTesting(
      size: size,
      location: irelandLocation,
      countryData: ireland,
    );
    final iranFrame = simpleModeMapFocusedCameraFrameForTesting(
      size: size,
      location: directLocation,
      countryData: iran,
    );

    expect(
      irelandFrame.scale,
      closeTo(size.width / (12 * math.pi / 180), 0.001),
      reason: 'Ireland should keep surrounding geography in view.',
    );
    expect(
      irelandFrame.scale,
      lessThan(2588.89),
      reason: 'The previous fit zoomed in too tightly on Ireland.',
    );
    expect(
      iranFrame.scale,
      closeTo(863.442, 0.01),
      reason: 'Iran should retain its existing framing.',
    );
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

  testWidgets('keeps the verified source focused until the exit is measured', (
    tester,
  ) async {
    final pendingExit = Completer<IpLocation?>();
    await pumpMap(
      tester,
      status: VpnConnectionStatus.disconnected,
      lookupSourceIpLocation: () async => directLocation,
      lookupCurrentIpLocation: () async => exitLocation,
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
              lookupSourceIpLocation: () async => directLocation,
              lookupCurrentIpLocation: () => pendingExit.future,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Direct IP · Iran'), findsOneWidget);
    expect(find.textContaining('VPN exit'), findsNothing);
    expect(
      find.byKey(const ValueKey('simple-world-map-location-IR')),
      findsOneWidget,
    );

    pendingExit.complete(exitLocation);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('VPN exit · Germany'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('simple-world-map-location-DE')),
      findsOneWidget,
    );
  });

  testWidgets('same-country source-to-exit transition completes cleanly', (
    tester,
  ) async {
    const sameCountryExit = IpLocation(
      countryCode: 'IR',
      countryName: 'Iran',
      latitude: 35.7,
      longitude: 51.4,
    );
    final pendingExit = Completer<IpLocation?>();
    await pumpMap(
      tester,
      status: VpnConnectionStatus.disconnected,
      lookupSourceIpLocation: () async => directLocation,
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
              lookupSourceIpLocation: () async => directLocation,
              lookupCurrentIpLocation: () => pendingExit.future,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    pendingExit.complete(sameCountryExit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(find.text('VPN exit · Iran'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('simple-world-map-location-IR')),
      findsOneWidget,
    );
  });

  test('same-country transitions preserve every source camera-frame value', () {
    const sourceFrame = SimpleModeMapCameraFrame(
      scale: 278.0,
      centerX: 200.0,
      centerY: 160.0,
      focusLongitude: 53.0,
      centerMercatorY: 0.56,
      wrapLongitudes: true,
    );
    const destinationFrame = SimpleModeMapCameraFrame(
      scale: 145.0,
      centerX: 200.0,
      centerY: 160.0,
      focusLongitude: 51.4,
      centerMercatorY: 0.64,
      wrapLongitudes: true,
    );

    for (final progress in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final frame = transitionSimpleModeMapCameraFrame(
        size: const Size(400, 320),
        from: sourceFrame,
        to: destinationFrame,
        progress: progress,
        sameCountry: true,
      );

      expect(
        identical(frame, sourceFrame),
        isTrue,
        reason: 'progress=$progress',
      );
    }
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

  testWidgets('country name appears on the focused map after zoom settles', (
    tester,
  ) async {
    final pendingExit = Completer<IpLocation?>();
    await pumpMap(
      tester,
      status: VpnConnectionStatus.disconnected,
      lookupSourceIpLocation: () async => directLocation,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('simple-world-map-country-name-IR')),
      findsOneWidget,
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
              lookupSourceIpLocation: () async => directLocation,
              lookupCurrentIpLocation: () => pendingExit.future,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('simple-world-map-country-name-IR')),
      findsOneWidget,
    );

    pendingExit.complete(exitLocation);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.byKey(const ValueKey('simple-world-map-country-name-IR')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('simple-world-map-country-name-DE')),
      findsNothing,
    );

    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('simple-world-map-country-name-DE')),
      findsOneWidget,
    );
  });

  testWidgets('full-screen country name stays clear of the center control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: SimpleModeWorldMap(
            status: VpnConnectionStatus.disconnected,
            connecting: false,
            isDark: true,
            lookupSourceIpLocation: () async => directLocation,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final label = find.byKey(
      const ValueKey('simple-world-map-country-name-IR'),
    );
    expect(label, findsOneWidget);
    final controlBounds = Rect.fromCenter(
      center: const Offset(216, 768 * 0.42),
      width: 168,
      height: 168,
    );
    expect(tester.getRect(label).overlaps(controlBounds), isFalse);
  });

  testWidgets('a failed location lookup leaves the map unmarked', (
    tester,
  ) async {
    await pumpMap(
      tester,
      status: VpnConnectionStatus.disconnected,
      lookupSourceIpLocation: () async => null,
    );

    expect(
      find.byKey(const ValueKey('simple-world-map-canvas')),
      findsOneWidget,
    );
    expect(find.textContaining('Direct IP'), findsNothing);
    expect(find.textContaining('VPN exit'), findsNothing);
    expect(
      find.byKey(const ValueKey('simple-world-map-location-IR')),
      findsNothing,
    );
  });
}
