import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/four_win_loader.dart';

Widget host(Widget child, {bool reducedMotion = false, bool dark = false}) {
  return MaterialApp(
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

Finder loaderPaint() => find.descendant(
  of: find.byType(FourWinLoader),
  matching: find.byType(CustomPaint),
);

void main() {
  testWidgets('has a branded vector painter and accessible loading label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const FourWinLoader(size: 52)));
    expect(tester.getSize(find.byType(FourWinLoader)), const Size(52, 52));
    expect(loaderPaint(), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('fits compact existing constraints and both themes', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      for (final size in [12.0, 14.0, 18.0, 20.0, 40.0, 52.0]) {
        await tester.pumpWidget(
          host(
            SizedBox.square(dimension: size, child: const FourWinLoader()),
            dark: dark,
          ),
        );
        await tester.pump(const Duration(milliseconds: 180));
        expect(tester.getSize(loaderPaint()), Size.square(size));
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'respects reduced motion and resumes when the preference changes',
    (tester) async {
      await tester.pumpWidget(host(const FourWinLoader(), reducedMotion: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(loaderPaint(), findsOneWidget);
      await tester.pumpWidget(host(const FourWinLoader()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(host(const FourWinLoader(), reducedMotion: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('supports contrast color, stroke width and custom semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        const FourWinLoader(
          color: Colors.white,
          strokeWidth: 3,
          semanticsLabel: 'Connecting VPN',
        ),
      ),
    );
    expect(find.bySemanticsLabel('Connecting VPN'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('muted tickers do not request background animation frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const TickerMode(enabled: false, child: FourWinLoader())),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
