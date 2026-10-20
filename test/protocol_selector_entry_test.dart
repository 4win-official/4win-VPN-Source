import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/widgets/protocol_selector_dialog.dart';

import 'home_rain_layer_test.dart' show FakeVpnProvider, pumpHome;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'guide_seen': true,
      'selected_theme': 0,
    });
  });

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets(
      'capsule opens selector without a duplicate protocol pill at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = FakeVpnProvider();
        await pumpHome(tester, provider);

        expect(find.textContaining('Protocol:'), findsNothing);
        final entry = find.byTooltip('Select protocol');
        expect(entry, findsOneWidget);
        expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
        expect(tester.getSize(entry).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(entry).height, greaterThanOrEqualTo(48));
        final capsule = tester.widget<Container>(
          find.byKey(const ValueKey('protocol-selector-trigger')),
        );
        final capsuleDecoration = capsule.decoration! as BoxDecoration;
        expect(capsuleDecoration.borderRadius, BorderRadius.circular(24));
        await tester.tap(entry);
        // Home contains repeating animations, so settle only the dialog route.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(ProtocolSelectorDialog), findsOneWidget);
        expect(find.text('Select Protocol'), findsOneWidget);
        expect(find.textContaining('Protocol:'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Close protocol selector'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(ProtocolSelectorDialog), findsNothing);
        expect(find.byTooltip('Select protocol'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
