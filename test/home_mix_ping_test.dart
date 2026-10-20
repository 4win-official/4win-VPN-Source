import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';

import 'home_rain_layer_test.dart' show FakeVpnProvider, pumpHome;

class _PingProvider extends FakeVpnProvider {
  _PingProvider({
    this.protocol = 'mix',
    this.ping = 42,
    this.pinging = false,
    this.failed = false,
  });

  final String protocol;
  final int? ping;
  final bool pinging;
  final bool failed;
  int pingCalls = 0;

  @override
  String get selectedProtocol => protocol;
  @override
  bool get isConnected => true;
  @override
  VpnConnectionStatus get status => VpnConnectionStatus.connected;
  @override
  Duration get connectionDuration => const Duration(seconds: 5);
  @override
  int? get currentPing => ping;
  @override
  bool get xrayPinging => pinging;
  @override
  bool get xrayPingAwaitingFirstTap => false;
  @override
  bool get pingFailed => failed;
  @override
  Future<void> manualXrayPing() async => pingCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #selectedMixStrategy ||
        invocation.memberName == #mixDiagnostics) {
      return null;
    }
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

  for (final protocol in ['mix', 'xray', 'warp', 'proxy']) {
    testWidgets('home ping tap behavior for $protocol', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = _PingProvider(protocol: protocol);
      await pumpHome(tester, provider);
      await tester.ensureVisible(find.text('42ms'));
      await tester.tap(find.text('42ms'));
      expect(provider.pingCalls, protocol == 'proxy' ? 0 : 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Mix ping shows hint, loading, and retryable failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final state in ['hint', 'loading', 'failure']) {
      final provider = _PingProvider(
        ping: null,
        pinging: state == 'loading',
        failed: state == 'failure',
      );
      await pumpHome(tester, provider);
      final label = state == 'hint'
          ? 'click to ping'
          : state == 'loading'
          ? 'Pinging…'
          : 'Failed';
      expect(find.text(label), findsOneWidget);
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      expect(provider.pingCalls, state == 'loading' ? 0 : 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
