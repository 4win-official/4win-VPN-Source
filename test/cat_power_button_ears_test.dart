import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/cat_power_button_ears.dart';

void main() {
  testWidgets('rounded Cat ears keep their footprint and ignore input', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 66,
              child: CatPowerButtonEars(
                furColor: Color(0xFF4C8A70),
                outlineColor: Color(0xFFCDE8DC),
              ),
            ),
          ),
        ),
      ),
    );

    final ears = find.byType(CatPowerButtonEars);
    expect(tester.getSize(ears), const Size(200, 66));
    expect(
      find.descendant(of: ears, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: ears, matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    final ignorePointer = tester.widget<IgnorePointer>(
      find.descendant(of: ears, matching: find.byType(IgnorePointer)),
    );
    expect(ignorePointer.ignoring, isTrue);
    await tester.tapAt(tester.getCenter(ears));
    expect(tester.takeException(), isNull);
  });
}
