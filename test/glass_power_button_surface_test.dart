import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/glass_power_button_surface.dart';

Finder _glassPaint() => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint && widget.painter is GlassPowerButtonPainter,
);

Widget _host({required bool disableAnimations}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 200,
          height: 200,
          child: GlassPowerButtonSurface(
            isDark: true,
            tint: const Color(0xFF8CBDF4),
            child: const Icon(Icons.power_settings_new, size: 80),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('glass caustic moves and honors reduced-motion preference', (
    tester,
  ) async {
    await tester.pumpWidget(_host(disableAnimations: false));
    final first =
        tester.widget<CustomPaint>(_glassPaint()).painter!
            as GlassPowerButtonPainter;
    final firstPhase = first.animation.value;
    expect(
      tester.getSize(find.byType(GlassPowerButtonSurface)),
      const Size(200, 200),
    );

    await tester.pump(const Duration(seconds: 2));
    final moving =
        tester.widget<CustomPaint>(_glassPaint()).painter!
            as GlassPowerButtonPainter;
    expect(moving.animation.value, isNot(firstPhase));

    await tester.pumpWidget(_host(disableAnimations: true));
    await tester.pump();
    final reduced =
        tester.widget<CustomPaint>(_glassPaint()).painter!
            as GlassPowerButtonPainter;
    expect(reduced.animation.value, 0);

    await tester.pump(const Duration(seconds: 2));
    final stopped =
        tester.widget<CustomPaint>(_glassPaint()).painter!
            as GlassPowerButtonPainter;
    expect(stopped.animation.value, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
