import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNBottomSheet, CNTabBarRouteObserver;
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';

import 'appbox_kit_frosted_surface.dart';

/// Shows a platform-adaptive modal bottom sheet hosting [builder].
///
/// Routing:
///
/// - **Android** → Flutter's built-in [showModalBottomSheet]. There is no
///   `m3e_collection` sheet class, and the kit owns no native sheet code — the
///   M3 theme already styles the built-in Material sheet. Never glassed: the
///   M3 sheet is the correct idiom there.
/// - **iOS / macOS / else** → [CNBottomSheet.show] with a **Flutter-drawn
///   glass body** (ADR 0011 item 1, on ADR 0010's frosted content tier): the
///   route chrome is transparent and [builder]'s child is wrapped in a
///   floating [AppBoxKitFrostedSurface] panel (28 dp corners, blur 30) with a
///   grabber pill above the content — the iOS 26 partial-height-sheet idiom
///   (floating rounded panel, dimmed host page visible in the insets).
///   Accepted ceiling: no morph-from-button transition (system-presentation
///   feature). [CNBottomSheet.show] stays load-bearing: its
///   `CNSheetGeometryProbe` publishes the sheet body's live rect so
///   `ModalHideMixin` widgets on the host page hide only when geometrically
///   covered.
///
/// The floating geometry is composed **inside** the sheet route (transparent
/// background + inset padding around the glass panel) rather than by
/// fighting the route's own positioning: drag-to-dismiss and barrier-tap
/// dismiss work unchanged, the transparent inset simply being part of the
/// sheet's drag area. Trade-off: the geometry probe measures the padded
/// body, so the published rect is a ~12 dp superset of the visible glass —
/// a conservative hide, fine for `ModalHideMixin` consumers.
///
/// A caller-supplied [backgroundColor] opts out of the glass body entirely:
/// the iOS tier then keeps the pre-glass stock sheet chrome painted with
/// that color, so every pre-wave-2 call site behaves exactly as before.
///
/// Both tiers present with a plain-dim barrier (`Colors.black54` default) —
/// per ADR 0010 chrome stays mounted behind plain-dim scrims; no blur scrim
/// is used anywhere in this path.
///
/// The public surface is **primitives only** ([builder], [context],
/// [isDismissible], [backgroundColor]) so hosts never import either underlying
/// dep. The generic return type is honored end-to-end: both tiers return
/// `Future<T?>`, so a host that closes the sheet with
/// `Navigator.pop(context, value)` receives `value` here.
///
/// Mirrors [AppBoxKitNotificationService]'s tier-routing pattern
/// (reuses existing infra rather than reinventing a sheet controller).
Future<T?> appBoxKitShowNativeSheet<T>({
  required WidgetBuilder builder,
  required BuildContext context,
  bool isDismissible = true,
  Color? backgroundColor,
}) async {
  // Bump the shared modal depth for the sheet's lifetime. No navigator in
  // either app registers `CNTabBarRouteObserver`, so route pushes alone never
  // move `anyModalDepth` — this manual bracket (same pattern as
  // `kit_native_overlay.dart`) is what makes every modal-aware native widget
  // ([AppBoxKitNativeChromeGate], [AppBoxKitScrollOcclusionGate], `CNSearchBar`'s
  // self-hide) react to kit sheets. Without it, platform views on the
  // obscured page composite *above* the sheet (ghost chrome over the cart
  // sheet).
  CNTabBarRouteObserver.markAnyModalActive();
  try {
    // Android → built-in Material modal sheet (M3 theme drives it; no m3e
    // class).
    if (AppBoxKitPlatform.supportsComposeM3E) {
      return await showModalBottomSheet<T>(
        context: context,
        builder: builder,
        isDismissible: isDismissible,
        backgroundColor: backgroundColor,
      );
    }
    // iOS / macOS / else → CNBottomSheet.show (geometry probe stays, see
    // doc). A caller-supplied backgroundColor wins: it opts out of the glass
    // body into the pre-glass stock chrome.
    if (backgroundColor != null) {
      return await CNBottomSheet.show<T>(
        context: context,
        builder: builder,
        isDismissible: isDismissible,
        backgroundColor: backgroundColor,
      );
    }
    return await CNBottomSheet.show<T>(
      context: context,
      isDismissible: isDismissible,
      // Transparent route chrome, no elevation, no shape: the stock sheet
      // would paint/clip around the glass panel otherwise; the panel
      // supplies its own chrome.
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      builder: (_) => _GlassSheetBody(builder: builder),
    );
  } finally {
    // Future completes on pop → restore. `finally` keeps the depth balanced
    // even if the sheet route throws.
    CNTabBarRouteObserver.markAnyModalInactive();
  }
}

/// The iOS-tier sheet body: [builder]'s child in a floating
/// [AppBoxKitFrostedSurface] panel — horizontal inset + safe-area-aware bottom
/// gap, grabber pill above the content (ADR 0011 item 1).
class _GlassSheetBody extends StatelessWidget {
  const _GlassSheetBody({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Floating-sheet geometry: the stock route renders flush to the screen
      // edges, so the inset is composed here. The transparent margin belongs
      // to the sheet (not the barrier), keeping drag-to-dismiss live on it.
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        8 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: AppBoxKitFrostedSurface(
        borderRadius: 28,
        blur: 30,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetGrabber(),
            Flexible(child: builder(context)),
          ],
        ),
      ),
    );
  }
}

/// The grabber pill at the top edge of the glass sheet — the iOS 26
/// floating-sheet affordance (36×5 dp, fully rounded).
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          key: const ValueKey<String>('appBoxKitNativeSheetGrabber'),
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: const BorderRadius.all(Radius.circular(2.5)),
          ),
        ),
      ),
    );
  }
}
