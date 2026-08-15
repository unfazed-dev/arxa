import 'package:cupertino_native_better/cupertino_native_better.dart'
    show
        CNGlassEffect,
        CNGlassEffectShape,
        CNTabBarRouteObserver,
        LiquidGlassConfig,
        LiquidGlassContainer;
import 'package:flutter/material.dart';
import 'package:get/get.dart' show SnackbarController;

/// Runs [present] (a full-screen Flutter overlay — e.g. a GetX snackbar with
/// `overlayBlur`) with every CN* native platform view hidden for its lifetime,
/// then restores them.
///
/// **Why this exists.** On iOS, `CNButton` / `CNSegmentedControl` / `CNTabBar`
/// render as `UiKitView`s composited *above* the Flutter scene. A Flutter
/// `BackdropFilter` (what GetX's `overlayBlur` scrim uses) cannot sample or
/// cover those native pixels, so they bleed through the blur, sharp — the iOS
/// hybrid-composition z-order bug (cupertino_native_better Issue #53). The
/// package's fix is to destroy the platform views while a modal is up; it wires
/// that to route pushes via `CNTabBarRouteObserver`, but a snackbar is an
/// `Overlay` entry, not a route, so that machinery never fires on its own.
/// `markAnyModalActive` / `markAnyModalInactive` is the package's public hook
/// for exactly this non-route overlay case.
///
/// **Reach (ADR 0010 second amendment).** The modal-hide counter only
/// dematerializes widgets that opt in with `autoHideOnModal: true` — post
/// Issue-#53 containment that is the tab bar alone. In-page CN components
/// (buttons, segmented controls, sliders…) stay mounted, keep slicing the
/// scene, and the GetX `BackdropFilter` therefore blurs *nothing* on any
/// platform-view-bearing page — only its child dim composites. The frost on
/// the Liquid Glass tier is instead supplied by [scrimOverlay]: a kit-owned
/// root-overlay entry hosting a full-screen native glass platform view
/// (`CNGlassEffect.regular`) with the dim painted *above* it. Native UIKit
/// glass samples the full CALayer hierarchy — platform views included — so
/// nothing beneath is readable. Being inserted before the GetX entries, the
/// scrim is the scene-last platform view at snackbar paint time: the engine's
/// view slicer hoists the later Flutter snackbar ops above it (the same
/// plain-anchor mechanism the center pill rides; full-screen is deliberate
/// here — a scrim *should* swallow taps: tap = dismiss). Callers on other
/// tiers pass `scrimOverlay: null` and keep the sigma-20 GetX path.
///
/// **Contract.** [present]'s Future should complete on dismiss, OR resolve to
/// a GetX [SnackbarController] — stacked_services' `showCustomSnackBar` does
/// the LATTER: it is `async` but its last statement is `return getBar.show()`,
/// which returns the [SnackbarController] *object* (not a future), so the
/// wrapper future completes one frame after the snackbar APPEARS. The dismissal
/// signal is the controller's own `.future` (completes when the exit transition
/// finishes), so this helper unwraps and awaits it — otherwise the hide was
/// released while the blur was still up and the CN platform views remounted
/// sharp over the scrim (the exact bug this helper exists to fix). The
/// `finally` releases the hide even if [present] throws, so the depth counter
/// can't get stuck > 0. The scrim lease is released in the same `finally`,
/// fades out, and is removed only when no other presentation still leases it
/// (concurrent snackbars share one entry — no double dim).
Future<void> appBoxKitWithNativeChromeHidden(
  Future<dynamic>? Function() present, {
  OverlayState? scrimOverlay,
  Color scrimColor = Colors.black54,
}) async {
  final scrim = scrimOverlay == null
      ? null
      : AppBoxKitSnackbarScrimLease.acquire(scrimOverlay, scrimColor);
  CNTabBarRouteObserver.markAnyModalActive();
  try {
    final result = await present();
    // showCustomSnackBar resolves at SHOW time with the controller; the
    // dismissal signal is controller.future. Hold the hide until then.
    if (result is SnackbarController) {
      scrim?.bind(result);
      await result.future;
    }
  } finally {
    CNTabBarRouteObserver.markAnyModalInactive();
    await scrim?.release();
  }
}

/// Ref-counted lease on the single shared native snackbar scrim entry.
///
/// Visible for testing; production callers only ever touch it through
/// [appBoxKitWithNativeChromeHidden]. GetX queues concurrent snackbars, but
/// each presentation wraps itself — the shared entry + depth counter keeps
/// overlapping wrappers from stacking two dims.
class AppBoxKitSnackbarScrimLease {
  AppBoxKitSnackbarScrimLease._();

  static int _depth = 0;
  static OverlayEntry? _entry;

  /// True between inserting a fresh entry and its mount frame landing, so a
  /// lease arriving in the same turn defers the fade-in flip to the scheduled
  /// post-frame instead of pre-lighting the entry.
  static bool _mountPending = false;
  static final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);
  static final List<SnackbarController> _controllers = <SnackbarController>[];

  /// Test hook: whether the shared scrim entry is currently mounted.
  @visibleForTesting
  static bool get debugScrimMounted => _entry != null;

  /// Test hook: current lease depth.
  @visibleForTesting
  static int get debugDepth => _depth;

  static AppBoxKitSnackbarScrimLease acquire(
      OverlayState overlay, Color color) {
    _depth++;
    if (_entry == null) {
      // Mount DARK and light it on the next frame. Setting `_visible` true
      // before the insert made the entry's first build already 1.0, and
      // AnimatedOpacity does not animate its initial value — so a full-screen
      // Glass.regular frost snapped on at full strength while dismissal got a
      // 200ms fade. The post-frame flip gives the entry one frame at 0, so the
      // implicit animation has a value to travel from and the fade is
      // symmetric in and out.
      _visible.value = false;
      _mountPending = true;
      _entry = OverlayEntry(
        builder: (_) => _AppBoxKitSnackbarNativeScrim(
          visible: _visible,
          color: color,
          onTap: _closeTopController,
        ),
      );
      overlay.insert(_entry!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mountPending = false;
        // Guard the release that beat the frame: no lease left means the
        // scrim is already tearing down and must not light back up.
        if (_depth > 0) _visible.value = true;
      });
    } else if (!_mountPending) {
      // Entry already up and past its mount frame (a lease arriving mid-fade):
      // flip immediately so AnimatedOpacity animates back up from wherever the
      // fade-out had reached. While a mount is still pending — GetX queues
      // concurrent snackbars, so two acquires can share one synchronous turn —
      // the scheduled post-frame owns the flip; lighting it here would pre-lit
      // the mount frame and restore the snap-on this fix removes.
      _visible.value = true;
    }
    return AppBoxKitSnackbarScrimLease._();
  }

  /// Wires tap-outside-to-dismiss: with `overlayBlur: 0` GetX mounts no
  /// gesture entry of its own, so the scrim restores that affordance.
  void bind(SnackbarController controller) {
    _controllers.add(controller);
    controller.future.whenComplete(() => _controllers.remove(controller));
  }

  static void _closeTopController() {
    if (_controllers.isEmpty) return;
    _controllers.last.close();
  }

  Future<void> release() async {
    _depth--;
    if (_depth > 0) return;
    // Fade the scrim out over the same beat as the snackbar's exit, then
    // remove — unless a new lease arrived mid-fade and re-lit it.
    _visible.value = false;
    await Future<void>.delayed(_AppBoxKitSnackbarNativeScrim.fadeDuration);
    if (_depth > 0) return;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    // Clear alongside the entry it guards: a teardown that beat the mount
    // frame must not leave the next acquire deferring to a callback that
    // already ran.
    _mountPending = false;
    _controllers.clear();
  }
}

class _AppBoxKitSnackbarNativeScrim extends StatelessWidget {
  const _AppBoxKitSnackbarNativeScrim({
    required this.visible,
    required this.color,
    required this.onTap,
  });

  static const Duration fadeDuration = Duration(milliseconds: 200);

  final ValueNotifier<bool> visible;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, shown, child) => IgnorePointer(
          ignoring: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1.0 : 0.0,
            duration: fadeDuration,
            curve: Curves.easeOutCubic,
            child: child,
          ),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Native frost FIRST (beneath the dim): real UIKit glass
              // samples every CALayer under it — platform views included —
              // which a Flutter BackdropFilter structurally cannot. On tiers
              // without native glass the container degrades to its bare
              // child (never inserted there anyway — service gates on
              // supportsLiquidGlass).
              // transition-exempt: transient overlay, not chrome — the scrim
              // lives in the ROOT overlay above every route by design (the
              // snackbar law: highest surface, resolves the root overlay). It
              // must ride over route slides, not gate with them; its lifetime
              // is the lease's, torn down by release(), never by navigation.
              const LiquidGlassContainer(
                config: LiquidGlassConfig(
                  effect: CNGlassEffect.regular,
                  shape: CNGlassEffectShape.rect,
                  cornerRadius: 0,
                ),
                child: SizedBox.expand(),
              ),
              // Dim ABOVE the glass: platform-view creation is async, so the
              // Flutter-drawn dim guarantees nothing readable from frame
              // zero while the effect view attaches.
              ColoredBox(color: color),
            ],
          ),
        ),
      ),
    );
  }
}
