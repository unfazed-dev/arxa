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

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitNativeTabBar, AppBoxKitNativeInputBar;

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
