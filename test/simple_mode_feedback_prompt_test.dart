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
  VpnConnectionStatus currentStatus = VpnConnectionStatus.connected;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void emit() {
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  bool get isConnected => currentStatus == VpnConnectionStatus.connected;

  @override
  bool get isConnecting => currentStatus == VpnConnectionStatus.connecting;

  @override
  VpnConnectionStatus get status => currentStatus;

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

  testWidgets(
    'shows the app logo and animates disconnected, connecting, connected colors',
    (tester) async {
      final provider = _FakeVpnProvider()
        ..currentStatus = VpnConnectionStatus.disconnected;
      await tester.pumpWidget(
        ChangeNotifierProvider<VpnProvider>.value(
          value: provider,
          child: const MaterialApp(home: SimpleHomeScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/icons/app_icon.png',
        ),
        findsOneWidget,
      );
      final background = find.byKey(const ValueKey('simple-status-background'));
      expect(background, findsOneWidget);
      final disconnectedDecoration =
          tester.widget<AnimatedContainer>(background).decoration
              as BoxDecoration;
      expect(
        (disconnectedDecoration.gradient! as LinearGradient).colors.first,
        const Color(0xFFB7D8FF),
      );

      provider.currentStatus = VpnConnectionStatus.connecting;
      provider.emit();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final backgroundDecoration = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: background,
              matching: find.byType(DecoratedBox),
            ),
          )
          .firstWhere(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).gradient is LinearGradient,
          );
      final inTransition =
          (backgroundDecoration.decoration as BoxDecoration).gradient!
              as LinearGradient;
      expect(inTransition.colors.first, isNot(const Color(0xFFB7D8FF)));
      expect(inTransition.colors.first, isNot(const Color(0xFFFFE59A)));
      final connectingTarget =
          tester.widget<AnimatedContainer>(background).decoration
              as BoxDecoration;
      expect(
        (connectingTarget.gradient! as LinearGradient).colors.first,
        const Color(0xFFFFE59A),
      );
      await tester.pump(const Duration(milliseconds: 350));
      final connectingDecoration = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: background,
              matching: find.byType(DecoratedBox),
            ),
          )
          .firstWhere(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).gradient is LinearGradient,
          );
      expect(
        ((connectingDecoration.decoration as BoxDecoration).gradient!
                as LinearGradient)
            .colors
            .first,
        const Color(0xFFFFE59A),
      );

      provider.currentStatus = VpnConnectionStatus.connected;
      provider.emit();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final changingToGreen = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: background,
              matching: find.byType(DecoratedBox),
            ),
          )
          .firstWhere(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).gradient is LinearGradient,
          );
      final yellowToGreen =
          (changingToGreen.decoration as BoxDecoration).gradient!
              as LinearGradient;
      expect(yellowToGreen.colors.first, isNot(const Color(0xFFFFE59A)));
      expect(yellowToGreen.colors.first, isNot(const Color(0xFFB9E7C6)));
      await tester.pump(const Duration(milliseconds: 700));
      final connectedDecoration =
          tester.widget<AnimatedContainer>(background).decoration
              as BoxDecoration;
      expect(
        (connectedDecoration.gradient! as LinearGradient).colors.first,
        const Color(0xFFB9E7C6),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
