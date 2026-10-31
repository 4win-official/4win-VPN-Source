import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/screens/logs_screen.dart';
import 'package:vpn_swift/services/connection_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows all logs when the selected protocol has no entries', (
    tester,
  ) async {
    final logger = ConnectionLogger.instance;
    await logger.clear();
    logger.info('sstp', 'visible fallback log marker');

    await tester.pumpWidget(
      const MaterialApp(home: LogsScreen(initialProtocol: 'xray')),
    );
    await tester.pumpAndSettle();

    final visibleLogText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((richText) => richText.text.toPlainText())
        .join('\n');
    expect(visibleLogText, contains('visible fallback log marker'));

    await tester.pumpWidget(const SizedBox.shrink());
    await logger.clear();
  });
}
