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

  Finder tileFor(String package) => find
      .ancestor(of: find.text(package), matching: find.byType(CheckboxListTile))
      .first;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SplitTunnelScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump();
  }

  testWidgets('checked apps stay first and new defaults start checked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'split_tunnel_mode': 'exclude',
      'split_tunnel_mode_migrated_v1': true,
      'split_tunnel_apps': 'com.example.reader',
    });
    messenger.setMockMethodCallHandler(appsChannel, (call) async {
      if (call.method != 'getInstalledApps') {
        throw PlatformException(code: 'not_implemented');
      }
      return [
        'com.example.unchecked',
        'com.example.reader',
        'ir.nasim',
        'com.farsitel.bazaar',
        'com.z_unchecked',
      ].map((package) => {'package': package, 'name': package}).toList();
    });

    await pumpScreen(tester);

    expect(
      tester.widget<CheckboxListTile>(tileFor('com.farsitel.bazaar')).value,
      isTrue,
    );
    expect(tester.widget<CheckboxListTile>(tileFor('ir.nasim')).value, isTrue);
    expect(
      tester.widget<CheckboxListTile>(tileFor('com.example.unchecked')).value,
      isFalse,
    );

    double top(String package) => tester.getTopLeft(tileFor(package)).dy;
    expect(top('com.example.reader'), lessThan(top('com.farsitel.bazaar')));
    expect(top('com.farsitel.bazaar'), lessThan(top('ir.nasim')));
    expect(top('ir.nasim'), lessThan(top('com.example.unchecked')));
    expect(top('com.example.unchecked'), lessThan(top('com.z_unchecked')));

    await tester.ensureVisible(tileFor('com.example.unchecked'));
    await tester.tap(tileFor('com.example.unchecked'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(tileFor('com.example.unchecked')).value,
      isTrue,
    );
    expect(top('com.example.unchecked'), lessThan(top('com.farsitel.bazaar')));
    expect(top('com.example.unchecked'), lessThan(top('com.z_unchecked')));
    expect(tester.takeException(), isNull);
  });
}
