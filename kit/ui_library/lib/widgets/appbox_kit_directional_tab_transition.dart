import 'package:flutter/widgets.dart';

/// Direction-aware slide+fade for `StackedTabsRouter` tab switches.
///
/// **Do NOT wrap tab stacks that mount platform views (any `AppBoxKitNative*` /
/// UiKitView chrome).** Fade/slide-animating a platform-view subtree forces
/// per-frame native layer mutations for the whole animation, and the outgoing
/// tab's UIViews linger frame-submit-gated (flutter#148639) — the two tabs'
/// native chrome composites over each other mid-switch (ghosted icons, merged
/// titles). Flutter's platform-view docs advise against animating live
/// platform views at all. P2's application shell hit exactly this on the iOS
/// 26 simulator and switched to an instant swap (the native bar's own
/// selection-pill morph keeps the motion cue). Reserve this widget for
/// pure-Flutter tab bodies.
///
/// Wrap the `child` handed to the tabs-router `builder` and forward the same
/// `animation` (stacked restarts it 0→1 on every switch). The widget tracks
/// the previous tab index: moving to a HIGHER index slides the incoming stack
/// in from the trailing edge (right in LTR), moving to a LOWER index slides
/// in from the leading edge — so the motion always matches the direction of
/// travel along the tab bar. Mirrored automatically under RTL because the
/// offset is resolved against [Directionality].
///
/// ```dart
/// StackedTabsRouter(
///   routes: MyShellView.tabs,
///   builder: (context, child, animation) => Scaffold(
///     body: AppBoxKitDirectionalTabTransition(
///       activeIndex: context.tabsRouter.activeIndex,
///       animation: animation,
///       child: child,
///     ),
///   ),
/// )
/// ```
class AppBoxKitDirectionalTabTransition extends StatefulWidget {
  const AppBoxKitDirectionalTabTransition({
    required this.activeIndex,
    required this.animation,
    required this.child,
    this.slideFraction = 0.18,
    this.curve = Curves.easeOutCubic,
    super.key,
  });

  /// Current tab index (`tabsRouter.activeIndex`).
  final int activeIndex;

  /// Switch animation from the tabs-router builder; runs 0→1 per switch.
  final Animation<double> animation;

  /// Horizontal travel of the incoming stack, as a fraction of its width.
  /// Kept subtle by default so full-chrome tab scaffolds don't "fling".
  final double slideFraction;

  /// Easing applied to the slide (the fade uses the raw animation so the
  /// outgoing frame never lingers translucent over chrome).
  final Curve curve;

  /// The `child` provided by the tabs-router builder (the tabs stack).
  final Widget child;

  /// The tab-switch timeline for descendants of the tabs stack, or null
  /// before the first switch (at startup the animation has never run, so
  /// callers should fall back to their route animation — the default of
  /// [AppBoxKitMotionScope]).
  ///
  /// Pass this as a `AppBoxKitMotionScope.driver` inside a tab body to replay its
  /// wake choreography on every tab switch:
  ///
  /// ```dart
  /// AppBoxKitMotionScope(
  ///   driver: AppBoxKitDirectionalTabTransition.timelineOf(context),
  ///   child: ...,
  /// )
  /// ```
  static Animation<double>? timelineOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_KitTabTimeline>()?.timeline;

  @override
  State<AppBoxKitDirectionalTabTransition> createState() =>
      _KitDirectionalTabTransitionState();
}

/// Publishes the tab-switch animation to the tabs-stack subtree. Always
/// present (with a null timeline before the first switch) so flipping it on
/// never restructures the tree above the tab bodies.
class _KitTabTimeline extends InheritedWidget {
  const _KitTabTimeline({required this.timeline, required super.child});

  final Animation<double>? timeline;

  @override
  bool updateShouldNotify(_KitTabTimeline oldWidget) =>
      timeline != oldWidget.timeline;
}

class _KitDirectionalTabTransitionState
    extends State<AppBoxKitDirectionalTabTransition> {
  /// 0 until the first switch, then +1 (moved to a higher index) or -1.
  int _direction = 0;

  @override
  void didUpdateWidget(AppBoxKitDirectionalTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndex != oldWidget.activeIndex) {
      _direction = widget.activeIndex > oldWidget.activeIndex ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ALWAYS wrap the child in the same Fade+Slide structure — even before the
    // first switch. The child is an IndexedStack that retains visited tabs;
    // inserting these wrappers only on the first switch would move the stack to
    // a different position in the element tree, so Flutter would rebuild it and
    // reset EVERY retained tab (scroll, forms, viewmodels) on the first switch.
    // Keeping the structure stable preserves the stack's element across switches.
    //
    // Before the first switch we drive the wrappers with an always-complete
    // animation: opacity is full and _direction == 0 makes the slide offset
    // zero, so there is no phantom motion at startup. The timeline is still
    // published as null so motion scopes fall back to their route animation.
    final beforeFirstSwitch = _direction == 0;
    final animation =
        beforeFirstSwitch ? kAlwaysCompleteAnimation : widget.animation;
    return _KitTabTimeline(
      timeline: beforeFirstSwitch ? null : widget.animation,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          // Positive dx enters from the trailing edge; providing the ambient
          // text direction flips it under RTL.
          textDirection: Directionality.of(context),
          position: Tween<Offset>(
            begin: Offset(_direction * widget.slideFraction, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: widget.curve),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
