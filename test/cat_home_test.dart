import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/mix_diagnostics.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/home_screen.dart';
import 'package:vpn_swift/widgets/cat_scene.dart';
import 'package:vpn_swift/widgets/mix_chain_diagnostics.dart';
import 'package:vpn_swift/widgets/psiphon_server_list_status.dart';

import 'home_rain_layer_test.dart' show FakeVpnProvider;

class _CatVpn extends FakeVpnProvider {
  final listeners = <VoidCallback>{};
  String protocol = 'xray';
  VpnConnectionStatus connectionStatus = VpnConnectionStatus.disconnected;
  @override
  VpnConnectionStatus get status => connectionStatus;
  @override
  bool get isConnected => connectionStatus == VpnConnectionStatus.connected;
  @override
  bool get isConnecting => connectionStatus == VpnConnectionStatus.connecting;
  String? error;
  ProxyServer? proxy;
  MixDiagnostics? diagnostics;
  final strategy = MixStrategy(
    id: 'cat-layout',
    name: 'Cozy connection',
    hops: const [MixHop(protocol: 'xray', serverId: 'default')],
  );

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);
  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);
  void refresh() {
    for (final listener in listeners.toList()) {
      listener();
    }
  }

  @override
  String get selectedProtocol => protocol;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #errorMessage) return error;
    if (invocation.memberName == #activeProxyServer) return proxy;
    if (invocation.memberName == #selectedMixStrategy) return strategy;
    if (invocation.memberName == #selectedMixStrategyId) return strategy.id;
    if (invocation.memberName == #mixDiagnostics) return diagnostics;
    return super.noSuchMethod(invocation);
  }
}

Finder _paint() => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is CatScenePainter,
);

void main() {
  setUpAll(() async {
    // Use the installed SDK fonts rather than Ahem boxes in visual baselines.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
    final flutter = packages.cast<Map>().singleWhere(
      (p) => p['name'] == 'flutter',
    );
    final sdk = config.uri
        .resolve(flutter['rootUri'] as String)
        .resolve('../');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File.fromUri(
        sdk.resolve('bin/cache/artifacts/material_fonts/${entry.value}'),
      ).readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  for (final dark in [false, true]) {
    for (final size in const [Size(320, 640), Size(390, 844), Size(430, 932)]) {
      testWidgets('Cat ${dark ? 'night' : 'day'} controls stay fixed at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        SharedPreferences.setMockInitialValues({
          'guide_seen': true,
          'selected_theme': AppTheme.cat.index,
          'is_dark_mode': dark,
        });
        final themes = ThemeProvider();
        final vpn = _CatVpn();
        addTearDown(themes.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: themes),
              ChangeNotifierProvider<VpnProvider>.value(value: vpn),
            ],
            child: AnimatedBuilder(
              animation: themes,
              builder: (context, _) => MaterialApp(
                theme: themes.currentTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: child!,
                ),
                home: const RepaintBoundary(
                  key: ValueKey('cat-home-preview'),
                  child: HomeScreen(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(themes.isDarkMode, dark);
        expect(find.byType(CatScene), findsOneWidget);
        final painter =
            tester.widget<CustomPaint>(_paint()).painter! as CatScenePainter;
        expect(painter.isDark, dark);
        final box = tester.renderObject<RenderBox>(_paint());
        final mascot = painter
            .mascotBounds(box.size)
            .inflate(2)
            .shift(box.localToGlobal(Offset.zero));
        final power = find.byKey(const ValueKey('power-button'));
        final selector = find.byKey(
          const ValueKey('protocol-selector-trigger'),
        );
        final powerRect = tester.getRect(power);
        final selectorRect = tester.getRect(selector);
        expect(powerRect.size, const Size(200, 200));
        expect(
          mascot.overlaps(powerRect),
          isFalse,
          reason:
              'mascot=$mascot power=$powerRect selector=$selectorRect canvas=${box.size}',
        );
        expect(mascot.overlaps(selectorRect), isFalse);
        expect(
          mascot.top,
          greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
        );
        expect(
          selectorRect.top,
          greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
        );
        expect(selector.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        if (size == const Size(390, 844)) {
          await expectLater(
            find.byKey(const ValueKey('cat-home-preview')),
            matchesGoldenFile('goldens/cat_${dark ? 'dark' : 'light'}.png'),
          );
        }

        void expectStable() {
          expect(tester.getRect(power), powerRect);
          expect(tester.getRect(selector), selectorRect);
          expect(selector.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        await tester.tap(find.byIcon(Icons.power_settings_new));
        expect(vpn.connectCalls, 1);
        for (final protocol in ['proxy', 'psiphon', 'mix', 'xray']) {
          vpn.protocol = protocol;
          vpn.proxy = ProxyServer(
            id: 'test',
            remark: 'A very long active proxy name for layout testing',
            link: '',
            protocol: 'socks5',
            address: 'example.invalid',
            port: 443,
          );
          vpn.error = 'Connection unavailable. Please try again.';
          vpn.diagnostics = MixDiagnostics.begin(vpn.strategy, 'attempt')
              .applyNative({
                'attemptId': 'attempt',
                'phase': 'Chain failed',
                'message': 'Connection failed',
                'blocks': [
                  {'index': 0, 'state': 'failed'},
                ],
              });
          vpn.refresh();
          await tester.pump();
          expectStable();
          if (protocol == 'psiphon') {
            expect(find.byType(PsiphonServerListStatus), findsOneWidget);
          }
          if (protocol == 'mix') {
            expect(find.byType(MixChainDiagnostics), findsOneWidget);
          }
        }
        final context = tester.element(find.byType(HomeScreen));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Connection notice')));
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Connection notice'), findsOneWidget);
        expectStable();
        await tester.tap(selector);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select Protocol'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }

  testWidgets('Cat animation respects reduced motion and TickerMode', (
    tester,
  ) async {
    Future<void> scene({bool reduced = false, bool ticker = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: TickerMode(
              enabled: ticker,
              child: const CatScene(isDark: false),
            ),
          ),
        ),
      );
    }

    double phase() =>
        (tester.widget<CustomPaint>(_paint()).painter! as CatScenePainter)
            .animation
            .value;
    await scene();
    final start = phase();
    await tester.pump(const Duration(milliseconds: 500));
    expect(phase(), isNot(start));
    await scene(reduced: true);
    final stopped = phase();
    await tester.pump(const Duration(seconds: 1));
    expect(phase(), stopped);
    await scene(ticker: false);
    final muted = phase();
    await tester.pump(const Duration(seconds: 1));
    expect(phase(), muted);
    await scene();
    await tester.pump(const Duration(milliseconds: 500));
    expect(phase(), isNot(muted));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
