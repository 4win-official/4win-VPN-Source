import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/home_screen.dart';
import 'package:vpn_swift/widgets/liquid_background.dart';

import 'home_rain_layer_test.dart' show FakeVpnProvider;

void main() {
  testWidgets(
    'Liquid stays behind unchanged home controls and leaves other themes alone',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'guide_seen': true,
        'selected_theme': 7,
        'is_dark_mode': true,
      });
      final themes = ThemeProvider();
      addTearDown(themes.dispose);
      final vpn = FakeVpnProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: themes),
            ChangeNotifierProvider<VpnProvider>.value(value: vpn),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      final liquid = find.byType(LiquidBackground);
      expect(liquid, findsOneWidget);
      final stack = tester.widget<Stack>(
        find.ancestor(of: liquid, matching: find.byType(Stack)).first,
      );
      expect(
        find.descendant(
          of: find.byWidget(stack.children.first),
          matching: liquid,
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: liquid, matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
      final power = find.byIcon(Icons.power_settings_new);
      final powerRect = tester.getRect(power);
      final protocolRect = tester.getRect(find.text('Xray').first);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.getRect(power), powerRect);
      expect(tester.getRect(find.text('Xray').first), protocolRect);
      await tester.tap(power);
      expect(vpn.connectCalls, 1);
      await themes.toggleTheme();
      await tester.pump();
      expect(liquid, findsOneWidget);
      expect(tester.getRect(power), powerRect);
      for (final theme in AppTheme.values.where(
        (theme) => theme != AppTheme.liquidGlass,
      )) {
        await themes.setTheme(theme);
        await tester.pump();
        expect(
          liquid,
          findsNothing,
          reason: 'Liquid must not render in $theme',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
