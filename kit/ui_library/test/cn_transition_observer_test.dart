import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
