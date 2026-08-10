import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart' show CupertinoTabBar;
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';
import 'appbox_kit_native_chrome_gate.dart';

/// One bottom-nav tab. [icon] drives the Flutter fallback; [sfSymbol] drives the
/// iOS 26 native tier ([CNTabBar] renders it as a real SF Symbol).
///
/// Prefer [glyph] (a paired icon + SF Symbol from [AppBoxKitGlyphs]) over the raw
/// [icon] / [sfSymbol] escape hatches — one token, both tiers, no drift.
class AppBoxKitTab {
  const AppBoxKitTab({
    this.glyph,
    IconData? icon,
    required this.label,
    String? sfSymbol,
  })  : assert(
            glyph != null || icon != null, 'AppBoxKitTab needs a glyph or an icon'),
        _icon = icon,
        _sfSymbol = sfSymbol;

  /// Paired Material icon + SF Symbol (see [AppBoxKitGlyphs]).
  final AppBoxKitGlyph? glyph;

  final IconData? _icon;
  final String? _sfSymbol;

  /// Material glyph — raw `icon` override first, then [glyph].
  IconData get icon => (_icon ?? glyph?.icon)!;

  /// SF Symbol name — raw `sfSymbol` override first, then [glyph], then the
  /// legacy `'circle'` placeholder.
  String get sfSymbol => _sfSymbol ?? glyph?.sfSymbol ?? 'circle';

  final String label;
}

/// Adaptive bottom tab bar — three-tier:
/// - **iOS 26 native** — delegates to `cupertino_native_better`'s [CNTabBar],
///   which renders real Liquid Glass (a native UIView via hybrid composition) and
///   reports taps via [onTap]. The owner (ViewModel / scaffold) holds
///   [currentIndex]; the bar is a projection, never a second source of truth.
/// - **Android M3 Expressive** — `NavigationBarM3E`; the selection pill
///   shape-morphs between destinations (token-driven by the kit's `M3ETheme`).
/// - **Flutter fallback** — `CupertinoTabBar` on iOS/macOS, Material 3
///   `NavigationBar` on desktop / web.
///
/// The native glass tier is delegated to `cupertino_native_better` (no kit-owned
/// native code for the bar); the kit owns the cross-platform fallback. See
/// `NATIVE_COMPONENTS.md` + `docs/plans/liquid-glass-uikit-recipe.md`.
class AppBoxKitNativeTabBar extends StatelessWidget {
  const AppBoxKitNativeTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    this.iconSize,
    this.native,
  });

  final List<AppBoxKitTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Explicit icon point size. Default null = let each tier pick its own:
  /// the native tier passes 0 so CNTabBar skips `SymbolConfiguration(pointSize:)`
  /// entirely and UIKit auto-sizes tab symbols per HIG (a forced 25pt renders
  /// visibly oversized — verified against the starling `native_liquid_glass`
  /// bar, which passes no size by default); the Cupertino fallback uses 25
  /// (its own 30 default is oversized).
  final double? iconSize;

  /// Force native-chrome/fallback. null = auto (glass on iOS 26, M3E on
  /// Android).
  final bool? native;

  @override
  Widget build(BuildContext context) {
    final wantNative = native ?? AppBoxKitPlatform.supportsNativeChrome;
    // Tier 1 — iOS 26 Liquid Glass.
    if (wantNative && AppBoxKitPlatform.supportsLiquidGlass) {
      // The regular CNTabBar (non-search variant) auto-hides via the narrow
      // `modalDepth` counter — only bumped by sheet-type *routes* through
      // `CNTabBarRouteObserver`.  Our `appBoxKitWithNativeChromeHidden` helper bumps
      // the *broad* `anyModalDepth` counter instead, so the tab bar's own
      // listener never fires and the native platform view would bleed through
      // any blur overlay a host presents on iOS (the kit's own scrims are now
      // plain dims / none per ADR 0010, but the depth signal still fires).
      //
      // Fix: AppBoxKitNativeChromeGate hides the bar on `anyModalDepth` at the
      // PAINT level (alpha 0 → the UIView leaves the native hierarchy, but
      // the platform view stays alive; the bottomNavigationBar slot never
      // collapses because the bar never stops laying out), then fades the
      // same live view back in on dismiss — no native re-init, no
      // thread-merge hitch, no single-frame pop.
      return AppBoxKitNativeChromeGate(
        child: CNTabBar(
          // C5 — SINGLE HIDE AUTHORITY. `CNTabBar` ships its own transition
          // hide (`autoHideOnPageTransition`, default true): an `IndexedStack`
          // swapped to a blank `SizedBox` the instant
          // `ModalRoute.secondaryAnimation` starts. The gate above hides the
          // very same bar for the very same event, but ANIMATED (alpha 1 -> 0
          // over `hideDuration`, 160 ms). Two authorities, one event: the
          // instant swap blanks the bar in frame one while the gate is still
          // fading something already invisible — the "fade-then-pop" artifact.
          // The gate owns hide/show; the ad-hoc swap is off.
          //
          // Safe w.r.t. the vendor's warning at `tab_bar.dart:558-565` ("ALWAYS
          // wrap in IndexedStack ... so the tree shape is identical"): that
          // guards against the wrapper appearing/disappearing WHILE the feature
          // is on. A constant `false` returns the bare platform view on every
          // build, so the tree shape is invariant and the UiKitView is never
          // destroyed/re-created.
          autoHideOnPageTransition: false,
          // `autoHideOnModal` deliberately STAYS ON. The modal hide must
          // DESTROY the platform view (`tab_bar.dart:521-526`, Issue #31) or
          // the native UITabBar layer keeps rendering above modal content; the
          // gate's keep-alive alpha-0 does not destroy it. Folding this path
          // into the gate would need `hideMode: unmount` and on-device z-order
          // verification, so it is left as a documented exception rather than
          // an unverified regression.
          items: [
            for (final t in tabs)
              CNTabBarItem(label: t.label, icon: CNSymbol(t.sfSymbol)),
          ],
          // 0 = sentinel CNTabBar's native side treats as "no symbol config"
          // (its Swift skips sizes <= 0), which is the only way to reach
          // UIKit's own HIG symbol sizing through CNSymbol's non-null 24 default.
          iconSize: iconSize ?? 0,
          // Fixed bar geometry, stock-UITabBar behavior. CNTabBar's default
          // shrinkCentered:true sizes the platform view to the native bar's
          // sizeThatFits width, which VARIES per selection on iOS 26 (the
          // Liquid Glass pill + label metrics of the active item change), so
          // the whole bar re-centers on every tab switch: items slide 15-20pt
          // horizontally and taps aimed at a moving icon land on the neighbor
          // or in a gap (verified on P2's application shell). Stock UITabBar
          // never moves items on selection change — and HIG calls unstable
          // tab positions unpredictable UI. Full width, fixed positions.
          shrinkCentered: false,
          currentIndex: currentIndex,
          onTap: onTap,
        ),
      );
    }
    // Tier 2 — Android Material 3 Expressive (selection pill morphs).
    if (wantNative && AppBoxKitPlatform.supportsComposeM3E) return _m3e(context);
    // Tier 3 — Cupertino (Apple < 26) / Material (desktop/web).
    return _KitFallbackTabBar(
      tabs: tabs,
      currentIndex: currentIndex,
      onTap: onTap,
      iconSize: iconSize ?? 25.0,
    );
  }

  Widget _m3e(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // NavigationBarM3E paints its container via an outer Material whose shape is
    // RoundedRectangleBorder(square.lg = 16px), read from the shared M3ETheme shape
    // token. That token is NOT overridable from outside the package — a scoped
    // Theme wrapper doesn't reach the package's internal NavTokensAdapter (verified:
    // a red test bar stayed 16px-rounded even with the token zeroed). So the flat,
    // edge-to-edge bar has to come from OUR side: make the package container
    // transparent (its inner Flutter NavigationBar is already transparent) and paint
    // our own rectangle — a Material with no shape, which cannot round.
    return Material(
      color:
          scheme.surfaceContainerHigh, // matches the package's container token
      child: NavigationBarM3E(
        backgroundColor:
            Colors.transparent, // suppress the package's rounded container
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        // M3E "flexible navigation bar": the shorter (64dp) bar Expressive uses in
        // place of the original 80dp one. Full-width per M3E spec.
        size: NavBarM3ESize.small,
        safeArea: true,
        // iOS-parity: saturated primary pill on the active tab.
        indicatorColor: scheme.primary,
        destinations: [
          for (final t in tabs)
            NavigationDestinationM3E(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.icon, color: scheme.onPrimary),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

/// Platform-adaptive Flutter fallback: CupertinoTabBar on iOS/macOS,
/// Material 3 NavigationBar everywhere else.
class _KitFallbackTabBar extends StatelessWidget {
  const _KitFallbackTabBar({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    required this.iconSize,
  });

  final List<AppBoxKitTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    switch (AppBoxKitPlatform.targetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _cupertino(context);
      default:
        return _material(context);
    }
  }

  Widget _material(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationBar(
      selectedIndex: currentIndex,
      backgroundColor: scheme.surface,
      // iOS-parity primary active pill — matches the M3E tier above.
      indicatorColor: scheme.primary,
      onDestinationSelected: onTap,
      destinations: [
        for (final t in tabs)
          NavigationDestination(
            icon: Icon(t.icon),
            selectedIcon: Icon(t.icon, color: scheme.onPrimary),
            label: t.label,
          ),
      ],
    );
  }

  Widget _cupertino(BuildContext context) {
    return CupertinoTabBar(
      currentIndex: currentIndex,
      onTap: onTap,
      iconSize: iconSize,
      items: [
        for (final t in tabs)
          BottomNavigationBarItem(icon: Icon(t.icon), label: t.label),
      ],
    );
  }
}
