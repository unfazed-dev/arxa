import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart' show SliverAppBarM3E;
import 'package:arxa_kit_core/common/arxa_kit_app_constants.dart'
    show abxGap8;
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';

import 'arxa_kit_native_icon_button.dart';

/// Adaptive sliver app bar — the scrollable-surface counterpart of
/// [ArxaKitNativeAppBar]. Drop it in as the FIRST sliver of a [CustomScrollView] so
/// the bar participates in the scroll (collapses / floats) instead of pinning
/// fixed above the body in [Scaffold.appBar].
///
/// Defaults to the stock [SliverAppBar] rhythm (the Flutter sample's initial
/// state) — `pinned: true`, `floating: false`, `snap: false`: the bar collapses
/// to its toolbar as the list scrolls down and stays pinned at the top; it does
/// not re-float mid-list. Override the three flags per surface (`snap` requires
/// `floating` — asserted, the same coupling the sample's switches enforce).
///
/// For the sample's full collapsing-header shape, pass [background] (the
/// sample's `background: FlutterLogo()` slot — e.g. the host's brand mark):
/// the Material tier then builds `FlexibleSpaceBar(title: Text(title),
/// background: background)` itself and defaults [expandedHeight] to the
/// sample's 160. Pass [flexibleSpace] instead when the header needs more than
/// title-over-background (the two are mutually exclusive — asserted).
///
/// Tiers (mirrors [ArxaKitNativeAppBar]):
/// - **Android M3 Expressive** — [SliverAppBarM3E] (its own scroll motion).
///   `floating`/`pinned`/`snap`/`flexibleSpace` are ignored on this tier — M3E
///   owns the collapsing behavior, the same documented-gap shape as
///   [ArxaKitNativeAppBar]'s `automaticallyImplyLeading` on M3E.
/// - **iOS / desktop / web / fallback** — Material [SliverAppBar], honoring
///   `floating`/`pinned`/`snap`/`expandedHeight`/`flexibleSpace`/`stretch`.
///   Cupertino has no sliver nav bar and the Liquid Glass large-title bar is not
///   yet wrapped by `cupertino_native_better`, so the iOS tier is a themed
///   Material [SliverAppBar] (color-pinned to the active [ColorScheme]).
///
/// Prefer this over [ArxaKitNativeAppBar] in `Scaffold.appBar` when the body is a
/// [CustomScrollView] and you want the bar to scroll with the content. For a
/// fixed bar over any body, use [ArxaKitNativeAppBar] in `Scaffold.appBar`.
class ArxaKitNativeSliverAppBar extends StatelessWidget {
  const ArxaKitNativeSliverAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.floating = false,
    this.pinned = true,
    this.snap = false,
    this.expandedHeight,
    this.flexibleSpace,
    this.background,
    this.collapsedHeight,
    this.stretch = false,
    this.toolbarHeight = kToolbarHeight,
    this.wantNative = true,
  })  : assert(
          !snap || floating,
          'snap can only be true if floating is also true (SliverAppBar invariant)',
        ),
        assert(
          flexibleSpace == null || background == null,
          'Pass either flexibleSpace or background, not both — flexibleSpace '
          'owns the whole slot.',
        );

  /// Title text. [Text] on the Material tier, `titleText` on the M3E tier.
  final String? title;

  /// Trailing action widgets, 1:1 to each tier's trailing slot.
  final List<Widget>? actions;

  /// Leading widget (typically back/close). Null → tier may imply one per
  /// [automaticallyImplyLeading].
  final Widget? leading;

  /// Let the tier auto-build a back button when [leading] is null. Material
  /// tier only; the M3E tier always implies a leading when [leading] is null.
  final bool automaticallyImplyLeading;

  /// Whether the bar floats (re-appears on scroll-up) while collapsed. Default
  /// `false`. Ignored on the M3E tier.
  final bool floating;

  /// Whether the bar stays visible at the top when fully collapsed. Default
  /// `true`. Ignored on the M3E tier.
  final bool pinned;

  /// Whether the floating bar snaps into view on scroll-up. Default `false`.
  /// Only meaningful with [floating] `true` (asserted). Ignored on the M3E tier.
  final bool snap;

  /// Expanded height the bar collapses from. Null → toolbar height only.
  final double? expandedHeight;

  /// Stacked behind the toolbar (e.g. [FlexibleSpaceBar]). Material tier only.
  /// When set, it owns the title — the toolbar [title] is suppressed there
  /// (still passed on the M3E tier, which ignores [flexibleSpace]).
  final Widget? flexibleSpace;

  /// Brand mark / hero art behind the collapsing title — the
  /// [FlexibleSpaceBar.background] slot from the SliverAppBar sample
  /// (`background: FlutterLogo()`). When set (and [flexibleSpace] is null) the
  /// Material tier builds the sample's `FlexibleSpaceBar(title: Text(title),
  /// background: background)` itself and defaults [expandedHeight] to 160
  /// (pass [expandedHeight] to override). Material tier only — ignored on the
  /// M3E tier, the same documented gap as [flexibleSpace]. Mutually exclusive
  /// with [flexibleSpace] (asserted).
  final Widget? background;

  /// Min height once collapsed. Material tier only.
  final double? collapsedHeight;

  /// Over-scroll stretch of [flexibleSpace]. Material tier only.
  final bool stretch;

  /// Toolbar height. Default Material `kToolbarHeight`.
  final double toolbarHeight;

  /// Host opt-out of native chrome (forces the Material tier).
  final bool wantNative;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (wantNative && ArxaKitPlatform.supportsComposeM3E) {
      // M3E owns its collapsing scroll motion; floating/pinned/snap are ignored
      // here (documented gap — same shape as ArxaKitNativeAppBar's
      // automaticallyImplyLeading M3E gap).
      return SliverAppBarM3E(
        titleText: title,
        actions: actions,
        leading: leading,
      );
    }
    // The sample-shaped shorthand: a [background] without an explicit
    // [flexibleSpace] builds the sample's FlexibleSpaceBar(title, background)
    // — which then owns the title, so the toolbar title is suppressed below.
    final brandBackground = background;
    final effectiveFlexibleSpace = flexibleSpace ??
        (brandBackground == null
            ? null
            : FlexibleSpaceBar(
                title: title == null ? null : Text(title!),
                background: brandBackground,
              ));
    // Material's leading slot LEFT-aligns its child (gap 0) AND vertically
    // stretches it to the full toolbar height, while the trailing rides at
    // natural size inset 16 — so a bare sliver bar's leading (a back button)
    // hugs the edge and renders TALLER than the trailing actions. Inset it 16
    // (symmetric with the trailing / CupertinoNavigationBar's
    // _kNavBarEdgePadding) and Center it at natural size so leading + trailing
    // buttons are the same size and aligned. leadingWidth widened to fit the
    // 16 inset + button without clipping.
    // Only reserve the widened slot when there IS a leading — a null leading
    // must keep Material's default so the title isn't pushed right.
    // Implied-leading parity with the fixed bar: the stock BackButton drifts
    // from the ArxaKitNativeIconButton trailing actions, so the kit implies its
    // own back button (maybePop + stock a11y label preserved).
    final effectiveLeading = arxaKitImpliedAppBarLeading(
      context,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
    );
    return SliverAppBar(
      key: key,
      // A FlexibleSpaceBar owns the title when provided (the SliverAppBar
      // sample pattern) — also passing the toolbar title would double-render.
      title:
          title == null || effectiveFlexibleSpace != null ? null : Text(title!),
      // A bare Material SliverAppBar hugs its trailing actions to the edge, so a
      // trailing menu button sits tighter than the iOS fixed bar (ArxaKitNativeAppBar
      // → CupertinoNavigationBar, whose trailing is inset by _kNavBarEdgePadding =
      // 16). Match that inset so the shared account menu lands at the showcase
      // default in any appbar. (The M3E + CN tiers already self-inset.)
      actionsPadding: const EdgeInsets.only(right: 16),
      // ...and a bare SliverAppBar packs adjacent actions flush together, while
      // the fixed CN bar spaces its trailing Row by abxGap8. Wrap the actions in
      // the same Row so two bar buttons sit the same distance apart in either
      // appbar — shared abxGap8 (not a literal) so the two bars can't drift.
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
              // centerLeft (not Center) so the 16 inset is exact — Center would
              // center the button in leadingWidth and add slack; centerLeft
              // pins it to the left, keeping vertical centering.
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: effectiveLeading,
              ),
            ),
      automaticallyImplyLeading: automaticallyImplyLeading,
      floating: floating,
      pinned: pinned,
      snap: snap,
      expandedHeight:
          expandedHeight ?? (brandBackground == null ? null : 160.0),
      flexibleSpace: effectiveFlexibleSpace,
      collapsedHeight: collapsedHeight,
      stretch: stretch,
      toolbarHeight: toolbarHeight,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    );
  }
}
