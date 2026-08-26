import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

/// [ArxaKitEdgeAwareListView] moves the scroll edge treatment from the leaf
/// to the scrollable. The property under test is coverage: a container cannot
/// skip a child, which is the failure the per-widget `.scrollEdgeEffect()`
/// sugar kept producing (7 of 18 showcase glass widgets had it; 11 did not).
void main() {
  /// Deliberately mixed: a card, a bare native-ish control, and a spacer. The
  /// old hand-wiring treated only the first kind — "cards only" — which is
  /// exactly how the toolbar demo and the section labels went untreated.
  List<Widget> mixedChildren() => const [
        SizedBox(key: Key('card'), height: 80),
        SizedBox(key: Key('spacer'), height: 16),
        SizedBox(key: Key('toolbar'), height: 44),
      ];

  Widget harness({
    ArxaKitScrollEdges edges = ArxaKitScrollEdges.both,
    double? bottomOcclusion,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: ArxaKitEdgeAwareListView(
            edges: edges,
            bottomOcclusion: bottomOcclusion,
            children: mixedChildren(),
          ),
        ),
      );

  int effectCount(WidgetTester tester) => find
      .byType(ArxaKitScrollEdgeEffect, skipOffstage: false)
      .evaluate()
      .length;

  testWidgets(
      'kit.ui-library.edge-aware-list — extendBehindTopBar oversizes the '
      'viewport upward so children cull at the screen edge, not the bar seam',
      (tester) async {
    // Sliver paint culling is layout-based (RenderSliverMultiBoxAdaptor.paint
    // drops a child once it is fully above the viewport's leading edge;
    // clipBehavior never participates — clips 12-48/13-17). The fix is
    // geometry: the ListView must be TALLER than the body, bottom-aligned,
    // with the extra height returned as top padding so resting layout holds.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ArxaKitEdgeAwareListView(
          extendBehindTopBar: true,
          padding: const EdgeInsets.all(16),
          children: mixedChildren(),
        ),
      ),
    ));
    const overdraw = kToolbarHeight + 8.0; // test env: viewPadding.top == 0
    final body = tester.getRect(find.byType(ArxaKitEdgeAwareListView));
    final list = tester.getRect(find.byType(ListView));
    expect(list.height, body.height + overdraw,
        reason: 'the viewport leading edge must sit above the physical top');
    expect(list.bottom, body.bottom,
        reason: 'the trailing edge must not move — only the top overdraws');
    expect(
      (tester.widget<ListView>(find.byType(ListView)).padding as EdgeInsets)
          .top,
      16 + overdraw,
      reason: 'overdraw is returned as top padding so resting layout holds',
    );

    // Default: no overdraw — the list matches its constraints exactly.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ArxaKitEdgeAwareListView(children: mixedChildren()),
      ),
    ));
    expect(tester.getRect(find.byType(ListView)),
        tester.getRect(find.byType(ArxaKitEdgeAwareListView)));
  });

  testWidgets(
      'kit.ui-library.edge-aware-list — no edge configured means no effect at all',
      (tester) async {
    // An edge effect with no chrome on that edge is wrong, not redundant: it
    // would fade content out just before the viewport clips it.
    await tester.pumpWidget(harness(edges: ArxaKitScrollEdges.none));
    expect(effectCount(tester), 0);
  });

  testWidgets(
      'kit.ui-library.edge-aware-list — bottom occlusion treats EVERY child exactly once',
      (tester) async {
    await tester.pumpWidget(
        harness(edges: ArxaKitScrollEdges.bottom, bottomOcclusion: 64));

    // One per child, no more: the count is the anti-double-apply assertion.
    // A child arriving already wrapped (a leaf that still calls the sugar)
    // would push this above the child count.
    expect(effectCount(tester), mixedChildren().length);

    // And every child individually — a total that happens to match while one
    // child is skipped and another double-wrapped would slip past the count.
    for (final key in const ['card', 'spacer', 'toolbar']) {
      expect(
        find.ancestor(
          of: find.byKey(Key(key), skipOffstage: false),
          matching: find.byType(ArxaKitScrollEdgeEffect, skipOffstage: false),
        ),
        findsOneWidget,
        reason: '"$key" must be treated — including the spacer, so the rule '
            'has no exceptions to remember',
      );
    }
  });

  testWidgets(
      'kit.ui-library.edge-aware-list — both edges nest one wrapper per edge per child',
      (tester) async {
    await tester.pumpWidget(harness(bottomOcclusion: 64));
    expect(effectCount(tester), mixedChildren().length * 2);

    for (final key in const ['card', 'spacer', 'toolbar']) {
      expect(
        find.ancestor(
          of: find.byKey(Key(key), skipOffstage: false),
          matching: find.byType(ArxaKitScrollEdgeEffect, skipOffstage: false),
        ),
        findsNWidgets(2),
      );
    }
  });

  testWidgets(
      'kit.ui-library.edge-aware-list — top edge is applied inside bottom',
      (tester) async {
    // Order matters for the geometry each wrapper measures; this preserves the
    // hand-written order the conversion replaced (top applied first, so it
    // ends up the inner wrapper).
    await tester.pumpWidget(harness(bottomOcclusion: 64));

    final wrappers = find
        .ancestor(
          of: find.byKey(const Key('card'), skipOffstage: false),
          matching: find.byType(ArxaKitScrollEdgeEffect, skipOffstage: false),
        )
        .evaluate()
        .map((e) => (e.widget as ArxaKitScrollEdgeEffect).edge)
        .toList();

    // find.ancestor walks outward from the child: innermost first.
    expect(wrappers, [ArxaKitScrollEdge.top, ArxaKitScrollEdge.bottom]);
  });

  testWidgets(
      'kit.ui-library.edge-aware-list — occlusion padding reaches the bottom wrapper',
      (tester) async {
    await tester.pumpWidget(
        harness(edges: ArxaKitScrollEdges.bottom, bottomOcclusion: 64));
    final effect = tester.widget<ArxaKitScrollEdgeEffect>(
      find.byType(ArxaKitScrollEdgeEffect, skipOffstage: false).first,
    );
    expect(effect.edge, ArxaKitScrollEdge.bottom);
    expect(effect.occlusionPadding, 64);
  });

  // -------------------------------------------------------------------------
  // Sliver counterpart — same guarantee inside a CustomScrollView.
  // -------------------------------------------------------------------------

  Widget sliverHarness({
    ArxaKitScrollEdges edges = ArxaKitScrollEdges.both,
    double? bottomOcclusion,
    EdgeInsetsGeometry? padding,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverAppBar(pinned: true, title: Text('Bar')),
              ArxaKitEdgeAwareSliverList(
                edges: edges,
                bottomOcclusion: bottomOcclusion,
                padding: padding,
                itemCount: 3,
                itemBuilder: (context, i) =>
                    SizedBox(key: Key('item$i'), height: 80),
              ),
            ],
          ),
        ),
      );

  testWidgets(
      'kit.ui-library.edge-aware-sliver-list — treats every item exactly once',
      (tester) async {
    await tester.pumpWidget(
        sliverHarness(edges: ArxaKitScrollEdges.bottom, bottomOcclusion: 64));
    expect(effectCount(tester), 3);
    for (var i = 0; i < 3; i++) {
      expect(
        find.ancestor(
          of: find.byKey(Key('item$i'), skipOffstage: false),
          matching: find.byType(ArxaKitScrollEdgeEffect, skipOffstage: false),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets(
      'kit.ui-library.edge-aware-sliver-list — no edge configured means no effect',
      (tester) async {
    await tester.pumpWidget(sliverHarness(edges: ArxaKitScrollEdges.none));
    expect(effectCount(tester), 0);
  });

  testWidgets(
      'kit.ui-library.edge-aware-sliver-list — both edges nest one wrapper per edge, top inside',
      (tester) async {
    await tester.pumpWidget(sliverHarness(bottomOcclusion: 64));
    expect(effectCount(tester), 6);

    final wrappers = find
        .ancestor(
          of: find.byKey(const Key('item0'), skipOffstage: false),
          matching: find.byType(ArxaKitScrollEdgeEffect, skipOffstage: false),
        )
        .evaluate()
        .map((e) => (e.widget as ArxaKitScrollEdgeEffect).edge)
        .toList();
    expect(wrappers, [ArxaKitScrollEdge.top, ArxaKitScrollEdge.bottom]);
  });

  testWidgets(
      'kit.ui-library.edge-aware-sliver-list — padding becomes a SliverPadding, omitted when null',
      (tester) async {
    await tester.pumpWidget(sliverHarness(bottomOcclusion: 64));
    expect(find.byType(SliverPadding, skipOffstage: false), findsNothing);

    await tester.pumpWidget(sliverHarness(
      bottomOcclusion: 64,
      padding: const EdgeInsets.all(16),
    ));
    expect(find.byType(SliverPadding, skipOffstage: false), findsOneWidget);
  });
}
