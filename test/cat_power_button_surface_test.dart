import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/cat_power_button_surface.dart';

Finder _paint() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is CatPowerButtonPainter,
);

Widget _host({
  required VoidCallback onTap,
  required VoidCallback onLongPress,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: const SizedBox.square(
          dimension: 200,
          child: CatPowerButtonSurface(
            child: Icon(
              Icons.power_settings_new,
              size: 80,
              color: Color(0xFF18231E),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('mint Cat head keeps the button footprint and power control', (
    tester,
  ) async {
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(
      _host(onTap: () => taps++, onLongPress: () => longPresses++),
    );

    final surface = find.byType(CatPowerButtonSurface);
    expect(tester.getSize(surface), const Size(200, 200));
    expect(_paint(), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.power_settings_new));
    expect(icon.color, const Color(0xFF18231E));

    final painter = tester.widget<CustomPaint>(_paint()).painter!;
    expect(painter.shouldRepaint(const CatPowerButtonPainter()), isFalse);
    await tester.tap(surface);
    await tester.longPress(surface);
    expect(taps, 1);
    expect(longPresses, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
