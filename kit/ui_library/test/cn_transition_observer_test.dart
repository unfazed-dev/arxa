import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The counter and the observer registry are static, and each test's FakeAsync
  // discards pending end/watchdog timers — so a test that ends mid-transition
  // strands a count for the next one.
  setUp(CNTransitionObserver.resetForTesting);

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
}
