import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNGlassEffect, LiquidGlassConfig, LiquidGlassContainer;
import 'package:flutter/material.dart';
import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';

import 'appbox_kit_frosted_surface.dart';

/// Height of the floating bar's control block, below the status bar: the
/// 44pt control row plus the same breathing gap the boxed app bar reserves.
/// Hosts that lay content full-bleed behind the bar add this (plus the
/// status-bar inset) to their content's top padding.
const double kAppBoxKitFloatingBarBlockHeight = 44 + abxGap8;

/// Tuck/hide motion for the floating chrome. Apple publishes no duration for
/// the iOS 26 bar minimize; its system chrome uses springs that settle in
/// roughly 0.4–0.5s, so 400ms with a fast-start/soft-settle ease-out is the
/// closest overshoot-free match (device-tuned 2026-08-13; 280ms read
/// snappier than system). One knob — every chrome slide uses this pair.
const Duration kAppBoxKitFloatingBarMotionDuration =
    Duration(milliseconds: 400);
const Curve kAppBoxKitFloatingBarMotionCurve = Curves.easeOutCubic;

/// Which end of [AppBoxKitNativeFloatingBar] tucks away when minimized.
enum AppBoxKitFloatingBarTuck {
  /// Nothing tucked — the full bar.
  none,

  /// The trailing actions slide off the right edge; the title pill stays.
  trailing,

  /// The title pill slides off the left edge; the actions stay.
  leading,

  /// Both ends tuck — pill off the left, actions off the right.
  both;

  bool get _tucksLeading =>
      this == AppBoxKitFloatingBarTuck.leading ||
      this == AppBoxKitFloatingBarTuck.both;
  bool get _tucksTrailing =>
      this == AppBoxKitFloatingBarTuck.trailing ||
      this == AppBoxKitFloatingBarTuck.both;
}

/// Floating top chrome for the Liquid Glass tier — the top-edge counterpart
/// of the floating native tab bar.
///
/// Why this exists (allowlist rule 4, clips 12-48/13-17/13-32): a
/// Flutter-drawn opaque app bar cannot coexist with native glass controls in
/// the scrollable beneath it — culling them at the bar seam pops/shimmers,
/// and painting them behind the bar flashes body content OVER the bar
/// (overlay-layer churn, flutter#86787 class). Native chrome resolves both:
/// this bar's glass surface is a platform view painted after the scrolled
/// content, so it composites above every platform view in that content with
/// deterministic UIView z-order — the exact lifecycle that keeps the bottom
/// tab bar clean. Content scrolls full-bleed behind it and culls at the
/// physical screen edge, off-screen.
///
/// Layout contract: place over a full-bleed body (Stack), and raise the
/// body's `MediaQuery.padding.top` by [kAppBoxKitFloatingBarBlockHeight] so
/// descendants inset themselves. The title rides its own native glass
/// capsule; actions are expected to be native glass controls already
/// (icon buttons, popup menus). On tiers without native glass the vendor
/// container degrades to its bare child — hosts should only mount this bar
/// on `AppBoxKitPlatform.supportsLiquidGlass`.
class AppBoxKitNativeFloatingBar extends StatelessWidget {
  const AppBoxKitNativeFloatingBar({
    super.key,
    this.leading,
    this.title,
    this.actions,
    this.tuck = AppBoxKitFloatingBarTuck.none,
  });

  /// Back/close affordance at the row start, before the title pill (ratified
  /// 2026-08-13 — pushed routes use the floating chrome instead of a
  /// hand-assembled `Scaffold` + boxed bar).
  ///
  /// **Tucks with the leading edge** (device ruling 2026-08-13, clip 22-34:
  /// the pill sliding away alone while the back button stayed read as a
  /// half-minimized bar). Any leading-tucking variant slides this slot off
  /// the left together with the title pill; scroll-back or reaching the top
  /// restores both, so the route is one small reverse gesture from its back
  /// affordance, never stranded. While tucked it ignores pointers, like the
  /// actions.
  ///
  /// A NATIVE glass icon button is lawful here: law rule 5 demotes only the
  /// fixed chrome that scrolled glass passes UNDER (hence the Flutter-drawn
  /// title pill), while "interactive bar controls stay native glass" — the
  /// same carve-out the bar's action icon buttons already ship on.
  final Widget? leading;

  /// Title text, shown in a native glass capsule at the leading edge.
  final String? title;

  /// Trailing action widgets — native glass controls, spaced [abxGap8].
  final List<Widget>? actions;

  /// Apple-style minimize: the tucked end SLIDES off its screen edge and the
  /// other stays. Slide, never fade — partial-alpha over platform views
  /// is composition rule 1's forbidden shape, while transform mutators are
  /// proven to land on iOS platform views. Tucked widgets stay mounted
  /// throughout, so restoring them never re-materializes glass (clip
  /// 13-53-b's lesson). [leading] rides the leading edge with the pill —
  /// see its contract. Drive this from scroll direction via
  /// [AppBoxKitFloatingChrome], or directly for custom hosts — but note the
  /// chrome also hard-clips the bar's left/right edges to its slot so a
  /// route transform (the iOS back-swipe) cannot carry the parked ends back
  /// into the frame; a direct host that tucks must clip likewise
  /// (horizontally only — a full-rect clip slices the pill's shadow).
  final AppBoxKitFloatingBarTuck tuck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, abxGap8),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              if (leading != null) ...[
                AnimatedSlide(
                  // 2.0× own width clears the 16px edge padding with margin;
                  // off-screen native views stay attached (no detach, no
                  // re-materialize on return).
                  offset:
                      tuck._tucksLeading ? const Offset(-2, 0) : Offset.zero,
                  duration: kAppBoxKitFloatingBarMotionDuration,
                  curve: kAppBoxKitFloatingBarMotionCurve,
                  child: IgnorePointer(
                    ignoring: tuck._tucksLeading,
                    child: leading!,
                  ),
                ),
                const SizedBox(width: abxGap8),
              ],
              if (title != null)
                AnimatedSlide(
                  // 2.0× own width clears the 16px edge padding with margin.
                  // ponytail: with a [leading] present the pill starts one
                  // control-width further in, so a very short title tucks to
                  // just shy of the leading edge rather than past it. Widen
                  // the multiplier only if a device clip shows a sliver.
                  offset:
                      tuck._tucksLeading ? const Offset(-2, 0) : Offset.zero,
                  duration: kAppBoxKitFloatingBarMotionDuration,
                  curve: kAppBoxKitFloatingBarMotionCurve,
                  child:
                      // Flutter-drawn pill, DELIBERATELY not native glass
                      // (clip 13-53): scrolled native glass buttons crossing a
                      // native glass capsule stack glass-on-glass — the passing
                      // button's glass washed to a square ghost for exactly the
                      // capsule's span, while buttons crossing the pill gaps
                      // stayed crisp. A platform-view-safe frosted pill leaves
                      // no native surface in the title region to stack against.
                      // The vibrant fill is also Apple's own degrade for nested
                      // glass (§3).
                      //
                      // The PLAIN native anchor beneath it exists because Flutter
                      // ops floating over a platform-view-bearing scrollable have
                      // no stable home: the engine's view slicer
                      // (flow/view_slicer.cc) keeps them in an overlay above the
                      // platform views only while they intersect a platform-view
                      // rect, and otherwise drops them to a background canvas that
                      // is difference-clipped by every overlay — on device
                      // (clip 21-32 + composited-window probe, 2026-08-13) the
                      // pill's overlay shrank from (16,59,361x78) to the actions'
                      // bbox during top rubber-band overscroll and the pill
                      // vanished wholesale. The anchor is a stationary platform
                      // view exactly under the pill, so the intersection holds
                      // every frame. `plain` renders NO glass material (clear
                      // fill, Glass.identity), so 13-53 cannot recur — this is a
                      // compositing anchor, not a visible surface.
                      // transition-exempt: the anchor renders NOTHING (plain
                      // effect, clear fill, Glass.identity) — there is no visible
                      // glass to leak over a route slide, and gating it would
                      // re-open the erasure for exactly the frames a transition
                      // spans.
                      LiquidGlassContainer(
                    config: const LiquidGlassConfig(
                      effect: CNGlassEffect.plain,
                    ),
                    child: AppBoxKitFrostedSurface(
                      platformViewSafe: true,
                      borderRadius: 22,
                      child: SizedBox(
                        height: 44,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                            child: Text(
                              title!,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (actions != null)
                AnimatedSlide(
                  // 2.0× own width clears the 16px edge padding with margin;
                  // off-screen native views stay attached (no detach, no
                  // re-materialize on return).
                  offset:
                      tuck._tucksTrailing ? const Offset(2, 0) : Offset.zero,
                  duration: kAppBoxKitFloatingBarMotionDuration,
                  curve: kAppBoxKitFloatingBarMotionCurve,
                  child: IgnorePointer(
                    ignoring: tuck._tucksTrailing,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: abxGap8,
                      children: actions!,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status-bar-zone scrim: a Flutter-DRAWN vertical gradient from the scaffold
/// background (opaque at y=0, through the status-bar inset) to transparent by
/// the bottom of the floating bar block. Drawn ON TOP of a full-bleed body so
/// scrolled content — including native platform views, which ruling 4 now
/// allows in scrollables — dissolves before it reaches the clock, battery and
/// Dynamic Island instead of garbling with them.
///
/// Why a drawn gradient and not the obvious alternatives: iOS's own
/// scroll-edge effect is a system chrome affordance, unavailable to
/// Flutter-composited content, and every effect-based equivalent is barred by
/// composition rule 1 — a BackdropFilter band cannot sample platform-view
/// pixels (they would punch through) and an Opacity/fade over the content
/// saveLayers a platform-view-hosting subtree. A gradient fill adds no layer
/// at all.
///
/// **Watch-item, not a validated mechanism (law rule 4, clip 13-32).** The
/// nearest precedent — the bar's frosted title pill — is a PARTIAL-width
/// overlay, and that is the discriminating difference: the arrangement clip
/// 13-32 rejected was a full-width OPAQUE Flutter bar over passing platform
/// views, where overlay-layer churn flashed body content OVER the bar during
/// fast scrolls. This scrim is full-width and opaque at its top edge, so it
/// is the same shape. It is lawful (no saveLayer, no alpha over platform
/// views) and reverts in one deletion; if a device clip shows content
/// flashing over the status band during a fast fling, that is this, and the
/// answer is native chrome for the band, not another gradient.
///
/// Height is `MediaQuery.paddingOf(context).top` plus [fadeExtent] —
/// deliberately the same `padding.top` the bar's own `SafeArea` reads, so
/// under the floating chrome the fade lands exactly on the bar's bottom edge
/// under every inset (pinned by test). Read it from the chrome's own context,
/// never the body's raised MediaQuery, or the scrim double-counts the block.
class AppBoxKitTopEdgeScrim extends StatelessWidget {
  const AppBoxKitTopEdgeScrim({
    super.key,
    this.fadeExtent = kAppBoxKitFloatingBarBlockHeight,
  });

  /// How far BELOW the status-bar inset the gradient takes to reach fully
  /// clear. The default spans the bar block, which is what the floating
  /// chrome wants: scrolled content is already dissolving by the time it
  /// reaches the bar row.
  ///
  /// Bar-less hosts must shrink this to their content's own top inset.
  /// The scrim is opaque at the status-bar line and only reaches clear after
  /// [fadeExtent], so a ramp longer than the host's resting top padding lays
  /// a partial wash over static content that never scrolls — a washed-out
  /// heading instead of a dissolving one. Sizing the ramp to the host's top
  /// padding makes the scrim bite only on content that has actually scrolled
  /// up into the band.
  final double fadeExtent;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final height = top + fadeExtent;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Opaque for the whole status-bar band, then a single ramp to
            // clear across the control row. withValues, never an Opacity
            // widget: the law gate scans this file for the alpha shapes.
            colors: [
              background,
              background,
              background.withValues(alpha: 0),
            ],
            stops: [0, top / height, 1],
          ),
        ),
      ),
    );
  }
}

/// Bottom-edge counterpart of [AppBoxKitTopEdgeScrim]: a Flutter-DRAWN
/// vertical gradient from transparent down to the scaffold background —
/// opaque through the home-indicator band, with the ramp landing on the tab
/// bar row. Drawn ON TOP of a full-bleed `extendBody: true` body so scrolled
/// content dissolves before it hard-clips at the physical bottom edge,
/// mirroring the dissolve the top chrome already gets.
///
/// Exists because the per-child [AppBoxKitScrollEdgeEffect] is deliberately
/// inert on the Liquid Glass tier (alpha over platform-view-hosting subtrees
/// ghosts — clip 12-48), so on device the bottom edge showed NO fade at all
/// (clip 18-50) while the top dissolved via the scrim. Same lawful mechanism
/// as the top: a gradient fill, no saveLayer, no alpha over platform views,
/// and it reverts in one deletion. The clip 13-32 watch-item on full-width
/// background-colored overlays applies here identically.
///
/// Height is `MediaQuery.viewPaddingOf(context).bottom` plus [fadeExtent] —
/// the RAW device inset, so read it OUTSIDE [AppBoxKitExtendBodyFabLift] (or
/// any wrapper that mirrors bar clearance into `viewPadding`), or the scrim
/// double-counts the bar block and washes resting content.
class AppBoxKitBottomEdgeScrim extends StatelessWidget {
  const AppBoxKitBottomEdgeScrim({
    super.key,
    this.fadeExtent = kAppBoxKitFloatingBarBlockHeight,
  });

  /// How far ABOVE the home-indicator inset the gradient takes to reach fully
  /// clear. The default spans the floating-bar block, which is what the tab
  /// bar wants: content is already dissolving by the time it reaches the bar
  /// row. Bar-less hosts must shrink this to their content's own bottom
  /// inset, for the same wash-over-static-content reason as the top scrim.
  final double fadeExtent;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final height = bottom + fadeExtent;
    final background = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // A single ramp from clear across the bar row, then opaque for
            // the whole home-indicator band. withValues, never an Opacity
            // widget: the law gate scans this file for the alpha shapes.
            colors: [
              background.withValues(alpha: 0),
              background,
              background,
            ],
            stops: [0, fadeExtent / height, 1],
          ),
        ),
      ),
    );
  }
}

/// Overlays [AppBoxKitBottomEdgeScrim] on a full-bleed body: the body fills,
/// the scrim pins to the bottom edge between the body and whatever bottom
/// chrome the host mounts (`bottomNavigationBar` renders above the body, so
/// mounting the scrim inside the body Stack keeps it under the bar).
///
/// Wrap the *body* of a `Scaffold(extendBody: true, bottomNavigationBar: …)`
/// OUTSIDE any viewPadding-raising wrapper ([AppBoxKitExtendBodyFabLift]),
/// so the scrim reads the raw device inset. [enabled] exists so a route can
/// opt out by design; the kit default is ON at both edges.
class AppBoxKitBottomEdgeScrimHost extends StatelessWidget {
  const AppBoxKitBottomEdgeScrimHost({
    super.key,
    required this.child,
    this.enabled = true,
    this.fadeExtent = kAppBoxKitFloatingBarBlockHeight,
  });

  final Widget child;
  final bool enabled;
  final double fadeExtent;

  @override
  Widget build(BuildContext context) {
    // Shape-stable by construction: the Stack and the body's Positioned.fill
    // slot exist regardless of [enabled]; only the scrim child comes and
    // goes. An `if (!enabled) return child` early return would swap the
    // subtree's shape on a flag flip and remount everything below — dropping
    // nested-router stacks mid-push (the C4 class, measured in the showcase
    // tab host) — and `enabled` exists precisely to be steered per-route at
    // runtime by hosts that yield the bottom edge.
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (enabled)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AppBoxKitBottomEdgeScrim(fadeExtent: fadeExtent),
          ),
      ],
    );
  }
}

/// How [AppBoxKitFloatingChrome] reacts to the body scrolling away from the
/// top.
enum AppBoxKitFloatingBarBehavior {
  /// The bar stays put while content scrolls beneath it.
  pinned,

  /// Full minimize: scrolling away tucks BOTH ends — the leading and the
  /// title pill off the leading edge, the actions off the trailing edge;
  /// scrolling back (or reaching the top) restores them.
  minimize,

  /// Minimize, trailing only: the actions tuck; the title pill stays.
  /// Mirrors the iOS 26 tab-bar minimize.
  minimizeTrailing,

  /// Minimize, leading only: the leading and the TITLE PILL tuck; the
  /// actions stay.
  minimizeLeading,

  /// The whole bar slides off the top on scroll-away and returns on
  /// scroll-back or at the top.
  hide,
}

/// Full-bleed body + [AppBoxKitNativeFloatingBar] + the scroll wiring, in one
/// widget — the glass tier's replacement for `Scaffold.appBar`.
///
/// Owns the two pieces every host was about to duplicate:
/// - raises the body's `MediaQuery.padding.top` by the status-bar inset plus
///   [kAppBoxKitFloatingBarBlockHeight], so descendants (nested Scaffolds,
///   lists reading `MediaQuery.paddingOf`) inset themselves correctly;
/// - listens to the body's vertical scroll notifications and drives
///   [behavior] — minimize/hide on scroll-away, restore on scroll-back or at
///   the top. All motion is slide (transform), per composition rule 1.
class AppBoxKitFloatingChrome extends StatefulWidget {
  const AppBoxKitFloatingChrome({
    super.key,
    required this.body,
    this.leading,
    this.title,
    this.actions,
    this.behavior = AppBoxKitFloatingBarBehavior.pinned,
  });

  /// Full-bleed content the bar floats over.
  final Widget body;

  /// See [AppBoxKitNativeFloatingBar.leading] — it tucks off the leading
  /// edge together with the title pill under the leading-tucking minimize
  /// variants, and rides the whole-bar slide under
  /// [AppBoxKitFloatingBarBehavior.hide].
  final Widget? leading;

  /// See [AppBoxKitNativeFloatingBar.title].
  final String? title;

  /// See [AppBoxKitNativeFloatingBar.actions].
  final List<Widget>? actions;

  /// Scroll reaction; [AppBoxKitFloatingBarBehavior.pinned] by default.
  final AppBoxKitFloatingBarBehavior behavior;

  @override
  State<AppBoxKitFloatingChrome> createState() =>
      _AppBoxKitFloatingChromeState();
}

class _AppBoxKitFloatingChromeState extends State<AppBoxKitFloatingChrome> {
  bool _away = false;

  /// Hysteresis: accumulated same-direction travel, reset on reversal. The
  /// state only toggles after [_toggleThreshold] px of committed travel, so
  /// finger micro-jitter mid-drag and the rubber-band bounce after a hard
  /// fling cannot twitch the chrome. (The 280ms AnimatedSlide retargets
  /// smoothly either way — this guards the TRIGGER, not the animation.)
  double _travel = 0;

  /// ~half a control row of committed travel before the chrome reacts.
  static const double _toggleThreshold = 24;

  void _setAway(bool away) {
    if (_away != away && mounted) setState(() => _away = away);
  }

  bool _onScroll(ScrollNotification notification) {
    if (widget.behavior == AppBoxKitFloatingBarBehavior.pinned) return false;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) {
      // At (or overscrolled past) the top the chrome always restores — a
      // minimized bar over top-of-content reads as missing, not tucked.
      if (metrics.pixels <= 0) {
        _travel = 0;
        _setAway(false);
        return false;
      }
      // Bottom rubber-band: the bounce-back is not the user asking for
      // chrome — don't accumulate while overscrolled.
      if (metrics.pixels >= metrics.maxScrollExtent) return false;
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      // Reversal resets the accumulator: travel must be committed.
      if (delta.sign != _travel.sign) _travel = 0;
      _travel += delta;
      if (_travel > _toggleThreshold) _setAway(true);
      if (_travel < -_toggleThreshold) _setAway(false);
    } else if (notification is ScrollEndNotification) {
      _travel = 0;
      if (metrics.pixels <= 0) _setAway(false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final hide = widget.behavior == AppBoxKitFloatingBarBehavior.hide;
    Widget bar = AppBoxKitNativeFloatingBar(
      leading: widget.leading,
      title: widget.title,
      actions: widget.actions,
      tuck: !_away
          ? AppBoxKitFloatingBarTuck.none
          : switch (widget.behavior) {
              AppBoxKitFloatingBarBehavior.minimize =>
                AppBoxKitFloatingBarTuck.both,
              AppBoxKitFloatingBarBehavior.minimizeTrailing =>
                AppBoxKitFloatingBarTuck.trailing,
              AppBoxKitFloatingBarBehavior.minimizeLeading =>
                AppBoxKitFloatingBarTuck.leading,
              _ => AppBoxKitFloatingBarTuck.none,
            },
    );
    if (hide) {
      bar = AnimatedSlide(
        // -1.5× own height clears the status-bar inset the SafeArea adds.
        offset: _away ? const Offset(0, -1.5) : Offset.zero,
        duration: kAppBoxKitFloatingBarMotionDuration,
        curve: kAppBoxKitFloatingBarMotionCurve,
        child: IgnorePointer(ignoring: _away, child: bar),
      );
    }
    // Route-transform containment (device clip: tucked chrome flashing mid
    // back-swipe). The minimize tuck parks the leading + pill off the leading
    // screen edge and the actions off the trailing edge with a TRANSFORM —
    // they stay mounted and painted (clip 13-53-b), merely translated
    // off-screen. A Cupertino back-swipe translates the whole outgoing route
    // right by up to a full screen width, and that transform is an ancestor
    // of this bar, so the parked leading end rides it straight back into the
    // visible frame — exactly once per swipe, then gone (the forward push
    // mirrors it at the trailing edge). Untucked chrome rides the same
    // transform at its normal position, which is why the defect only ever
    // showed while tucked. This hard ClipRect pins PAINT to the bar slot's
    // LEFT/RIGHT edges — which ride the same route transform — so tucked
    // ends are culled at the route edge no matter where the route is. When
    // the route is stationary the slot edge IS the screen edge, so nothing
    // about the ratified minimize motion changes.
    //
    // HORIZONTAL ONLY, on pain of slicing the pill's shadow: the title
    // pill's BoxShadow (blurRadius 16, offset (0, 4)) feathers ~20px below
    // the pill, but the slot reserves only abxGap8 of slack beneath it — a
    // full-rect clip hard-cuts that feather mid-fade (the luminance/shadow
    // regression, device-verified). The clip's job is the horizontal axis —
    // the tucks slide horizontally and the back-swipe carries them back in
    // horizontally; vertically the slot is bounded by the physical screen
    // edge exactly as it was before containment existed, so the clipper
    // leaves y open.
    //
    // Placement is deliberate:
    // - Around the bar ONLY, never the Stack: the body and the
    //   AppBoxKitTopEdgeScrim are siblings below, structurally unreachable
    //   by this clip.
    // - AROUND the AnimatedSlide tuck machinery, never replacing it: law
    //   rule 8 — clip bounds paint, but the view slicer reads UNCLIPPED
    //   rects, so only the transforms bound slicing geometry. Same pairing
    //   as the hidden-tab stack's clip + transform.
    // Why a clip and not the alternatives: composition rule 1 bans
    // alpha/saveLayer shapes over platform views; a hard-edge ClipRect adds
    // no saveLayer, and kClipRect is an embedder-applied mutator on iOS
    // platform views (FlutterPlatformViewsController.mm, ApplyMutators — the
    // same SDK verification AppBoxKitNativeChromeGate cites), so the native
    // glass leading/actions are clipped by the native side, not just the
    // canvas. A bigger tuck multiplier would keep the ends off-screen
    // through a full-width swipe but quadruples the slide distance inside
    // the device-tuned 400ms — visibly faster than the system minimize.
    // Always mounted, never conditional (the C4 tree-shape lesson): a bar
    // that never tucks still wraps, so the subtree shape is constant.
    // (NATIVE_COMPONENTS.md carries the clip-over-platform-view reliability
    // caveat — mostly reliable on Flutter 3.41+, residuals
    // flutter#176473/#188971.)
    bar = ClipRect(
      clipBehavior: Clip.hardEdge,
      clipper: const _AppBoxKitHorizontalContainmentClipper(),
      child: bar,
    );
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(
                  top: media.padding.top + kAppBoxKitFloatingBarBlockHeight,
                ),
              ),
              child: widget.body,
            ),
          ),
          // Between body and bar, and deliberately OUTSIDE the `hide`
          // AnimatedSlide above: keeping the status bar legible is the
          // scrim's whole job, so it must survive the bar tucking or hiding.
          const Positioned(
              top: 0, left: 0, right: 0, child: AppBoxKitTopEdgeScrim()),
          Positioned(top: 0, left: 0, right: 0, child: bar),
        ],
      ),
    );
  }
}

/// The containment clip's shape: the bar slot's left/right edges, vertically
/// open. Horizontal because the tucks and the route transforms that expose
/// them are horizontal; vertically open because the pill's BoxShadow (and any
/// chrome elevation) legitimately feathers past the slot's top/bottom — the
/// physical screen edge owns vertical culling, as it did before containment
/// existed. A widget-rect clip here hard-cut the shadow's 20px feather at
/// the slot's 8px bottom slack (the luminance/shadow regression).
class _AppBoxKitHorizontalContainmentClipper extends CustomClipper<Rect> {
  const _AppBoxKitHorizontalContainmentClipper();

  // Finite slack, not double.infinity: the canvas clip would tolerate it,
  // but the iOS platform-view path frames a FlutterClippingMaskView with
  // this rect when a native view straddles the edge mid-tuck — an infinite
  // frame is not a legal UIView frame. 10000 mirrors the tab stack's
  // off-screen idiom: far past any shadow feather, never reachable by paint
  // that matters.
  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -10000, size.width, size.height + 10000);

  @override
  bool shouldReclip(_AppBoxKitHorizontalContainmentClipper oldClipper) => false;
}
