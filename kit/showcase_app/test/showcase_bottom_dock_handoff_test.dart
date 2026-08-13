// Regression guards for the bottom-dock handoff.
//
// Symptom (device, 2026-08-11): on Profile → Components the message dock and
// the floating tab bar drew on the same pixels — the tab bar's pill covered
// the bottom of the input row. Both want the bottom of the screen, and a
// nested `Scaffold`'s `bottomSheet` lands inside the host's `extendBody: true`
// body, so a fixed lift can only ever approximate the bar's real block.
//
// Contract: one dock at a time. A route that pins its own bar wins the slot
// and the shared tab bar yields it — scoped to the ACTIVE tab, which is the
// half that makes this different from the global counter recorded as C2 in
// `docs/plans/glass-chrome-root-cause-fixes.md` (a claim raised inside one
// tab's nested router hid the bar in every tab).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show
        AppBoxKitNativeAppBar,
        AppBoxKitNativeTabBar,
        AppBoxKitNativeInputBar,
        AppBoxKitNativeFabMenu;

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(signedIn: true);
  });

  tearDownAll(teardownShowcase);

  testWidgets(
      'shell-demos.browse-the-application-shell — Components takes the bottom '
      'dock and the tab bar yields it', (tester) async {
    final router = await bootShell(tester);

    // Baseline is Home, not the profile root: `/profile` overflows 92px in
    // AppBoxKitNativeToolbar at phone width (pre-existing, verified against a
    // probe that never enters Components) and would fail this test for an
    // unrelated reason.
    unawaited(router.navigateNamed('/home'));
    await settle(tester);
    expect(find.byType(AppBoxKitNativeTabBar), findsOneWidget,
        reason: 'anti-vacuous: the tab bar must be up before we navigate, '
            'or the assertion below proves nothing');

    unawaited(router.navigateNamed('/profile/components'));
    await settle(tester);

    expect(find.byType(AppBoxKitNativeInputBar), findsOneWidget,
        reason: 'Components pins the message dock as Scaffold.bottomSheet');
    expect(find.byType(AppBoxKitNativeTabBar), findsNothing,
        reason: 'two bars on the same pixels is the bug — the shared tab bar '
            'yields the slot to the route that pinned its own');

    // The yield is only worth anything if the bar then takes the space. The
    // input bar carries its own SafeArea INSIDE its box, so its outer rect
    // runs to the physical bottom edge; the 64pt tab-bar lift it used to
    // carry would leave it stranded above dead space.
    expect(
      tester.getRect(find.byType(AppBoxKitNativeInputBar)).bottom,
      closeTo(tester.view.physicalSize.height / tester.view.devicePixelRatio, 0.5),
      reason: 'the dock must sit on the bottom edge once the tab bar is gone',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
      'shell-demos.browse-the-application-shell — the composer clears the home '
      'indicator instead of sitting on it', (tester) async {
    // Device symptom (2026-08-11): the composer sat flush against the screen
    // edge, on top of the home indicator. Two Scaffolds were each stripping the
    // bottom inset before it could reach the dock:
    //
    //  1. the host tab bar yielded as a zero-height `SizedBox` rather than
    //     `null`, and Scaffold removes the body's bottom padding whenever
    //     `bottomNavigationBar != null` (`scaffold.dart:3032`);
    //  2. the Components Scaffold left `resizeToAvoidBottomInset` at its
    //     default `true`, and the `bottomSheet` slot is registered with
    //     `removeBottomPadding: _resizeToAvoidBottomInset`
    //     (`scaffold.dart:3086`).
    //
    // `removePadding` takes the consumed amount off `viewPadding` too, so
    // nothing downstream could recover it — measured, the composer received
    // padding.bottom = 0.0 AND viewPadding.bottom = 0.0.
    final router = await bootShell(tester);
    // 34pt home indicator at dpr 3.0.
    tester.view.padding = const FakeViewPadding(bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(bottom: 102);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    unawaited(router.navigateNamed('/profile/components'));
    await settle(tester);

    final Finder bar = find.byType(AppBoxKitNativeInputBar);
    final MediaQueryData mq = MediaQuery.of(tester.element(bar));
    expect(mq.padding.bottom, 34,
        reason: 'the inset must survive both Scaffolds to reach the dock');

    // The bar's own SafeArea is inside its box, so the box grows by the inset
    // and its content lifts clear.
    final Finder row = find.descendant(of: bar, matching: find.byType(Row)).first;
    final double screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(screenBottom - tester.getRect(row).bottom, greaterThanOrEqualTo(34),
        reason: 'the composer row must sit at least the home-indicator inset '
            'above the screen edge');

    // CHANGED 2026-08-13 (per-surface chrome ruling): this used to assert the
    // gallery FAB was on screen and cleared the composer by geometry. The
    // gallery chrome now lives on each TAB ROOT, not on the shell, so a pushed
    // route is no longer a descendant of it — the FAB is gone here and the
    // overlap it guarded is structurally impossible rather than merely
    // measured. Pinning the absence keeps the guard non-vacuous.
    expect(find.byType(AppBoxKitNativeFabMenu), findsNothing,
        reason: 'a pushed route carries only its own chrome — a gallery FAB '
            'here means the shell-level wrapper came back and it will sit over '
            "the composer's trailing mic again");
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
      'shell-demos.browse-the-application-shell — a pushed route wears only its '
      'own chrome, no gallery bar stacked above it', (tester) async {
    // CHANGED 2026-08-13 (per-surface chrome ruling). This test used to pin the
    // FAB/composer clearance at a zero bottom inset — the worry being that the
    // clearance only worked because a 34pt home indicator made the numbers
    // come out. That arithmetic is now moot: the gallery chrome moved from the
    // three tab SHELLS onto the three tab ROOT views, so a route pushed on a
    // tab's nested router has no gallery chrome above it at all.
    //
    // Retargeted at the property that replaced it, which is the user-visible
    // ruling: exactly one bar on a pushed surface, and it is the route's own.
    // The old assertion could not catch a returning wrapper (a second bar high
    // on screen never overlaps a composer at the bottom); this one does.
    final router = await bootShell(tester);
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    unawaited(router.navigateNamed('/profile/components'));
    await settle(tester);

    expect(find.byType(AppBoxKitNativeInputBar), findsOneWidget,
        reason: 'anti-vacuous: Components must actually be up');

    Finder barTitled(String title) => find.byWidgetPredicate(
        (w) => w is AppBoxKitNativeAppBar && w.title == title);

    expect(barTitled('Components'), findsOneWidget,
        reason: "the pushed route keeps its own 'Components' bar");
    expect(barTitled('Kit Showcase'), findsNothing,
        reason: "the gallery's 'Kit Showcase' bar belongs to the tab ROOT; "
            'finding it here is the double-bar stack the ruling removed');
    expect(find.byType(AppBoxKitNativeFabMenu), findsNothing,
        reason: 'the gallery FAB is part of that same tab-root chrome');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
      'shell-demos.browse-the-application-shell — the yield is per-tab: Home '
      'keeps its tab bar while Components stays on the profile stack',
      (tester) async {
    final router = await bootShell(tester);

    unawaited(router.navigateNamed('/profile/components'));
    await settle(tester);
    expect(find.byType(AppBoxKitNativeTabBar), findsNothing);

    // Components is still mounted in the profile tab's stack (the tab bodies
    // live in an IndexedStack) — only the ACTIVE tab's top route may decide.
    unawaited(router.navigateNamed('/home'));
    await settle(tester);

    expect(find.byType(AppBoxKitNativeTabBar), findsOneWidget,
        reason: 'a mounted-but-inactive Components must not hold the dock; '
            'that cross-tab leak is C2 and it strands the user with no tabs');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
