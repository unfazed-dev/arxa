import 'dart:io';

import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The counter and the observer registry are static, and each test's FakeAsync
  // discards pending end/watchdog timers — so a test that ends mid-transition
  // strands a count for the next one.
  setUp(CNTransitionObserver.resetForTesting);

  test(
      'cn.transition-observer — the navigator observer never drives the NATIVE '
      'transition flag (single hide authority)', () {
    // Source-level on purpose, and the reason is worth stating: the old call
    // sites were guarded by `Platform.isIOS`, which is FALSE under the test
    // host. A runtime "no method call was made" assertion would therefore pass
    // identically before and after the fix — vacuous. Scanning the source is
    // the only guard here that can actually fail.
    //
    // What it protects: `beginTransition`/`endTransition` set
    // `CNTransitionObserver.shared.isTransitioning` natively, and its only
    // consumers swap glass for a flat fill in a SwiftUI `@ViewBuilder` if/else
    // (`LiquidGlassContainerView.swift:280`). Flipping it back re-applies
    // `.glassEffect` on a structurally new view, which materializes with an
    // animation — invisible on push (the route is still covered), fully visible
    // on POP. AppBoxKitNativeChromeGate already removes the view from the frame,
    // which de-tinting cannot do, so the native flag is a second authority that
    // buys nothing and costs an animation.
    final src = File(
            'vendor/cupertino_native_better/lib/utils/transition_observer.dart')
        .readAsStringSync();

    // Strip doc comments: the reasoning above is quoted in the source, and it
    // names the very methods we are forbidding.
    final code = src
        .split('\n')
        .where((l) =>
            !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
        .join('\n');

    // CNTransitionHelper is a deliberate manual-control escape hatch and keeps
    // its calls; the NavigatorObserver's own lifecycle hooks must not.
    final observerBody =
        code.substring(0, code.indexOf('class CNTransitionHelper'));

    // Match the PLATFORM-qualified call, not the bare name: the observer's own
    // private `_beginTransition()` / `_endTransition()` contain the bare names
    // as substrings and must keep existing.
    expect(observerBody.contains('instance.beginTransition('), isFalse,
        reason: 'CNTransitionObserver must not drive the native glass tint — '
            'it re-materializes glass on every pop. The gate owns the hide.');
    expect(observerBody.contains('instance.endTransition('), isFalse,
        reason: 'same: endTransition is what fires the materialize, exactly as '
            'the revealed route becomes visible');
    expect(observerBody.contains('void _beginTransition('), isTrue,
        reason:
            'control: the Dart-side counter bookkeeping must still be here, '
            'or the two assertions above are passing because the whole method '
            'vanished rather than because the native call did');
    expect(code.contains('class CNTransitionHelper'), isTrue,
        reason: 'control: if the helper is renamed or removed this test would '
            'silently scan the wrong region and pass for the wrong reason');
  });

  testWidgets(
      'pop holds the hide window for the WHOLE slide, not a blind 350ms timer',
      (WidgetTester tester) async {
    // Regression guard. `didPop` used to schedule the end on `previousRoute` —
    // the route being REVEALED, whose own animation settled at 1.0 when it was
    // pushed. `status == completed` sent it down the "no animation" fallback, a
    // fixed 350ms timer, while a Cupertino slide runs 500ms
    // (CupertinoRouteTransitionMixin.kTransitionDuration, cupertino/route.dart).
    // The window therefore closed ~150ms early and native Liquid Glass was
    // restored over a page still in motion — the wrong-looking reappear on back.
    //
    // The probe below is the whole point: the pre-existing pop coverage only
    // asserted 1 → pumpAndSettle → 0, which the blind timer satisfies happily.
    // Only a MID-pop sample can tell the two apart.
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(CupertinoApp(
      navigatorKey: navKey,
      navigatorObservers: <NavigatorObserver>[CNTransitionObserver()],
      home: const CupertinoPageScaffold(child: Text('home')),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(CNTransitionObserver.activeTransitions.value, 0);

    navKey.currentState!.push(CupertinoPageRoute<void>(
      builder: (_) => const CupertinoPageScaffold(child: Text('pushed')),
    ));
    await tester.pumpAndSettle();
    // Drain the push's watchdog (transitionDuration + 1000ms) so nothing from
    // the push can be mistaken for pop state below.
    await tester.pump(const Duration(seconds: 2));
    expect(CNTransitionObserver.activeTransitions.value, 0,
        reason: 'control: the push must be fully drained before we pop');

    navKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(CNTransitionObserver.activeTransitions.value, greaterThan(0),
        reason: '400ms into a 500ms pop the page is STILL sliding. Releasing '
            'here is what let glass snap back over moving content — this is '
            'the assertion that fails on the previousRoute scheduling');

    await tester.pumpAndSettle();
    expect(CNTransitionObserver.activeTransitions.value, 0,
        reason: 'and it must still actually release — a window that never '
            'closes hides every glass surface in the app forever');

    // Scheduling on the outgoing route also arms that route's watchdog
    // (transitionDuration + 1000ms). It is a deliberate no-op once `end` has
    // run, but it is still a live timer, so drain it or the binding reports
    // "A Timer is still pending after the widget tree was disposed".
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'a zero-duration pop releases promptly instead of waiting out the watchdog',
      (WidgetTester tester) async {
    // Scheduling on the outgoing route means its animation can already be
    // `dismissed` when there is no transition to run. Treating that as
    // in-flight would attach a listener nothing ever fires, leaving the
    // watchdog to hide chrome for a full second after an instant pop.
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(CupertinoApp(
      navigatorKey: navKey,
      navigatorObservers: <NavigatorObserver>[CNTransitionObserver()],
      home: const CupertinoPageScaffold(child: Text('home')),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));

    navKey.currentState!.push(PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const CupertinoPageScaffold(
        child: Text('instant'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(CNTransitionObserver.activeTransitions.value, 0);

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(CNTransitionObserver.activeTransitions.value, 0,
        reason: 'an instant pop must not pin the counter for the watchdog\'s '
            'full budget');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'activeTransitions returns to 0 when a route is disposed mid-transition',
      (WidgetTester tester) async {
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      navigatorObservers: <NavigatorObserver>[CNTransitionObserver()],
      home: const Scaffold(body: Text('home')),
    ));
    // The initial route's didPush ends via the 350ms delayed fallback.
    await tester.pump(const Duration(milliseconds: 400));
    expect(CNTransitionObserver.activeTransitions.value, 0);

    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('pushed')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(CNTransitionObserver.activeTransitions.value, greaterThan(0),
        reason: 'push transition should be in flight');

    // Tear the navigator down mid-flight: the route is disposed before its
    // animation ever reaches completed/dismissed, so the status listener that
    // normally decrements the counter never fires.
    await tester.pumpWidget(const SizedBox.shrink());

    // The watchdog must reclaim the orphaned increment; otherwise every
    // chrome-gated widget in the app stays hidden (alpha 0) forever.
    await tester.pump(const Duration(seconds: 3));
    expect(CNTransitionObserver.activeTransitions.value, 0,
        reason: 'stuck counter leaves all glass chrome permanently hidden');
  });

  testWidgets(
      'counter holds through the whole push transition despite the hero '
      'offstage spurious `completed` notification, then settles to 0',
      (WidgetTester tester) async {
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(CupertinoApp(
      navigatorKey: navKey,
      navigatorObservers: <NavigatorObserver>[CNTransitionObserver()],
      home: const CupertinoPageScaffold(child: Text('home')),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(CNTransitionObserver.activeTransitions.value, 0);

    navKey.currentState!.push(CupertinoPageRoute<void>(
      builder: (_) => const CupertinoPageScaffold(child: Text('pushed')),
    ));
    // HeroController flips route.offstage during the push, which makes the
    // ModalRoute ProxyAnimation emit a synchronous spurious `completed`.
    // Before the offstage guard this collapsed the counter to 0 inside
    // push() itself, so the chrome gate never hid native views during route
    // transitions (the ghosting/remnant symptom).
    expect(CNTransitionObserver.activeTransitions.value, 1,
        reason: 'hide window must survive the synchronous push stack');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(CNTransitionObserver.activeTransitions.value, 1,
        reason: 'hide window must span the full route transition');

    await tester.pumpAndSettle();
    expect(CNTransitionObserver.activeTransitions.value, 0,
        reason: 'real completion must release the counter');

    // Pop balances the same way.
    navKey.currentState!.pop();
    expect(CNTransitionObserver.activeTransitions.value, 1);
    await tester.pumpAndSettle();
    // Watchdog fires later than the listener here; the once-only guard must
    // keep it from double-decrementing.
    await tester.pump(const Duration(seconds: 3));
    expect(CNTransitionObserver.activeTransitions.value, 0);
  });

  testWidgets('non-opaque routes (dialogs, popups) never drive the chrome hide',
      (WidgetTester tester) async {
    // The hide exists so a platform view leaves the frame while a page COVERS
    // the screen. A dialog / modal popup / sheet is `opaque: false` — the page
    // below stays visible for its whole lifetime, so counting it blanks native
    // chrome on open and re-materializes it on close: the user-visible blink.
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(CupertinoApp(
      navigatorKey: navKey,
      navigatorObservers: <NavigatorObserver>[CNTransitionObserver()],
      home: const CupertinoPageScaffold(child: Text('home')),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));

    showCupertinoDialog<void>(
      context: navKey.currentContext!,
      builder: (_) => const CupertinoAlertDialog(title: Text('dialog')),
    );
    await tester.pump();
    expect(CNTransitionObserver.activeTransitions.value, 0,
        reason: 'a dialog push must not hide native chrome mid-transition');
    await tester.pumpAndSettle();
    expect(CNTransitionObserver.activeTransitions.value, 0);

    navKey.currentState!.pop();
    await tester.pump();
    expect(CNTransitionObserver.activeTransitions.value, 0,
        reason: 'a dialog dismiss uncovers nothing — no hide window');
    await tester.pumpAndSettle();
    expect(CNTransitionObserver.activeTransitions.value, 0);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'a user gesture on a non-opaque route cannot latch the counter negative',
      (WidgetTester tester) async {
    final CNTransitionObserver observer = CNTransitionObserver();
    final PageRouteBuilder<void> translucent = PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (_, __, ___) => const SizedBox(),
    );
    // Start is skipped by the opacity filter…
    observer.didStartUserGesture(translucent, null);
    expect(CNTransitionObserver.activeTransitions.value, 0);
    // …so the unconditional stop must not decrement what was never begun.
    observer.didStopUserGesture();
    expect(CNTransitionObserver.activeTransitions.value, 0,
        reason: 'stop without a counted start must be a no-op, or every '
            'later real transition ends one hide too early');
    translucent.dispose();
  });
}
