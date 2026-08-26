// Padding pin for the three gallery TAB ROOTS (Home, Search, Profile), added
// with the per-surface chrome move of 2026-08-13.
//
// Before that move the gallery chrome lived on each tab SHELL, so a tab root's
// list read `MediaQuery.padding.top` from a context that was already below the
// chrome and the raise came for free. The chrome now sits INSIDE each tab root,
// which means the list must be built under a `Builder` or it reads the padding
// from ABOVE its own chrome — unraised on the glass tier (first card tucked
// under the floating bar) and carrying an unstripped status bar on the boxed
// tier (a doubled gap). Neither is loud: the list still renders, just wrong by
// one inset. `showcase_components_view_test.dart` pins exactly this for the
// pushed Components surface; nothing pinned it for the three tab roots, so a
// regression here would have been silent.
//
// These go through the real shell rather than a bare `pumpWidget`: the gallery
// chrome's app-bar actions call `context.tabsRouter`, which only resolves
// inside the hub's tab router.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_view.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(signedIn: true);
  });

  tearDownAll(teardownShowcase);
  tearDown(ArxaKitPlatform.reset);

  // `bootShell` pins the view at 3.0 dpr, and `FakeViewPadding` is in physical
  // pixels — 132 physical is the 44pt status bar the assertions below use.
  const double statusBar = 44;

  // Scoped to the tab root's own view: the hub keeps every visited tab alive,
  // and on the glass tier a sibling tab's list is still in the tree (it is
  // kept painted, not `Offstage`), so a bare `find.byType` would be ambiguous.
  Future<EdgeInsets> pumpTabAndReadPadding(
    WidgetTester tester,
    String route,
    Type view,
  ) async {
    tester.view.padding = const FakeViewPadding(top: statusBar * 3);
    addTearDown(tester.view.resetPadding);
    final router = await bootShell(tester);
    await router.navigateNamed(route);
    await settle(tester);

    expect(find.byType(view), findsOneWidget,
        reason: 'anti-vacuous: $route must be mounted or the reading below '
            'proves nothing');
    final Finder list = find.descendant(
      of: find.byType(view),
      matching: find.byType(ArxaKitEdgeAwareListView),
    );
    expect(list, findsOneWidget);
    return tester
        .widget<ArxaKitEdgeAwareListView>(list)
        .padding!
        .resolve(TextDirection.ltr);
  }

  for (final (String name, String route, Type view) in const [
    ('home', '/home', ShowcaseHomeView),
    ('search', '/search', ShowcaseSearchView),
    ('profile', '/profile', ShowcaseProfileView),
  ]) {
    testWidgets(
        'shell-demos.browse-the-application-shell — the $name list takes the '
        'bare inset on the boxed tier (its chrome Scaffold stripped it)',
        (tester) async {
      ArxaKitPlatform.override =
          const ArxaKitPlatformOverride(isAndroid: true);
      expect((await pumpTabAndReadPadding(tester, route, view)).top, abxSize16,
          reason: 'a boxed tier that leaks the status bar into the list is the '
              "padding read from above the tab root's own chrome");
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets(
        'shell-demos.browse-the-application-shell — the $name list adds the '
        'status bar + floating-bar block on the glass tier', (tester) async {
      ArxaKitPlatform.override =
          const ArxaKitPlatformOverride(isIOS: true, iosMajor: 26);
      expect((await pumpTabAndReadPadding(tester, route, view)).top,
          abxSize16 + statusBar + kArxaKitFloatingBarBlockHeight,
          reason: 'missing the raise means the padding was read above the '
              'floating chrome, tucking the first card under the bar');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
