import 'package:flutter/widgets.dart';

/// A kept-alive tab stack with a PAIRED tab-switch transition: on an index
/// change the outgoing tab's LIVE element slides out (toward the edge opposite
/// the incoming tab's origin) while the incoming tab slides in — one
/// controller run, then idle frames render exactly the active tab.
///
/// **Why this exists (router-safe exit animation):** a wrapper around an
/// already-swapped tabs stack ([KitTabSwitchTransition]) can only animate the
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
/// state intact) — the pattern [KitLazyIndexedStack] established. Unvisited
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
///     body: KitAnimatedTabStack(
///       activeIndex: tabsRouter.activeIndex,
///       children: children,
///     ),
///   ),
/// )
/// ```
///
/// **Flat model:** any fixed `tabViews` list works the same way —
/// `KitAnimatedTabStack(activeIndex: viewModel.currentIndex, children: MyView.tabViews)`.
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
/// that mount platform views (`KitNative*` / UiKitView chrome). Opacity-
/// animating a platform-view subtree forces per-frame native layer mutations,
/// and the outgoing tab's UIViews linger frame-submit-gated (flutter#148639,
/// group-opacity exclusion flutter#24164) — the ghosting P2 verified on the
/// iOS 26 simulator. The slide is the smaller mutation surface; re-verify on
/// device when the tabs carry native chrome (review check 1c2).
class KitAnimatedTabStack extends StatefulWidget {
  const KitAnimatedTabStack({
    required this.activeIndex,
    required this.children,
    this.duration = const Duration(milliseconds: 220),
    this.slideFraction = 0.18,
    this.curve = Curves.easeOutCubic,
    this.fade = false,
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

  /// Horizontal travel of BOTH tabs, as a fraction of the stack's width.
  /// Kept subtle by default so full-chrome tab scaffolds don't "fling".
  final double slideFraction;

  /// Easing applied to the slide (and fade when enabled).
  final Curve curve;

  /// Also cross-fade the pair. Default false: opacity-animating platform-view
  /// subtrees ghosts (see class docs; review check 1c2).
  final bool fade;

  @override
  State<KitAnimatedTabStack> createState() => _KitAnimatedTabStackState();
}

class _KitAnimatedTabStackState extends State<KitAnimatedTabStack>
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
  void didUpdateWidget(KitAnimatedTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.activeIndex != _currentIndex) {
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
      // text direction flips it under RTL.
      textDirection: textDirection,
      position: Tween<Offset>(begin: travel, end: Offset.zero).animate(curved),
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            if (!_initialized.contains(i) || i == _exitingIndex)
              // Constant-length slot, never hit-testable: a bare expanded box
              // above the active tab would swallow its taps.
              const IgnorePointer(child: SizedBox.shrink())
            else
              Offstage(
                offstage: i != _currentIndex,
                child: KeyedSubtree(
                  key: _childKeys[i],
                  child: widget.children[i],
                ),
              ),
        ],
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

    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.fade)
          FadeTransition(opacity: curved, child: incoming)
        else
          incoming,
        if (widget.fade)
          FadeTransition(opacity: ReverseAnimation(curved), child: exiting)
        else
          exiting,
      ],
    );
  }
}
