import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vpn_swift/models/simple_connection_plan.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/simple_mode_screens.dart';

class _FakeVpnProvider extends ChangeNotifier implements VpnProvider {
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  bool leftApp = false;
  bool satisfied = false;
  int refreshCalls = 0;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  bool get isConnected => true;

  @override
  bool get isConnecting => false;

  @override
  VpnConnectionStatus get status => VpnConnectionStatus.connected;

  @override
  bool get simpleConnectionFailed => false;

  @override
  String? get simpleConnectionFailureMessage => null;

  @override
  bool get simpleConnectionInProgress => false;

  @override
  SimpleConnectionAttempt? get simpleCurrentAttempt =>
      const SimpleConnectionAttempt(protocol: 'warp');

  @override
  bool get simpleConnectionNeedsFeedback => !satisfied;

  @override
  bool get simpleConnectionFeedbackReadyOnReturn => leftApp && !satisfied;

  @override
  int get simpleConnectionGeneration => 1;

  @override
  Future<void> refreshConnectionState() async {
    refreshCalls++;
  }

  @override
  Future<void> markSimpleAppLeft() async {
    if (!satisfied) leftApp = true;
  }

  @override
  Future<void> markSimpleConnectionSatisfied() async {
    satisfied = true;
    leftApp = false;
  }

  @override
  Future<bool> cycleSimpleConnection() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('feedback becomes ready only after leaving the same session', () {
    final feedback = SimpleConnectionFeedbackState()
      ..beginSession('simple-session-1');

    expect(feedback.feedbackReadyOnReturn, isFalse);
    expect(feedback.markAppLeft(), isTrue);

    final restored = SimpleConnectionFeedbackState()
      ..restore(
        activeSessionId: 'simple-session-1',
        leftAppSessionId: feedback.leftAppSessionId,
      );
    expect(restored.feedbackReadyOnReturn, isTrue);
    restored.markSatisfied();
    expect(restored.feedbackReadyOnReturn, isFalse);

    restored.beginSession('simple-session-2');
    expect(restored.feedbackReadyOnReturn, isFalse);
  });

  testWidgets('satisfaction prompt waits until the user returns to the app', (
    tester,
  ) async {
    final provider = _FakeVpnProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<VpnProvider>.value(
        value: provider,
        child: const MaterialApp(home: SimpleHomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Are you satisfied with this connection?'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(provider.leftApp, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(provider.refreshCalls, 1);
    expect(
      find.text('Are you satisfied with this connection?'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
