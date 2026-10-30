import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/services/update_notification_service.dart';
import 'package:vpn_swift/services/update_service.dart';
import 'package:vpn_swift/widgets/update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('update notifications stay off until the user opts in', () async {
    SharedPreferences.setMockInitialValues({});
    final notifications = UpdateNotificationService(isAndroid: true);

    expect(await notifications.shouldPromptForConsent(), isTrue);
    expect(await notifications.areNotificationsEnabled(), isFalse);

    await notifications.markConsentPrompted();

    expect(await notifications.shouldPromptForConsent(), isFalse);
    expect(await notifications.areNotificationsEnabled(), isFalse);
  });

  test('posting an update notification is skipped before opt-in', () async {
    SharedPreferences.setMockInitialValues({});
    final notifications = UpdateNotificationService(isAndroid: true);
    var notificationChannelCalled = false;
    const channel = MethodChannel('com.forwin.vpn/update_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          notificationChannelCalled = true;
          return true;
        });

    await notifications.showAvailableUpdate(
      updateInfo: UpdateInfo(
        latestVersion: '1.5.1',
        tagName: 'v1.5.1',
        releaseUrl: UpdateService.releasesPageUrl,
      ),
      currentVersion: '1.5.0',
    );

    expect(notificationChannelCalled, isFalse);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('notification update action starts the download flow', (
    tester,
  ) async {
    final updateInfo = UpdateInfo(
      latestVersion: '1.5.1',
      tagName: 'v1.5.1',
      releaseUrl: UpdateService.releasesPageUrl,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                UpdateDialog.show(
                  context,
                  updateInfo: updateInfo,
                  currentVersion: '1.5.0',
                  autoDownload: true,
                );
              },
              child: const Text('Open update'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open update'));
    await tester.pumpAndSettle();

    expect(
      find.text('Installer not found. Please download from the GitHub page.'),
      findsOneWidget,
    );
  });
}
