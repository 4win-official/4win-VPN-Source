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
  expect(attemptedTargets, ['Plus', 'warp', 'Free']);
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

  test('a successful Plus or WARP attempt prevents later fallback attempts', () async {
    for (final successIndex in [0, 1]) {
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
        expect(attempted.single.protocol, 'xray');
        expect(attempted.single.xrayGroup, XrayServer.plusGroup);
      } else {
        expect(attempted.map((attempt) => attempt.protocol), ['xray', 'warp']);
      }
    }
  });

  test('Plus, WARP, and Free sessions restore Advanced protocol only after stop', () async {
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
      expect(activeProtocol, ['xray', 'warp', 'xray'][successIndex]);
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
