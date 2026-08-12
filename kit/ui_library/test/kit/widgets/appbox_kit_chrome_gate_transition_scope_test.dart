// C2 — chrome-gate transition scoping (docs/plans/glass-chrome-root-cause-fixes.md).
//
// Root cause: the gate hid on `CNTransitionObserver.activeTransitions > 0`, a
// GLOBAL counter bumped by EVERY observer instance — root and nested navigators
// alike. In the Notes shell, a push inside one tab's nested Navigator therefore
// dematerialized the ROOT tab bar in ALL tabs for the transition's duration.
//
// The fix scopes the hide: a gate only hides when the active transition belongs
// to a navigator that is an ANCESTOR of the gate (its own navigator scope),
// mirroring the `_mountDepth` baseline pattern already used for modal depth.
import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_chrome_gate.dart';

/// The gate's `_hidden` flag drives `IgnorePointer.ignoring` synchronously —
/// the cleanest observable proxy for "the gate acted on a hide".
bool _gateHidden(WidgetTester tester) {
  final ignore = tester.widget<IgnorePointer>(
    find
        .descendant(
          of: find.byType(AppBoxKitNativeChromeGate),
          matching: find.byType(IgnorePointer),
        )
        .first,
  );
  return ignore.ignoring;
}

/// Flush the CNTransitionObserver watchdog timers (transitionDuration + 1 s)
/// so testWidgets does not fail on pending timers.
Future<void> _flushWatchdog(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  // Static counters leak across testWidgets zones (FakeAsync discards each
  // test's pending end/watchdog timers, stranding transitions mid-flight).
  setUp(CNTransitionObserver.resetForTesting);

  testWidgets(
      'kit.ui-library.chrome-gate-scope — nested-navigator push never hides the root chrome gate',
      (tester) async {
    final nestedKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [CNTransitionObserver()],
        home: Column(
          children: [
            // One tab's nested router — its own observer, as
            // AppBoxKitPlatformRouter nested navigators register by default.
            Expanded(
              child: Navigator(
                key: nestedKey,
                observers: [CNTransitionObserver()],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) => const Text('tab-content'),
                ),
              ),
            ),
            // The ROOT tab bar's chrome gate: sibling of the nested router,
            // inside the root navigator's scope only.
            const AppBoxKitNativeChromeGate(child: Text('root-tab-bar')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Flush the boot didPush: the initial route's animation is already
    // complete, so its end lands on the observer's 350 ms fallback timer.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_gateHidden(tester), isFalse);

    // Push INSIDE the nested navigator only.
    nestedKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('detail')),
    );

    // Sample throughout the transition: start, mid-flight, and settle. The
    // root gate must never act on a hide — the transition is not in its scope.
    await tester.pump();
    expect(_gateHidden(tester), isFalse,
        reason: 'root chrome gate hid at nested-push start');
    await tester.pump(const Duration(milliseconds: 50));
    expect(_gateHidden(tester), isFalse,
        reason: 'root chrome gate hid mid nested transition');
    await tester.pump(const Duration(milliseconds: 150));
    expect(_gateHidden(tester), isFalse,
        reason: 'root chrome gate hid late in nested transition');
    await tester.pumpAndSettle();
    // Flush the boot didPush: the initial route's animation is already
    // complete, so its end lands on the observer's 350 ms fallback timer.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_gateHidden(tester), isFalse);
    expect(find.text('detail'), findsOneWidget);

    await _flushWatchdog(tester);
  });

  testWidgets(
      'kit.ui-library.chrome-gate-scope — root-navigator push still hides the chrome gate (companion)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [CNTransitionObserver()],
        home: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Text('pushed-route'),
                  ),
                ),
                child: const Text('push'),
              ),
              const AppBoxKitNativeChromeGate(child: Text('root-tab-bar')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Flush the boot didPush: the initial route's animation is already
    // complete, so its end lands on the observer's 350 ms fallback timer.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_gateHidden(tester), isFalse);

    // Push on the ROOT navigator — the gate's own scope: it must hide for the
    // whole transition (intended behavior, must not regress).
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_gateHidden(tester), isTrue,
        reason: 'root-navigator push must still dematerialize chrome');

    // And restore once transitions settle (pop back first — the settled push
    // leaves the home route offstage, where default finders don't look).
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    // The pop's end-of-transition lands on a 350 ms fallback timer (the
    // popped-to route's animation is already complete) — pump past it.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_gateHidden(tester), isFalse,
        reason: 'chrome must restore after root transitions settle');

    await _flushWatchdog(tester);
  });
}
