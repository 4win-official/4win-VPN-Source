import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/four_win_loader.dart';
import 'package:vpn_swift/widgets/snow_button_surface.dart';

Widget host({
  bool enabled = true,
  Color tint = Colors.white,
  double size = 200,
  Widget child = const Icon(Icons.power_settings_new, size: 80),
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox.square(
          dimension: size,
          child: SnowButtonSurface(
            enabled: enabled,
            tint: tint,
            child: Center(child: child),
          ),
        ),
      ),
    ),
  ),
);

Finder surfacePaint() => find.descendant(
  of: find.byType(SnowButtonSurface),
  matching: find.byType(CustomPaint),
);

void main() {
  testWidgets('snow paints ice and a snowcap without resizing the button', (
    tester,
  ) async {
    for (final size in [120.0, 200.0, 280.0]) {
      await tester.pumpWidget(host(size: size));
      expect(surfacePaint(), findsOneWidget);
      final paint = tester.widget<CustomPaint>(surfacePaint());
      expect(paint.painter, isNotNull);
      expect(paint.foregroundPainter, isNotNull);
      expect(tester.getSize(surfacePaint()), Size.square(size));
      expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('other themes return their unmodified child', (tester) async {
    await tester.pumpWidget(host(enabled: false));
    expect(surfacePaint(), findsNothing);
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    await tester.pumpWidget(host());
    expect(surfacePaint(), findsOneWidget);
    await tester.pumpWidget(host(enabled: false));
    expect(surfacePaint(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('surface preserves tap and long press handlers', (tester) async {
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(
      host(onTap: () => taps++, onLongPress: () => longPresses++),
    );
    await tester.tap(find.byType(SnowButtonSurface));
    await tester.longPress(find.byType(SnowButtonSurface));
    expect(taps, 1);
    expect(longPresses, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ice repaints for status tint while snow stays static', (
    tester,
  ) async {
    CustomPainter? previous;
    CustomPainter? snow;
    for (final tint in [
      Colors.white,
      Colors.green,
      Colors.orange,
      Colors.red,
    ]) {
      await tester.pumpWidget(host(tint: tint));
      final paint = tester.widget<CustomPaint>(surfacePaint());
      if (previous != null) {
        expect(paint.painter!.shouldRepaint(previous), isTrue);
        expect(paint.foregroundPainter!.shouldRepaint(snow!), isFalse);
      }
      expect(paint.painter!.shouldRepaint(paint.painter!), isFalse);
      previous = paint.painter;
      snow = paint.foregroundPainter;
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('connecting loader remains visible within the icy surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        tint: Colors.orange,
        child: const FourWinLoader(color: Colors.black87),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FourWinLoader), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
