// C5 — SINGLE HIDE AUTHORITY for the native tab bar
// (docs/plans/glass-chrome-root-cause-fixes.md).
//
// The native tier stacks TWO independent hide authorities on the SAME widget,
// both reacting to a route transition over the tab host:
//
//   1. `AppBoxKitNativeChromeGate` (appbox_kit_tab_bar.dart:100) — an ANIMATED
//      paint-level hide: alpha 1 -> 0 over `hideDuration` (160 ms), platform
//      view never unmounted.
//   2. `CNTabBar.autoHideOnPageTransition` (vendor tab_bar.dart:566-574) — an
//      INSTANT `IndexedStack` swap to a blank `SizedBox`, flipped by
//      `ModalRoute.secondaryAnimation` (vendor tab_bar.dart:381-382).
//
// Both fire on the same event, so the instant swap blanks the bar in frame one
// while the gate is still 159 ms into a fade nobody can see: the "fade-then-pop"
// artifact. The gate must be the single authority — the ad-hoc swap is turned
// off at the kit call site.
//
// NOTE on the vendor's own warning (tab_bar.dart:558-565): "ALWAYS wrap in
// IndexedStack when the feature is on, so the tree shape is identical
// regardless of `_pageTransitioning`". That warns against toggling the wrapper
// WHILE the feature is on. A literal, constant `false` returns the bare
// platform view on every build — the tree shape is still invariant, so the
// UiKitView is never destroyed/re-created.
//
// `autoHideOnModal` is deliberately left ALONE: the vendor requires the modal
// hide to DESTROY the platform view (tab_bar.dart:521-526, Issue #31 — the
// UITabBar layer otherwise renders above modal content), which the gate's
// keep-alive alpha-0 does not do. Collapsing that path cannot be verified
// headless, so it stays as a documented conflict rather than an unverified
// z-order regression.
import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_native_chrome_gate.dart';
import 'package:appbox_kit_ui_library/widgets/appbox_kit_tab_bar.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host() => MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: AppBoxKitNativeTabBar(
          tabs: const [
            AppBoxKitTab(glyph: AppBoxKitGlyphs.home, label: 'Home'),
            AppBoxKitTab(glyph: AppBoxKitGlyphs.search, label: 'Search'),
          ],
          currentIndex: 0,
          onTap: (_) {},
        ),
      ),
    );

void main() {
  setUp(() {
    // Force tier 1 (iOS 26 Liquid Glass) — the only tier that mounts CNTabBar.
    AppBoxKitPlatform.override =
        const AppBoxKitPlatformOverride(isIOS: true, iosMajor: 26);
  });
  tearDown(AppBoxKitPlatform.reset);

  testWidgets(
      'kit.ui-library.tab-bar — the chrome gate is the SINGLE hide authority: '
      "CNTabBar's instant page-transition swap is off", (tester) async {
    await tester.pumpWidget(_host());

    expect(find.byType(AppBoxKitNativeChromeGate), findsOneWidget,
        reason: 'the gate is the authority that must own hide/show');

    final CNTabBar bar = tester.widget<CNTabBar>(find.byType(CNTabBar));
    expect(bar.autoHideOnPageTransition, isFalse,
        reason: 'a second, INSTANT hide path racing the gate\'s 160 ms fade '
            'blanks the bar in frame one — the fade-then-pop artifact. The '
            'gate owns the transition hide; the ad-hoc IndexedStack swap must '
            'be off.');
  });

  testWidgets(
      'kit.ui-library.tab-bar — the modal-destroy path is deliberately LEFT ON '
      '(vendor Issue #31: alpha-0 does not stop a UITabBar over a sheet)',
      (tester) async {
    await tester.pumpWidget(_host());

    final CNTabBar bar = tester.widget<CNTabBar>(find.byType(CNTabBar));
    expect(bar.autoHideOnModal, isTrue,
        reason: 'the gate keeps the platform view ALIVE at alpha 0; the vendor '
            'requires the modal hide to DESTROY it or the native bar renders '
            'over modal content. Not collapsed — unverifiable headless.');
  });
}
