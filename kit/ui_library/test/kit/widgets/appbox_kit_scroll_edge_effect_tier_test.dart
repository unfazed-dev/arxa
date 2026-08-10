import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// The blur half of [AppBoxKitScrollEdgeEffect] is frosted-tier only.
///
/// `ImageFilterLayer` filters Flutter's painted output. On the Liquid Glass
/// tier the kit's content surfaces are platform views composited natively, so
/// the filter reaches a card's text but never the glass slab beneath it —
/// softening labels on a crisp slab. Opacity still applies (it is the mutator
/// iOS hybrid composition handles reliably), so the surface fades as one piece
/// instead.
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
      'kit.ui-library.scroll-edge-effect — Liquid Glass tier fades without a filter layer',
      (tester) async {
    AppBoxKitPlatform.override = const AppBoxKitPlatformOverride(
      isIOS: true,
      iosMajor: 26,
    );
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));
    await engage(tester, controller);

    // Same coverage, same fade — only the filter is gone.
    expect(alpha(tester), lessThan(1.0),
        reason: 'the fade is tier-independent; only the blur is gated');
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
