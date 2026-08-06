import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// iOS 26 scroll edge effect (ADR 0010): scrolled CONTENT softens —
/// progressive blur + fade — where it underlaps pinned chrome; the chrome
/// itself is never hidden. Geometry mirrors the retired scroll gate's:
/// coverage comes from the viewport's getOffsetToReveal, so pinned slivers
/// fold in with zero configuration.
void main() {
  const effectKey = Key('effect');
  const markerKey = Key('marker');

  Widget harness({
    required ScrollController controller,
    AppBoxKitScrollEdgeEffectStyle style = AppBoxKitScrollEdgeEffectStyle.automatic,
    AppBoxKitScrollEdge edge = AppBoxKitScrollEdge.top,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            const SliverAppBar(
              pinned: true,
              expandedHeight: 160,
              title: Text('Bar'),
            ),
            SliverToBoxAdapter(
              child: AppBoxKitScrollEdgeEffect(
                key: effectKey,
                style: style,
                edge: edge,
                child: const SizedBox(key: markerKey, height: 48, width: 48),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 2000)),
          ],
        ),
      ),
    );
  }

  // A fully-covered child sits outside the viewport's visible band, and
  // finders treat culled sliver children as offstage — every lookup here
  // must opt out of skipOffstage (same discipline as the occlusion gate
  // test).
  T effectDescendant<T extends Widget>(WidgetTester tester) {
    return tester.widget<T>(find.descendant(
      of: find.byKey(effectKey, skipOffstage: false),
      matching: find.byType(T, skipOffstage: false),
      skipOffstage: false,
    ));
  }

  Finder effectDescendantFinder(Type type) {
    return find.descendant(
      of: find.byKey(effectKey, skipOffstage: false),
      matching: find.byType(type, skipOffstage: false),
      skipOffstage: false,
    );
  }

  double effectAlpha(WidgetTester tester) =>
      effectDescendant<Opacity>(tester).opacity;

  // Geometry: child top starts at 160 (below the expanded bar). Collapsed
  // pinned extent = kToolbarHeight (56) with zero window padding. Covered
  // fraction = (56 - (160 - pixels)) / 48.
  testWidgets('kit.ui-library.scroll-edge-effect — child fully clear of the edge builds its bare subtree',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));

    expect(effectDescendantFinder(ImageFiltered), findsNothing);
    expect(effectDescendantFinder(Opacity), findsNothing);
    expect(find.byKey(markerKey), findsOneWidget);
  });

  testWidgets(
      'kit.ui-library.scroll-edge-effect — partially covered child blurs and fades progressively '
      '(automatic resolves to soft)', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));

    controller.jumpTo(128); // half of the 48px child under the 56px bar
    await tester.pump();

    // t = 0.5 → soft math: alpha = 1 - 0.85 * 0.5 = 0.575 (hard would be
    // 0.5, so this pins automatic → soft).
    expect(effectAlpha(tester), closeTo(0.575, 0.001));
    expect(effectDescendantFinder(ImageFiltered), findsOneWidget);
    expect(effectDescendant<IgnorePointer>(tester).ignoring, isFalse);
  });

  testWidgets('kit.ui-library.scroll-edge-effect — fully covered child — soft keeps a faint remnant',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(
      controller: controller,
      style: AppBoxKitScrollEdgeEffectStyle.soft,
    ));

    controller.jumpTo(300); // well past full coverage (>=152)
    await tester.pump();

    // t = 1 → alpha = 1 - 0.85 = 0.15: the content reads through the blur,
    // it is never hard-hidden — and it keeps taking pointers.
    expect(effectAlpha(tester), closeTo(0.15, 0.001));
    expect(effectDescendantFinder(ImageFiltered), findsOneWidget);
    expect(effectDescendant<IgnorePointer>(tester).ignoring, isFalse);
    expect(find.byKey(markerKey, skipOffstage: false), findsOneWidget);
  });

  testWidgets('kit.ui-library.scroll-edge-effect — hard style fully obscures and ignores pointers', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(
      controller: controller,
      style: AppBoxKitScrollEdgeEffectStyle.hard,
    ));

    controller.jumpTo(300);
    await tester.pump();

    expect(effectAlpha(tester), 0.0);
    expect(effectDescendant<IgnorePointer>(tester).ignoring, isTrue);
    // Child stays mounted — nothing ever unmounts under the edge effect.
    expect(find.byKey(markerKey, skipOffstage: false), findsOneWidget);
  });

  testWidgets('kit.ui-library.scroll-edge-effect — restores to a bare subtree when scrolled back out',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));

    controller.jumpTo(300);
    await tester.pump();
    expect(effectDescendantFinder(ImageFiltered), findsOneWidget);

    controller.jumpTo(0);
    await tester.pump();
    expect(effectDescendantFinder(ImageFiltered), findsNothing);
    expect(effectDescendantFinder(Opacity), findsNothing);
  });

  testWidgets('kit.ui-library.scroll-edge-effect — bottom edge fades content straddling the trailing fold',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    // 600px-tall test viewport, no pinned chrome: spacer 560 + child 48 →
    // the child's bottom 8px poke past the trailing fold → covered = 8,
    // t = 8/48 quantized to 0.16.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 560)),
            SliverToBoxAdapter(
              child: AppBoxKitScrollEdgeEffect(
                key: effectKey,
                edge: AppBoxKitScrollEdge.bottom,
                child: const SizedBox(key: markerKey, height: 48, width: 48),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 2000)),
          ],
        ),
      ),
    ));
    // The initial coverage recompute lands in a post-frame callback, so its
    // setState only rebuilds on the next frame.
    await tester.pump();

    // t = 0.16 → soft alpha = 1 - 0.85 * 0.16 = 0.864.
    expect(effectAlpha(tester), closeTo(0.864, 0.01));
    expect(effectDescendantFinder(ImageFiltered), findsOneWidget);

    controller.jumpTo(24); // child bottom fully above the fold
    await tester.pump();
    expect(effectDescendantFinder(ImageFiltered), findsNothing);
    expect(effectDescendantFinder(Opacity), findsNothing);
  });

  testWidgets('kit.ui-library.scroll-edge-effect — .scrollEdgeEffect() extension wraps child in an effect',
      (tester) async {
    const childKey = Key('ext-child');
    final wrapped = const SizedBox(key: childKey, height: 40).scrollEdgeEffect(
      style: AppBoxKitScrollEdgeEffectStyle.hard,
      edge: AppBoxKitScrollEdge.bottom,
      occlusionPadding: 8,
    );

    expect(wrapped, isA<AppBoxKitScrollEdgeEffect>());
    final effect = wrapped as AppBoxKitScrollEdgeEffect;
    expect(effect.style, AppBoxKitScrollEdgeEffectStyle.hard);
    expect(effect.edge, AppBoxKitScrollEdge.bottom);
    expect(effect.occlusionPadding, 8);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: wrapped)));
    expect(
      find.ancestor(
        of: find.byKey(childKey),
        matching: find.byType(AppBoxKitScrollEdgeEffect),
      ),
      findsOneWidget,
    );
  });
}
