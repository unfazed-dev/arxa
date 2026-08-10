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
}
