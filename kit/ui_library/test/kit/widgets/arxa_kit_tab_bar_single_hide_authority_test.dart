// C5 — SINGLE HIDE AUTHORITY for the native tab bar
// (docs/plans/glass-chrome-root-cause-fixes.md).
//
// The native tier stacks TWO independent hide authorities on the SAME widget,
// both reacting to a route transition over the tab host:
//
//   1. `ArxaKitNativeChromeGate` (arxa_kit_tab_bar.dart:100) — a paint-level
//      hide via an unselected `IndexedStack` index; platform view never
//      unmounted.
//   2. `CNTabBar.autoHideOnPageTransition` (vendor tab_bar.dart:566-574) — an
//      INSTANT `IndexedStack` swap to a blank `SizedBox`, flipped by
//      `ModalRoute.secondaryAnimation` (vendor tab_bar.dart:381-382).
//
// Historical: (1) used to be ANIMATED — alpha 1 -> 0 over a 160 ms
// `hideDuration` — so the instant swap blanked the bar in frame one while the
// gate was still 159 ms into a fade nobody could see: the "fade-then-pop"
// artifact. The fade has since been removed outright (animating alpha over a
// platform view is unsupported: flutter#93757, flutter#24164), so the two would
// now agree. One authority for one event remains the rule regardless, and the
// gate is the one that also covers modal depth — the ad-hoc swap stays off at
// the kit call site.
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
import 'package:arxa_kit_core/common/arxa_kit_glyphs.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_native_chrome_gate.dart';
import 'package:arxa_kit_ui_library/widgets/arxa_kit_tab_bar.dart';
import 'package:cupertino_native_better/cupertino_native.dart'
    show CNTransitionObserver;
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [observed] installs the transition observer the gate listens to — the
/// showcase installs exactly this at `main.dart:97`. Off by default: the
/// observer's boot `didPush` arms a 350 ms fallback timer, and the
/// property-only tests below never pump long enough to drain it.
Widget _host({int currentIndex = 0, bool observed = false}) => MaterialApp(
      navigatorObservers: [
        if (observed) CNTransitionObserver(),
      ],
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: ArxaKitNativeTabBar(
          tabs: const [
            ArxaKitTab(glyph: ArxaKitGlyphs.home, label: 'Home'),
            ArxaKitTab(glyph: ArxaKitGlyphs.search, label: 'Search'),
          ],
          currentIndex: currentIndex,
          onTap: (_) {},
        ),
      ),
    );

void main() {
  setUp(() {
    // Static transition state leaks between testWidgets zones (FakeAsync
    // discards the pending end/watchdog timers mid-transition).
    CNTransitionObserver.resetForTesting();
    // Force tier 1 (iOS 26 Liquid Glass) — the only tier that mounts CNTabBar.
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isIOS: true, iosMajor: 26);
  });
  tearDown(ArxaKitPlatform.reset);

  testWidgets(
      'kit.ui-library.tab-bar — the chrome gate is the SINGLE hide authority: '
      "CNTabBar's instant page-transition swap is off", (tester) async {
    await tester.pumpWidget(_host());

    expect(find.byType(ArxaKitNativeChromeGate), findsOneWidget,
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

  // The load-bearing negative behind "C5 does not explain TAB-SWITCH flicker":
  // a tab-index change is not a route event, so no hide authority may fire.
  // `_pageTransitioning` keys off `ModalRoute.secondaryAnimation`
  // (vendor tab_bar.dart:381-382) and the gate keys off an enclosing
  // navigator's transition — a tab switch pushes neither.
  testWidgets(
      'kit.ui-library.tab-bar — a tab-index change hides NOTHING (a tab switch '
      'is not a route transition)', (tester) async {
    await tester.pumpWidget(_host(observed: true));
    // Settle the boot `didPush` (its end runs off the observer's fallback
    // timer, not an animation status).
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 16));

    expect(_gateHidden(tester), isFalse, reason: 'idle baseline');

    // The tab switch: only the projected index changes.
    await tester.pumpWidget(_host(currentIndex: 1, observed: true));
    await tester.pump();

    expect(_gateHidden(tester), isFalse,
        reason: 'a tab switch pushes no route, so neither the gate nor the '
            "vendor's secondaryAnimation path may hide the bar — if this ever "
            'goes true, tab-switch flicker HAS a Flutter-side mechanism');
  });
}

/// The gate drives `IgnorePointer.ignoring` synchronously on hide — a cleaner
/// probe than the animated opacity (which lags a frame). Mirrors the helper in
/// `arxa_kit_chrome_gate_transition_scope_test.dart:22-32`.
bool _gateHidden(WidgetTester tester) => tester
    .widget<IgnorePointer>(
      find
          .descendant(
            of: find.byType(ArxaKitNativeChromeGate),
            matching: find.byType(IgnorePointer),
          )
          .first,
    )
    .ignoring;
