import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/glass_power_button_surface.dart';

Finder _glassPaint() => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && widget.painter is GlassPowerButtonPainter,
);

Widget _host() => const MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: GlassPowerButtonSurface(
          isDark: true,
          tint: Color(0xFF8CBDF4),
          child: Icon(Icons.power_settings_new, size: 80),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('polished glass stays still and preserves the power control', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    final surface = find.byType(GlassPowerButtonSurface);
    expect(tester.getSize(surface), const Size(200, 200));
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);

    final painter =
        tester.widget<CustomPaint>(_glassPaint()).painter!
            as GlassPowerButtonPainter;
    expect(painter.isDark, isTrue);
    expect(painter.tint, const Color(0xFF8CBDF4));
    expect(
      painter.shouldRepaint(
        const GlassPowerButtonPainter(isDark: true, tint: Color(0xFF8CBDF4)),
      ),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        const GlassPowerButtonPainter(isDark: false, tint: Color(0xFF8CBDF4)),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        const GlassPowerButtonPainter(isDark: true, tint: Color(0xFF00FF88)),
      ),
      isTrue,
    );

    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
