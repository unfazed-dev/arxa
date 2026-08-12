import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:cupertino_native_better/cupertino_native.dart'
    show CNTransitionObserver;
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;

/// How [AppBoxKitNativeChromeGate] takes the child's pixels off screen.
enum AppBoxKitChromeHideMode {
  /// Paint-level hide (default): the child stays mounted and is
  /// **dematerialized** — Apple's `effect = nil` semantic (WWDC25 #284),
  /// rendered as a fade + slight scale-out over `hideDuration`. At alpha 0
  /// `RenderAnimatedOpacity` skips painting entirely, and a platform view
  /// absent from the frame's layer tree is removed from the native view
  /// hierarchy — so it cannot bleed through an overlay — while the native
  /// view instance stays ALIVE. Restore fades + scales the same live view
  /// back in: no native re-init, no raster/platform thread-merge stall (the
  /// jank the unmount strategy caused on every reappear).
  keepAlive,

  /// Unmount the subtree while hidden (destroys the platform view; a
  /// measured same-size placeholder holds the layout). Escape hatch in case
  /// a specific native view misbehaves at alpha 0 — costs a full native
  /// re-init + thread merge on every restore, which visibly hitches. The
  /// swap is still instant (a destroyed view has nothing to animate).
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
/// - `CNTransitionObserver.activeTransitions` — `> 0` during any route slide
///   (push/pop/replace/remove or the interactive back-swipe). A platform view
///   neither clips nor translates with the routes mid-transition, so it must
///   leave the frame — otherwise it floats over the slide (glass, or a flat
///   panel if merely de-tinted; hiding is the only thing that actually works).
///   This makes the gate the kit-wide "autoHideOnPageTransition (alpha-0)" for
///   every Liquid Glass surface it wraps, the same protection `CNTabBar` has.
///
/// **Behavior.**
/// - *Mount-depth snapshot* (mirrors the package's `ModalHideMixin`): the
///   depth at mount is the baseline; the gate hides only when live depth
///   grows PAST it — a gate used *inside* a sheet never self-destroys.
/// - *No layout shift, ever*: in [AppBoxKitChromeHideMode.keepAlive] the child
///   never stops laying out, so its footprint is simply still there (the
///   scale is a paint-time transform, not a layout change); in
///   [AppBoxKitChromeHideMode.unmount] a measured same-size placeholder stands in.
/// - *Hide dematerializes* (ADR 0010, part 3): fade + slight scale-out over
///   [hideDuration] — Apple's sanctioned `effect = nil` removal for
///   content-layer glass, replacing the old instant alpha-0. The instant
///   hide existed because a fade kept the native view bleeding through a
///   *blur* scrim for the fade's length; kit-owned scrims are now plain dims
///   (or gone), which cover platform views fine post-2019, so the animated
///   removal is safe. A host that still presents a *blur* overlay can pass
///   `hideDuration: Duration.zero` to keep the legacy instant hide.
/// - *Show fades + scales in* over [showDuration]: masks the reattach (and,
///   in unmount mode, the re-init flash). Opacity is the one mutator iOS
///   hybrid composition applies to platform views fully reliably; the scale
///   is kept slight (0.95) — larger transforms on platform views are dicier,
///   and any translate would move pixels.
/// - Hidden children also stop receiving pointers ([IgnorePointer]) —
///   alpha-0 widgets are otherwise still hit-testable.
///
/// **Ceiling (named on purpose):** all-or-nothing. The package's
/// `ModalHideMixin` can consult `topModalRect` to keep widgets a partial
/// sheet doesn't cover; this gate ignores that and hides regardless. For
/// snackbar blurs (rect null) the behavior is identical. A true crossfade
/// of native content is impossible — platform views can't be snapshotted by
/// `RepaintBoundary.toImage`, so there is nothing to fade *from*.
///
/// No-op in practice on tiers that mount no platform views (Android
/// composites in-layer; Flutter-fallback tiers are ordinary widgets) — the
/// gate still functions, it just guards nothing that needed guarding.
class AppBoxKitNativeChromeGate extends StatefulWidget {
  const AppBoxKitNativeChromeGate({
    super.key,
    required this.child,
    this.showDuration = const Duration(milliseconds: 180),
    this.hideDuration = const Duration(milliseconds: 160),
    this.hideMode = AppBoxKitChromeHideMode.keepAlive,
  });

  final Widget child;

  /// Fade-in length when the child is restored after a modal dismisses.
  /// [Duration.zero] = instant reappear.
  final Duration showDuration;

  /// Dematerialize length when the child hides (keepAlive mode) — the fade +
  /// slight scale-out of Apple's `effect = nil` semantic. [Duration.zero] =
  /// the legacy instant alpha-0 hide; use it only behind a *blur* overlay,
  /// where an animated hide would keep the native view bleeding through the
  /// blur for the animation's length.
  final Duration hideDuration;

  final AppBoxKitChromeHideMode hideMode;

  @override
  State<AppBoxKitNativeChromeGate> createState() => _KitNativeChromeGateState();
}

class _KitNativeChromeGateState extends State<AppBoxKitNativeChromeGate>
    with SingleTickerProviderStateMixin {
  /// Depth at mount — the baseline. Hide only when depth exceeds it, so a
  /// gate mounted inside an already-open modal stays visible.
  late final int _mountDepth;

  bool _hidden = false;

  /// 1.0 = fully shown. reverse()ed on hide (the dematerialize animation;
  /// jumped to 0 only when `hideDuration` is zero); forward()ed on restore.
  late final AnimationController _fade;

  /// Child's last laid-out size — the unmount-mode placeholder's footprint.
  /// Written from layout (plain field, no setState: it is only *read* on
  /// the rebuild that hides, by which point the latest layout stamped it).
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    _mountDepth = CNTabBarRouteObserver.anyModalDepth.value;
    _fade = AnimationController(
      vsync: this,
      duration: widget.showDuration, // forward = restore
      reverseDuration: widget.hideDuration, // reverse = dematerialize
      value: 1.0,
    );
    CNTabBarRouteObserver.anyModalDepth.addListener(_onDepthChanged);
    CNTransitionObserver.activeTransitions.addListener(_onDepthChanged);
  }

  @override
  void didUpdateWidget(AppBoxKitNativeChromeGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fade.duration = widget.showDuration;
    _fade.reverseDuration = widget.hideDuration;
  }

  @override
  void dispose() {
    CNTabBarRouteObserver.anyModalDepth.removeListener(_onDepthChanged);
    CNTransitionObserver.activeTransitions.removeListener(_onDepthChanged);
    _fade.dispose();
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
    // Scoped, not global: only a transition in a navigator ABOVE this gate
    // slides the gate itself. A push inside one tab's nested router must not
    // dematerialize the ROOT tab bar in every tab (C2,
    // docs/plans/glass-chrome-root-cause-fixes.md) — same baseline-scoping
    // idea as the `_mountDepth` modal check on the line above.
    final hidden = CNTabBarRouteObserver.anyModalDepth.value > _mountDepth ||
        CNTransitionObserver.hasActiveTransitionAbove(context);
    if (hidden == _hidden) return;
    setState(() => _hidden = hidden);
    if (hidden) {
      if (widget.hideDuration == Duration.zero) {
        // Legacy instant hide — only for hosts still presenting a *blur*
        // overlay (an animated fade would bleed through it). Kit-owned
        // scrims are plain dims, so the default path dematerializes.
        _fade.stop();
        _fade.value = 0.0;
      } else {
        // Dematerialize (Apple `effect = nil`): fade + slight scale-out over
        // hideDuration. The same live view animates away — never unmounted.
        _fade.reverse();
      }
    } else if (widget.showDuration == Duration.zero) {
      _fade.value = 1.0;
    } else {
      _fade.forward(from: 0.0);
    }
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

    // easeOut on restore (quick start, soft land); easeIn on the reverse so
    // the dematerialize starts leaving immediately instead of lingering.
    final dematerialize = CurvedAnimation(
      parent: _fade,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    // Constant tree shape across hide/show in keepAlive mode — the child
    // must never be reparented, or the platform view re-inits anyway. The
    // scale is paint-time only (Transform), so the footprint never shifts.
    return IgnorePointer(
      ignoring: _hidden,
      child: FadeTransition(
        opacity: dematerialize,
        child: ScaleTransition(
          scale: dematerialize.drive(Tween(begin: 0.95, end: 1.0)),
          child: child,
        ),
      ),
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
/// appends to its Apple/glass tier so the platform view dematerializes (fade +
/// slight scale) out of the frame during route transitions (and modal overlays)
/// instead of leaking over the slide. One call, both signals (route transition
/// + modal depth).
extension AppBoxKitNativeChromeGateX on Widget {
  Widget chromeGated({
    Duration showDuration = const Duration(milliseconds: 180),
    Duration hideDuration = const Duration(milliseconds: 160),
    AppBoxKitChromeHideMode hideMode = AppBoxKitChromeHideMode.keepAlive,
  }) =>
      AppBoxKitNativeChromeGate(
        showDuration: showDuration,
        hideDuration: hideDuration,
        hideMode: hideMode,
        child: this,
      );
}
