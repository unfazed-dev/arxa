import 'package:cupertino_native_better/cupertino_native.dart'
    show CNTabBarRouteObserver, CNTransitionObserver;
import 'package:flutter/cupertino.dart';
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
  tearDown(() {
    // Drain any modal depth a test left behind — the counter is a static
    // global (same discipline as kit_native_overlay_test.dart).
    CNTabBarRouteObserver.publishTopModalRect(null);
    while (CNTabBarRouteObserver.anyModalDepth.value > 0) {
      CNTabBarRouteObserver.markAnyModalInactive();
    }
  });

  const childKey = Key('gated-child');
  const gateKey = Key('gate');

  var initCount = 0;
  setUp(() {
    initCount = 0;
    CNTransitionObserver.resetForTesting();
  });

  final navKey = GlobalKey<NavigatorState>();

  Widget host({
    AppBoxKitChromeHideMode hideMode = AppBoxKitChromeHideMode.keepAlive,
  }) {
    return CupertinoApp(
      navigatorKey: navKey,
      navigatorObservers: <NavigatorObserver>[CNTransitionObserver()],
      home: Center(
        child: AppBoxKitNativeChromeGate(
          key: gateKey,
          hideMode: hideMode,
          child: _InitSpy(
            onInit: () => initCount++,
            child: const SizedBox(key: childKey, width: 120, height: 50),
          ),
        ),
      ),
    );
  }

  /// The gate's only remaining hide authority is a REAL opaque route
  /// transition above it (`CNTransitionObserver.hasActiveTransitionAbove`).
  /// Modal depth and sheet rects were removed as channels — a sheet or dialog
  /// leaves the page below visible for its whole lifetime, so hiding on it IS
  /// the "glass vanishes, then pops back" defect. Tests therefore drive the
  /// hide the way production does: push, then hold the transition mid-flight.
  /// Assertions about the hidden state must happen mid-flight — once an
  /// opaque push SETTLES, the Navigator offstages the whole home route and a
  /// default finder goes empty for reasons that have nothing to do with the
  /// gate.
  Future<void> beginCover(WidgetTester tester) async {
    navKey.currentState!.push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => const SizedBox.expand(),
    ));
    await tester.pump(); // the frame the transition starts — and the hide
  }

  Future<void> abandonCover(WidgetTester tester) async {
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
  }

  /// 1 = child painted, 0 = placeholder painted. Reading the index is reading
  /// the whole hide decision: `RenderIndexedStack` paints, hit-tests and
  /// exposes semantics for only this child.
  int? paintedIndex(WidgetTester tester) => tester
      .widget<IndexedStack>(find.descendant(
          of: find.byKey(gateKey, skipOffstage: false),
          matching: find.byType(IndexedStack, skipOffstage: false)))
      .index;

  /// Every element below the gate. A coarse shape check only — note its limit:
  /// an `IndexedStack` always builds BOTH children, so this stays constant for
  /// structural reasons that have nothing to do with the invariant, and it
  /// would keep passing under a conditional wrapper that really did reparent
  /// the child. `initCount` is the actual reparenting guard; this is here to
  /// catch gross shape changes, not to prove mount stability.
  int nodeCount(WidgetTester tester) {
    var n = 0;
    void visit(Element e) {
      n++;
      e.visitChildren(visit);
    }

    tester
        .element(find.byKey(gateKey, skipOffstage: false))
        .visitChildren(visit);
    return n;
  }

  testWidgets(
      'kit.ui-library.native-chrome-gate — CONTRACT: hidden means unpainted, mounted, '
      'same size, same instance — stated without naming the mechanism',
      (tester) async {
    // Every other test in this file reads the IndexedStack index, which is a
    // mechanism-shaped assertion: swap the implementation for Opacity(0) or
    // Offstage and those either stop compiling or get rewritten, taking the
    // real guarantee with them. This one is written in observables the gate's
    // CALLERS depend on, so it keeps holding the line across any such swap.
    await tester.pumpWidget(host());
    final shownSize = tester.getSize(find.byKey(gateKey));
    expect(find.byKey(childKey), findsOneWidget);

    await beginCover(tester);
    await tester.pump(const Duration(milliseconds: 50)); // mid-flight

    expect(find.byKey(childKey), findsNothing,
        reason: 'NOT PAINTED — a platform view still in the frame floats over '
            'the route slide, which is the whole bug the gate exists for');
    expect(find.byKey(childKey, skipOffstage: false), findsOneWidget,
        reason: 'STILL MOUNTED — unmounting destroys the native view and buys '
            'a re-init + thread-merge stall on the way back');
    expect(tester.getSize(find.byKey(gateKey, skipOffstage: false)), shownSize,
        reason: 'SAME FOOTPRINT — a collapsing box reflows the layout around '
            'it mid-transition');
    expect(initCount, 1,
        reason: 'SAME INSTANCE — this is the reparenting '
            'guard: any wrapper swap that re-parents the child shows up here as a '
            'second initState, whatever the hide mechanism is called');

    await abandonCover(tester);
    expect(find.byKey(childKey), findsOneWidget);
    expect(tester.getSize(find.byKey(gateKey)), shownSize);
    expect(initCount, 1);
  });

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
    final inGate = find.descendant(
        of: find.byKey(gateKey, skipOffstage: false),
        matching: find.byType(FadeTransition, skipOffstage: false));
    expect(inGate, findsNothing);
    expect(
        find.descendant(
            of: find.byKey(gateKey, skipOffstage: false),
            matching: find.byType(ScaleTransition, skipOffstage: false)),
        findsNothing);
    expect(
        find.descendant(
            of: find.byKey(gateKey, skipOffstage: false),
            matching: find.byType(Opacity, skipOffstage: false)),
        findsNothing);
    expect(
        find.descendant(
            of: find.byKey(gateKey, skipOffstage: false),
            matching: find.byType(AnimatedOpacity, skipOffstage: false)),
        findsNothing);
  });

  testWidgets(
      'kit.ui-library.native-chrome-gate — visible when no transition is running: '
      'child is the painted index', (tester) async {
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

    await beginCover(tester);

    expect(paintedIndex(tester), 0,
        reason: 'the frame the transition starts is the whole hide — no ramp '
            'to sit through');

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
    expect(tester.getSize(find.byKey(gateKey, skipOffstage: false)), shownSize,
        reason: 'RenderIndexedStack lays out every child, so an empty '
            'placeholder cannot collapse the footprint');
    expect(nodeCount(tester), shownNodes,
        reason: 'tree shape must not change at the toggle — only the index');
    expect(initCount, 1);

    // Still hidden while the push keeps sliding.
    await tester.pump(const Duration(milliseconds: 150));
    expect(paintedIndex(tester), 0);
    expect(initCount, 1);
  });

  testWidgets(
      'kit.ui-library.native-chrome-gate — keepAlive restore remounts nothing '
      '(the anti-jank guarantee)', (tester) async {
    await tester.pumpWidget(host());
    final shownNodes = nodeCount(tester);

    await beginCover(tester);
    expect(paintedIndex(tester), 0);

    await abandonCover(tester);

    expect(paintedIndex(tester), 1,
        reason: 'restored when the transition ends — this is what makes '
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
      await beginCover(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await abandonCover(tester);
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

    await beginCover(tester);
    expect(find.byKey(childKey, skipOffstage: false), findsNothing,
        reason: 'unmount mode really unmounts — gone from the tree entirely, '
            'not merely offstage the way keepAlive leaves it');
    expect(tester.getSize(find.byKey(gateKey, skipOffstage: false)), shownSize,
        reason: 'measured placeholder holds the footprint');

    await abandonCover(tester);
    expect(find.byKey(childKey), findsOneWidget);
    expect(initCount, 2, reason: 'remount is inherent to this mode');
  });

  testWidgets(
      'kit.ui-library.native-chrome-gate — modal depth and sheet rects are NOT hide '
      'channels: a sheet or dialog above keeps the gate painted',
      (tester) async {
    // The removed defect, pinned. A sheet/dialog/popup is `opaque: false`; the
    // page below stays visible for its whole lifetime, so hiding on modal
    // depth or rect coverage IS the user-visible blink: chrome dematerializes
    // on open and pops back on dismiss. Only a real opaque route transition
    // may hide.
    await tester.pumpWidget(host());

    CNTabBarRouteObserver.markAnyModalActive();
    await tester.pump();
    expect(paintedIndex(tester), 1,
        reason: 'modal depth alone must not blank chrome any more');

    CNTabBarRouteObserver.publishTopModalRect(
      const Rect.fromLTRB(0, 0, 800, 600), // full-screen coverage
    );
    await tester.pump();
    expect(paintedIndex(tester), 1,
        reason: 'even a full-coverage sheet rect must not blank chrome — the '
            'sheet itself is translucent glass over a live page');
    expect(initCount, 1);
  });
}
