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
/// 3. **Flutter, open bugs.** flutter#93757 (`FadeTransition` does not apply to
///    hybrid-composition platform views) and flutter#24164 (an opacity layer
///    spanning a platform view splits into two groups) are both OPEN, with no
///    merged fix. Animating alpha over a `UiKitView` is unsupported, not just
///    costly.
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

  @override
  void initState() {
    super.initState();
    _mountDepth = CNTabBarRouteObserver.anyModalDepth.value;
    CNTabBarRouteObserver.anyModalDepth.addListener(_onDepthChanged);
    CNTransitionObserver.activeTransitions.addListener(_onDepthChanged);
  }

  @override
  void dispose() {
    CNTabBarRouteObserver.anyModalDepth.removeListener(_onDepthChanged);
    CNTransitionObserver.activeTransitions.removeListener(_onDepthChanged);
    super.dispose();
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
    final hidden = CNTabBarRouteObserver.anyModalDepth.value > _mountDepth ||
        CNTransitionObserver.hasActiveTransitionAbove(context);
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
