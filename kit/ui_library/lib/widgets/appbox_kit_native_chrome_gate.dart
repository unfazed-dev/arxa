import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:cupertino_native_better/cupertino_native.dart'
    show CNTransitionObserver;
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;

/// How [AppBoxKitNativeChromeGate] takes the child's pixels off screen.
enum AppBoxKitChromeHideMode {
  /// Paint-level hide (default): the child stays mounted and simply stops
  /// being *painted*, via an [IndexedStack] whose index selects an empty
  /// placeholder instead of the child.
  ///
  /// `RenderIndexedStack` overrides `paintStack`, `hitTestChildren` and
  /// `visitChildrenForSemantics`, but **not** `performLayout` or
  /// `computeDryLayout` — so it inherits `RenderStack`'s layout, which sizes
  /// itself from *every* child (`rendering/stack.dart:768`). That single fact
  /// buys all four properties this gate needs:
  ///
  /// 1. The platform view is absent from the frame's layer tree, so the
  ///    embedder takes it out of the native hierarchy and it cannot bleed
  ///    through an overlay.
  /// 2. Its Element stays MOUNTED — no native re-init, no raster/platform
  ///    thread-merge stall on restore.
  /// 3. Its footprint is unchanged, because it is still laid out; the empty
  ///    placeholder cannot collapse the box.
  /// 4. Nothing is animated, which is the point — see the class doc.
  ///
  /// Hit-testing and semantics are handled by `IndexedStack` itself (it only
  /// visits the displayed child), so no `IgnorePointer` is needed.
  keepAlive,

  /// Unmount the subtree while hidden (destroys the platform view; a
  /// measured same-size placeholder holds the layout). Costs a full native
  /// re-init + thread merge on every restore, which visibly hitches.
  ///
  /// Not merely a theoretical escape hatch: the vendored package found that
  /// for a *modal* specifically, mounted-but-unpainted is not enough — the
  /// iOS `UITabBar` layer kept rendering above Flutter-drawn modal content
  /// (a `TextField` vanished, the bar bled during sheet drags), and only
  /// destroying the view fixed it (`vendor/cupertino_native_better/lib/
  /// components/tab_bar.dart:521-526`, its Issue #31). That finding is
  /// specific to the native tab bar; the kit's other glass surfaces have not
  /// reproduced it, so [keepAlive] stays the default and this is the lever to
  /// pull if one of them does.
  unmount,
}

/// Hides [child] — typically a subtree containing a native platform view —
/// while ANY full-screen Flutter overlay is up, then fades it back in.
///
/// **Why.** On iOS, `UiKitView`s composite in a native layer *above* the
/// Flutter scene, so a Flutter `BackdropFilter` (snackbar `overlayBlur`,
/// dialog scrim…) can neither blur nor cover them — they bleed through,
/// sharp (cupertino_native_better Issue #53). The CN package fixes its own
/// widgets via `ModalHideMixin`, but `CNIcon`, `search_scaffold`, the raw
/// (non-search) `CNTabBar`, and any third-party platform view (maps,
/// webview, video) have no such guard. This gate is the kit-side guard for
/// all of them: wrap the widget, done.
///
/// **Signal.** Two, OR'd:
/// - `CNTabBarRouteObserver.anyModalDepth` — the broad counter bumped by
///   sheet/dialog routes AND by `appBoxKitWithNativeChromeHidden` (a snackbar's full
///   on-screen lifetime).
/// - `CNTransitionObserver.hasActiveTransitionAbove(context)` — true during a
///   route slide (push/pop/replace/remove or the interactive back-swipe) in a
///   navigator that ENCLOSES this gate. A platform view neither clips nor
///   translates with the routes mid-transition, so it must leave the frame —
///   otherwise it floats over the slide (glass, or a flat panel if merely
///   de-tinted; hiding is the only thing that actually works). This makes the
///   gate the kit-wide "autoHideOnPageTransition (alpha-0)" for every Liquid
///   Glass surface it wraps, the same protection `CNTabBar` has.
///   *Scoped on purpose*: the raw `activeTransitions` counter is global across
///   every observer, so a push inside one tab's nested router used to hide the
///   ROOT tab bar in all tabs (C2, `docs/plans/glass-chrome-root-cause-fixes.md`).
///   The global notifier is still the listen target — it ticks on every begin
///   and end anywhere, which is exactly the "re-evaluate now" signal.
///
/// **Behavior.**
/// - *Mount-depth snapshot* (mirrors the package's `ModalHideMixin`): the
///   depth at mount is the baseline; the gate hides only when live depth
///   grows PAST it — a gate used *inside* a sheet never self-destroys.
/// - *No layout shift, ever*: in [AppBoxKitChromeHideMode.keepAlive] the child
///   never stops laying out (`RenderIndexedStack` inherits `RenderStack`'s
///   all-children layout), so its footprint is simply still there; in
///   [AppBoxKitChromeHideMode.unmount] a measured same-size placeholder stands in.
///
/// **The swap is INSTANT, on both edges — and that is the whole point.**
/// This gate used to dematerialize: fade + slight scale-out on hide, fade +
/// scale back in on restore. That is wrong for a platform view, and four
/// independent sources say so:
///
/// 1. **Apple.** WWDC25 #284, verbatim: *"Always prefer setting the effect
///    property over the **alpha** to ensure that the glass dematerializes or
///    materializes with the appropriate animation."* And #219: *"Instead of
///    **fading**, Liquid Glass objects materialize in and out by gradually
///    modulating the light bending and lensing."* We cannot reach `effect`
///    from Dart, and a Flutter alpha ramp is precisely the thing Apple names
///    as the wrong substitute. The old code cited `effect = nil` as its
///    sanction, but that API's documented purpose is *overlap avoidance*
///    (Maps hiding buttons when a sheet expands), not transition sequencing.
/// 2. **This repo, simulator-verified.** `docs/research/flutter-platform-view-best-practices.md`
///    §3.2 **[R]**: *"animating opacity across a platform-view subtree is the
///    expensive mistake"*, and recommendation 3: *"Do not opacity-animate any
///    subtree containing a platform view… Fade forces per-frame native layer
///    mutations and leaves ghosting UIViews."*
/// 3. ~~**Flutter, open bugs.**~~ **RETRACTED — this pillar was mis-cited, and
///    it does not hold on iOS.** flutter#93757 is titled *"[android]
///    FadeTransitions do not work with platform views using hybrid
///    composition"* and carries `platform-android`/`team-android` labels: it is
///    Android-specific and cannot support an iOS claim. And opacity is *not*
///    unsupported on iOS — the embedder applies the `kOpacity` mutator
///    directly (`embeddedView.alpha = GetAlphaFloat() * embeddedView.alpha`,
///    landed in flutter/engine PR #9667, 2019). flutter#24164 did not resolve
///    to a matching issue and should be treated as unverified until someone
///    checks it.
///
///    **This removes one of four pillars, not the conclusion.** Points 1, 2 and
///    4 stand on their own: Apple's explicit prefer-`effect`-over-`alpha`
///    guidance, this repo's simulator-verified ghosting observation, and the
///    vendored package's own no-animation implementation. Keep the instant
///    swap. The materialize this gate exists to avoid is caused by the view
///    LEAVING THE FRAME (engine `removeFromSuperview`/`addSubview`), not by
///    fading — which is why de-tinting could never have fixed it either.
/// 4. **The vendored package.** Its own `autoHideOnPageTransition` uses this
///    exact `IndexedStack` toggle with an explicit "no recreate animation"
///    rationale, and `ModalHideMixin` restores with a plain `setState` — no
///    controller, no duration anywhere in the file.
///
/// So there is no `showDuration` / `hideDuration`. They were removed rather
/// than defaulted to zero: silently ignoring a caller's `showDuration: 300`
/// is worse than not offering it. `hideDuration: Duration.zero` also existed
/// to stop a fade bleeding through a *blur* scrim — going instant satisfies
/// that constraint automatically, so the parameter's reason to exist is gone
/// too, not merely its value.
///
/// - Hit-testing and semantics need no [IgnorePointer]: `RenderIndexedStack`
///   overrides `hitTestChildren` and `visitChildrenForSemantics` to visit only
///   the displayed child.
///
/// **Second ceiling — resolved, and it was a false alarm.** This used to warn
/// that a gate which is a *sibling* of the transitioning router rather than a
/// descendant of its routes — `bottomNavigationBar` on a Scaffold whose `body`
/// holds the Navigator, exactly where the showcase's tab bar sits — would read
/// a **root-level page push over the tab scaffold** as "travelling", stay
/// painted, and bleed through the incoming page. It was recorded as untestable
/// because every showcase push is nested (`context.router.pushNamed` inside a
/// tab's own router), so the configuration never occurs there.
///
/// Untestable *in the showcase* is not untestable in general: the shape is
/// constructible directly, and
/// `appbox_kit_chrome_gate_transition_scope_test.dart` now builds it. The bar
/// **hides**, correctly. The reason is the same push/pop asymmetry the
/// predicate is built on: on a push, no route above this gate exists yet when
/// it evaluates, so `secondaryAnimation` is still the unwired
/// `kAlwaysDismissedAnimation` and reads *dismissed* — not travelling. The
/// sibling-vs-descendant distinction the old note wanted is therefore not
/// needed for pushes. (Still not device-verified — no such configuration
/// exists to run — but no longer unexamined.)
///
/// **Ceiling (named on purpose):** all-or-nothing. The package's
/// `ModalHideMixin` can consult `topModalRect` to keep widgets a partial
/// sheet doesn't cover; this gate ignores that and hides regardless. For
/// snackbar blurs (rect null) the behavior is identical. A true crossfade of
/// native content is out of reach *from Dart* — `RepaintBoundary.toImage`
/// cannot capture a platform view, so there is nothing to fade *from*. (Not
/// impossible in absolute terms: UIKit's own
/// `UIView.snapshotView(afterScreenUpdates:)` could supply one, but that is a
/// plugin-level change on the native side, not something this widget can do.)
///
/// **Known interaction — flutter#148639, OPEN.** iOS defers deleting platform
/// views until a frame is submitted that *contains* a platform-view layer:
/// with none painted, `HasPlatformViewThisOrNextFrame` is false, the raster
/// thread merger never engages, `SubmitFrame` is not called, and disposed
/// views sit in `views_to_dispose_`. While this gate hides, it manufactures
/// exactly that condition — and a route being popped is disposing its own
/// platform views at the same moment. The accumulation is bounded here (the
/// next restore paints a platform view and drains the queue) rather than the
/// unbounded leak in the issue's repro, which churns views inside a
/// permanently hidden branch. Worth knowing: it is a reason to keep the
/// all-hidden window SHORT, not a reason to prefer a different hide
/// mechanism — `Opacity(0)`, `Offstage(true)` and a non-selected
/// `IndexedStack` index are identical on this axis (all lay out, none paint).
///
/// No-op in practice on tiers that mount no platform views (Android
/// composites in-layer; Flutter-fallback tiers are ordinary widgets) — the
/// gate still functions, it just guards nothing that needed guarding.
class AppBoxKitNativeChromeGate extends StatefulWidget {
  const AppBoxKitNativeChromeGate({
    super.key,
    required this.child,
    this.hideMode = AppBoxKitChromeHideMode.keepAlive,
  });

  final Widget child;

  final AppBoxKitChromeHideMode hideMode;

  @override
  State<AppBoxKitNativeChromeGate> createState() => _KitNativeChromeGateState();
}

class _KitNativeChromeGateState extends State<AppBoxKitNativeChromeGate> {
  /// Depth at mount — the baseline. Hide only when depth exceeds it, so a
  /// gate mounted inside an already-open modal stays visible.
  late final int _mountDepth;

  bool _hidden = false;

  /// Child's last laid-out size — the unmount-mode placeholder's footprint.
  /// Written from layout (plain field, no setState: it is only *read* on
  /// the rebuild that hides, by which point the latest layout stamped it).
  Size? _lastSize;

  /// This gate's OWN route, captured once per dependency change rather than
  /// looked up inside the visibility callback (which can run from a post-frame
  /// callback, where registering an inherited-widget dependency is not valid).
  /// Null when the gate is not under a [ModalRoute] at all — a bare
  /// `runApp(...)` tree, or a test harness — in which case it can never be
  /// travelling with a route transition, so the gate falls back to hiding.
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    _mountDepth = CNTabBarRouteObserver.anyModalDepth.value;
    CNTabBarRouteObserver.anyModalDepth.addListener(_onDepthChanged);
    // The sheet's live rect moves every frame while it slides, and each move
    // can change whether it covers this gate — so it is a decision input, not
    // just a one-shot at open. See [_modalCoversMe].
    CNTabBarRouteObserver.topModalRect.addListener(_onDepthChanged);
    CNTransitionObserver.activeTransitions.addListener(_onDepthChanged);
  }

  @override
  void dispose() {
    CNTabBarRouteObserver.anyModalDepth.removeListener(_onDepthChanged);
    CNTabBarRouteObserver.topModalRect.removeListener(_onDepthChanged);
    CNTransitionObserver.activeTransitions.removeListener(_onDepthChanged);
    super.dispose();
  }

  /// Whether a modal newer than this gate's host route actually COVERS it.
  ///
  /// Not merely "is a modal up". A bottom sheet occupies the lower part of the
  /// screen; blanking the native chrome still plainly visible above it is the
  /// all-or-nothing ceiling this gate used to have, and it is exactly what
  /// `CNBottomSheet`'s geometry probe exists to prevent — its own comment:
  /// *"measuring the route would tear down native chrome sitting in the clear
  /// space above a short sheet."* The kit published that rect and then ignored
  /// it here, so every glass surface behind a sheet dematerialized and
  /// materialized back on dismiss.
  ///
  /// Same predicate the vendor's `ModalHideMixin._computeShouldHide` applies
  /// (`vendor/…/utils/modal_hide_mixin.dart:97-113`) — deliberately identical,
  /// so the two authorities cannot disagree about the same sheet.
  ///
  /// Fails toward HIDING on every uncertainty: no rect published (a plain
  /// `showModalBottomSheet`, or any sheet without the probe) and no measurable
  /// box both return true. That keeps the original bleed fix intact for every
  /// presentation that cannot describe its own geometry.
  bool _modalCoversMe() {
    if (CNTabBarRouteObserver.anyModalDepth.value <= _mountDepth) return false;
    final Rect? modalRect = CNTabBarRouteObserver.topModalRect.value;
    if (modalRect == null) return true;
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return true;
    return (box.localToGlobal(Offset.zero) & box.size).overlaps(modalRect);
  }

  void _onDepthChanged() {
    // The transition/modal notifiers can fire mid-build: the Navigator flushes
    // its route observers during its own build/restore, so a `didPush` →
    // `activeTransitions` bump lands INSIDE the build phase, where a synchronous
    // setState throws "setState() called during build". Defer to end-of-frame in
    // that case (a one-frame-late hide at a transition's very start is
    // imperceptible next to the assertion/leak it avoids).
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _applyVisibility());
    } else {
      _applyVisibility();
    }
  }

  void _applyVisibility() {
    if (!mounted) return;
    // Hide while a modal overlay covers the view (depth past the mount
    // baseline) OR while a route transition is animating — push/pop/replace or
    // the interactive back-swipe (CNTransitionObserver.activeTransitions). A
    // native platform view composites ABOVE the Flutter scene and neither
    // clips nor slides with the routes, so it must leave the frame for the
    // transition, not merely drop its glass tint (which leaves a flat panel
    // floating over the slide — the leak this gate now also closes).
    // SCOPED, not global: only a transition in a navigator that ENCLOSES this
    // gate actually carries the gate along. A push inside one tab's nested
    // router must not dematerialize the ROOT tab bar across every tab — that
    // was C2 of docs/plans/glass-chrome-root-cause-fixes.md, and it is the
    // same baseline-scoping idea as the `_mountDepth` modal check it sits
    // beside. `activeTransitions` remains the change signal (it ticks on every
    // begin/end anywhere); `hasActiveTransitionAbove` makes the decision.
    // A transition ABOVE me is only a reason to hide if I am NOT part of what
    // is moving. This is the distinction the gate was missing, and it is why
    // Liquid Glass re-materialized on every back-navigation:
    //
    // - Chrome the route slides OVER (the tab bar in the tab-host scaffold,
    //   outside every tab's nested router) is static while the page moves. A
    //   platform view composites above the Flutter scene, so it must leave the
    //   frame. This is the case `autoHideOnPageTransition` was written for and
    //   the one with device hours behind it.
    // - Content INSIDE the transitioning route is the opposite case. It is
    //   carried by that route's own transform, so there is nothing to prevent
    //   — and hiding it is actively harmful: leaving the frame makes the engine
    //   `removeFromSuperview` the platform view, and re-entering the frame
    //   `addSubview`s it, which is what re-establishes (materializes) iOS 26
    //   Liquid Glass. Fully visible on pop, invisible on push only because
    //   there the views are appearing for the first time, where materialize is
    //   Apple's intended behavior.
    //
    // Verified against the SDK on disk rather than assumed, because the old
    // premise ("a platform view neither clips nor translates with the routes")
    // is FALSE for Cupertino in-route content:
    //   * `CupertinoPageTransition` is a plain nested `SlideTransition` +
    //     `DecoratedBoxTransition` (cupertino/route.dart:563-570) — a
    //     `Transform`, i.e. the `kTransform` mutator.
    //   * The iOS embedder applies `kTransform` as a full 4x4 `CATransform3D`,
    //     and `kClipRect`/`kClipRRect`/`kClipPath` via a `FlutterClippingMaskView`
    //     (`FlutterPlatformViewsController.mm`, `ApplyMutators`).
    //   * Cupertino never snapshots: `SnapshotWidget` is consumed in exactly
    //     one framework file, `material/page_transitions_theme.dart` (the Zoom
    //     transition). So `allowSnapshotting: true` on `CupertinoPageRoute`
    //     cannot strand the view here — that caveat is Material-only.
    //   * Flutter content painted above a platform view becomes an *overlay*
    //     (widgets/platform_view.dart:632), so staying painted does not bleed
    //     through the outgoing page — z-order is preserved.
    // Read at the instant the observer ticks, and that instant is meaningful —
    // this is the part to not "fix" later thinking it is a race:
    //
    // - POP. A route was already above me, so my `secondaryAnimation` proxy is
    //   already wired to it and sitting at `completed`. The pop reverses it, so
    //   this reads `reverse` → travelling → I stay painted. I am being
    //   REVEALED, and revealed content must not re-materialize.
    // - PUSH. Nothing was above me yet, so the Navigator has not wired anything
    //   into that proxy at tick time and it reads `dismissed` → not travelling
    //   → I hide, exactly as before. I am being COVERED for the first time, and
    //   hiding under an incoming opaque route is invisible.
    //
    // So the discriminator is really *whether a route above me already
    // existed*, which is precisely "am I being revealed, or covered?". It is
    // determined by prior wiring state, not by callback ordering. (Sampling
    // from a post-frame callback registered BEFORE the push instead reads
    // `forward`, one beat later in the same frame — that is the misleading
    // reading, not this one.)
    // INTERACTIVE BACK-SWIPE (device clip 00-26, 2026-08-14): the two
    // isAnimating reads above are tick-order truths, and the gesture breaks
    // their timing. `didStartUserGesture` ticks the observer BEFORE the drag
    // has moved any controller — both proxies still sit at a terminal status
    // (`completed`), so isAnimating reads false on the dragged route AND the
    // route being revealed. Since this gate re-evaluates only on observer
    // ticks, every gate in the gesturing navigator hid for the entire drag
    // (all glass on both routes vanished under the finger), then popped back
    // mid-settle at the `didPop` tick — the re-materialize this predicate
    // exists to prevent. A gesture pop must read exactly like a button pop:
    // dragged content is carried by its route's transform (kTransform applies
    // to platform views — see the SDK verification above), revealed content
    // must not re-materialize, and z-order slicing keeps it under the
    // outgoing page either way.
    //
    // `userGestureInProgress` is incremented by `NavigatorState` BEFORE it
    // notifies observers (navigator.dart, didStartUserGesture) — so it is
    // already readable at the tick that matters — and it is held true through
    // the settle (the back-gesture controller calls didStopUserGesture from
    // its settle-completion listener, both on commit and on cancel).
    //
    // Asked of every ENCLOSING navigator, not just this route's own: the flag
    // lives on the single NavigatorState that owns the DRAGGED route, which is
    // not necessarily mine. A gate inside a nested router, on a route an outer
    // navigator is revealing, is travelling — carried by the outer route's
    // transform — while its own navigator reports no gesture at all. That is
    // exactly CupertinoSheetRoute's shape: it hands its drag controller
    // `route.navigator!` (the ROOT navigator, sheet.dart:855) while content
    // inside the sheet's own Navigator reads a different NavigatorState, so
    // the sheet's contents blanked under the finger. Same walk as
    // `hasActiveTransitionAbove` uses, and the same reasoning: a navigator
    // that encloses me can move me.
    final travellingWithTransition =
        (_route?.animation?.isAnimating ?? false) ||
            (_route?.secondaryAnimation?.isAnimating ?? false) ||
            _gestureInEnclosingNavigator(context);

    final hidden = _modalCoversMe() ||
        (CNTransitionObserver.hasActiveTransitionAbove(context) &&
            !travellingWithTransition);
    if (hidden == _hidden) return;
    // One setState, no controller: the swap is a paint toggle on both edges.
    setState(() => _hidden = hidden);
  }

  @override
  Widget build(BuildContext context) {
    final unmounting = widget.hideMode == AppBoxKitChromeHideMode.unmount;

    if (unmounting && _hidden) {
      // Same-size stand-in: the no-layout-shift guarantee for this mode.
      final s = _lastSize;
      return s == null
          ? const SizedBox.shrink()
          : SizedBox(width: s.width, height: s.height);
    }

    Widget child = widget.child;
    if (unmounting) {
      child = _MeasureSize(onSize: (size) => _lastSize = size, child: child);
    }

    // The wrap is UNCONDITIONAL — never `_hidden ? IndexedStack(...) : child`.
    // Returning the child bare on one branch changes the tree shape at exactly
    // the moment a platform view is transitioning, which reparents it and
    // forces the native re-init this gate exists to avoid. Only `index` moves.
    // (Same reasoning, and the same bug, as the vendored tab bar's Issue #35:
    // `vendor/cupertino_native_better/lib/components/tab_bar.dart:558-565`.)
    //
    // For the same reason the children list must stay FIXED at these two slots,
    // in this order. Changing an `IndexedStack`'s child-list length or order
    // disposes and re-creates the subsequent children even when they carry
    // stable keys (flutter#182303, OPEN) — which would silently reintroduce the
    // native re-init through the back door. Vary `index`, never the list.
    //
    // `StackFit.passthrough` hands our own constraints to both children, so
    // the box is sized by the parent exactly as it was before this wrap
    // existed. The placeholder can be empty without collapsing the footprint:
    // `RenderIndexedStack` lays out every child regardless of `index`.
    return IndexedStack(
      // NON-directional on purpose. `IndexedStack`'s default is
      // `AlignmentDirectional.topStart`, which asserts on a missing
      // `Directionality` ancestor — this gate is wrapped around leaf glass
      // tiers inside 13 kit widgets and must not impose a new ancestor
      // requirement on any of them. Nothing is lost: the placeholder is 0×0,
      // so the real child is always the sizing child and sits at the origin
      // under any alignment.
      alignment: Alignment.topLeft,
      index: _hidden ? 0 : 1,
      sizing: StackFit.passthrough,
      children: [
        const SizedBox.shrink(),
        child,
      ],
    );
  }
}

/// True when ANY navigator enclosing [context] is running a user gesture
/// (iOS edge back-swipe, Cupertino sheet drag-to-dismiss, Android predictive
/// back — all three funnel through `didStartUserGesture`).
///
/// Walks outwards from the innermost navigator. `nav.context` is the
/// Navigator's own element, so the step is `findAncestorStateOfType` from
/// there — `Navigator.maybeOf` would hand back the same state and spin
/// forever. Deliberately NOT an inherited-widget lookup: this runs from a
/// post-frame callback, where registering a dependency is invalid.
bool _gestureInEnclosingNavigator(BuildContext context) {
  NavigatorState? nav = Navigator.maybeOf(context);
  while (nav != null) {
    if (nav.userGestureInProgress) return true;
    nav = nav.context.findAncestorStateOfType<NavigatorState>();
  }
  return false;
}

/// Records the child's size after every layout (unmount mode only).
/// Callback writes a field — never setState — so mid-layout calls are safe.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onSize);

  @override
  void updateRenderObject(
          BuildContext context, _RenderMeasureSize renderObject) =>
      renderObject.onSize = onSize;
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onSize);

  ValueChanged<Size> onSize;

  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}

/// Fluent sugar for wrapping a native-glass tier in [AppBoxKitNativeChromeGate] — the
/// kit-wide "autoHideOnPageTransition" every `AppBoxKitNative*` Liquid Glass widget
/// appends to its Apple/glass tier so the platform view leaves the frame during
/// route transitions (and modal overlays) instead of leaking over the slide.
/// One call, both signals (route transition + modal depth).
///
/// There is deliberately no duration to pass: the swap is instant on both
/// edges. See the class doc for the four sources that rule out animating it.
extension AppBoxKitNativeChromeGateX on Widget {
  Widget chromeGated({
    AppBoxKitChromeHideMode hideMode = AppBoxKitChromeHideMode.keepAlive,
  }) =>
      AppBoxKitNativeChromeGate(
        hideMode: hideMode,
        child: this,
      );
}
