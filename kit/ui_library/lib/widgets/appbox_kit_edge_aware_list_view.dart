import 'package:flutter/material.dart' show kToolbarHeight;
import 'package:flutter/widgets.dart';
import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';

import 'appbox_kit_scroll_edge_effect.dart';

/// Which scroll edges an edge-aware container treats. A four-value enum, not
/// a `Set<AppBoxKitScrollEdge>`, so the default is a compile-time constant
/// and "no edges" is a named, greppable decision rather than an empty
/// literal.
enum AppBoxKitScrollEdges {
  none,
  top,
  bottom,
  both;

  bool get treatsTop => this == top || this == both;
  bool get treatsBottom => this == bottom || this == both;
}

/// A [ListView] that applies [AppBoxKitScrollEdgeEffect] to every child, so the
/// edge treatment is a property of the *scrollable* rather than something each
/// leaf widget has to remember.
///
/// **Why the container owns it.** The effect is per-call-site sugar
/// (`.scrollEdgeEffect()`), and call sites forget: at the time this widget was
/// written, 7 of 18 glass-bearing showcase widgets had it and 11 did not — a
/// bare `AppBoxKitNativeToolbar` sat in the profile list between two treated
/// cards, staying crisp at full alpha while its neighbours faded under the tab
/// bar. Forgetting is the failure mode, and a leaf cannot detect that it was
/// forgotten. A container can't miss a child, and a widget added later inherits
/// the treatment instead of regressing the screen.
///
/// The leaf sugar stays public — a `CustomScrollView` (slivers) still needs it,
/// and that is the right tool there. This widget is for the box-child case.
///
/// **Edges are ON by default, and turned off by design choice** (ratified
/// 2026-08-14, superseding the original opt-in stance): the soft dissolve at
/// both scroll edges is part of the kit's look, not merely occlusion repair,
/// so a fade with no chrome under it is a design effect rather than a bug.
/// Steer with [edges] (`none` / `top` / `bottom` / `both`, default `both`):
/// - **Top** fades content as it leaves the leading edge. Skipped
///   automatically under [extendBehindTopBar]: the cull boundary then sits
///   above the physical screen, so the band would be off-screen by
///   construction — wrapping for it buys nothing.
/// - **Bottom** fades content into whatever the trailing edge holds. The band
///   height is auto-derived from `MediaQuery.paddingOf(context).bottom` —
///   which is the tab-bar block under `Scaffold(extendBody: true)` and the
///   home-indicator inset elsewhere — or overridden via [bottomOcclusion].
///
/// **Do not also call `.scrollEdgeEffect()` on a child** — the wrappers nest,
/// and the inner one measures its own coverage against the same viewport, so
/// the fade applies twice.
///
/// ```dart
/// AppBoxKitEdgeAwareListView(
///   padding: const EdgeInsets.all(16),
///   bottomOcclusion: kTabBarBlockHeight,
///   children: [
///     ProfileRailCard(),      // treated
///     NativeToolbarDemo(),    // treated — the gap this widget closes
///     ProfileFeedbackCard(),  // treated
///   ],
/// )
/// ```
class AppBoxKitEdgeAwareListView extends StatelessWidget {
  const AppBoxKitEdgeAwareListView({
    super.key,
    required this.children,
    this.padding,
    this.controller,
    this.physics,
    this.edges = AppBoxKitScrollEdges.both,
    this.bottomOcclusion,
    this.style = AppBoxKitScrollEdgeEffectStyle.automatic,
    this.extendBehindTopBar = false,
  });

  /// The list's children. Each is wrapped in the configured edge effects —
  /// spacers included, so the treatment is uniform and the wrapping rule has
  /// no exceptions to remember.
  final List<Widget> children;

  /// Padding around the list contents. Where [bottomOcclusion] is set, this
  /// should still reserve trailing space so the last child can scroll clear of
  /// the overlaying chrome — the effect softens the underlap, it does not
  /// create room.
  final EdgeInsetsGeometry? padding;

  final ScrollController? controller;
  final ScrollPhysics? physics;

  /// Which edges get the fade. Default: both — turning one off is a design
  /// decision, made here, per edge. The top treatment is additionally skipped
  /// under [extendBehindTopBar] (band off-screen by construction).
  final AppBoxKitScrollEdges edges;

  /// Override for the bottom band height. `null` (default) auto-derives it
  /// from `MediaQuery.paddingOf(context).bottom` — correct for a floating tab
  /// bar over `extendBody: true` and for the bare home-indicator inset alike.
  /// Ignored unless [edges] treats the bottom.
  final double? bottomOcclusion;

  /// Strength profile forwarded to every child's effect.
  final AppBoxKitScrollEdgeEffectStyle style;

  /// Extend the viewport's leading edge ABOVE the physical screen top, as
  /// materialization headroom for native glass in the list.
  ///
  /// Why: sliver children are paint-culled at the viewport's leading edge by a
  /// LAYOUT test (`RenderSliverMultiBoxAdaptor.paint`: child painted only while
  /// `mainAxisDelta + paintExtent > 0`) — `clipBehavior` never participates
  /// (proven on device, clips 12-48 and 13-17). A culled child's platform
  /// views are fully detached, and iOS 26 glass re-runs its materialize
  /// animation on re-add — so whichever row of a multi-row child leads
  /// re-entry is VISIBLE mid-animation at the boundary (clip 13-53-b: the
  /// smoke block's bottom row flashed; the top row, 52px further out, always
  /// finished off-screen). This flag oversizes the viewport upward (status
  /// bar + `kToolbarHeight` + gap) via an [OverflowBox] and adds the same
  /// amount to the top padding, so resting layout is unchanged but the
  /// cull/re-add boundary sits above the physical top and the animation
  /// finishes before the view enters the screen.
  ///
  /// **Use only under NATIVE or no top chrome (full-bleed body).** With an
  /// opaque Flutter-drawn bar, the overdraw region is on-screen under the bar
  /// and overlay-layer churn flashes body content OVER the bar during fast
  /// scrolls (clip 13-32, flutter#86787 class) — that arrangement is why the
  /// gallery's top bar went native (allowlist rule 4). Overflow is
  /// paint-only: taps above the body's bounds still go to whatever chrome
  /// floats there.
  final bool extendBehindTopBar;

  @override
  Widget build(BuildContext context) {
    // Generous seam-to-top estimate: kToolbarHeight (56) covers the CN bar
    // (44 + abxGap8 gap) and the Material bar alike. Overshoot just culls a
    // little earlier off-screen; undershoot would put the boundary back in
    // view. viewPadding survives Scaffold's body padding removal, so the
    // status-bar height is still readable here.
    final overdraw = extendBehindTopBar
        ? MediaQuery.viewPaddingOf(context).top + kToolbarHeight + abxGap8
        : 0.0;
    // Under overdraw the cull boundary is above the physical top, so a top
    // band could never be seen — skip the wrapper rather than pay for it.
    final treatTop = edges.treatsTop && !extendBehindTopBar;
    final bottomBand = edges.treatsBottom
        ? (bottomOcclusion ?? MediaQuery.paddingOf(context).bottom)
        : null;
    final list = ListView(
      padding: (padding ?? EdgeInsets.zero)
          .add(EdgeInsets.only(top: overdraw)),
      controller: controller,
      physics: physics,
      children: [
        for (final child in children)
          _treat(child,
              topEdge: treatTop,
              bottomOcclusion: bottomBand,
              style: style),
      ],
    );
    if (overdraw == 0) return list;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight + overdraw;
        // Bottom-aligned: the trailing edge stays put (extendBody's boundary),
        // only the leading edge moves up behind the bar.
        return OverflowBox(
          alignment: Alignment.bottomCenter,
          minHeight: height,
          maxHeight: height,
          child: list,
        );
      },
    );
  }
}

/// Applies the configured edges to one child. Top is applied first so it ends
/// up the *inner* wrapper, matching the hand-written order these containers
/// replace. Shared by both containers so their treatment cannot drift — a
/// drift between two copies of this is the same class of bug the containers
/// exist to prevent.
Widget _treat(
  Widget child, {
  required bool topEdge,
  required double? bottomOcclusion,
  required AppBoxKitScrollEdgeEffectStyle style,
}) {
  var treated = child;
  if (topEdge) {
    treated = treated.scrollEdgeEffect(style: style);
  }
  if (bottomOcclusion != null) {
    treated = treated.scrollEdgeEffect(
      style: style,
      edge: AppBoxKitScrollEdge.bottom,
      occlusionPadding: bottomOcclusion,
    );
  }
  return treated;
}

/// The sliver counterpart of [AppBoxKitEdgeAwareListView], for the
/// `CustomScrollView` case: a `SliverList` whose every item is edge-treated.
///
/// Use this wherever a list of box children lives inside a `CustomScrollView`
/// — typically alongside a pinned header, which is the reason to be in slivers
/// at all and the reason the default top treatment earns its keep here
/// (content genuinely underlaps chrome pinned *inside* the scrollable).
///
/// The item builder returns the *untreated* child; wrappers are added around
/// whatever it returns. Any per-item animation the builder applies (a
/// staggered rise-in, say) therefore ends up **inside** the edge wrappers.
/// That is safe: the effect measures layout geometry via `getOffsetToReveal`,
/// which paint-time opacity and transforms do not move.
///
/// ```dart
/// AppBoxKitEdgeAwareSliverList(
///   padding: const EdgeInsets.all(16),
///   // edges defaults to both — the pinned search header above is covered
///   bottomOcclusion: kTabBarBlockHeight,
///   itemCount: groups.length,
///   itemBuilder: (context, i) => GroupSection(groups[i]),
/// )
/// ```
class AppBoxKitEdgeAwareSliverList extends StatelessWidget {
  const AppBoxKitEdgeAwareSliverList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.edges = AppBoxKitScrollEdges.both,
    this.bottomOcclusion,
    this.style = AppBoxKitScrollEdgeEffectStyle.automatic,
  });

  final int itemCount;

  /// Builds the untreated item. The edge wrappers are applied around the
  /// returned widget.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Padding around the list, applied as a `SliverPadding` outside it.
  final EdgeInsetsGeometry? padding;

  /// Which edges get the fade. Default: both. Slivers have no overdraw flag,
  /// so top is honored whenever set — the pinned-header case this container
  /// exists for.
  final AppBoxKitScrollEdges edges;

  /// Override for the bottom band height. `null` (default) auto-derives it
  /// from `MediaQuery.paddingOf(context).bottom`. Ignored unless [edges]
  /// treats the bottom.
  final double? bottomOcclusion;

  final AppBoxKitScrollEdgeEffectStyle style;

  @override
  Widget build(BuildContext context) {
    final list = SliverList.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) => _treat(
        itemBuilder(context, index),
        topEdge: edges.treatsTop,
        bottomOcclusion: edges.treatsBottom
            ? (bottomOcclusion ?? MediaQuery.paddingOf(context).bottom)
            : null,
        style: style,
      ),
    );
    return padding == null
        ? list
        : SliverPadding(padding: padding!, sliver: list);
  }
}
