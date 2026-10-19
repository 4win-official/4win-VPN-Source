import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/sstp_server_group.dart';
import 'package:vpn_swift/models/vpn_server.dart';
import 'package:vpn_swift/models/xray_server.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/mix_strategy_editor_screen.dart';

class _FakeVpnProvider extends ChangeNotifier implements VpnProvider {
  _FakeVpnProvider({required this.xrayServers, required this.sstpGroups});

  @override
  final List<XrayServer> xrayServers;
  @override
  final List<SstpServerGroup> sstpGroups;
  final List<MixStrategy> saved = <MixStrategy>[];
  int loadXrayCalls = 0;
  int loadSstpCalls = 0;

  @override
  Future<void> saveMixStrategy(MixStrategy strategy) async =>
      saved.add(strategy);

  @override
  Future<void> loadXrayServers() async => loadXrayCalls++;

  @override
  Future<void> loadServers({bool forceRefresh = false}) async =>
      loadSstpCalls++;

  @override
  bool get isConnected => false;
  @override
  bool get isConnecting => false;
  @override
  bool get xrayRefreshing => false;
  @override
  bool get xrayGroupTesting => false;
  @override
  bool get sstpGroupTesting => false;
  @override
  bool get sstpRefreshing => false;
  @override
  XrayServer? get selectedXrayServer => null;
  @override
  String? get selectedXrayGroup => null;
  @override
  VpnServer? get selectedServer => null;
  @override
  String? get selectedSstpGroup => null;

  @override
  noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #xrayTestingIds || name == #xrayTcpTestingIds) {
      return <String>{};
    }
    if (name == #xrayGroupTestingFor ||
        name == #xrayGroupTcpTestingFor ||
        name == #xrayGroupSelectedFor ||
        name == #isSstpServerTesting) {
      return false;
    }
    if (name == #warpAccount ||
        name == #activeXrayServer ||
        name == #selectedProxyServer ||
        name == #activeProxyServer ||
        name == #errorMessage ||
        name == #sstpTestError) {
      return null;
    }
    if (name == #servers) return const <VpnServer>[];
    if (name == #status) return VpnConnectionStatus.disconnected;
    if (name == #connectionDuration) return Duration.zero;
    if (name == #dataUsage) return '0 B';
    if (name == #selectedProtocol) return 'mix';
    return super.noSuchMethod(invocation);
  }
}

final _xray = XrayServer(
  id: 'x1',
  remark: 'Xray One',
  link: 'vless://uuid@example.com:443?type=tcp#one',
  protocol: 'vless',
  address: 'example.com',
  port: 443,
  group: 'Work Xray',
);

final _sstp = VpnServer(address: 'sstp.example.com', port: 443);

Widget _editor(_FakeVpnProvider provider, {MixStrategy? existing}) =>
    ChangeNotifierProvider<VpnProvider>.value(
      value: provider,
      child: MaterialApp(
        home: MixStrategyEditorScreen(existingStrategy: existing),
      ),
    );

_FakeVpnProvider _provider() => _FakeVpnProvider(
  xrayServers: <XrayServer>[_xray],
  sstpGroups: <SstpServerGroup>[
    SstpServerGroup(
      id: 'office',
      name: 'Office SSTP',
      servers: <VpnServer>[_sstp],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor renders black route canvas with start and palette', (
    tester,
  ) async {
    final provider = _provider();
    await tester.pumpWidget(_editor(provider));
    expect(find.text('START'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('INTERNET'), findsOneWidget);
    expect(find.text('Drop or add a protocol block'), findsOneWidget);
    expect(find.text('ADD PROTOCOL BLOCK  (0/50)'), findsOneWidget);
    expect(find.text('Xray'), findsOneWidget);
    expect(find.text('Proxy'), findsOneWidget);
  });

  testWidgets('Xray block opens the real list page and saves a group target', (
    tester,
  ) async {
    final provider = _provider();
    await tester.pumpWidget(_editor(provider));
    await tester.tap(find.text('Xray'));
    await tester.pumpAndSettle();
    expect(find.text('Xray Servers'), findsOneWidget);
    expect(find.text('Choose a server or group'), findsNothing);

    await tester.tap(find.text('Work Xray (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Xray Servers'), findsNothing);
    expect(find.text('Group: Work Xray'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Xray chain');
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();
    expect(provider.saved.single.hops.single.protocol, 'xray');
    expect(provider.saved.single.hops.single.group, 'Work Xray');
    expect(provider.saved.single.hops.single.serverId, isNull);
  });

  testWidgets(
    'SSTP server selection returns to editor without standalone mutation',
    (tester) async {
      final provider = _provider();
      await tester.pumpWidget(_editor(provider));
      await tester.tap(find.text('SSTP'));
      await tester.pumpAndSettle();
      expect(find.text('SSTP Servers'), findsOneWidget);
      expect(find.text('Choose a server or group'), findsNothing);

      await tester.tap(find.byTooltip('Expand'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sstp.example.com:443'));
      await tester.pumpAndSettle();
      expect(find.text('SSTP Servers'), findsNothing);
      expect(find.textContaining('sstp.example.com:443'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'SSTP chain');
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();
      expect(provider.saved.single.hops.single.protocol, 'sstp');
      expect(
        provider.saved.single.hops.single.serverId,
        'sstp.example.com:443',
      );
      expect(provider.saved.single.hops.single.group, 'office');
    },
  );

  testWidgets(
    'reopening a saved editor shows initial Xray selection and cancel preserves it',
    (tester) async {
      final provider = _provider();
      final original = MixStrategy(
        id: 'existing',
        name: 'Existing',
        hops: <MixHop>[MixHop(protocol: 'xray', group: 'Work Xray')],
      );
      await tester.pumpWidget(_editor(provider, existing: original));
      await tester.tap(find.text('Group: Work Xray'));
      await tester.pumpAndSettle();
      expect(find.text('Xray Servers'), findsOneWidget);
      expect(find.text('Work Xray (1)'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Edit Mix Strategy'), findsOneWidget);
      expect(find.text('Group: Work Xray'), findsOneWidget);
      expect(provider.saved, isEmpty);
    },
  );

  testWidgets('save validates an empty strategy before provider access', (
    tester,
  ) async {
    final provider = _provider();
    await tester.pumpWidget(_editor(provider));
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pump();
    expect(find.text('Enter a strategy name.'), findsOneWidget);
    expect(provider.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor shows the hard 50-block ceiling', (tester) async {
    final hops = List.generate(
      MixStrategy.maxBlocks,
      (i) => MixHop(protocol: 'xray', serverId: 'server-$i'),
    );
    final provider = _provider();
    await tester.pumpWidget(
      _editor(
        provider,
        existing: MixStrategy(id: 'full', name: 'Full', hops: hops),
      ),
    );
    expect(find.text('ADD PROTOCOL BLOCK  (50/50)'), findsOneWidget);
    expect(
      find.textContaining(
        'DNS is a resolver at the selected position, not a tunnel:',
      ),
      findsOneWidget,
    );
  });
}
