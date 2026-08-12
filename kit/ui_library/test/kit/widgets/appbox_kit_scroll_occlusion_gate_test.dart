import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Repro for the liquid-glass scroll ghost: a platform-view-backed widget
/// scrolling under a pinned app bar is never occluded natively (UiKitViews
/// composite ABOVE the Flutter scene), so it must be driven to alpha 0 —
/// which drops it from the layer tree and detaches the native view — by the
/// time its slot is fully covered.
void main() {
  const gateKey = Key('gate');
  const markerKey = Key('marker');

  Widget harness({
    required ScrollController controller,
    AppBoxKitChromeHideMode hideMode = AppBoxKitChromeHideMode.keepAlive,
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
              child: AppBoxKitScrollOcclusionGate(
                key: gateKey,
                hideMode: hideMode,
                child: const SizedBox(key: markerKey, height: 48, width: 48),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 2000)),
          ],
        ),
      ),
    );
  }

  // A fully-covered gate sits outside the viewport's visible band, and
  // finders treat culled sliver children as offstage — every lookup here
  // must opt out of skipOffstage or the hide-path assertions can't see the
  // (intentionally still-mounted) subtree.
  T gateDescendant<T extends Widget>(WidgetTester tester) {
    return tester.widget<T>(find.descendant(
      of: find.byKey(gateKey, skipOffstage: false),
      matching: find.byType(T, skipOffstage: false),
      skipOffstage: false,
    ));
  }

  double gateAlpha(WidgetTester tester) => gateDescendant<Opacity>(tester).opacity;

  // Geometry: gate top starts at 160 (below the expanded bar). Collapsed
  // pinned extent = kToolbarHeight (56) with zero window padding. Covered
  // fraction = (56 - (160 - pixels)) / 48.
  testWidgets('kit.ui-library.scroll-occlusion-gate — fully visible child paints at alpha 1', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));
    expect(gateAlpha(tester), 1.0);
  });

  testWidgets('kit.ui-library.scroll-occlusion-gate — partially covered child fades proportionally', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));

    controller.jumpTo(128); // half of the 48px child under the 56px bar
    await tester.pump();

    final alpha = gateAlpha(tester);
    expect(alpha, greaterThan(0.2));
    expect(alpha, lessThan(0.8));
  });

  testWidgets('kit.ui-library.scroll-occlusion-gate — fully covered child snaps to alpha 0 and ignores pointers',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));

    controller.jumpTo(300); // well past full coverage (>=152)
    await tester.pump();

    expect(gateAlpha(tester), 0.0);
    expect(gateDescendant<IgnorePointer>(tester).ignoring, isTrue);

    // Child stays mounted in keepAlive mode — the whole point: no native
    // re-init on restore.
    expect(find.byKey(markerKey, skipOffstage: false), findsOneWidget);
  });

  testWidgets('kit.ui-library.scroll-occlusion-gate — restores to alpha 1 when scrolled back out', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller: controller));

    controller.jumpTo(300);
    await tester.pump();
    controller.jumpTo(0);
    await tester.pump();

    expect(gateAlpha(tester), 1.0);
    expect(gateDescendant<IgnorePointer>(tester).ignoring, isFalse);
  });

  testWidgets('kit.ui-library.scroll-occlusion-gate — unmount mode swaps in a same-size placeholder when covered',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(
      controller: controller,
      hideMode: AppBoxKitChromeHideMode.unmount,
    ));

    final sizeBefore = tester.getSize(find.byKey(gateKey));

    controller.jumpTo(300);
    await tester.pump();

    // skipOffstage:false so this asserts real destruction, not mere culling.
    expect(find.byKey(markerKey, skipOffstage: false), findsNothing);
    expect(
      tester.getSize(find.byKey(gateKey, skipOffstage: false)),
      sizeBefore, // no layout shift
    );

    controller.jumpTo(0);
    await tester.pump();
    expect(find.byKey(markerKey), findsOneWidget); // re-mounted
  });

  group('modal depth', () {
    // The gate must also hide under kit sheets/popups: a platform view under
    // a modal barrier still composites above the blur, so any modal opened
    // *after* the gate mounted must drive it to alpha 0.
    // Drain any depth a test left behind — the counter is a static global
    // (same discipline as kit_native_chrome_gate_test.dart).
    tearDown(() {
      while (CNTabBarRouteObserver.anyModalDepth.value > 0) {
        CNTabBarRouteObserver.markAnyModalInactive();
      }
    });

    testWidgets('kit.ui-library.scroll-occlusion-gate — hides while a modal opened above it is active',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller: controller));
      expect(gateAlpha(tester), 1.0);

      CNTabBarRouteObserver.markAnyModalActive(); // sheet presented
      await tester.pump();
      expect(gateAlpha(tester), 0.0);
      expect(gateDescendant<IgnorePointer>(tester).ignoring, isTrue);

      CNTabBarRouteObserver.markAnyModalInactive(); // sheet dismissed
      await tester.pump();
      expect(gateAlpha(tester), 1.0);
      expect(gateDescendant<IgnorePointer>(tester).ignoring, isFalse);
    });

    testWidgets('kit.ui-library.scroll-occlusion-gate — gate mounted inside an open modal stays visible',
        (tester) async {
      // Content *inside* a sheet captures the depth at mount time — only
      // modals opened above it may hide it.
      CNTabBarRouteObserver.markAnyModalActive();
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller: controller));
      expect(gateAlpha(tester), 1.0); // not hidden by its own host modal

      CNTabBarRouteObserver.markAnyModalActive(); // modal above the sheet
      await tester.pump();
      expect(gateAlpha(tester), 0.0);

      CNTabBarRouteObserver.markAnyModalInactive();
      await tester.pump();
      expect(gateAlpha(tester), 1.0);
    });
  });

  testWidgets('kit.ui-library.scroll-occlusion-gate — .scrollOcclusion() extension wraps child in a gate',
      (tester) async {
    const childKey = Key('ext-child');
    final gated = const SizedBox(key: childKey, height: 40)
        .scrollOcclusion(occlusionPadding: 8, hideMode: AppBoxKitChromeHideMode.unmount);

    expect(gated, isA<AppBoxKitScrollOcclusionGate>());
    final gate = gated as AppBoxKitScrollOcclusionGate;
    expect(gate.occlusionPadding, 8);
    expect(gate.hideMode, AppBoxKitChromeHideMode.unmount);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: gated)));
    expect(
      find.ancestor(
        of: find.byKey(childKey),
        matching: find.byType(AppBoxKitScrollOcclusionGate),
      ),
      findsOneWidget,
    );
  });
}
