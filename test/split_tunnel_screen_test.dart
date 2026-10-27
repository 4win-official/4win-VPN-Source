import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/screens/split_tunnel_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const appsChannel = MethodChannel('com.forwin.vpn/apps');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(appsChannel, null);
  });

  void mockInstalledApps(List<String> packages) {
    messenger.setMockMethodCallHandler(appsChannel, (call) async {
      if (call.method != 'getInstalledApps') {
        throw PlatformException(code: 'not_implemented');
      }
      return packages
          .map((package) => {'package': package, 'name': package})
          .toList();
    });
  }

  Finder tileFor(String package) => find
      .ancestor(
        of: find.text(package),
        matching: find.byType(CheckboxListTile),
      )
      .first;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplitTunnelScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'migrates legacy settings, defaults installed packages checked, preserves other selections, and remembers opt-outs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'split_tunnel_mode': 'include',
      'split_tunnel_apps':
          'com.isc.bminew,com.example.reader,ir.bmi.bam.nativeweb',
      // The previous defaults-history key must not suppress the new list.
      'split_tunnel_banking_defaults_seen': ['com.isc.bminew'],
    });
    mockInstalledApps([
      'com.isc.bminew',
      'ir.eitaa.messenger',
      'com.example.reader',
      'com.example.unchecked',
      'ir.bmi.bam.nativeweb',
    ]);

    await pumpScreen(tester);

    expect(find.text('Off'), findsNothing);
    expect(find.text('Only selected'), findsOneWidget);
    expect(find.text('Bypass selected'), findsOneWidget);
    expect(
      tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      ).selected,
      {'exclude'},
    );
    expect(
      tester.widget<CheckboxListTile>(tileFor('com.isc.bminew')).value,
      isTrue,
    );
    expect(
      tester.widget<CheckboxListTile>(tileFor('ir.eitaa.messenger')).value,
      isTrue,
    );
    expect(
      tester.widget<CheckboxListTile>(tileFor('com.example.reader')).value,
      isTrue,
    );
    expect(
      tester.widget<CheckboxListTile>(tileFor('ir.bmi.bam.nativeweb')).value,
      isTrue,
    );
    expect(
      tester.widget<CheckboxListTile>(tileFor('com.example.unchecked')).value,
      isFalse,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('split_tunnel_mode'), 'exclude');
    expect(prefs.getBool('split_tunnel_mode_migrated_v1'), isTrue);

    final messengerTile = tileFor('ir.eitaa.messenger');
    await tester.ensureVisible(messengerTile);
    await tester.tap(messengerTile);
    await tester.pumpAndSettle();
    expect(prefs.getString('split_tunnel_banking_opt_outs'), 'ir.eitaa.messenger');
    expect(prefs.getString('split_tunnel_apps'), isNot(contains('ir.eitaa.messenger')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScreen(tester);
    expect(
      tester.widget<CheckboxListTile>(tileFor('ir.eitaa.messenger')).value,
      isFalse,
    );
    expect(
      tester.widget<CheckboxListTile>(tileFor('com.isc.bminew')).value,
      isTrue,
    );
  });

  testWidgets('retains a later explicit Only selected choice', (tester) async {
    SharedPreferences.setMockInitialValues({
      'split_tunnel_mode': 'include',
      'split_tunnel_mode_migrated_v1': true,
      'split_tunnel_apps': 'com.example.reader',
    });
    mockInstalledApps(['com.example.reader']);

    await pumpScreen(tester);

    expect(
      tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      ).selected,
      {'include'},
    );
    expect(find.text('Off'), findsNothing);
  });
}
