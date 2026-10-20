import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vpn_swift/providers/vpn_provider.dart';
import 'package:vpn_swift/screens/settings_screen.dart';
import 'package:vpn_swift/widgets/protocol_selector_dialog.dart';

class _SelectorProvider extends ChangeNotifier implements VpnProvider {
  @override
  String get selectedProtocol => 'warp';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RouteRecorder extends NavigatorObserver {
  MaterialPageRoute<dynamic>? settingsRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute<dynamic>) settingsRoute = route;
  }
}

const _captureKey = ValueKey('selector-paint-capture');

Future<_SelectorProvider> _open(
  WidgetTester tester,
  Brightness brightness, {
  NavigatorObserver? observer,
}) async {
  final provider = _SelectorProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider<VpnProvider>.value(
      value: provider,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          navigatorObservers: [if (observer != null) observer],
          home: Scaffold(
            backgroundColor: const Color(0xFF172329),
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
      ),
    ),
  );
  await tester.tap(find.text('Open selector'));
  await tester.pumpAndSettle();
  return provider;
}

// Compare real painted pixels, not just text bounds: Ink can paint on a
// Material outside the viewport even while its ListTile is correctly clipped.
Future<Uint8List> _pixels(WidgetTester tester, Rect rect) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  return tester
      .runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final bytes = data.buffer.asUint8List();
        final result = BytesBuilder();
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
          result.add(
            bytes.sublist(
              (y * image.width + rect.left.ceil()) * 4,
              (y * image.width + rect.right.floor()) * 4,
            ),
          );
        }
        image.dispose();
        return result.takeBytes();
      })
      .then((value) => value!);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'scrolling keeps selected ink out of ${brightness.name} header',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = await _open(tester, brightness);
        final scroll = find.byType(SingleChildScrollView);
        final viewport = tester.getRect(scroll);
        final header = Rect.fromLTRB(
          viewport.left,
          tester.getRect(find.text('Select Protocol')).top - 4,
          viewport.right,
          viewport.top - 1,
        );
        final before = await _pixels(tester, header);
        final row = find.byKey(const ValueKey('protocol-row-warp'));
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        // Put the selected row across the header/list boundary, as in the
        // reported screenshot. Only its portion inside the list may paint.
        position.jumpTo(tester.getRect(row).top - viewport.top + 32);
        await tester.pumpAndSettle();
        expect(tester.getRect(row).top, lessThan(viewport.top));
        expect(tester.getRect(row).bottom, greaterThan(viewport.top));
        final after = await _pixels(tester, header);
        var changedBytes = 0;
        for (var i = 0; i < before.length; i++) {
          if (before[i] != after[i]) changedBytes++;
        }
        expect(
          changedBytes,
          0,
          reason: 'Scrolling row ink must not enter the fixed header',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      },
    );

    testWidgets('visible ${brightness.name} labels keep painting at the edge', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = await _open(tester, brightness);
      final scroll = find.byType(SingleChildScrollView);
      final viewport = tester.getRect(scroll);
      final title = tester.getRect(find.text('WARP'));
      final subtitle = tester.getRect(find.text('Cloudflare WireGuard tunnel'));
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      // Put half the title above the real viewport. Its remaining pixels and
      // the entire description must remain unchanged below the boundary.
      final offset = (title.center.dy - viewport.top).ceilToDouble();
      final visibleLabels = Rect.fromLTRB(
        title.left,
        viewport.top + offset,
        subtitle.right,
        subtitle.bottom,
      );
      final before = await _pixels(tester, visibleLabels);
      position.jumpTo(offset);
      await tester.pumpAndSettle();
      expect(position.pixels, offset);
      expect(tester.getRect(find.text('WARP')).top, lessThan(viewport.top));
      expect(
        tester.getRect(find.text('WARP')).bottom,
        greaterThan(viewport.top),
      );
      expect(
        viewport.contains(
          tester.getRect(find.text('Cloudflare WireGuard tunnel')).center,
        ),
        isTrue,
      );
      final after = await _pixels(
        tester,
        visibleLabels.shift(Offset(0, -offset)),
      );
      // The fixed glass gradient underneath moves relative to the row, so
      // allow a small background shift, but not missing/faded text pixels.
      var maxChannelDifference = 0;
      expect(after.length, before.length);
      for (var i = 0; i < before.length; i++) {
        final difference = (after[i] - before[i]).abs();
        if (difference > maxChannelDifference) {
          maxChannelDifference = difference;
        }
      }
      expect(
        maxChannelDifference,
        lessThanOrEqualTo(8),
        reason: 'Only pixels outside the viewport may be clipped',
      );
      // Decorations and text must share a scrolling Material rather than
      // painting selected-row ink on the fixed glass above the viewport.
      final rowContext = tester.element(
        find.byKey(const ValueKey('protocol-row-warp')),
      );
      expect(
        rowContext.findAncestorWidgetOfExactType<Material>()!.key,
        const ValueKey('protocol-scroll-material'),
      );
      expect(
        tester.widget<SingleChildScrollView>(scroll).clipBehavior,
        Clip.hardEdge,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });

    testWidgets(
      '${brightness.name} general gear has a ring and opens global settings',
      (tester) async {
        final observer = _RouteRecorder();
        final provider = await _open(tester, brightness, observer: observer);
        final button = find.byTooltip('General settings (all protocols)');
        final ink = tester.widget<Ink>(
          find.byKey(const ValueKey('protocol-general-settings-ring')),
        );
        final decoration = ink.decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        final border = decoration.border! as Border;
        expect(border.top.width, greaterThanOrEqualTo(1));
        expect(border.top.color.a, greaterThanOrEqualTo(0.7));
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(
          find.byKey(const ValueKey('protocol-general-settings-ring')),
          findsOneWidget,
        );
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        observer.settingsRoute = null;
        await tester.tap(button);
        // Inspect the pushed route's actual payload without mounting the
        // unrelated Settings UI (which has its own provider/plugin needs).
        expect(observer.settingsRoute, isNotNull);
        final settings =
            observer.settingsRoute!.builder(tester.element(button))
                as SettingsScreen;
        expect(settings.generalOnly, isTrue);
        expect(settings.initialProtocol, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      },
    );

    testWidgets(
      '${brightness.name} row gear still opens protocol-specific settings',
      (tester) async {
        final observer = _RouteRecorder();
        final provider = await _open(tester, brightness, observer: observer);
        final button = find.byTooltip('WARP settings');
        await tester.ensureVisible(button);
        observer.settingsRoute = null;
        await tester.tap(button);
        expect(observer.settingsRoute, isNotNull);
        final settings =
            observer.settingsRoute!.builder(tester.element(button))
                as SettingsScreen;
        expect(settings.generalOnly, isFalse);
        expect(settings.initialProtocol, 'warp');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      },
    );
  }
}
