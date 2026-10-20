import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/vpn_server.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/services/server_service.dart';

class FakeServerService extends ServerService {
  FakeServerService(
    this.servers, {
    Map<String, int?>? results,
    this.throwOnTest = false,
  }) : results = results ?? {};

  final List<VpnServer> servers;
  final Map<String, int?> results;
  bool throwOnTest;
  final List<List<VpnServer>> tested = [];
  Completer<List<VpnServer>>? pending;

  @override
  Future<List<VpnServer>> fetchServers({bool forceRefresh = false}) async =>
      servers.map((server) => server.copyWith()).toList();

  @override
  Future<List<VpnServer>> testServersInParallel(
    List<VpnServer> targets, {
    Function(int tested, int total)? onProgress,
  }) async {
    tested.add(List<VpnServer>.of(targets));
    if (throwOnTest) throw StateError('test failed');
    final wait = pending;
    if (wait != null) return wait.future;
    final reachable = <VpnServer>[];
    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      onProgress?.call(i + 1, targets.length);
      final ping = results[target.fullAddress];
      if (ping != null) reachable.add(target.copyWith(ping: ping));
    }
    return reachable;
  }
}

class TestVpnProvider extends VpnProvider {
  TestVpnProvider({required super.serverService});

  @override
  Future<void> loadServers({bool forceRefresh = false}) async {}

  Future<void> loadSstpServers() => super.loadServers(forceRefresh: true);

  @override
  Future<void> loadXrayServers() async {}

  @override
  Future<void> loadProxyServers() async {}

  @override
  Future<void> loadSelectedProtocol() async {}

  @override
  Future<void> loadOpenVpnConfigs() async {}
}

VpnServer server(String host, int port) =>
    VpnServer(address: host, port: port, username: 'vpn', password: 'vpn');

Future<void> seedPrefs({Map<String, Object> extra = const {}}) async {
  SharedPreferences.setMockInitialValues({
    'psiphon_default_v1': true,
    'xray_default_v1': true,
    'selected_protocol': 'xray',
    'connection_mode': 'vpn',
    'xray_servers': <String>[],
    'proxy_servers': <String>[],
    ...extra,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sstpChannel = MethodChannel('sstp_flutter');
  late FakeServerService fake;
  late TestVpnProvider provider;
  late List<String> nativeCalls;

  setUp(() async {
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sstpChannel, (call) async {
          nativeCalls.add(call.method);
          return true;
        });
    await seedPrefs();
    fake = FakeServerService(
      [
        server('fast.example', 443),
        server('zero.example', 444),
        server('down.example', 445),
      ],
      results: {'fast.example:443': 40, 'zero.example:444': 0},
    );
    provider = TestVpnProvider(serverService: fake);
    await provider.loadSstpServers();
    await provider.switchProtocol('sstp');
  });

  tearDown(() => provider.dispose());

  test(
    'loads the default group through the injected service without network',
    () {
      expect(provider.sstpGroups, hasLength(1));
      expect(provider.sstpGroups.single.id, 'default');
      expect(
        provider.servers.map((s) => s.fullAddress),
        contains('fast.example:443'),
      );
    },
  );

  test(
    'selecting a group tests it and chooses the lowest ping including zero',
    () async {
      await provider.addSstpGroup(
        'Custom',
        'custom-a.example:443\ncustom-b.example:443',
      );
      final custom = provider.sstpGroups.firstWhere((g) => g.name == 'Custom');
      fake.results['custom-a.example:443'] = 12;
      fake.results['custom-b.example:443'] = 0;

      await provider.selectSstpGroup(custom.id);

      expect(provider.selectedSstpGroup, custom.id);
      expect(provider.selectedServer!.fullAddress, 'custom-b.example:443');
      expect(provider.selectedServer!.ping, 0);
      expect(
        fake.tested.last.map((s) => s.fullAddress),
        containsAll(<String>['custom-a.example:443', 'custom-b.example:443']),
      );
    },
  );

  test('retains unreachable servers and allows retesting them', () async {
    await provider.testAllServers();
    final down = provider.servers.firstWhere(
      (s) => s.address == 'down.example',
    );
    expect(down.ping, -1);
    final before = fake.tested.length;
    fake.results['down.example:445'] = 7;
    await provider.testAllServers();
    expect(fake.tested.length, before + 1);
    expect(
      provider.servers.firstWhere((s) => s.address == 'down.example').ping,
      7,
    );
  });

  test(
    'non-selected group marks every target while its test is pending',
    () async {
      await provider.addSstpGroup('Custom', 'custom.example:443');
      final custom = provider.sstpGroups.firstWhere((g) => g.name == 'Custom');
      final target = custom.servers.single..ping = 23;
      final pending = Completer<List<VpnServer>>();
      fake.pending = pending;
      final operation = provider.testSstpGroup(custom.id);
      await Future<void>.delayed(Duration.zero);

      expect(provider.isSstpServerTesting(target), isTrue);
      expect(target.ping, isNull);
      expect(provider.sstpGroupTesting, isTrue);
      pending.complete(<VpnServer>[]);
      await operation;
      expect(provider.isSstpServerTesting(target), isFalse);
      expect(target.ping, -1);
    },
  );

  test(
    'test-all marks every target unreachable when the probe throws',
    () async {
      fake.throwOnTest = true;
      await expectLater(provider.testAllServers(), throwsStateError);
      expect(
        provider.servers,
        everyElement(predicate<VpnServer>((s) => s.ping == -1)),
      );
      expect(provider.sstpTestError, contains('Could not test SSTP servers'));
    },
  );

  test(
    'reports testing progress and marks a failed probe unreachable',
    () async {
      final target = provider.servers.firstWhere(
        (s) => s.address == 'down.example',
      );
      final pending = Completer<List<VpnServer>>();
      fake.pending = pending;
      final operation = provider.testSstpServer('default', target);
      await Future<void>.delayed(Duration.zero);

      expect(provider.sstpGroupTesting, isTrue);
      expect(provider.isSstpServerTesting(target), isTrue);
      expect(provider.sstpTestedCount, 0);
      expect(provider.sstpTestTotal, 1);
      expect(target.ping, isNull);

      pending.complete(<VpnServer>[]);
      await operation;
      expect(provider.isSstpServerTesting(target), isFalse);
      expect(provider.sstpTestedCount, 1);
      expect(target.ping, -1);
    },
  );

  test(
    'probe failure records a test error and keeps the server unreachable',
    () async {
      fake.throwOnTest = true;
      final target = provider.servers.first;

      await expectLater(
        provider.testSstpServer('default', target),
        throwsStateError,
      );
      expect(target.ping, -1);
      expect(provider.sstpTestError, contains('Could not test SSTP server'));
    },
  );

  test(
    'manual server selection survives a failed connect and probes only itself',
    () async {
      final target = provider.servers.firstWhere(
        (s) => s.address == 'down.example',
      );
      provider.selectServer(target);
      fake.tested.clear();
      await provider.connect();

      expect(provider.selectedServer!.fullAddress, target.fullAddress);
      expect(fake.tested, hasLength(1));
      expect(fake.tested.single, hasLength(1));
      expect(fake.tested.single.single.fullAddress, target.fullAddress);
      expect(provider.status, VpnConnectionStatus.error);
    },
  );

  test('group target restricts connect probing to that group', () async {
    await provider.addSstpGroup('Only group', 'group.example:443');
    final group = provider.sstpGroups.firstWhere((g) => g.name == 'Only group');
    fake.tested.clear();
    await provider.selectSstpGroup(group.id);
    fake.tested.clear();
    await provider.connect();

    expect(fake.tested, hasLength(1));
    expect(fake.tested.last.single.fullAddress, 'group.example:443');
    expect(provider.status, VpnConnectionStatus.error);
  });

  test('refuses deletion of the built-in default group', () async {
    expect(() => provider.removeSstpGroup('default'), throwsStateError);
    expect(provider.sstpGroups, hasLength(1));
  });

  test(
    'restores a selected group and manual server from preferences',
    () async {
      await provider.addSstpGroup(
        'Saved',
        'saved-a.example:443\nsaved-b.example:443',
      );
      final group = provider.sstpGroups.firstWhere((g) => g.name == 'Saved');
      final target = group.servers.last;
      provider.selectServer(target);
      await Future<void>.delayed(Duration.zero);
      provider.dispose();

      final restored = TestVpnProvider(serverService: fake);
      await restored.loadSstpServers();
      expect(restored.selectedSstpGroup, isNull);
      expect(restored.selectedServer!.fullAddress, target.fullAddress);
      expect(restored.selectedServer!.username, 'vpn');
      restored.dispose();
      provider = TestVpnProvider(serverService: fake);
    },
  );

  test('removes obsolete custom-server settings during restore', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_custom_server', true);
    await prefs.setString('custom_server', 'old.example:443');
    await prefs.setString('custom_username', 'old');
    await prefs.setString('custom_password', 'old');
    provider.dispose();
    final restored = TestVpnProvider(serverService: fake);
    await restored.loadSstpServers();
    expect(prefs.getBool('use_custom_server'), isNull);
    expect(prefs.getString('custom_server'), isNull);
    expect(prefs.getString('custom_username'), isNull);
    expect(prefs.getString('custom_password'), isNull);
    restored.dispose();
    provider = TestVpnProvider(serverService: fake);
  });

  test(
    'cancelling a pending SSTP test never requests permission or starts native connect',
    () async {
      final pending = Completer<List<VpnServer>>();
      fake.pending = pending;
      final connecting = provider.connect();
      await Future<void>.delayed(Duration.zero);
      await provider.disconnect();
      pending.complete(<VpnServer>[]);
      await connecting;

      expect(provider.status, VpnConnectionStatus.disconnected);
      expect(nativeCalls, isNot(contains('takePermission')));
      expect(nativeCalls, isNot(contains('connect')));
    },
  );

  test(
    'SSTP operations do not alter unrelated Xray and proxy selections',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_xray_server', 'xray-keep');
      await prefs.setString('xray_selected_group', 'xray-group-keep');
      await prefs.setString('selected_proxy_server', 'proxy-keep');
      await prefs.setString('proxy_selected_group', 'proxy-group-keep');
      await provider.addSstpGroup('Independent', 'independent.example:443');
      final group = provider.sstpGroups.firstWhere(
        (g) => g.name == 'Independent',
      );
      await provider.selectSstpGroup(group.id);

      expect(prefs.getString('selected_xray_server'), 'xray-keep');
      expect(prefs.getString('xray_selected_group'), 'xray-group-keep');
      expect(prefs.getString('selected_proxy_server'), 'proxy-keep');
      expect(prefs.getString('proxy_selected_group'), 'proxy-group-keep');
    },
  );
}
