import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vpn_swift/models/sstp_server_group.dart';
import 'package:vpn_swift/models/vpn_server.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/sstp_servers_screen.dart';

class FakeVpnProvider extends ChangeNotifier implements VpnProvider {
  FakeVpnProvider({
    List<SstpServerGroup>? groups,
    this.connected = false,
    this.connecting = false,
  }) : groups =
           groups ??
           [
             SstpServerGroup(
               id: SstpServerGroup.defaultId,
               name: SstpServerGroup.defaultName,
               servers: <VpnServer>[],
             ),
           ];

  final List<SstpServerGroup> groups;
  bool connected;
  bool connecting;
  VpnServer? selected;
  String? selectedGroup;
  int loadCalls = 0;
  int forcedLoadCalls = 0;
  final List<String> selectedGroups = <String>[];
  final List<VpnServer> selectedServers = <VpnServer>[];
  final List<String> removedGroups = <String>[];
  final List<(String, String, String, String)> addedGroups =
      <(String, String, String, String)>[];
  final List<(String, int, String, String)> addedServers =
      <(String, int, String, String)>[];

  @override
  bool get isConnected => connected;

  @override
  bool get isConnecting => connecting;

  @override
  List<SstpServerGroup> get sstpGroups => groups;

  @override
  String? get selectedSstpGroup => selectedGroup;

  @override
  VpnServer? get selectedServer => selected;

  @override
  bool get sstpGroupTesting => false;

  @override
  bool get sstpRefreshing => false;
  @override
  bool isSstpServerTesting(VpnServer server) => false;

  @override
  int get sstpTestedCount => 0;

  @override
  int get sstpTestTotal => 0;

  @override
  String? get sstpTestError => null;

  @override
  Future<void> loadServers({bool forceRefresh = false}) async {
    loadCalls++;
    if (forceRefresh) forcedLoadCalls++;
  }

  @override
  Future<void> selectSstpGroup(String id) async {
    selectedGroup = id;
    selectedGroups.add(id);
    notifyListeners();
  }

  @override
  void selectServer(VpnServer server) {
    selected = server;
    selectedGroup = null;
    selectedServers.add(server);
    notifyListeners();
  }

  @override
  Future<void> refreshSstpGroup(String id) async {}

  @override
  Future<void> removeSstpGroup(String id) async {
    removedGroups.add(id);
    groups.removeWhere((group) => group.id == id);
    notifyListeners();
  }

  @override
  Future<void> addSstpGroup(
    String name,
    String content, {
    String username = 'vpn',
    String password = 'vpn',
  }) async {
    addedGroups.add((name, content, username, password));
    groups.add(
      SstpServerGroup(
        id: 'custom-${groups.length}',
        name: name,
        servers: <VpnServer>[
          VpnServer(
            address: content.split(':').first,
            port: int.parse(content.split(':').last),
            username: username,
            password: password,
          ),
        ],
      ),
    );
    notifyListeners();
  }

  @override
  Future<void> addSstpServer(
    String host,
    int port, {
    required String username,
    required String password,
  }) async {
    addedServers.add((host, port, username, password));
    groups.add(
      SstpServerGroup(
        id: 'manual-${groups.length}',
        name: '$host:$port',
        servers: <VpnServer>[
          VpnServer(
            address: host,
            port: port,
            username: username,
            password: password,
          ),
        ],
      ),
    );
    notifyListeners();
  }

  @override
  noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #errorMessage) return null;
    if (name == #activeProxyServer ||
        name == #activeXrayServer ||
        name == #selectedProxyServer ||
        name == #selectedXrayServer ||
        name == #warpAccount) {
      return null;
    }
    if (name == #status) return VpnConnectionStatus.disconnected;
    if (name == #connectionDuration) return Duration.zero;
    if (name == #dataUsage) return '0 B';
    if (name == #selectedProtocol) return 'sstp';
    if (name == #servers) return const <VpnServer>[];
    if (name == #isLoadingServers ||
        name == #warpRegistering ||
        name == #xrayPinging ||
        name == #xrayPingAwaitingFirstTap ||
        name == #pingFailed) {
      return false;
    }
    return super.noSuchMethod(invocation);
  }
}

SstpServerGroup group(String id, String name, List<VpnServer> servers) =>
    SstpServerGroup(id: id, name: name, servers: servers);

VpnServer server(String address, int port) =>
    VpnServer(address: address, port: port);

Future<void> pumpScreen(WidgetTester tester, FakeVpnProvider provider) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<VpnProvider>.value(
      value: provider,
      child: MaterialApp(home: const SstpServersScreen()),
    ),
  );
  await tester.pump();
}

Future<void> openAddMenu(WidgetTester tester, String entry) async {
  await tester.tap(find.byTooltip('Add SSTP entry'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default group is locked, undeletable, and empty by default', (
    tester,
  ) async {
    final provider = FakeVpnProvider();
    await pumpScreen(tester, provider);

    expect(find.text('4win Free Servers (0)'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byTooltip('Delete group'), findsNothing);
    expect(find.text('Not tested'), findsNothing);
    expect(provider.loadCalls, 1);
  });

  testWidgets('group selection is separate from expansion', (tester) async {
    final target = server('one.example', 443);
    final provider = FakeVpnProvider(
      groups: [
        group('custom', 'Custom', [target]),
      ],
    );
    await pumpScreen(tester, provider);

    await tester.tap(find.text('Custom (1)'));
    await tester.pump();
    expect(provider.selectedGroups, ['custom']);
    expect(find.text('one.example:443'), findsNothing);

    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();
    expect(find.text('one.example:443'), findsOneWidget);
    expect(provider.selectedGroups, ['custom']);
  });

  testWidgets('tapping a server selects only that server', (tester) async {
    final target = server('manual.example', 443);
    final provider = FakeVpnProvider(
      groups: [
        group('custom', 'Custom', [target]),
      ],
    );
    await pumpScreen(tester, provider);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('manual.example:443'));
    await tester.pump();
    expect(provider.selectedServers, [target]);
    expect(provider.selected, same(target));
    expect(provider.selectedGroup, isNull);
    expect(find.text('Manual server selected'), findsOneWidget);
  });

  testWidgets('server rows distinguish untested and unreachable results', (
    tester,
  ) async {
    final untested = server('untested.example', 443);
    final unreachable = server('unreachable.example', 443)..ping = -1;
    final provider = FakeVpnProvider(
      groups: [
        group('custom', 'Custom', [untested, unreachable]),
      ],
    );
    await pumpScreen(tester, provider);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();

    expect(find.text('Untested'), findsOneWidget);
    expect(find.text('Unreachable'), findsOneWidget);
    expect(find.text('Failed'), findsNothing);
  });

  testWidgets('zero latency is a positive TCP connect result', (tester) async {
    final zero = server('zero.example', 443)..ping = 0;
    final provider = FakeVpnProvider(
      groups: [
        group('custom', 'Custom', [zero]),
      ],
    );
    await pumpScreen(tester, provider);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();

    expect(find.text('0 ms TCP connect'), findsOneWidget);
    expect(find.byTooltip('Test TCP latency'), findsOneWidget);
  });

  testWidgets('custom group deletion requires confirmation', (tester) async {
    final provider = FakeVpnProvider(
      groups: [group('custom', 'Custom', const <VpnServer>[])],
    );
    await pumpScreen(tester, provider);

    await tester.tap(find.byTooltip('Delete group'));
    await tester.pumpAndSettle();
    expect(find.text('Delete group?'), findsOneWidget);
    expect(find.text('Delete "Custom" and its servers?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(provider.removedGroups, isEmpty);

    await tester.tap(find.byTooltip('Delete group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(provider.removedGroups, ['custom']);
    expect(find.text('Custom (0)'), findsNothing);
  });

  testWidgets('add group validates required name and source', (tester) async {
    final provider = FakeVpnProvider();
    await pumpScreen(tester, provider);

    await openAddMenu(tester, 'Add group');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    expect(provider.addedGroups, isEmpty);
    expect(find.text('Enter a group name and server source.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a valid group safely closes the dialog', (tester) async {
    final provider = FakeVpnProvider();
    await pumpScreen(tester, provider);
    await openAddMenu(tester, 'Add group');
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Office');
    await tester.enterText(fields.at(1), 'office.example:443');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    expect(provider.addedGroups, [
      ('Office', 'office.example:443', 'vpn', 'vpn'),
    ]);
    expect(find.text('Office (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adding a standalone server captures all four connection fields',
    (tester) async {
      final provider = FakeVpnProvider();
      await pumpScreen(tester, provider);
      await openAddMenu(tester, 'Add server');

      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(4));
      await tester.enterText(fields.at(0), 'manual.example');
      await tester.enterText(fields.at(1), '8443');
      await tester.enterText(fields.at(2), 'alice');
      await tester.enterText(fields.at(3), 'secret');
      await tester.tap(find.text('Add server').last);
      await tester.pumpAndSettle();

      expect(provider.addedServers, [
        ('manual.example', 8443, 'alice', 'secret'),
      ]);
      expect(find.text('manual.example:8443 (1)'), findsOneWidget);
      expect(find.byTooltip('Delete server'), findsOneWidget);
      await tester.tap(find.byTooltip('Expand').last);
      await tester.pumpAndSettle();
      expect(find.text('manual.example:8443'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('connected state blocks group and server selection', (
    tester,
  ) async {
    final target = server('connected.example', 443);
    final provider = FakeVpnProvider(
      groups: [
        group('custom', 'Custom', [target]),
      ],
      connected: true,
    );
    await pumpScreen(tester, provider);
    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('connected.example:443'));
    await tester.pump();
    expect(provider.selectedServers, isEmpty);
    expect(
      find.text('Disconnect first to change the SSTP server.'),
      findsOneWidget,
    );
  });
}
