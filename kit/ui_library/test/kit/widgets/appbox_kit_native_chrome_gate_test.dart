import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_chrome_gate.dart';

/// Counts initState calls — a remount detector. keepAlive mode must never
/// re-init the child (that re-init IS the reappear jank on iOS: new platform
/// view + raster/platform thread merge); unmount mode re-inits by design.
class _InitSpy extends StatefulWidget {
  const _InitSpy({required this.onInit, required this.child});
  final VoidCallback onInit;
  final Widget child;
  @override
  State<_InitSpy> createState() => _InitSpyState();
}

class _InitSpyState extends State<_InitSpy> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  int depth() => CNTabBarRouteObserver.anyModalDepth.value;

  tearDown(() {
    // Drain any depth a test left behind — the counter is a static global
    // (same discipline as kit_native_overlay_test.dart).
    while (depth() > 0) {
      CNTabBarRouteObserver.markAnyModalInactive();
    }
  });

  const childKey = Key('gated-child');
  const gateKey = Key('gate');

  var initCount = 0;
  setUp(() => initCount = 0);

  Widget host({
    AppBoxKitChromeHideMode hideMode = AppBoxKitChromeHideMode.keepAlive,
  }) {
    return Center(
      child: AppBoxKitNativeChromeGate(
        key: gateKey,
        hideMode: hideMode,
        child: _InitSpy(
          onInit: () => initCount++,
          child: const SizedBox(key: childKey, width: 120, height: 50),
        ),
      ),
    );
  }

  /// 1 = child painted, 0 = placeholder painted. Reading the index is reading
  /// the whole hide decision: `RenderIndexedStack` paints, hit-tests and
  /// exposes semantics for only this child.
  int? paintedIndex(WidgetTester tester) => tester
      .widget<IndexedStack>(find.descendant(
          of: find.byKey(gateKey), matching: find.byType(IndexedStack)))
      .index;

  /// Every element below the gate. Must be identical hidden vs shown: a tree
  /// whose shape changes at the toggle reparents the platform view, which is
  /// the native re-init this gate exists to prevent.
  int nodeCount(WidgetTester tester) {
    var n = 0;
    void visit(Element e) {
      n++;
      e.visitChildren(visit);
    }

    tester.element(find.byKey(gateKey)).visitChildren(visit);
    return n;
  }

  testWidgets(
      'kit.ui-library.native-chrome-gate — nothing in the tree animates the platform view',
      (tester) async {
    // The regression this file exists for. The gate used to dematerialize with
    // FadeTransition + ScaleTransition. Animating alpha across a platform-view
    // subtree is unsupported (flutter#93757, flutter#24164 — both OPEN), costly
    // (per-frame native layer mutation) and against Apple's own instruction to
    // prefer `effect` over alpha (WWDC25 #284). If either transition comes
    // back, the reappear-on-back artifact comes back with it.
    await tester.pumpWidget(host());
    expect(find.byType(FadeTransition, skipOffstage: false), findsNothing);
    expect(find.byType(ScaleTransition, skipOffstage: false), findsNothing);
    expect(find.byType(Opacity, skipOffstage: false), findsNothing);
    expect(find.byType(AnimatedOpacity, skipOffstage: false), findsNothing);
  });

  testWidgets(
      'kit.ui-library.native-chrome-gate — visible at depth 0: child is the painted index',
      (tester) async {
    await tester.pumpWidget(host());
    expect(find.byKey(childKey), findsOneWidget);
    expect(paintedIndex(tester), 1);
  });

  testWidgets(
      'kit.ui-library.native-chrome-gate — keepAlive hide is INSTANT and complete in one frame',
      (tester) async {
    await tester.pumpWidget(host());
    final shownSize = tester.getSize(find.byKey(gateKey));
    final shownNodes = nodeCount(tester);

    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();

    expect(paintedIndex(tester), 0,
        reason: 'one frame is the whole hide — no ramp to sit through');

    // The two halves of "unpainted but alive", asserted separately because
    // each without the other is the bug. Default finders skip offstage
    // subtrees, and Flutter counts a non-selected IndexedStack child as
    // offstage — so this pair says: genuinely off the frame (the platform view
    // leaves the native hierarchy and cannot bleed), yet still mounted (no
    // re-init, no thread-merge stall on restore).
    expect(find.byKey(childKey), findsNothing,
        reason: 'not painted: an unhidden child would still be leaking over '
            'the route slide');
    expect(find.byKey(childKey, skipOffstage: false), findsOneWidget,
        reason: 'still mounted: unmounting is what re-creates the native view');
    expect(tester.getSize(find.byKey(gateKey)), shownSize,
        reason: 'RenderIndexedStack lays out every child, so an empty '
            'placeholder cannot collapse the footprint');
    expect(nodeCount(tester), shownNodes,
        reason: 'tree shape must not change at the toggle — only the index');
    expect(initCount, 1);

    // Nothing is in flight: settling changes nothing.
    await tester.pump(const Duration(milliseconds: 400));
    expect(paintedIndex(tester), 0);
    expect(initCount, 1);
  });

  testWidgets(
      'kit.ui-library.native-chrome-gate — keepAlive restore is INSTANT and remounts nothing '
      '(the anti-jank guarantee)', (tester) async {
    await tester.pumpWidget(host());
    final shownNodes = nodeCount(tester);

    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();
    expect(paintedIndex(tester), 0);

    CNTabBarRouteObserver.markAnyModalInactive();
    await tester.pump();

    expect(paintedIndex(tester), 1,
        reason: 'restored in the frame the signal cleared — this is what makes '
            'chrome arrive WITH the settled route instead of zooming in after '
            'it');
    expect(nodeCount(tester), shownNodes);
    expect(initCount, 1,
        reason: 'child must NEVER re-init in keepAlive mode — a remount '
            'means a new platform view + thread-merge stall (the jank)');

    await tester.pump(const Duration(milliseconds: 400));
    expect(paintedIndex(tester), 1,
        reason: 'and it stays put; nothing was animating');
  });

  testWidgets(
      'kit.ui-library.native-chrome-gate — a full hide/show cycle costs zero remounts',
      (tester) async {
    await tester.pumpWidget(host());
    for (var i = 0; i < 5; i++) {
      CNTabBarRouteObserver.markAnyModalActive();
      await tester.pump();
      CNTabBarRouteObserver.markAnyModalInactive();
      await tester.pump();
    }
    expect(initCount, 1,
        reason: 'five navigations must not cost five native re-inits');
    expect(paintedIndex(tester), 1);
  });

  testWidgets(
      'kit.ui-library.native-chrome-gate — unmount mode (escape hatch): child destroyed, '
      'exact-size placeholder, restore remounts', (tester) async {
    await tester.pumpWidget(host(hideMode: AppBoxKitChromeHideMode.unmount));
    final shownSize = tester.getSize(find.byKey(gateKey));

    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();
    expect(find.byKey(childKey, skipOffstage: false), findsNothing,
        reason: 'unmount mode really unmounts — gone from the tree entirely, '
            'not merely offstage the way keepAlive leaves it');
    expect(tester.getSize(find.byKey(gateKey)), shownSize,
        reason: 'measured placeholder holds the footprint');

    CNTabBarRouteObserver.markAnyModalInactive();
    await tester.pump();
    expect(find.byKey(childKey), findsOneWidget);
    expect(initCount, 2, reason: 'remount is inherent to this mode');
  });

  testWidgets(
      'kit.ui-library.native-chrome-gate — mount-depth snapshot: a gate mounted INSIDE an open modal does not '
      'self-destroy, but hides when depth grows past its baseline',
      (tester) async {
    CNTabBarRouteObserver.markAnyModalActive(); // depth 1 BEFORE mount
    await tester.pumpWidget(host());
    expect(paintedIndex(tester), 1,
        reason: 'baseline is the mount-time depth, not zero');

    CNTabBarRouteObserver.markAnyModalActive(); // depth 2 > baseline 1
    await tester.pump();
    expect(paintedIndex(tester), 0);

    CNTabBarRouteObserver.markAnyModalInactive(); // back to baseline
    await tester.pump();
    expect(paintedIndex(tester), 1);
    expect(initCount, 1);
  });
}
