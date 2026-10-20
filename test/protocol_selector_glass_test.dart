import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/widgets/protocol_glass_surface.dart';
import 'package:vpn_swift/widgets/protocol_selector_dialog.dart';

class _SelectorProvider extends ChangeNotifier implements VpnProvider {
  String? switchedTo;

  @override
  String get selectedProtocol => 'warp';

  @override
  Future<void> switchProtocol(String protocol) async {
    switchedTo = protocol;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_SelectorProvider provider, Brightness brightness) =>
    ChangeNotifierProvider<VpnProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ProtocolSelectorDialog(),
              ),
              child: const Text('Open selector'),
            ),
          ),
        ),
      ),
    );

Future<void> _open(
  WidgetTester tester,
  _SelectorProvider provider,
  Brightness brightness,
) async {
  await tester.pumpWidget(_host(provider, brightness));
  await tester.tap(find.text('Open selector'));
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('clear glass and readable controls in ${brightness.name}', (
      tester,
    ) async {
      final provider = _SelectorProvider();
      await _open(tester, provider, brightness);
      expect(find.byType(ProtocolGlassSurface), findsOneWidget);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor, Colors.transparent);
      expect(dialog.surfaceTintColor, Colors.transparent);
      expect(dialog.elevation, 0);
      final tint = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('protocol-glass-tint')),
      );
      final gradient = (tint.decoration as BoxDecoration).gradient!;
      // Guard against reverting to a nearly opaque light/dark panel.
      expect(gradient.colors.every((color) => color.a <= 0.24), isTrue);
      expect(find.byType(BackdropFilter), findsOneWidget);
      final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(blur.filter.toString(), contains('2.0'));
      final selectedRow = tester.widget<Ink>(
        find.byKey(const ValueKey('protocol-row-warp')),
      );
      final otherRow = tester.widget<Ink>(
        find.byKey(const ValueKey('protocol-row-xray')),
      );
      final selectedDecoration = selectedRow.decoration! as BoxDecoration;
      final otherDecoration = otherRow.decoration! as BoxDecoration;
      expect(selectedDecoration.gradient, isNot(otherDecoration.gradient));
      expect(selectedDecoration.border, isNot(otherDecoration.border));
      expect(
        selectedDecoration.gradient!.colors.every(
          (color) => HSLColor.fromColor(color).saturation < 0.01,
        ),
        isTrue,
      );
      final settings = find.byTooltip('WARP settings');
      expect(tester.getSize(settings).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(settings).height, greaterThanOrEqualTo(44));
      final glass = find.byType(ProtocolGlassSurface);
      final clip = tester.widget<ClipRRect>(
        find.descendant(of: glass, matching: find.byType(ClipRRect)).first,
      );
      expect(clip.borderRadius, BorderRadius.circular(28));
      final paint = tester.widget<CustomPaint>(
        find.descendant(of: glass, matching: find.byType(CustomPaint)).first,
      );
      expect(paint.painter, isNull);
      expect(paint.foregroundPainter, isNotNull);
      expect(find.text('Select Protocol'), findsOneWidget);
      expect(
        find.byTooltip('General settings (all protocols)'),
        findsOneWidget,
      );
      expect(find.byTooltip('WARP settings'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final selectedSemantics = tester.getSemantics(
        find.byKey(const ValueKey('protocol-row-warp')),
      );
      expect(
        selectedSemantics.flagsCollection.isSelected == Tristate.isTrue,
        isTrue,
      );
      expect(selectedSemantics.flagsCollection.isButton, isTrue);
      expect(tester.takeException(), isNull);
      // A theme change must update the glass rather than cache its old tint.
      final opposite = brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
      await tester.pumpWidget(_host(provider, opposite));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProtocolGlassSurface>(find.byType(ProtocolGlassSurface))
            .isDark,
        opposite == Brightness.dark,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  }

  testWidgets('protocol row icons are grayscale and selected row is semantic', (
    tester,
  ) async {
    final provider = _SelectorProvider();
    await _open(tester, provider, Brightness.dark);

    for (final protocol in const [
      'mix',
      'xray',
      'psiphon',
      'warp',
      'openvpn',
      'sstp',
      'direct_dns',
      'proxy',
      'slowdns',
    ]) {
      final row = find.byKey(ValueKey('protocol-row-$protocol'));
      final leadingIcon = tester.widget<Icon>(
        find.descendant(of: row, matching: find.byType(Icon)).first,
      );
      final channels = [
        (leadingIcon.color!.r * 255).round(),
        (leadingIcon.color!.g * 255).round(),
        (leadingIcon.color!.b * 255).round(),
      ];
      final maxChannel = channels.reduce((a, b) => a > b ? a : b);
      final minChannel = channels.reduce((a, b) => a < b ? a : b);
      final channelRange = maxChannel - minChannel;
      expect(channelRange, lessThanOrEqualTo(8));
    }

    final selected = tester.getSemantics(
      find.byKey(const ValueKey('protocol-row-warp')),
    );
    expect(selected.flagsCollection.isSelected == Tristate.isTrue, isTrue);
    expect(selected.flagsCollection.isButton, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('standalone selector scrolls on a compact display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = _SelectorProvider();
    await _open(tester, provider, Brightness.light);
    await tester.ensureVisible(find.text('Slow DNS'));
    await tester.tap(find.text('Slow DNS'));
    await tester.pumpAndSettle();
    expect(provider.switchedTo, 'slowdns');
    expect(find.byType(ProtocolSelectorDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('outside tap dismisses without changing protocol', (
    tester,
  ) async {
    final provider = _SelectorProvider();
    await _open(tester, provider, Brightness.dark);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(provider.switchedTo, isNull);
    expect(find.byType(ProtocolSelectorDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('close control dismisses without selecting a protocol', (
    tester,
  ) async {
    final provider = _SelectorProvider();
    await _open(tester, provider, Brightness.light);
    await tester.tap(find.byTooltip('Close protocol selector'));
    await tester.pumpAndSettle();
    expect(provider.switchedTo, isNull);
    expect(find.byType(ProtocolSelectorDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('large text stays scrollable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final provider = _SelectorProvider();
      await _open(tester, provider, Brightness.dark);
      await tester.ensureVisible(find.text('Slow DNS'));
      await tester.tap(find.text('Slow DNS'));
      await tester.pumpAndSettle();
      expect(provider.switchedTo, 'slowdns');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  }

  const protocols = {
    'Mix': 'mix',
    'Xray': 'xray',
    'Psiphon': 'psiphon',
    'WARP': 'warp',
    'OpenVPN': 'openvpn',
    'SSTP': 'sstp',
    'DNS changer': 'direct_dns',
    'Proxy': 'proxy',
    'Slow DNS': 'slowdns',
  };
  for (final entry in protocols.entries) {
    testWidgets('${entry.key} still selects its own protocol and dismisses', (
      tester,
    ) async {
      final provider = _SelectorProvider();
      await _open(tester, provider, Brightness.dark);
      await tester.ensureVisible(find.text(entry.key));
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(provider.switchedTo, entry.value);
      expect(find.byType(ProtocolSelectorDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  }
}
