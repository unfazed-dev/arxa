import 'package:flutter/widgets.dart';

/// Self-driving, direction-aware slide for kept-alive tab stacks
/// (`IndexedStack` + an index-tracking model), the sibling of
/// [ArxaKitDirectionalTabTransition] for setups WITHOUT a tabs-router animation —
/// e.g. stacked's `IndexTrackingViewModel` calling `setIndex` on a native tab
/// bar. It owns its [AnimationController]: when [activeIndex] changes, the
/// incoming tab replays a 0→1 entrance.
///
/// **Superseded by [ArxaKitAnimatedTabStack] for kept-alive tab stacks.** This
/// widget receives the ALREADY-SWAPPED stack, so it animates only the incoming
/// tab — the outgoing one vanishes with the index swap. [ArxaKitAnimatedTabStack]
/// owns the stack instead and reparents the outgoing tab's live element into
/// an exit slot: a paired exit+enter transition, router-safe, state-preserving.
/// What remains legitimate here: wrapping a stack widget you do NOT own (the
/// entrance-only fallback).
///
/// **Direction helper:** the widget tracks the previous index — moving to a
/// HIGHER index slides the incoming stack in from the trailing edge (right in
/// LTR), moving to a LOWER index slides it in from the leading edge — so the
/// motion always matches the direction of travel along the tab bar/rail.
/// Mirrored automatically under RTL (the offset resolves against
/// [Directionality]).
///
/// **Platform-view caution:** prefer `fade: false` (the default) over tabs
/// that mount platform views (`ArxaKitNative*` / UiKitView chrome). Opacity-animating
/// a platform-view subtree forces per-frame native layer mutations, and the
/// outgoing tab's UIViews linger frame-submit-gated (flutter#148639) — the
/// ghosting P2 verified on the iOS 26 simulator. The slide is the smaller
/// mutation surface; re-verify on device when the tabs carry native chrome.
///
/// ```dart
/// ArxaKitTabSwitchTransition(
///   activeIndex: viewModel.currentIndex, // IndexTrackingViewModel
///   child: IndexedStack(index: viewModel.currentIndex, children: tabs),
/// )
/// ```
class ArxaKitTabSwitchTransition extends StatefulWidget {
  const ArxaKitTabSwitchTransition({
    required this.activeIndex,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.slideFraction = 0.18,
    this.curve = Curves.easeOutCubic,
    this.fade = false,
    super.key,
  });

  /// Current tab index. A change restarts the entrance animation.
  final int activeIndex;

  /// Entrance duration per switch.
  final Duration duration;

  /// Horizontal travel of the incoming stack, as a fraction of its width.
  /// Kept subtle by default so full-chrome tab scaffolds don't "fling".
  final double slideFraction;

  /// Easing applied to the slide (and fade when enabled).
  final Curve curve;

  /// Also cross-fade the incoming stack in. Default false: opacity-animating
  /// platform-view subtrees ghosts (see class docs).
  final bool fade;

  /// The kept-alive tabs stack (typically an `IndexedStack`).
  final Widget child;

  @override
  State<ArxaKitTabSwitchTransition> createState() =>
      _KitTabSwitchTransitionState();
}

class _KitTabSwitchTransitionState extends State<ArxaKitTabSwitchTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0, // no phantom motion before the first switch
  );

  /// 0 until the first switch, then +1 (moved to a higher index) or -1.
  int _direction = 0;

  @override
  void didUpdateWidget(ArxaKitTabSwitchTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndex != oldWidget.activeIndex) {
      _direction = widget.activeIndex > oldWidget.activeIndex ? 1 : -1;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ALWAYS wrap the child in the same structure — even before the first
    // switch (controller parked at 1.0, so full opacity / zero offset). The
    // child is an IndexedStack that retains tabs; inserting wrappers only on
    // the first switch would move the stack in the element tree and reset
    // every retained tab (scroll, forms, viewmodels).
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    final slide = SlideTransition(
      // Positive dx enters from the trailing edge; providing the ambient
      // text direction flips it under RTL.
      textDirection: Directionality.of(context),
      position: Tween<Offset>(
        begin: Offset(_direction * widget.slideFraction, 0),
        end: Offset.zero,
      ).animate(curved),
      child: widget.child,
    );
    if (!widget.fade) return slide;
    return FadeTransition(opacity: curved, child: slide);
  }
}
