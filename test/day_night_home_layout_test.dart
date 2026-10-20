import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/widgets/day_night_animation.dart';

import 'home_rain_layer_test.dart' show FakeVpnProvider, pumpHome;

Finder _dayNightPaint() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is DayNightPainter,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'guide_seen': true,
      'selected_theme': AppTheme.summer.index,
      'is_dark_mode': false,
    });
  });

  for (final size in const [Size(320, 640), Size(390, 844), Size(430, 932)]) {
    testWidgets('sun is below the AppBar and clear of controls at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);

      final provider = FakeVpnProvider();
      await pumpHome(tester, provider);

      final paintFinder = _dayNightPaint();
      expect(paintFinder, findsOneWidget);
      final paint = tester.widget<CustomPaint>(paintFinder);
      final painter = paint.painter! as DayNightPainter;
      final paintBox = tester.renderObject<RenderBox>(paintFinder);
      final sun = painter
          .sunBounds(paintBox.size)
          .shift(paintBox.localToGlobal(Offset.zero));

      expect(sun.isEmpty, isFalse);
      final appBar = tester.getRect(find.byType(AppBar));
      expect(sun.top, greaterThanOrEqualTo(appBar.bottom));

      final selector = tester.getRect(find.byTooltip('Select protocol'));
      expect(sun.overlaps(selector), isFalse);

      final powerIcon = find.byIcon(Icons.power_settings_new);
      expect(powerIcon, findsOneWidget);
      final powerButton = tester.getRect(
        find
            .ancestor(of: powerIcon, matching: find.byType(GestureDetector))
            .first,
      );
      expect(powerButton.width, closeTo(200, 0.001));
      expect(powerButton.height, closeTo(200, 0.001));
      expect(sun.overlaps(powerButton), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
