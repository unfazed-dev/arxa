import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
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
/// can't get stuck > 0.
///
/// **Reach.** No-op on Android / iOS < 26 (those tiers mount no CN widgets to
/// react). On iOS 26 the native controls VANISH behind the blur and return on
/// dismiss — they can't be rendered blurred-but-visible like the Flutter
/// fallback tiers, because their pixels aren't in the layer the blur samples.
Future<void> withNativeChromeHidden(Future<dynamic>? Function() present) async {
  CNTabBarRouteObserver.markAnyModalActive();
  try {
    final result = await present();
    // showCustomSnackBar resolves at SHOW time with the controller; the
    // dismissal signal is controller.future. Hold the hide until then.
    if (result is SnackbarController) await result.future;
  } finally {
    CNTabBarRouteObserver.markAnyModalInactive();
  }
}
