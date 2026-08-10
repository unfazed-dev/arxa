// C2 — chrome-gate transition SCOPING (docs/plans/glass-chrome-root-cause-fixes.md).
//
// Root cause: the gate hid whenever `CNTransitionObserver.activeTransitions > 0`
// — a GLOBAL static counter bumped by EVERY observer instance, root and nested
// navigators alike, with no mount-scope guard (contrast the modal check on the
// very same line, which does compare `_mountDepth`). Each nested router installs
// its own observer, so in the Notes shell a push inside ONE tab's nested
// Navigator dematerialized the ROOT tab bar across ALL tabs for the whole
// transition, snapping back when it settled — user-confirmed on device.
//
// The fix scopes the decision: a gate hides only when the in-flight transition
// belongs to a navigator that ENCLOSES the gate, mirroring the `_mountDepth`
// baseline pattern already used for modal depth.
import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_chrome_gate.dart';

/// The gate's `_hidden` flag drives the `IndexedStack` index directly: 0 is the
/// empty placeholder, 1 is the child. This used to read `IgnorePointer.ignoring`
/// because the hide was an animation and opacity lagged a frame behind the
/// decision — there is no animation now, so the index IS the decision, observed
/// in the same frame it is made.
bool _gateHidden(WidgetTester tester) {
  final IndexedStack stack = tester.widget<IndexedStack>(
    find
        .descendant(
          of: find.byType(AppBoxKitNativeChromeGate),
          matching: find.byType(IndexedStack),
          skipOffstage: false,
        )
        .first,
  );
  return stack.index == 0;
}

/// Same reading, but tolerant of the gate being offstage — a route that has
/// been covered by an opaque push is not painted, so the default finders skip
/// it. The pop regression below must observe a gate in exactly that state.
bool _gateHiddenDeep(WidgetTester tester) {
  final IndexedStack stack = tester.widget<IndexedStack>(
    find
        .descendant(
          of: find.byType(AppBoxKitNativeChromeGate, skipOffstage: false),
          matching: find.byType(IndexedStack, skipOffstage: false),
        )
        .first,
  );
  return stack.index == 0;
}

/// Settle the boot `didPush`: the initial route's animation is already
/// complete, so the observer ends it on the 350 ms fallback timer rather than
/// an animation status.
Future<void> _settleBoot(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 16));
}

/// Drain the observer watchdogs (`transitionDuration + 1000 ms`) so the test
/// does not end with pending timers.
Future<void> _flushWatchdogs(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  // The observer's counters are static and its end/watchdog timers live in the
  // per-test FakeAsync zone, so an unfinished transition in one test would
  // strand the counter for the next one.
  setUp(CNTransitionObserver.resetForTesting);

  testWidgets(
      'kit.ui-library.chrome-gate-scope — a nested-router push never hides the root chrome gate',
      (WidgetTester tester) async {
    final GlobalKey<NavigatorState> nestedKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[CNTransitionObserver()],
        home: Scaffold(
          body: Column(
            children: <Widget>[
              // One tab's nested router, with its own observer — exactly how
              // the shell's nested navigators register.
              Expanded(
                child: Navigator(
                  key: nestedKey,
                  observers: <NavigatorObserver>[CNTransitionObserver()],
                  onGenerateRoute: (RouteSettings settings) =>
                      MaterialPageRoute<void>(
                    settings: settings,
                    builder: (_) => const Text('tab-content'),
                  ),
                ),
              ),
              // The ROOT tab bar's chrome gate: a sibling of the nested router,
              // enclosed by the root navigator only.
              const AppBoxKitNativeChromeGate(child: Text('root-tab-bar')),
            ],
          ),
        ),
      ),
    );
    await _settleBoot(tester);
    expect(_gateHidden(tester), isFalse);

    // Push INSIDE the nested navigator only. Nothing about the root tab bar
    // moves, so nothing about it may dematerialize.
    nestedKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('detail')),
    );

    // Sample across the whole transition: start, mid-flight, late.
    await tester.pump();
    expect(_gateHidden(tester), isFalse,
        reason: 'root chrome gate hid at nested-push start');
    await tester.pump(const Duration(milliseconds: 50));
    expect(_gateHidden(tester), isFalse,
        reason: 'root chrome gate hid mid nested transition');
    await tester.pump(const Duration(milliseconds: 150));
    expect(_gateHidden(tester), isFalse,
        reason: 'root chrome gate hid late in nested transition');

    await _settleBoot(tester);
    expect(_gateHidden(tester), isFalse);
    expect(find.text('detail'), findsOneWidget);

    await _flushWatchdogs(tester);
  });

  testWidgets(
      'kit.ui-library.chrome-gate-scope — a root-navigator push still hides the chrome gate, then restores',
      (WidgetTester tester) async {
    final GlobalKey<NavigatorState> rootKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootKey,
        navigatorObservers: <NavigatorObserver>[CNTransitionObserver()],
        home: const Scaffold(
          body: AppBoxKitNativeChromeGate(child: Text('root-tab-bar')),
        ),
      ),
    );
    await _settleBoot(tester);
    expect(_gateHidden(tester), isFalse);

    // Pin the gate's element so the restore assertion below is provably about
    // the SAME instance. (A gate that was torn down and rebuilt would report
    // `_hidden == false` by default, making the restore check unfalsifiable.)
    final Element gateElement =
        tester.element(find.byType(AppBoxKitNativeChromeGate));

    // Push on the ROOT navigator — the gate's own scope. It must hide for the
    // transition: this is the intended behavior the scoping must not break.
    rootKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('pushed-route')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_gateHidden(tester), isTrue,
        reason: 'root-navigator push must still dematerialize chrome');

    // Pop BEFORE the push settles. Once a push completes, the Overlay stops
    // building the entries beneath the now-opaque top route, which disposes
    // the gate — popping mid-flight keeps the very same gate alive.
    rootKey.currentState!.pop();
    await _settleBoot(tester);

    expect(
      identical(tester.element(find.byType(AppBoxKitNativeChromeGate)),
          gateElement),
      isTrue,
      reason: 'gate was rebuilt — the restore assertion below would be vacuous',
    );
    expect(_gateHidden(tester), isFalse,
        reason: 'chrome must restore once root transitions settle');

    await _flushWatchdogs(tester);
  });

  testWidgets(
      'kit.ui-library.chrome-gate-scope — a POP leaves the REVEALED route\'s '
      'in-route chrome painted for the whole slide', (WidgetTester tester) async {
    // The Liquid-Glass-reappears-on-back regression, at the layer that causes
    // it. Leaving the frame makes the engine `removeFromSuperview` the platform
    // view; re-entering `addSubview`s it, and re-insertion is what materializes
    // iOS 26 Liquid Glass. So for content on the route being REVEALED, "hidden
    // for the duration of the pop" is not a cosmetic choice — it is the whole
    // defect. It must stay painted every frame, not merely be restored at the
    // end.
    //
    // Contrast the test above: chrome being COVERED for the first time by a
    // push still hides, and must, because a platform view composites above the
    // Flutter scene. The gate distinguishes the two by whether a route above it
    // already existed (see the predicate's comment in the gate).
    //
    // Mutation-checked: reverting the gate to the unconditional
    // `|| hasActiveTransitionAbove(context)` fails the mid-pop assertions
    // below while the two tests above still pass — which is exactly why those
    // two could not catch this.
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navKey,
        navigatorObservers: <NavigatorObserver>[CNTransitionObserver()],
        home: const CupertinoPageScaffold(
          child: AppBoxKitNativeChromeGate(child: Text('in-route-glass')),
        ),
      ),
    );
    await _settleBoot(tester);
    expect(_gateHiddenDeep(tester), isFalse);

    navKey.currentState!.push(
      CupertinoPageRoute<void>(
        builder: (_) => const CupertinoPageScaffold(child: Text('detail')),
      ),
    );
    await tester.pumpAndSettle();
    // Drain the push's watchdog so nothing from the push is mistaken for pop
    // state below.
    await tester.pump(const Duration(seconds: 2));

    // The gate must have SURVIVED being covered — otherwise a fresh gate would
    // report `_hidden == false` by default and every assertion below would be
    // vacuous.
    final Element gateElement = tester.element(
      find.byType(AppBoxKitNativeChromeGate, skipOffstage: false),
    );

    navKey.currentState!.pop();
    await tester.pump();

    // Sample across the whole 500 ms Cupertino pop
    // (CupertinoRouteTransitionMixin.kTransitionDuration). A single end-state
    // check cannot tell "never hid" from "hid, then restored" — and it is
    // precisely the hide-then-restore that fires the materialize.
    for (final int ms in <int>[0, 100, 250, 400]) {
      if (ms > 0) await tester.pump(Duration(milliseconds: ms));
      expect(_gateHiddenDeep(tester), isFalse,
          reason: 'revealed route\'s chrome left the frame ${ms}ms into the '
              'pop — that detach/re-attach is the Liquid Glass materialize');
    }

    await tester.pumpAndSettle();
    expect(
      identical(
        tester.element(find.byType(AppBoxKitNativeChromeGate, skipOffstage: false)),
        gateElement,
      ),
      isTrue,
      reason: 'gate was rebuilt during the pop — assertions above were vacuous',
    );
    expect(_gateHiddenDeep(tester), isFalse);

    await _flushWatchdogs(tester);
  });
}
