import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/screens/home_screen.dart';
import 'package:vpn_swift/widgets/crying_scene.dart';

import 'home_rain_layer_test.dart' show FakeVpnProvider, pumpHome;

void main() {
  for (final dark in [false, true]) {
    testWidgets('saved Crying opens a usable default home, dark=$dark', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'guide_seen': true,
        'selected_theme': 8,
        'is_dark_mode': dark,
      });
      final vpn = FakeVpnProvider();
      await pumpHome(tester, vpn);
      final themes = tester
          .element(find.byType(HomeScreen))
          .read<ThemeProvider>();
      expect(themes.selectedTheme, AppTheme.system);
      expect(themes.isDarkMode, dark);
      expect(find.byType(CryingScene), findsNothing);
      expect(
        find.byKey(const ValueKey('power-button')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byTooltip('Select protocol').hitTestable(), findsOneWidget);
      await tester.tap(find.byIcon(Icons.power_settings_new));
      expect(vpn.connectCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
