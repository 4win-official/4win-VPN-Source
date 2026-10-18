import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/widgets/animated_server_group.dart';

void main() {
  Widget harness({
    required bool expanded,
    int count = 3,
    ValueChanged<int>? built,
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: CustomScrollView(
            slivers: [
              AnimatedServerGroup(
                key: const ValueKey('group'),
                expanded: expanded,
                backgroundColor: Colors.black12,
                collapsedBorderColor: Colors.amber,
                expandedBorderColor: Colors.amber,
                header: const SizedBox(height: 80, child: Text('Group')),
                itemCount: count,
                itemBuilder: (context, index) {
                  built?.call(index);
                  return SizedBox(height: 60, child: Text('Server $index'));
                },
              ),
              const SliverToBoxAdapter(child: Text('Next group')),
            ],
          ),
        ),
      ),
    );
  }

  double frameExtent(WidgetTester tester) => tester
      .renderObject<RenderSliver>(find.byType(DecoratedSliver))
      .geometry!
      .scrollExtent;

  testWidgets('opening unfolds over the refined 640ms timing', (tester) async {
    await tester.pumpWidget(harness(expanded: false));
    await tester.pumpWidget(harness(expanded: true));
    await tester.pump(const Duration(milliseconds: 320));
    expect(frameExtent(tester), greaterThan(80));
    expect(frameExtent(tester), lessThan(260));

    await tester.pump(const Duration(milliseconds: 320));
    expect(frameExtent(tester), closeTo(260, 0.01));
  });

  testWidgets('reduced motion jumps directly to the requested state', (
    tester,
  ) async {
    await tester.pumpWidget(harness(expanded: false, disableAnimations: true));
    await tester.pumpWidget(harness(expanded: true, disableAnimations: true));
    expect(frameExtent(tester), 260);
    expect(find.text('Server 0'), findsOneWidget);

    await tester.pumpWidget(harness(expanded: false, disableAnimations: true));
    expect(frameExtent(tester), 80);
    expect(find.text('Server 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one frame follows the rows in both directions', (tester) async {
    await tester.pumpWidget(harness(expanded: false));
    expect(frameExtent(tester), 80);
    expect(find.text('Server 0'), findsNothing);

    await tester.pumpWidget(harness(expanded: true));
    await tester.pump(const Duration(milliseconds: 160));
    final openingExtent = frameExtent(tester);
    expect(openingExtent, greaterThan(80));
    expect(openingExtent, lessThan(260));
    expect(find.byType(DecoratedSliver), findsOneWidget);
    expect(find.byType(Divider), findsNothing);

    await tester.pumpAndSettle();
    expect(frameExtent(tester), 260);
    await tester.pumpWidget(harness(expanded: false));
    await tester.pump(const Duration(milliseconds: 160));
    expect(frameExtent(tester), greaterThan(80));
    expect(frameExtent(tester), lessThan(260));
    expect(find.text('Server 0'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(frameExtent(tester), 80);
    expect(find.text('Server 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid reversal continues from the current height', (
    tester,
  ) async {
    await tester.pumpWidget(harness(expanded: false));
    await tester.pumpWidget(harness(expanded: true));
    await tester.pump(const Duration(milliseconds: 120));
    final before = frameExtent(tester);
    await tester.pumpWidget(harness(expanded: false));
    expect(frameExtent(tester), closeTo(before, 0.01));
    await tester.pump(const Duration(milliseconds: 40));
    expect(frameExtent(tester), lessThan(before));
    await tester.pumpWidget(harness(expanded: true));
    await tester.pumpAndSettle();
    expect(frameExtent(tester), 260);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large subscriptions stay lazy and scroll without replaying', (
    tester,
  ) async {
    final built = <int>{};
    await tester.pumpWidget(
      harness(expanded: false, count: 10000, built: built.add),
    );
    expect(built, isEmpty);
    await tester.pumpWidget(
      harness(expanded: true, count: 10000, built: built.add),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    expect(built.length, lessThan(500));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.byType(SizeTransition), findsNothing);
    expect(built.length, lessThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('near-zero progress and closing while scrolled stay lazy', (
    tester,
  ) async {
    final built = <int>{};
    await tester.pumpWidget(
      harness(expanded: false, count: 10000, built: built.add),
    );
    await tester.pumpWidget(
      harness(expanded: true, count: 10000, built: built.add),
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(built.length, lessThan(100));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      harness(expanded: false, count: 10000, built: built.add),
    );
    for (var frame = 0; frame < 320; frame++) {
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(built.length, lessThan(200));
    expect(frameExtent(tester), 80);
  });

  testWidgets('empty group and removal mid-animation are safe', (tester) async {
    await tester.pumpWidget(harness(expanded: false, count: 0));
    await tester.pumpWidget(harness(expanded: true, count: 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(frameExtent(tester), 80);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
