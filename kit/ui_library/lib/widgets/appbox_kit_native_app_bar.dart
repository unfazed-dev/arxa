import 'package:flutter/cupertino.dart' show CupertinoNavigationBar;
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart' show AppBarM3E;
import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';

import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';

import 'appbox_kit_native_icon_button.dart';
import 'appbox_kit_native_sliver_app_bar.dart';

/// Adaptive top app bar — two-way structural gate (mirrors [AppBoxKitNativeTabBar]'s
/// `wantNative && supportsComposeM3E` shape):
/// - **Android M3 Expressive** — [AppBarM3E] (real expressive container/scroll
///   motion via the kit's `M3ETheme`). The sliver variant routes to
///   [SliverAppBarM3E].
/// - **iOS** — [CupertinoNavigationBar] (the CN tier is pure-Flutter here; the
///   Liquid Glass nav bar is not yet wrapped by `cupertino_native_better`).
/// - **Fallback** (desktop/web, macOS, `wantNative: false`) — Material [AppBar]
///   or [SliverAppBar].
///
/// The public surface is **primitives only** so hosts never import
/// `m3e_collection`. The default constructor implements `PreferredSizeWidget`,
/// so slot it straight into `Scaffold.appBar` (no `PreferredSize` wrapper) —
/// the pattern every showcase tab uses. For a [CustomScrollView] where the bar
/// must collapse/float with the scroll, use [AppBoxKitNativeSliverAppBar] as the
/// first sliver instead (the kit default there is `pinned; floating + snap off`).
/// [AppBoxKitNativeAppBar.sliver] delegates to it for back-compat.
class AppBoxKitNativeAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const AppBoxKitNativeAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.wantNative = true,
  });

  /// [PreferredSizeWidget] so the bar drops straight into [Scaffold.appBar]
  /// (or [SliverAppBar]'s bottom) without a [PreferredSize] wrapper — the same
  /// slot pattern every showcase tab uses. Material `kToolbarHeight`; the
  /// Cupertino tier self-sizes its own nav-bar height and only consults this to
  /// reserve the slot.
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  /// Title text. Renders as a [Text] on the fallback tiers and via `titleText`
  /// on the M3E tier.
  final String? title;

  /// Trailing action widgets. Mapped 1:1 to each tier's trailing slot.
  final List<Widget>? actions;

  /// Leading widget (typically a back/close button). When null, the tier may
  /// imply one per [automaticallyImplyLeading].
  final Widget? leading;

  /// Let the tier auto-build a back button when [leading] is null. On the
  /// Flutter-drawn tiers (CupertinoNavigationBar, Material AppBar) the implied
  /// leading is a kit-owned [AppBoxKitNativeIconButton] with [AppBoxKitGlyphs.back] (see
  /// [appBoxKitImpliedAppBarLeading]) so the back affordance matches the trailing
  /// action buttons; dropped on the M3E sliver tier.
  // ponytail: SliverAppBarM3E has no `automaticallyImplyLeading` param, so the
  // sliver M3E tier always implies a leading when `leading` is null. Expose an
  // M3E token override only if a host needs to suppress it.
  final bool automaticallyImplyLeading;

  /// Host opt-out of native chrome.
  final bool wantNative;

  /// Sliver variant for [CustomScrollView]s — delegates to
  /// [AppBoxKitNativeSliverAppBar] (the first-class sliver bar; `pinned; floating +
  /// snap off` by default). Prefer constructing [AppBoxKitNativeSliverAppBar]
  /// directly when you need to tune the collapse flags or set a
  /// [FlexibleSpaceBar]. Returns a sliver widget, not a box.
  ///
  // ponytail: static *method*, not a `factory` constructor — a Dart factory
  // must return the enclosing type (`AppBoxKitNativeAppBar`), but the sliver tier
  // returns a sibling sliver widget. The call site `AppBoxKitNativeAppBar.sliver(...)`
  // is unchanged.
  static Widget sliver({
    String? title,
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
    bool wantNative = true,
  }) =>
      AppBoxKitNativeSliverAppBar(
        title: title,
        actions: actions,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        wantNative: wantNative,
      );

  @override
  Widget build(BuildContext context) {
    final want = wantNative && AppBoxKitPlatform.supportsComposeM3E;
    if (want) {
      final scheme = Theme.of(context).colorScheme;
      // AppBarM3E paints its container on an internal Material whose shape
      // token rounds the bar's corners — but a top app bar must meet the
      // status bar edge-to-edge. Same fix as AppBoxKitNativeTabBar._m3e: make the
      // package container transparent and paint our own unrounded,
      // theme-colored rectangle behind it.
      return Material(
        color: scheme.surface,
        child: AppBarM3E(
          key: key,
          titleText: title,
          actions: actions,
          leading: leading,
          backgroundColor: Colors.transparent,
          foregroundColor: scheme.onSurface,
          automaticallyImplyLeading: automaticallyImplyLeading,
        ),
      );
    }
    if (AppBoxKitPlatform.isIOS && wantNative) {
      final scheme = Theme.of(context).colorScheme;
      // The stock implied leading is a CupertinoNavigationBarBackButton —
      // visibly different chrome from the AppBoxKitNativeIconButtons in the trailing
      // slot. The CN tier is pure Flutter (no Liquid Glass nav bar yet), so the
      // kit implies its own back button instead (maybePop + the stock a11y
      // label preserved — see appBoxKitImpliedAppBarLeading).
      final effectiveLeading = appBoxKitImpliedAppBarLeading(
        context,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
      );
      // CupertinoNavigationBar's defaults read CupertinoTheme (system chrome),
      // not the app's Material ColorScheme — pin the bar + title to the active
      // scheme so brand colors and dark mode flow through.
      //
      // The CN persistent height is a FIXED 44 (== AppBoxKitNativeIconButton's 44pt
      // tap target), so a bar button fills the bar top-to-bottom and its bottom
      // edge lands flush on the content seam — the Material tier avoids this by
      // centering the 44 button in kToolbarHeight (56), leaving slack. The CN
      // bar can't be grown (no height param) and its own `padding` shrinks +
      // clips the toolbar, so reserve the slack BELOW the bar (a surface-colored
      // gap of abxGap8) so the buttons get the same bottom
      // breathing room as the Material tier. Guarded by kit_native_app_bar_test
      // + review_checklist 1v.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoNavigationBar(
            backgroundColor: scheme.surface,
            automaticBackgroundVisibility: false,
            // Kept-alive tab stacks (IndexedStack shells) mount one of these
            // bars per tab inside the SAME root-Navigator subtree; the stock
            // bar's default Hero tag collides across tabs on any route
            // transition ("multiple heroes share the same tag"). Per-tab
            // chrome never hero-morphs between routes, so opt out.
            transitionBetweenRoutes: false,
            middle: title == null
                ? null
                : Text(
                    title!,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            trailing: actions == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: abxGap8,
                    children: actions!),
            leading: effectiveLeading,
            automaticallyImplyLeading: automaticallyImplyLeading,
          ),
          ColoredBox(
            color: scheme.surface,
            child: const SizedBox(
              key: Key('appBoxKitNativeAppBarBottomGap'),
              height: abxGap8,
            ),
          ),
        ],
      );
    }
    // The Material fallback tier renders on neither iOS (→ CupertinoNavigationBar,
    // above) nor Android (→ AppBarM3E) — but a bare Material AppBar hugs its
    // trailing actions to the edge, packs adjacent actions flush, and left-aligns
    // + full-height-stretches its leading, so this tier drifts from the CN/M3E
    // tiers (which self-inset 16 + space by abxGap8). Mirror AppBoxKitNativeSliverAppBar's
    // Material-tier guards so every appbar tier lands its bar buttons at the same
    // inset (16), gap (abxGap8), and size — the two bars are kept in lockstep
    // (kit_native_sliver_app_bar_test + kit_native_app_bar_test assert both).
    // Same implied-leading parity as the CN tier: the stock BackButton drifts
    // from the AppBoxKitNativeIconButton trailing actions, so the kit implies its own.
    final effectiveLeading = appBoxKitImpliedAppBarLeading(
      context,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
    );
    return AppBar(
      key: key,
      title: title == null ? null : Text(title!),
      actionsPadding: const EdgeInsets.only(right: 16),
      actions: actions == null
          ? null
          : [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: abxGap8,
                children: actions!,
              ),
            ],
      leadingWidth: effectiveLeading == null ? null : 16 + 48.0,
      leading: effectiveLeading == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: effectiveLeading,
              ),
            ),
      automaticallyImplyLeading: automaticallyImplyLeading,
    );
  }
}
