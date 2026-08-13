import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// [AppBoxKitEdgeAwareListView] moves the scroll edge treatment from the leaf
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
    bool topEdge = false,
    double? bottomOcclusion,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: AppBoxKitEdgeAwareListView(
            topEdge: topEdge,
            bottomOcclusion: bottomOcclusion,
            children: mixedChildren(),
          ),
        ),
      );

  int effectCount(WidgetTester tester) =>
      find.byType(AppBoxKitScrollEdgeEffect, skipOffstage: false).evaluate().length;

  testWidgets(
      'kit.ui-library.edge-aware-list — clipBehavior forwards to the ListView '
      '(Clip.none = platform views cull at the screen edge, not the bar seam)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppBoxKitEdgeAwareListView(
          clipBehavior: Clip.none,
          children: mixedChildren(),
        ),
      ),
    ));
    expect(
      tester.widget<ListView>(find.byType(ListView)).clipBehavior,
      Clip.none,
      reason: 'under an opaque bar the viewport clip is what culls a native '
          'view at the seam and re-materializes it on re-entry (clip 12-48); '
          'Clip.none must reach the ListView for the transit fix to hold',
    );
    // Default stays hardEdge — Clip.none is only safe under OPAQUE chrome.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppBoxKitEdgeAwareListView(children: mixedChildren()),
      ),
    ));
    expect(tester.widget<ListView>(find.byType(ListView)).clipBehavior,
        Clip.hardEdge);
  });

  testWidgets(
      'kit.ui-library.edge-aware-list — no edge configured means no effect at all',
      (tester) async {
    // An edge effect with no chrome on that edge is wrong, not redundant: it
    // would fade content out just before the viewport clips it.
    await tester.pumpWidget(harness());
    expect(effectCount(tester), 0);
  });

  testWidgets(
      'kit.ui-library.edge-aware-list — bottom occlusion treats EVERY child exactly once',
      (tester) async {
    await tester.pumpWidget(harness(bottomOcclusion: 64));

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
          matching: find.byType(AppBoxKitScrollEdgeEffect, skipOffstage: false),
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
    await tester.pumpWidget(harness(topEdge: true, bottomOcclusion: 64));
    expect(effectCount(tester), mixedChildren().length * 2);

    for (final key in const ['card', 'spacer', 'toolbar']) {
      expect(
        find.ancestor(
          of: find.byKey(Key(key), skipOffstage: false),
          matching: find.byType(AppBoxKitScrollEdgeEffect, skipOffstage: false),
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
    await tester.pumpWidget(harness(topEdge: true, bottomOcclusion: 64));

    final wrappers = find
        .ancestor(
          of: find.byKey(const Key('card'), skipOffstage: false),
          matching: find.byType(AppBoxKitScrollEdgeEffect, skipOffstage: false),
        )
        .evaluate()
        .map((e) => (e.widget as AppBoxKitScrollEdgeEffect).edge)
        .toList();

    // find.ancestor walks outward from the child: innermost first.
    expect(wrappers, [AppBoxKitScrollEdge.top, AppBoxKitScrollEdge.bottom]);
  });

  testWidgets(
      'kit.ui-library.edge-aware-list — occlusion padding reaches the bottom wrapper',
      (tester) async {
    await tester.pumpWidget(harness(bottomOcclusion: 64));
    final effect = tester.widget<AppBoxKitScrollEdgeEffect>(
      find.byType(AppBoxKitScrollEdgeEffect, skipOffstage: false).first,
    );
    expect(effect.edge, AppBoxKitScrollEdge.bottom);
    expect(effect.occlusionPadding, 64);
  });

  // -------------------------------------------------------------------------
  // Sliver counterpart — same guarantee inside a CustomScrollView.
  // -------------------------------------------------------------------------

  Widget sliverHarness({
    bool topEdge = false,
    double? bottomOcclusion,
    EdgeInsetsGeometry? padding,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverAppBar(pinned: true, title: Text('Bar')),
              AppBoxKitEdgeAwareSliverList(
                topEdge: topEdge,
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
    await tester.pumpWidget(sliverHarness(bottomOcclusion: 64));
    expect(effectCount(tester), 3);
    for (var i = 0; i < 3; i++) {
      expect(
        find.ancestor(
          of: find.byKey(Key('item$i'), skipOffstage: false),
          matching: find.byType(AppBoxKitScrollEdgeEffect, skipOffstage: false),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets(
      'kit.ui-library.edge-aware-sliver-list — no edge configured means no effect',
      (tester) async {
    await tester.pumpWidget(sliverHarness());
    expect(effectCount(tester), 0);
  });

  testWidgets(
      'kit.ui-library.edge-aware-sliver-list — both edges nest one wrapper per edge, top inside',
      (tester) async {
    await tester.pumpWidget(sliverHarness(topEdge: true, bottomOcclusion: 64));
    expect(effectCount(tester), 6);

    final wrappers = find
        .ancestor(
          of: find.byKey(const Key('item0'), skipOffstage: false),
          matching: find.byType(AppBoxKitScrollEdgeEffect, skipOffstage: false),
        )
        .evaluate()
        .map((e) => (e.widget as AppBoxKitScrollEdgeEffect).edge)
        .toList();
    expect(wrappers, [AppBoxKitScrollEdge.top, AppBoxKitScrollEdge.bottom]);
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
