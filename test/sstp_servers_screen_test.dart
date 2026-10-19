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

    await tester.tap(find.text('Add group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    expect(provider.addedGroups, isEmpty);
    expect(find.text('Enter a group name and server source.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a valid group safely closes the dialog', (tester) async {
    final provider = FakeVpnProvider();
    await pumpScreen(tester, provider);
    await tester.tap(find.text('Add group'));
    await tester.pumpAndSettle();
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
