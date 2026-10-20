import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/mix_diagnostics.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/widgets/mix_chain_diagnostics.dart';
import 'package:vpn_swift/widgets/psiphon_server_list_status.dart';

import 'home_rain_layer_test.dart' show FakeVpnProvider, pumpHome;

class _LayoutProvider extends FakeVpnProvider {
  String protocol = 'xray';
  MixStrategy? strategy;
  MixDiagnostics? diagnostics;

  @override
  String get selectedProtocol => protocol;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #selectedMixStrategy) return strategy;
    if (invocation.memberName == #selectedMixStrategyId) return strategy?.id;
    if (invocation.memberName == #mixDiagnostics) return diagnostics;
    return super.noSuchMethod(invocation);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'guide_seen': true,
      'selected_theme': 0,
    });
  });

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets(
      'power and selector stay fixed for Psiphon and Mix failure at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final provider = _LayoutProvider();
        await pumpHome(tester, provider);
        final power = find.byKey(const ValueKey('power-button'));
        final selector = find.byKey(
          const ValueKey('protocol-selector-trigger'),
        );
        final powerRect = tester.getRect(power);
        final selectorRect = tester.getRect(selector);
        expect(powerRect.width, closeTo(200, .001));
        expect(powerRect.height, closeTo(200, .001));
        expect(selector.hitTestable(), findsOneWidget);
        final serverButton = find.descendant(
          of: find.byKey(const ValueKey('home-bottom-controls-zone')),
          matching: find.byType(ElevatedButton),
        ).first;
        expect(tester.getSize(serverButton).height, lessThan(90));

        void expectStable() {
          expect(tester.getRect(power), powerRect);
          expect(tester.getRect(selector), selectorRect);
          expect(selector.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        provider.protocol = 'psiphon';
        await pumpHome(tester, provider);
        await tester.pump();
        expect(find.byType(PsiphonServerListStatus), findsOneWidget);
        expectStable();
        // Metadata errors/updates may increase the card height, not move power.
        await tester.pump(const Duration(seconds: 5));
        expectStable();

        provider.protocol = 'mix';
        provider.strategy = MixStrategy(
          id: 'layout-test',
          name: 'Layout test strategy',
          hops: const [MixHop(protocol: 'xray', serverId: 'default')],
        );
        await pumpHome(tester, provider);
        expect(find.byType(MixChainDiagnostics), findsNothing);
        expectStable();

        provider.diagnostics =
            MixDiagnostics.begin(provider.strategy!, 'attempt').applyNative({
              'attemptId': 'attempt',
              'phase': 'Chain failed',
              'message': 'connection failed',
              'blocks': [
                {'index': 0, 'state': 'failed'},
              ],
            });
        await pumpHome(tester, provider);
        expect(find.text('Strategy'), findsOneWidget);
        expect(find.byType(MixChainDiagnostics), findsOneWidget);
        expectStable();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
