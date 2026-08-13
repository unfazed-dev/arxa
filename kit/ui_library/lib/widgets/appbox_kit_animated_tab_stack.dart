import 'package:flutter/widgets.dart';

import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';

/// A kept-alive tab stack with a PAIRED tab-switch transition: on an index
/// change the outgoing tab's LIVE element slides out (toward the edge opposite
/// the incoming tab's origin) while the incoming tab slides in — one
/// controller run, then idle frames render exactly the active tab.
///
/// **Why this exists (router-safe exit animation):** a wrapper around an
/// already-swapped tabs stack ([AppBoxKitTabSwitchTransition]) can only animate the
/// INCOMING tab — the outgoing one vanishes with the index swap. Keeping the
/// outgoing tab on stage for one more run requires owning the stack: this
/// widget inflates the tabs itself and, on a switch, REPARENTS the outgoing
/// child's live element into an exit slot via kit-owned per-slot [GlobalKey]s.
/// The element — nested router, ViewModels, scroll positions, form state and
/// all — MOVES once inside the same frame. Nothing is inflated twice (a ghost
/// copy of a `NestedRouter` body would win `_innerControllerOf` lookups and
/// show a fresh root page) and nothing is re-inflated afterwards: when the
/// exit completes, the element moves back into the kept-alive base layer.
///
/// **Kept-alive, lazy:** each child is built on first visit, then stays
/// mounted via `Offstage` (hidden, excluded from hit-testing and semantics,
/// state intact) — the pattern [AppBoxKitLazyIndexedStack] established. Unvisited
/// tabs cost nothing; visited tabs never reset, no matter the visit order.
///
/// **Router model (primary):** `StackedTabsRouter.builder` hands its per-tab
/// `children` (each hosting that tab's `NestedRouter`) straight to [children];
/// the index comes from `tabsRouter.activeIndex`:
///
/// ```dart
/// StackedTabsRouter.builder(
///   routes: MyShellView.tabs,
///   builder: (context, children, tabsRouter) => Scaffold(
///     body: AppBoxKitAnimatedTabStack(
///       activeIndex: tabsRouter.activeIndex,
///       children: children,
///     ),
///   ),
/// )
/// ```
///
/// **Flat model:** any fixed `tabViews` list works the same way —
/// `AppBoxKitAnimatedTabStack(activeIndex: viewModel.currentIndex, children: MyView.tabViews)`.
/// Note the kept-alive semantics are lazy (first visit builds the tab), where
/// a raw `IndexedStack` inflates every child up front.
///
/// **Direction helper:** the widget tracks the previous index — moving to a
/// HIGHER index slides the incoming tab in from the trailing edge (right in
/// LTR) while the outgoing leaves through the leading edge; moving to a LOWER
/// index mirrors it — so the pair always travels along the tab bar/rail.
/// Mirrored automatically under RTL (offsets resolve against [Directionality]).
///
/// **Element-tree stability:** the wrapper structure above the tab bodies
/// never changes with animation phase — the slide/fade wrappers and the exit
/// slot are always present (the slot holds a placeholder while idle), so the
/// transition itself never remounts a retained tab. The one structural swap
/// per switch is the exiting child's placeholder, which is exactly what frees
/// its [GlobalKey] for the exit slot.
///
/// **Platform-view caution:** prefer `fade: false` (the default) over tabs
/// that mount platform views (`AppBoxKitNative*` / UiKitView chrome). Opacity-
/// animating a platform-view subtree forces per-frame native layer mutations,
/// and the outgoing tab's UIViews linger frame-submit-gated (flutter#148639,
/// group-opacity exclusion flutter#24164) — the ghosting P2 verified on the
/// iOS 26 simulator. The slide is the smaller mutation surface; re-verify on
/// device when the tabs carry native chrome (review check 1c2).
///
/// **Instant on iOS (the default), and why:** `UITabBarController` cross-cuts
/// between tabs — it has never slid, faded or parallaxed (HIG "Tab bars") — so
/// [animated] resolves to false on iOS. That is not merely the native look, it
/// is the only shape that costs nothing. A run necessarily puts BOTH tabs on
/// stage at once, so the frame's platform-view set and z-order change
/// mid-switch, and the iOS embedder answers that by recomposing its overlays
/// and merging the raster and platform threads — the stall reported as
/// tab-switch flicker. Going instant also drops the exit slot outright, so the
/// outgoing tab's [GlobalKey] reparent never happens either. Two earlier
/// attempts (`20616f2` cover-parallax geometry, `6412916` opaque backing)
/// fixed artifacts OF the animation and left its cost in place; this removes
/// the cost on the tier that cannot afford it, and keeps the paired slide for
/// Material, where the tab bodies are Flutter-rendered and cost nothing to
/// have on stage together.
///
/// The cut also never changes the frame's platform-view SET: a visited tab
/// hides at ~1/255 alpha — the UIKit `isHidden` equivalent, the UIViews stay
/// in the window — rather than leaving the paint tree. Offstaging would
/// unpaint it, and an unpainted platform view leaves the native hierarchy:
/// every re-entry is an `addSubview`, which on iOS 26 is a glass materialize
/// against a not-yet-composited backdrop (the bright-card flash on tab
/// switches), and the detach/attach set change itself recomposes the
/// embedder's overlays (the tab-bar ghost). An earlier attempt instead
/// bracketed the cut as a manual `CNTransitionObserver` transition so every
/// chrome gate hid for two settle frames; on device that dematerialized the
/// whole screen's glass and left the outgoing tab's views lingering for
/// seconds — strictly worse than the flash. Alpha hides without touching the
/// native hierarchy at all.
class AppBoxKitAnimatedTabStack extends StatefulWidget {
  const AppBoxKitAnimatedTabStack({
    required this.activeIndex,
    required this.children,
    this.duration = const Duration(milliseconds: 220),
    this.slideFraction = 0.18,
    this.curve = Curves.easeOutCubic,
    this.fade = false,
    this.backgroundColor,
    this.animated,
    super.key,
  }) : assert(children.length > 0, 'need at least one tab');

  /// Current tab index. A change runs the paired exit+enter transition.
  final int activeIndex;

  /// The tab bodies, in tab order. Owned by this stack: each is inflated
  /// lazily on first visit and kept alive afterwards. The list may regenerate
  /// every build (fresh widget instances are fine — state binds to the slot,
  /// not the instance) and may grow or shrink (a live tab-list recomposition
  /// clamps the exit to what still exists).
  final List<Widget> children;

  /// Paired transition duration per switch.
  final Duration duration;

  /// Horizontal parallax travel of the UNDERLYING exiting tab, as a fraction
  /// of the stack's width. The incoming tab always enters full-width on top
  /// (cover geometry), so completion — which drops the exit slot — happens
  /// while the exiting tab is fully covered and is therefore invisible.
  /// Kept subtle by default so the under-layer reads as depth, not a fling.
  final double slideFraction;

  /// Easing applied to the slide (and fade when enabled).
  final Curve curve;

  /// Also cross-fade the pair. Default false: opacity-animating platform-view
  /// subtrees ghosts (see class docs; review check 1c2).
  final bool fade;

  /// Opaque backing painted behind the incoming layer while a switch is
  /// running, so background-less tab pages actually occlude the outgoing tab
  /// (otherwise the old tab reads through the new one — ghosting). Pass the
  /// host scaffold's background color. Null (default) keeps the run
  /// transparent — this widget is widgets-layer pure and cannot read a
  /// material Theme itself. Idle frames stay transparent regardless.
  final Color? backgroundColor;

  /// Whether an index change runs the paired transition at all.
  ///
  /// Null (default) resolves per platform: **instant on iOS**, animated
  /// everywhere else — see the class docs for why instant is both the native
  /// behaviour and the cheap one. Pass `true` to force the slide anyway (a
  /// non-native affordance on Apple: expect platform-view churn if the tabs
  /// carry `AppBoxKitNative*` chrome), or `false` to force instant everywhere.
  ///
  /// Instant is a real cross-cut, not a zero-duration animation: no controller
  /// run, no exit slot, no reparent — one frame, one tab on stage.
  final bool? animated;

  @override
  State<AppBoxKitAnimatedTabStack> createState() => _KitAnimatedTabStackState();
}

class _KitAnimatedTabStackState extends State<AppBoxKitAnimatedTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0, // no phantom motion before the first switch
  )..addStatusListener(_onStatus);

  /// Per-slot reparent keys, created once so a tab's live element can move
  /// between the base layer and the exit slot without losing state.
  final List<GlobalKey> _childKeys = [];

  /// Slots inflated at least once (lazy kept-alive).
  final Set<int> _initialized = {};

  int _currentIndex = 0;

  /// The tab mid-exit, or null while idle. Its live element sits in the exit
  /// slot; its base-layer slot holds a placeholder for the run.
  int? _exitingIndex;

  /// 0 until the first switch, then +1 (moved to a higher index) or -1.
  int _direction = 0;

  /// Whether a switch animates here. Platform-resolved unless pinned by the
  /// caller: iOS cross-cuts (see class docs), everything else slides.
  bool get _animates => widget.animated ?? !AppBoxKitPlatform.isIOS;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.activeIndex;
    _initialized.add(_currentIndex);
    _syncKeys();
  }

  void _syncKeys() {
    while (_childKeys.length < widget.children.length) {
      _childKeys.add(GlobalKey());
    }
  }

  @override
  void didUpdateWidget(AppBoxKitAnimatedTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.activeIndex != _currentIndex) {
      if (!_animates) {
        // Native cross-cut. Leaving `_exitingIndex` null keeps the exit slot
        // empty, so exactly ONE tab is on stage in every frame — the frame's
        // platform-view set never grows mid-switch (no overlay recomposition,
        // no raster/platform thread merge) and no element is ever reparented.
        // Clearing it explicitly also lands a switch cleanly if `animated`
        // flipped to false while a run was still in flight.
        setState(() {
          _exitingIndex = null;
          // A cross-cut has no direction. Clearing it keeps "instant ⇒ nothing
          // is translated anywhere" true, including the now-empty exit slot.
          _direction = 0;
          _currentIndex = widget.activeIndex;
          _initialized.add(_currentIndex);
        });
        // Park any in-flight run at the identity end-state (`stop()` is
        // implicit in the setter). `_onStatus` no-ops: `_exitingIndex` is null
        // already. Guarded because the setter notifies unconditionally, and in
        // the steady iOS path the controller is always already completed.
        if (!_controller.isCompleted) _controller.value = 1.0;
        return;
      }
      _direction = widget.activeIndex > _currentIndex ? 1 : -1;
      setState(() {
        // The leaving tab may have vanished with the same update (a live
        // tab-list recomposition shrank the children — e.g. a grant revoked
        // while sitting on its tab, the router clamping the index to
        // homeIndex) — then there is nothing to animate out; snap to the
        // clamped index.
        _exitingIndex =
            _currentIndex < widget.children.length ? _currentIndex : null;
        _currentIndex = widget.activeIndex;
        _initialized.add(_currentIndex);
      });
      _controller.forward(from: 0.0);
    } else if (_exitingIndex != null &&
        _exitingIndex! >= widget.children.length) {
      // The leaving tab vanished mid-exit without an index change — cut its
      // exit short.
      setState(() => _exitingIndex = null);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _exitingIndex != null) {
      // The exit finished: the element moves back into the kept-alive base
      // layer (offstage) — same-frame reparent, no re-inflation.
      setState(() => _exitingIndex = null);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    final travel = Offset(_direction * widget.slideFraction, 0);

    // Kept-alive base layer: every visited tab stays mounted behind the
    // active one. The exiting tab's slot is a hit-transparent placeholder for
    // the run — its live element sits in the exit slot below (the GlobalKey
    // move).
    final incoming = SlideTransition(
      // Positive dx enters from the trailing edge; providing the ambient
      // text direction flips it under RTL. Full-width entry: the incoming
      // layer paints ON TOP and must fully cover the exiting tab by the time
      // the animation completes, so dropping the exit slot is invisible
      // (regression 3b81414: a 0.18-travel opaque exit layer on top was
      // removed mid-cover, popping ~82% of the frame in one step).
      textDirection: textDirection,
      position: Tween<Offset>(begin: Offset(_direction * 1.0, 0), end: Offset.zero)
          .animate(curved),
      // Tab pages are routinely background-less (one host Scaffold paints the
      // shared surface), which makes the "cover" slide transparent: the old
      // tab stays readable through the new one for the whole run — perceived
      // as ghosting. While a run is live, back the incoming layer with the
      // ambient scaffold color so it actually occludes; idle keeps the color
      // transparent so tree shape (and GlobalKey slots) never changes and a
      // deliberately see-through stack still composites over custom app
      // backgrounds when not animating.
      child: ColoredBox(
        color: _exitingIndex == null
            ? const Color(0x00000000)
            : widget.backgroundColor ?? const Color(0x00000000),
        child: Stack(
          fit: StackFit.expand,
          children: [
          for (var i = 0; i < widget.children.length; i++)
            if (!_initialized.contains(i) || i == _exitingIndex)
              // Constant-length slot, never hit-testable: a bare expanded box
              // above the active tab would swallow its taps.
              const IgnorePointer(child: SizedBox.shrink())
            else if (_animates)
              Offstage(
                offstage: i != _currentIndex,
                child: KeyedSubtree(
                  key: _childKeys[i],
                  child: widget.children[i],
                ),
              )
            else
              // iOS cross-cut: a visited tab hides at ~1/255 alpha, NEVER by
              // leaving the paint tree. Offstaging unpaints it, and an
              // unpainted platform view leaves the native hierarchy — every
              // re-entry is an addSubview, which on iOS 26 is a glass
              // materialize against a not-yet-composited backdrop (the
              // bright-card flash), and the mid-switch platform-view-SET
              // change recomposes the embedder's overlays (the tab-bar
              // ghost). Alpha 0.0 hits RenderOpacity's zero shortcut and
              // unpaints too, so the floor is one engine alpha step; UIKit
              // ignores views below alpha 0.01 for hit-testing, and
              // IgnorePointer/ExcludeSemantics cover the Flutter side.
              // Alpha alone is NOT containment: the hidden tab still paints,
              // and its platform views slice the ACTIVE tab's frame into
              // overlay textures — on device (2026-08-12) pieces of hidden
              // subtrees composited over the active tab at visible alpha
              // (stale white rail-pane rectangle over Profile's Maps button,
              // "Maps showcase" ghost over Search's options section). The
              // sub-pixel ClipRect bounds everything a hidden tab can
              // contribute to the frame while the paint still happens, so the
              // platform views never leave the native hierarchy (the whole
              // point of hiding by alpha instead of Offstage). Clip.none on
              // the active tab = no layer, same driven-to-identity idiom as
              // the edge effect's blur.
              Opacity(
                opacity: i == _currentIndex ? 1.0 : 0.004,
                child: IgnorePointer(
                  ignoring: i != _currentIndex,
                  child: ExcludeSemantics(
                    excluding: i != _currentIndex,
                    // Both knobs must flip together: clipBehavior only gates
                    // PAINT clipping — RenderClipRect.hitTest consults the
                    // clipper even at Clip.none, so a sub-pixel clipper on the
                    // ACTIVE tab would swallow every tap in the app (caught by
                    // showcase M5: "All Notes" tap navigated nowhere).
                    child: ClipRect(
                      clipBehavior:
                          i == _currentIndex ? Clip.none : Clip.hardEdge,
                      clipper: i == _currentIndex
                          ? null
                          : const _HiddenTabClipper(),
                      child: KeyedSubtree(
                        key: _childKeys[i],
                        child: widget.children[i],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // Exit slot: the outgoing tab's live element sliding toward the edge
    // opposite the incoming tab's origin. ALWAYS present (holding a shrink
    // while idle) so the tree shape never changes with animation phase; dead
    // to pointer input so the leaving tab can't swallow the incoming tab's
    // taps mid-run.
    final exiting = IgnorePointer(
      child: SlideTransition(
        textDirection: textDirection,
        position:
            Tween<Offset>(begin: Offset.zero, end: -travel).animate(curved),
        child: _exitingIndex == null
            ? const SizedBox.shrink()
            : KeyedSubtree(
                key: _childKeys[_exitingIndex!],
                child: widget.children[_exitingIndex!],
              ),
      ),
    );

    // Paint order matters: exiting UNDER, incoming ON TOP. The incoming layer
    // travels the full width, so when completion drops the exit slot the
    // removal is already covered — no visible pop (see slideFraction docs).
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.fade)
          FadeTransition(opacity: ReverseAnimation(curved), child: exiting)
        else
          exiting,
        if (widget.fade)
          FadeTransition(opacity: curved, child: incoming)
        else
          incoming,
      ],
    );
  }
}

/// Clips a hidden tab's painting to a half-pixel window at the origin.
///
/// Half a pixel, not [Rect.zero]: the window must stay non-degenerate so the
/// subtree is still "painted" in every sense the engine checks — an empty
/// clip risks the platform views being culled out of the composition, which
/// is the removeFromSuperview → re-attach glass flash the alpha-hide exists
/// to prevent. Same idiom as hiding at 0.004 instead of 0.0 (RenderOpacity's
/// zero shortcut unpaints).
class _HiddenTabClipper extends CustomClipper<Rect> {
  const _HiddenTabClipper();

  @override
  Rect getClip(Size size) => const Rect.fromLTWH(0, 0, 0.5, 0.5);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
