import 'package:flutter/material.dart' show kToolbarHeight;
import 'package:flutter/widgets.dart';
import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';

import 'appbox_kit_scroll_edge_effect.dart';

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
/// **Edges are opt-in, and that is deliberate.** An edge effect with no chrome
/// on that edge is wrong, not merely redundant: it fades content out just
/// before the viewport clips it. Pass an edge only where something actually
/// overlays the scrollable —
/// - [topEdge] for chrome pinned *inside* the scrollable (a pinned sliver
///   header). Content under an opaque `Scaffold.appBar` never underlaps it
///   (absent `extendBodyBehindAppBar`), so the default is `false`.
/// - [bottomOcclusion] for chrome stacked *over* the scrollable from outside
///   (a floating tab bar above `Scaffold(extendBody: true)`); pass its height.
///   `null` (the default) means nothing overlays the bottom.
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
    this.topEdge = false,
    this.bottomOcclusion,
    this.style = AppBoxKitScrollEdgeEffectStyle.automatic,
    this.extendBehindTopBar = false,
  }) : assert(!(extendBehindTopBar && topEdge),
            'extendBehindTopBar is for an opaque bar OUTSIDE the scrollable; '
            'a top edge effect under one fades content the bar already hides');

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

  /// Treat the leading edge. Only for chrome pinned *inside* the scrollable.
  final bool topEdge;

  /// Height of chrome overlaying the trailing edge from outside the
  /// scrollable. `null` = nothing overlays it, so no bottom effect.
  final double? bottomOcclusion;

  /// Strength profile forwarded to every child's effect.
  final AppBoxKitScrollEdgeEffectStyle style;

  /// Extend the viewport's leading edge up behind an OPAQUE `Scaffold.appBar`
  /// so it sits at the physical screen top instead of the bar seam.
  ///
  /// Why: sliver children are paint-culled at the viewport's leading edge by a
  /// LAYOUT test (`RenderSliverMultiBoxAdaptor.paint`: child painted only while
  /// `mainAxisDelta + paintExtent > 0`) — `clipBehavior` never participates, so
  /// `Clip.none` cannot move the boundary (proven on device, clips 12-48 and
  /// 13-17). When the list hosts native platform views, culling at the bar
  /// seam means the engine drops the view mid-screen and re-materializes it on
  /// re-entry with a visible glass shimmer. This flag oversizes the viewport
  /// upward (status bar + `kToolbarHeight` + gap) via an [OverflowBox] and adds
  /// the same amount to the top padding, so resting layout is unchanged but
  /// children now cull at/above the physical screen edge — the same lifecycle
  /// `extendBody: true` gives the bottom. ONLY valid under opaque top chrome:
  /// the bar paints after the body and covers the overdraw region (taps above
  /// the body's bounds still go to the bar — overflow is paint-only).
  ///
  /// **WARNING (clip 13-32, device-observed):** when the overdraw region hosts
  /// PLATFORM VIEWS, the engine's overlay-layer churn can flash body content
  /// OVER a Flutter-drawn bar during fast scrolls (flutter#86787 class) — the
  /// bar's paint-order guarantee does not survive hybrid-composition slicing.
  /// Safe only when the content passing behind the bar is pure Flutter, or the
  /// covering chrome is itself a native view (deterministic UIView z-order).
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
    final list = ListView(
      padding: (padding ?? EdgeInsets.zero)
          .add(EdgeInsets.only(top: overdraw)),
      controller: controller,
      physics: physics,
      children: [
        for (final child in children)
          _treat(child,
              topEdge: topEdge,
              bottomOcclusion: bottomOcclusion,
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
/// at all and the reason [topEdge] usually belongs here (content genuinely
/// underlaps chrome pinned *inside* the scrollable).
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
///   topEdge: true,                    // pinned search header above
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
    this.topEdge = false,
    this.bottomOcclusion,
    this.style = AppBoxKitScrollEdgeEffectStyle.automatic,
  });

  final int itemCount;

  /// Builds the untreated item. The edge wrappers are applied around the
  /// returned widget.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Padding around the list, applied as a `SliverPadding` outside it.
  final EdgeInsetsGeometry? padding;

  /// Treat the leading edge — for chrome pinned inside the scrollable.
  final bool topEdge;

  /// Height of chrome overlaying the trailing edge from outside the
  /// scrollable. `null` = nothing overlays it.
  final double? bottomOcclusion;

  final AppBoxKitScrollEdgeEffectStyle style;

  @override
  Widget build(BuildContext context) {
    final list = SliverList.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) => _treat(
        itemBuilder(context, index),
        topEdge: topEdge,
        bottomOcclusion: bottomOcclusion,
        style: style,
      ),
    );
    return padding == null
        ? list
        : SliverPadding(padding: padding!, sliver: list);
  }
}
