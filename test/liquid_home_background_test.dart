import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/home_screen.dart';
import 'package:vpn_swift/widgets/glass_power_button_surface.dart';
import 'package:vpn_swift/widgets/liquid_background.dart';
import 'package:vpn_swift/widgets/liquid_power_button_surface.dart';

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
      final liquidButton = find.byType(LiquidPowerButtonSurface);
      expect(liquidButton, findsOneWidget);
      expect(find.byType(GlassPowerButtonSurface), findsNothing);
      expect(tester.getSize(liquidButton), const Size(200, 200));
      final powerButton = find.byKey(const ValueKey('power-button'));
      expect(tester.getRect(powerButton).size, const Size(200, 200));
      final power = find.byIcon(Icons.power_settings_new);
      final powerRect = tester.getRect(power);
      final expectedPowerColor =
          Theme.of(tester.element(power)).brightness == Brightness.dark
          ? Colors.white
          : Colors.black87;
      expect(tester.widget<Icon>(power).color, expectedPowerColor);
      final protocolRect = tester.getRect(find.text('Xray').first);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.getRect(power), powerRect);
      expect(tester.getRect(find.text('Xray').first), protocolRect);
      await tester.tap(power);
      expect(vpn.connectCalls, 1);
      await themes.toggleTheme();
      await tester.pump();
      expect(liquid, findsOneWidget);
      expect(liquidButton, findsOneWidget);
      expect(tester.getRect(power), powerRect);
      expect(tester.widget<Icon>(power).color, expectedPowerColor);
      for (final theme in AppTheme.values.where(
        (theme) => theme != AppTheme.liquidGlass,
      )) {
        await themes.setTheme(theme);
        await tester.pump();
        expect(liquidButton, findsNothing);
        if (theme == AppTheme.system) {
          expect(find.byType(GlassPowerButtonSurface), findsOneWidget);
        }
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
