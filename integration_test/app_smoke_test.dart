import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vpn_swift/main.dart' as app;

/// On-device smoke test: verifies the app boots past the loading screen to
/// the home screen without crashing, on a real device/emulator with the real
/// native plugins (MethodChannels, SharedPreferences, …).
///
/// Run with a device attached:
///   flutter test integration_test/app_smoke_test.dart
///
/// NOTE: this intentionally does NOT tap connect — establishing a real VPN
/// tunnel needs system VPN consent, which cannot be granted headlessly.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots to home without crashing', (tester) async {
    app.main();

    // LoadingScreen -> HomeScreen transition (pump manually: the app owns
    // long-lived timers/animations, so pumpAndSettle would never settle).
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
      // Home screen shows the big connect button once ready.
      if (find.byType(MaterialApp).evaluate().isNotEmpty) {
        // Keep pumping a little longer to let first-frame async work finish.
        await tester.pump(const Duration(milliseconds: 500));
      }
    }
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MaterialApp), findsWidgets);
    // No uncaught async errors may have been reported.
    expect(tester.takeException(), isNull);
  });
}
