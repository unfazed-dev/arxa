// Regression guard for the gallery chrome's app-bar search shortcut
// (device report 2026-08-13: tapping the search icon did nothing).
//
// Scope: this exercises the DART path only — the icon button's onPressed
// closure → `tabsRouter.setActiveIndex(ShowcaseTab.search.index)` — on the
// headless fallback tier. The iOS-26 native half (UiKitView tap → method
// channel → Dart) cannot run headless and is verified on device; if this
// test is green and the device button is still dead, the defect is native
// tap delivery, not the wiring.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show
        ArxaKitGlyphs,
        ArxaKitNativeAppBar,
        ArxaKitNativeIconButton,
        ArxaKitNativeTabBar;

import 'package:arxa_kit_showcase_app/enums/showcase_application_enums/enums.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await registerKitTestServices();
    await initShowcase(signedIn: true);
  });

  tearDownAll(teardownShowcase);

  testWidgets(
      'shell-demos.browse-the-application-shell — the app-bar search shortcut '
      'switches the hub to the Search tab', (tester) async {
    final router = await bootShell(tester);
    unawaited(router.navigateNamed('/home'));
    await settle(tester);

    ArxaKitNativeTabBar bar() => tester
        .widget<ArxaKitNativeTabBar>(find.byType(ArxaKitNativeTabBar));
    expect(bar().currentIndex, ShowcaseTab.home.index,
        reason: 'anti-vacuous: must start on Home or the switch below proves '
            'nothing');

    final searchShortcut = find.descendant(
      of: find.byType(ArxaKitNativeAppBar),
      matching: find.byWidgetPredicate((w) =>
          w is ArxaKitNativeIconButton && w.glyph == ArxaKitGlyphs.search),
    );
    expect(searchShortcut, findsOneWidget,
        reason: 'the gallery chrome app bar must carry the search shortcut');

    await tester.tap(searchShortcut);
    await settle(tester);

    expect(bar().currentIndex, ShowcaseTab.search.index,
        reason: 'tapping the shortcut must land on the Search tab — the '
            'closure captures context.tabsRouter and calls setActiveIndex');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
