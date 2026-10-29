import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/mix_diagnostics.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/models/sstp_server_group.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/dns_scanner_screen.dart';
import 'package:vpn_swift/widgets/mix_chain_diagnostics.dart';
import 'package:vpn_swift/widgets/psiphon_server_list_status.dart';

import 'home_rain_layer_test.dart' show FakeVpnProvider, pumpHome;

class _LayoutProvider extends FakeVpnProvider {
  String protocol = 'xray';
  MixStrategy? strategy;
  MixDiagnostics? diagnostics;
  String? error;
  bool connected = false;
  ProxyServer? proxy;

  @override
  String get selectedProtocol => protocol;
  @override
  bool get isConnected => connected;
  @override
  VpnConnectionStatus get status => connected
      ? VpnConnectionStatus.connected
      : error != null
      ? VpnConnectionStatus.error
      : VpnConnectionStatus.disconnected;
  @override
  Duration get connectionDuration =>
      connected ? const Duration(seconds: 65) : Duration.zero;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #selectedMixStrategy) return strategy;
    if (invocation.memberName == #selectedMixStrategyId) return strategy?.id;
    if (invocation.memberName == #mixDiagnostics) return diagnostics;
    if (invocation.memberName == #errorMessage) return error;
    if (invocation.memberName == #activeProxyServer) return proxy;
    if (invocation.memberName == #selectedSstpGroup ||
        invocation.memberName == #selectedServer) {
      return null;
    }
    if (invocation.memberName == #sstpGroups) return <SstpServerGroup>[];
    if (invocation.memberName == #currentPing) return 40;
    return super.noSuchMethod(invocation);
  }
}

const _protocols = {
  'xray': 'Xray',
  'proxy': 'Proxy',
  'psiphon': 'Psiphon',
  'warp': 'WARP',
  'openvpn': 'OpenVPN',
  'sstp': 'SSTP',
  'direct_dns': 'DNS changer',
  'slowdns': 'Slow DNS',
  'mix': 'Mix',
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'guide_seen': true,
      'selected_theme': 0,
    });
  });

  for (final size in const [
    Size(320, 640),
    Size(390, 844),
    Size(430, 932),
    Size(800, 1200),
  ]) {
    testWidgets(
      'centered power and low actions across every protocol at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);

        final provider = _LayoutProvider();
        await pumpHome(tester, provider);
        final power = find.byKey(const ValueKey('power-button'));
        final selector = find.byKey(
          const ValueKey('protocol-selector-trigger'),
        );
        final zone = find.byKey(const ValueKey('home-bottom-controls-zone'));
        final label = find.byKey(const ValueKey('selected-protocol-label'));
        final powerRect = tester.getRect(power);
        final selectorRect = tester.getRect(selector);
        final statusRect = tester.getRect(find.text('Disconnected'));
        expect(powerRect.size, const Size(200, 200));
        expect(powerRect.center.dx, closeTo(size.width / 2, .001));
        expect(powerRect.center.dy, closeTo((size.height - 24) / 2, .001));
        expect(tester.getRect(zone).bottom, closeTo(size.height - 32, .001));
        expect(tester.getRect(zone).top, greaterThan(size.height * .72));

        void expectStable(String name) {
          expect(tester.getRect(power), powerRect);
          expect(tester.getRect(selector), selectorRect);
          expect(tester.widget<Text>(label).data, name);
          expect(selector.hitTestable(), findsOneWidget);
          expect(power.hitTestable(), findsOneWidget);
          final details = tester.getRect(
            find.byKey(const ValueKey('home-connection-details')),
          );
          expect(details.bottom, lessThanOrEqualTo(tester.getRect(zone).top));
          expect(tester.takeException(), isNull);
        }

        for (final entry in _protocols.entries) {
          provider.protocol = entry.key;
          provider.proxy = ProxyServer(
            id: 'layout',
            remark:
                'A very long active server name that should not shift controls',
            link: '',
            protocol: 'socks5',
            address: 'example.invalid',
            port: 443,
          );
          await pumpHome(tester, provider);
          expectStable(entry.value);
          expect(tester.getRect(find.text('Disconnected')), statusRect);
        }

        provider.error = List.filled(
          18,
          'Connection failed. Please try another server.',
        ).join(' ');
        await pumpHome(tester, provider);
        expectStable('Mix');
        provider.error = null;
        provider.connected = true;
        provider.protocol = 'xray';
        await pumpHome(tester, provider);
        expectStable('Xray');
        provider.connected = false;
        provider.protocol = 'psiphon';
        await pumpHome(tester, provider);
        expect(find.byType(PsiphonServerListStatus), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        // Allow the unrelated, temporary Support Us callout to dismiss.
        await tester.pump(const Duration(seconds: 5));
        expectStable('Psiphon');

        provider.protocol = 'mix';
        provider.strategy = MixStrategy(
          id: 'layout-test',
          name: 'Layout test strategy',
          hops: const [MixHop(protocol: 'xray', serverId: 'default')],
        );
        provider.diagnostics =
            MixDiagnostics.begin(provider.strategy!, 'attempt').applyNative({
              'attemptId': 'attempt',
              'phase': 'Chain failed',
              'message': 'connection failed',
              'blocks': [
                {'index': 0, 'state': 'failed'},
              ],
            });
        await pumpHome(tester, provider);
        expect(find.byType(MixChainDiagnostics), findsOneWidget);
        expect(find.text('Strategy').hitTestable(), findsOneWidget);
        expectStable('Mix');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('RTL traffic counters keep download on the right', (
    tester,
  ) async {
    final provider = _LayoutProvider()..connected = true;
    await pumpHome(tester, provider, textDirection: TextDirection.rtl);

    final downloadCounter = tester.getRect(
      find.byKey(const ValueKey('download-data-counter')),
    );
    final uploadCounter = tester.getRect(
      find.byKey(const ValueKey('upload-data-counter')),
    );
    expect(downloadCounter.center.dx, greaterThan(uploadCounter.center.dx));
    expect(
      tester
          .widget<Directionality>(
            find.byKey(const ValueKey('download-data-value-direction')),
          )
          .textDirection,
      TextDirection.ltr,
    );
    expect(
      tester
          .widget<Directionality>(
            find.byKey(const ValueKey('upload-data-value-direction')),
          )
          .textDirection,
      TextDirection.ltr,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Slow DNS Resolver Scanner opens discovery directly', (
    tester,
  ) async {
    final provider = _LayoutProvider()..protocol = 'slowdns';
    await pumpHome(tester, provider);

    expect(find.text('Slow DNS Configs'), findsOneWidget);
    await tester.tap(find.text('Resolver Scanner'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DnsScannerScreen), findsOneWidget);
    expect(find.text('DNS resolver discovery'), findsOneWidget);
    expect(find.text('Slow DNS Configs'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
