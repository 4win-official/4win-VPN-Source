import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vpn_swift/l10n/app_localizations.dart';
import 'package:vpn_swift/models/simple_connection_plan.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/simple_mode_screens.dart';

class _FakeVpnProvider extends ChangeNotifier implements VpnProvider {
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  bool leftApp = false;
  bool satisfied = false;
  int refreshCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;
  VpnConnectionStatus currentStatus = VpnConnectionStatus.connected;
  int? ping = 42;
  String downloaded = '12.3 MB';
  String uploaded = '5.6 MB';

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
  int? get currentPing => ping;

  @override
  bool get pingFailed => false;

  @override
  String get downloadDataUsage => downloaded;

  @override
  String get uploadDataUsage => uploaded;

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
  Future<bool> connectSimple() async {
    connectCalls++;
    return true;
  }

  @override
  Future<void> disconnect({bool preserveSimpleAttempt = false}) async {
    disconnectCalls++;
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
    'uses the app logo as its connection control and shows live session stats',
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
      expect(
        find.byKey(const ValueKey('simple-logo-connect-control')),
        findsOneWidget,
      );
      expect(find.text('—'), findsNWidgets(3));
      final background = find.byKey(const ValueKey('simple-status-background'));
      expect(background, findsOneWidget);
      final disconnectedDecoration =
          tester.widget<AnimatedContainer>(background).decoration
              as BoxDecoration;
      expect(
        (disconnectedDecoration.gradient! as LinearGradient).colors.first,
        const Color(0xFFF8F9FB),
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
      expect(inTransition.colors.first, isNot(const Color(0xFFF8F9FB)));
      expect(inTransition.colors.first, isNot(const Color(0xFFFFF5D9)));
      final connectingTarget =
          tester.widget<AnimatedContainer>(background).decoration
              as BoxDecoration;
      expect(
        (connectingTarget.gradient! as LinearGradient).colors.first,
        const Color(0xFFFFF5D9),
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
        const Color(0xFFFFF5D9),
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
      expect(yellowToGreen.colors.first, isNot(const Color(0xFFFFF5D9)));
      expect(yellowToGreen.colors.first, isNot(const Color(0xFFE9F7ED)));
      await tester.pump(const Duration(milliseconds: 700));
      final connectedDecoration =
          tester.widget<AnimatedContainer>(background).decoration
              as BoxDecoration;
      expect(
        (connectedDecoration.gradient! as LinearGradient).colors.first,
        const Color(0xFFE9F7ED),
      );
      expect(find.text('42 ms'), findsOneWidget);
      expect(find.text('12.3 MB'), findsOneWidget);
      expect(find.text('5.6 MB'), findsOneWidget);
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

  testWidgets('the logo control connects and disconnects with the VPN state', (
    tester,
  ) async {
    final provider = _FakeVpnProvider()
      ..currentStatus = VpnConnectionStatus.disconnected;
    await tester.pumpWidget(
      ChangeNotifierProvider<VpnProvider>.value(
        value: provider,
        child: const MaterialApp(home: SimpleHomeScreen()),
      ),
    );
    await tester.pump();

    final logoControl = find.byKey(
      const ValueKey('simple-logo-connect-control'),
    );
    await tester.tap(logoControl);
    await tester.pump();
    expect(provider.connectCalls, 1);

    provider.currentStatus = VpnConnectionStatus.connected;
    provider.emit();
    await tester.pump();
    await tester.tap(logoControl);
    await tester.pump();
    expect(provider.disconnectCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Simple dashboard translates stats and preserves LTR values in RTL',
    (tester) async {
      final provider = _FakeVpnProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<VpnProvider>.value(
          value: provider,
          child: MaterialApp(
            locale: const Locale('fa'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SimpleHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('آمار اتصال'), findsOneWidget);
      expect(find.text('پینگ'), findsOneWidget);
      expect(find.text('دانلود'), findsOneWidget);
      expect(find.text('آپلود'), findsOneWidget);
      expect(find.text('42 ms'), findsOneWidget);
      expect(find.text('12.3 MB'), findsOneWidget);
      expect(find.text('5.6 MB'), findsOneWidget);
      final downloadDirections = tester.widgetList<Directionality>(
        find.ancestor(
          of: find.byKey(const ValueKey('simple-download-value')),
          matching: find.byType(Directionality),
        ),
      );
      expect(
        downloadDirections.any(
          (direction) => direction.textDirection == TextDirection.ltr,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
