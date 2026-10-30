import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/screens/split_tunnel_screen.dart';
import 'package:vpn_swift/widgets/four_win_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const appsChannel = MethodChannel('com.forwin.vpn/apps');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(appsChannel, null);
  });

  testWidgets('shows the animated loader until apps load and for two seconds', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final appsCompleter = Completer<List<Map<String, String>>>();
    messenger.setMockMethodCallHandler(appsChannel, (call) async {
      if (call.method != 'getInstalledApps') {
        throw PlatformException(code: 'not_implemented');
      }
      return appsCompleter.future;
    });

    await tester.pumpWidget(const MaterialApp(home: SplitTunnelScreen()));
    await tester.pump();

    expect(find.byType(FourWinLoader), findsOneWidget);
    expect(find.text('Loading installed apps…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.byType(FourWinLoader), findsOneWidget);

    appsCompleter.complete([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 399));
    expect(find.byType(FourWinLoader), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(find.byType(FourWinLoader), findsNothing);
    expect(find.text('Websites to bypass'), findsOneWidget);
  });
}
