import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/simple_connection_plan.dart';
import 'package:vpn_swift/models/xray_server.dart';
import 'package:vpn_swift/providers/app_mode_provider.dart';

XrayServer _server(String id, String remark, String group) => XrayServer(
  id: id,
  remark: remark,
  link: 'vless://$id@example.test:443#$remark',
  protocol: 'vless',
  address: '$id.example.test',
  port: 443,
  group: group,
);

Future<void> _expectFallbackIgnoresAdvancedTarget({
  String? selectedServerId,
  String? selectedGroup,
}) async {
  final manualServer = _server('manual', 'Advanced manual', '');
  final manualGroupServer = _server('grouped', 'Advanced group', 'My Servers');
  final plusServer = _server('plus-1', 'Plus', XrayServer.plusGroup);
  final freeServer = _server('free-1', 'Free', XrayServer.freeGroup);
  final initialPreferences = <String, Object>{
    'selected_protocol': 'openvpn',
    'xray_servers': jsonEncode([
      manualServer.toJson(),
      manualGroupServer.toJson(),
      plusServer.toJson(),
      freeServer.toJson(),
    ]),
  };
  if (selectedServerId != null) {
    initialPreferences['selected_xray_server'] = selectedServerId;
  }
  if (selectedGroup != null) {
    initialPreferences['xray_selected_group'] = selectedGroup;
  }
  SharedPreferences.setMockInitialValues(initialPreferences);

  final preferences = await SharedPreferences.getInstance();
  final advancedProtocol = preferences.getString('selected_protocol');
  final advancedServerId = preferences.getString('selected_xray_server');
  final advancedGroup = preferences.getString('xray_selected_group');
  final storedServers = (jsonDecode(
    preferences.getString('xray_servers')!,
  ) as List<dynamic>)
      .map((entry) => XrayServer.fromJson(entry as Map<String, dynamic>))
      .toList();
  final attemptedTargets = <String>[];
  const outcomes = <SimpleConnectionAttemptOutcome>[
    SimpleConnectionAttemptOutcome.failed,
    SimpleConnectionAttemptOutcome.failed,
    SimpleConnectionAttemptOutcome.connected,
  ];
  var attemptIndex = 0;
  final result = await SimpleConnectionPlan.execute((attempt) async {
    if (attempt.protocol == 'warp') {
      attemptedTargets.add('warp');
    } else {
      final target = SimpleConnectionPlan.resolveSimpleXrayTarget(
        servers: storedServers,
        simpleGroupOverride: attempt.xrayGroup,
      );
      attemptedTargets.add(target!.remark);
    }
    return outcomes[attemptIndex++];
  });

  expect(result, SimpleConnectionAttemptOutcome.connected);
  expect(attemptedTargets, ['warp', 'Plus', 'Free']);
  expect(preferences.getString('selected_protocol'), advancedProtocol);
  expect(preferences.getString('selected_xray_server'), advancedServerId);
  expect(preferences.getString('xray_selected_group'), advancedGroup);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stored Advanced manual server cannot hijack Simple fallback', () async {
    final manualServer = _server('manual', 'Advanced manual', '');
    await _expectFallbackIgnoresAdvancedTarget(
      selectedServerId: manualServer.id,
    );
  });

  test('stored Advanced Xray group cannot hijack Simple fallback', () async {
    final manualGroupServer = _server('grouped', 'Advanced group', 'My Servers');
    await _expectFallbackIgnoresAdvancedTarget(
      selectedGroup: manualGroupServer.group,
    );
  });

  test('built-in Simple groups expand to every matching server in order', () {
    final servers = [
      _server('manual', 'Advanced manual', ''),
      _server('plus-1', 'Plus 1', XrayServer.plusGroup),
      _server('free-1', 'Free 1', XrayServer.freeGroup),
      _server('plus-2', 'Plus 2', XrayServer.plusGroup),
      _server('custom', 'Custom subscription', 'My Servers'),
      _server('free-2', 'Free 2', XrayServer.freeGroup),
    ];

    expect(
      SimpleConnectionPlan.xrayTargetsForGroup(
        XrayServer.plusGroup,
        servers,
      ).map((attempt) => attempt.xrayServerId),
      ['plus-1', 'plus-2'],
    );
    expect(
      SimpleConnectionPlan.xrayTargetsForGroup(
        XrayServer.freeGroup,
        servers,
      ).map((attempt) => attempt.xrayServerId),
      ['free-1', 'free-2'],
    );
  });

  test('a successful attempt prevents later fallback attempts', () async {
    for (final successIndex in [0, 1, 2]) {
      final attempted = <SimpleConnectionAttempt>[];
      var index = 0;
      final result = await SimpleConnectionPlan.execute((attempt) async {
        attempted.add(attempt);
        return index++ == successIndex
            ? SimpleConnectionAttemptOutcome.connected
            : SimpleConnectionAttemptOutcome.failed;
      });

      expect(result, SimpleConnectionAttemptOutcome.connected);
      expect(attempted, hasLength(successIndex + 1));
      if (successIndex == 0) {
        expect(attempted.single.protocol, 'warp');
      } else if (successIndex == 1) {
        expect(attempted.map((attempt) => attempt.protocol), ['warp', 'xray']);
        expect(attempted.last.xrayGroup, XrayServer.plusGroup);
      } else {
        expect(attempted.map((attempt) => attempt.protocol), [
          'warp',
          'xray',
          'xray',
        ]);
        expect(attempted.last.xrayGroup, XrayServer.freeGroup);
      }
    }
  });

  test(
    'native readiness waits for confirmation instead of start acknowledgement',
    () async {
      var reads = 0;
      final ready = await SimpleConnectionPlan.waitForReadiness(
        () async => ++reads >= 3,
        isCurrent: () => true,
        timeout: const Duration(seconds: 1),
        pollInterval: Duration.zero,
      );

      expect(ready, isTrue);
      expect(reads, 3);
    },
  );

  test(
    'native readiness times out and stops when the attempt is stale',
    () async {
      var reads = 0;
      final timedOut = await SimpleConnectionPlan.waitForReadiness(
        () async {
          reads++;
          return false;
        },
        isCurrent: () => true,
        timeout: Duration.zero,
      );
      expect(timedOut, isFalse);
      expect(reads, 1);

      final stale = await SimpleConnectionPlan.waitForReadiness(
        () async => true,
        isCurrent: () => false,
        timeout: const Duration(seconds: 1),
      );
      expect(stale, isFalse);
    },
  );

  test(
    'fallback continues after a candidate fails native readiness',
    () async {
      final attempted = <SimpleConnectionAttempt>[];
      final result = await SimpleConnectionPlan.execute((attempt) async {
        attempted.add(attempt);
        final nativeReady = await SimpleConnectionPlan.waitForReadiness(
          () async => attempted.length == 3,
          isCurrent: () => true,
          timeout: Duration.zero,
        );
        return nativeReady
            ? SimpleConnectionAttemptOutcome.connected
            : SimpleConnectionAttemptOutcome.failed;
      });

      expect(result, SimpleConnectionAttemptOutcome.connected);
      expect(
        attempted.map((attempt) => attempt.xrayGroup ?? attempt.protocol),
        ['warp', XrayServer.plusGroup, XrayServer.freeGroup],
      );
    },
  );

  test('feedback advances WARP to Plus and Plus to Free', () {
    final freeServers = [
      _server('free-1', 'Free 1', XrayServer.freeGroup),
      _server('free-2', 'Free 2', XrayServer.freeGroup),
      _server('free-3', 'Free 3', XrayServer.freeGroup),
    ];
    final warpCycle = SimpleConnectionPlan.cycleAfter(
      current: const SimpleConnectionAttempt(protocol: 'warp'),
      freeServers: freeServers,
    );
    expect(
      warpCycle.map((attempt) => attempt.protocol == 'warp'
          ? 'warp'
          : attempt.xrayGroup),
      [XrayServer.plusGroup, XrayServer.freeGroup, 'warp'],
    );

    final plusCycle = SimpleConnectionPlan.cycleAfter(
      current: const SimpleConnectionAttempt(
        protocol: 'xray',
        xrayGroup: XrayServer.plusGroup,
        xrayServerId: 'plus-2',
      ),
      freeServers: freeServers,
    );
    expect(
      plusCycle.map((attempt) => attempt.protocol == 'warp'
          ? 'warp'
          : attempt.xrayGroup),
      [XrayServer.freeGroup, 'warp', XrayServer.plusGroup],
    );
  });

  test('feedback advances to the next Free server and wraps through WARP', () {
    final freeServers = [
      _server('free-1', 'Free 1', XrayServer.freeGroup),
      _server('free-2', 'Free 2', XrayServer.freeGroup),
      _server('free-3', 'Free 3', XrayServer.freeGroup),
    ];
    final cycle = SimpleConnectionPlan.cycleAfter(
      current: const SimpleConnectionAttempt(
        protocol: 'xray',
        xrayGroup: XrayServer.freeGroup,
        xrayServerId: 'free-1',
      ),
      freeServers: freeServers,
    );
    expect(
      cycle
          .where((attempt) => attempt.xrayServerId != null)
          .map((attempt) => attempt.xrayServerId),
      ['free-2', 'free-3', 'free-1'],
    );
    expect(
      cycle.map((attempt) => attempt.protocol == 'warp'
          ? 'warp'
          : attempt.xrayGroup),
      [
        XrayServer.freeGroup,
        XrayServer.freeGroup,
        'warp',
        XrayServer.plusGroup,
        XrayServer.freeGroup,
      ],
    );
  });

  test('satisfaction survives restoring the same session but not a new one', () {
    final feedback = SimpleConnectionFeedbackState();
    feedback.beginSession('simple-session-1');
    expect(feedback.needsFeedback, isTrue);
    expect(feedback.markSatisfied(), isTrue);
    expect(feedback.needsFeedback, isFalse);

    feedback.restore(
      activeSessionId: 'simple-session-1',
      satisfiedSessionId: 'simple-session-1',
    );
    expect(feedback.needsFeedback, isFalse);

    feedback.restore(
      activeSessionId: 'simple-session-2',
      satisfiedSessionId: 'simple-session-1',
    );
    expect(feedback.needsFeedback, isTrue);
  });

  test('WARP, Plus, and Free sessions restore Advanced protocol only after stop',
      () async {
    SharedPreferences.setMockInitialValues({
      'selected_protocol': 'openvpn',
      'selected_xray_server': 'manual-id',
      'xray_selected_group': 'My Servers',
    });
    final preferences = await SharedPreferences.getInstance();
    final appMode = AppModeProvider();
    addTearDown(appMode.dispose);

    for (var successIndex = 0; successIndex < 3; successIndex++) {
      await appMode.setMode(AppExperienceMode.simple);
      final session = SimpleConnectionSession();
      session.captureAdvancedProtocol(
        preferences.getString('selected_protocol')!,
      );
      var attemptIndex = 0;
      String? activeProtocol;
      final result = await SimpleConnectionPlan.execute((attempt) async {
        if (attemptIndex++ == successIndex) {
          activeProtocol = attempt.protocol;
          return SimpleConnectionAttemptOutcome.connected;
        }
        return SimpleConnectionAttemptOutcome.failed;
      });

      expect(result, SimpleConnectionAttemptOutcome.connected);
      expect(
        session.restoreAdvancedProtocolIfStopped(
          activeProtocol!,
          simpleTunnelActive: true,
        ),
        isNull,
      );
      await appMode.setMode(AppExperienceMode.advanced);
      expect(activeProtocol, ['warp', 'xray', 'xray'][successIndex]);
      expect(session.hasSavedAdvancedProtocol, isTrue);
      // Restore only after the active Simple tunnel has been stopped.
      activeProtocol = session.restoreAdvancedProtocolIfStopped(
        activeProtocol!,
        simpleTunnelActive: false,
      );

      expect(activeProtocol, 'openvpn');
      expect(session.hasSavedAdvancedProtocol, isFalse);
    }

    expect(preferences.getString('selected_protocol'), 'openvpn');
    expect(preferences.getString('selected_xray_server'), 'manual-id');
    expect(preferences.getString('xray_selected_group'), 'My Servers');
  });
}
