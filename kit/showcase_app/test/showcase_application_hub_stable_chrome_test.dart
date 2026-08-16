// Regression guard for the Notes-tab "reload on tap" fix.
//
// Root cause: ShowcaseApplicationHubView used to own the per-tab chrome conditionally —
//   appBar: inNotes ? null : PreferredSize(... AppBoxKitNativeAppBar ...)
//   floatingActionButton: index == 3 ? null : SizedBox(... AppBoxKitNativeFabMenu ...)
// so every Notes tap unmounted/remounted native chrome (platform views) and
// re-faded the body → "feels like the app reloaded." The fix hoists chrome
// into each tab shell (the host's Train/Shop shell paradigm), leaving the
// outer shell a stable body + bottom-nav host.
//
// This test pins the contract: the outer ShowcaseApplicationHubView Scaffold (the one
// holding the bottom tab bar) must NOT carry an appBar or a floating action
// button. If either returns, conditional chrome was re-added to the host and
// the reload-on-tap symptom will be back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(signedIn: true);
  });

  tearDownAll(teardownShowcase);

  testWidgets(
      'outer ShowcaseApplicationHubView owns no per-tab chrome (stable host)',
      (tester) async {
    await bootShell(tester);

    // The outer shell Scaffold is the one carrying the bottom tab bar.
    final scaffolds = tester.widgetList<Scaffold>(find.byType(Scaffold));
    final outer = scaffolds.firstWhere(
      (s) => s.bottomNavigationBar != null,
      orElse: () => throw StateError('outer shell Scaffold (with tab bar) '
          'not found — did the shell stop rendering AppBoxKitNativeTabBar?'),
    );

    expect(outer.appBar, isNull,
        reason: 'chrome must live in the tab shells, not the host; '
            'a non-null appBar here means conditional chrome returned and '
            'the Notes tab will reload on tap again');
    expect(outer.floatingActionButton, isNull,
        reason: 'the host must not own a per-tab FAB; '
            're-adding one re-introduces the native-view teardown flash');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
