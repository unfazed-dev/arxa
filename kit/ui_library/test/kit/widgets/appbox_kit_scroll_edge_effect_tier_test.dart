import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// [AppBoxKitScrollEdgeEffect] is frosted-tier only — BOTH halves.
///
/// Blur: `ImageFilterLayer` filters Flutter's painted output; on the Liquid
/// Glass tier content surfaces are platform views composited natively, so the
/// filter reaches a card's text but never the glass beneath it.
///
/// Alpha (gated 2026-08-13, clip 12-48): with the informed allowlist, scroll
/// content on the glass tier hosts real platform views, and a partial-alpha
/// fade lands as per-frame native view mutations — glyphs wash out ahead of
/// the shell and content pops on re-entry (home's smoke row / Glass CTA on
/// device). The kit's bars are opaque on this tier, and iOS clips crisply
/// under opaque chrome, so the glass tier renders the effect fully inert.
void main() {
  const effectKey = Key('effect');

  tearDown(AppBoxKitPlatform.reset);

  Widget harness(ScrollController controller) => MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: controller,
            slivers: [
              const SliverAppBar(
                pinned: true,
                expandedHeight: 160,
                title: Text('Bar'),
              ),
              const SliverToBoxAdapter(
                child: AppBoxKitScrollEdgeEffect(
                  key: effectKey,
                  child: SizedBox(height: 48, width: 48),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      );

  bool blurLayerActive(WidgetTester tester) =>
      tester.layers.whereType<ImageFilterLayer>().isNotEmpty;

  double alpha(WidgetTester tester) => tester
      .widget<Opacity>(find.descendant(
        of: find.byKey(effectKey, skipOffstage: false),
        matching: find.byType(Opacity, skipOffstage: false),
        skipOffstage: false,
      ))
      .opacity;

  /// Scrolls until the child is fully covered by the collapsed pinned bar.
  Future<void> engage(WidgetTester tester, ScrollController controller) async {
    controller.jumpTo(160);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'kit.ui-library.scroll-edge-effect — frosted tier blurs when engaged (control)',
      (tester) async {
    // The control. Without it the glass-tier assertion below is vacuous: it
    // would pass just as happily if the effect never engaged at all.
    AppBoxKitPlatform.override =
        const AppBoxKitPlatformOverride(isIOS: false);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));
    await engage(tester, controller);

    expect(alpha(tester), lessThan(1.0),
        reason: 'the effect must actually be engaged for this to mean anything');
    expect(blurLayerActive(tester), isTrue,
        reason: 'frosted tier: content is Flutter-drawn, so the blur applies');
  });

  testWidgets(
      'kit.ui-library.scroll-edge-effect — Liquid Glass tier is fully inert '
      'even when engaged (no fade, no filter layer)', (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(
      isIOS: true,
      iosMajor: 26,
    );
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));
    await engage(tester, controller);

    // Same coverage as the frosted control above — but nothing may engage:
    // in-scroll content hosts platform views on this tier (informed
    // allowlist), a partial-alpha fade over a UiKitView ghosts and pops on
    // device (clip 12-48), and the opaque bar means iOS would clip crisply
    // here anyway. Zero layers is also the lean path.
    expect(alpha(tester), 1.0,
        reason: 'glass tier: no partial-alpha saveLayer may wrap a subtree '
            'that can host platform views — children exit by viewport clip');
    expect(blurLayerActive(tester), isFalse,
        reason: 'no ImageFilterLayer may wrap a subtree whose surface becomes '
            'a UiKitView on device — the filter cannot reach its pixels');
  });

  testWidgets(
      'kit.ui-library.scroll-edge-effect — glass tier keeps the wrapper chain at identity when clear',
      (tester) async {
    // The tier gate must not change the tree shape: the constant node count is
    // what keeps a platform view from being unmounted at threshold crossings.
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(
      isIOS: true,
      iosMajor: 26,
    );
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));

    expect(alpha(tester), 1.0);
    expect(blurLayerActive(tester), isFalse);
    expect(
      find.descendant(
        of: find.byKey(effectKey, skipOffstage: false),
        matching: find.byType(ClipRect, skipOffstage: false),
        skipOffstage: false,
      ),
      findsOneWidget,
      reason: 'the ClipRect stays mounted on every tier, driven to Clip.none',
    );
  });
}
