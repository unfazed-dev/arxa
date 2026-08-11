import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNBottomSheet, CNTabBarRouteObserver;
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';

import 'appbox_kit_frosted_surface.dart';

/// Shows a platform-adaptive modal sheet hosting [builder].
///
/// **Not native, and deliberately not claiming to be.** Both tiers are drawn
/// by Flutter. Neither crosses a platform channel: iOS has no bridge here to
/// `UISheetPresentationController`, and Android has nothing to bridge *to* —
/// the platform's own bottom sheet is a Material component, which is exactly
/// what the Material tier renders. The former name (`…ShowNativeSheet`)
/// overclaimed; see `docs/plans/sheet-and-theme-propagation-fixes.md`.
///
/// Routing:
///
/// - **Android** → Flutter's built-in [showModalBottomSheet], styled by the
///   M3E theme. `m3e_collection` (0.3.7, the current release) ships no sheet
///   component, so the built-in M3 sheet *is* the M3E-correct surface here.
/// - **iOS / macOS / else** → [CNBottomSheet.showCupertino], i.e. Flutter's
///   `showCupertinoSheet`. The framework supplies the whole presentation: the
///   page behind slides up, scales down and rounds its corners
///   (`CupertinoSheetTransition`, a `delegatedTransition`), and the sheet
///   clips its own top corners at r=12. `showDragHandle: true` draws the
///   framework's grabber — the kit must not paint one too, or there are two.
///
/// **Why this replaced a Material sheet on iOS.** The previous iOS tier was
/// `showModalBottomSheet` with transparent chrome wrapping a 12 dp-inset
/// floating frosted panel. That is a floating card, not a sheet, which is
/// exactly how it read on device. The Cupertino route is the framework's iOS
/// idiom and restores the shape.
///
/// Two behaviour changes fall out of the route swap, both intended:
///
/// - **No dim barrier.** `CupertinoSheetRoute.barrierColor` is transparent and
///   `barrierDismissible` is false (`cupertino/sheet.dart:777,780`). The
///   scaled-back parent card *is* the separation, as on iOS. So
///   [isDismissible] now maps to `enableDrag` (drag-to-dismiss) rather than
///   barrier-tap — the closest honest mapping the route offers.
/// - **It pushes on the root navigator** as a page route, not a
///   `ModalBottomSheetRoute`. The `markAnyModalActive` bracket below is what
///   keeps modal-aware native widgets reacting, and it is route-type agnostic.
///
/// Glass is preserved: `CupertinoSheetRoute.opaque` is false
/// (`cupertino/sheet.dart:789`), so the scaled parent stays painted behind and
/// [AppBoxKitFrostedSurface]'s backdrop filter has real content to blur (ADR
/// 0011 item 1). A caller-supplied [backgroundColor] opts out into a flat
/// surface of that colour.
///
/// [CNBottomSheet] stays load-bearing on both tiers: its `CNSheetGeometryProbe`
/// publishes the sheet body's live rect so `ModalHideMixin` widgets on the host
/// page hide only when geometrically covered.
///
/// **Drag handle: on by default on BOTH tiers.** [showDragHandle] defaults to
/// `true` and is forwarded to each tier's own grabber — the framework draws it,
/// never the kit (painting one here as well yields two pills).
///
/// This is a deliberate departure from Flutter's Material default, which
/// resolves `showDragHandle ?? (enableDrag && (sheetTheme.showDragHandle ??
/// false))` (`material/bottom_sheet.dart:1161`). The kit sets no
/// `bottomSheetTheme.showDragHandle`, so leaving it unset gave Android sheets
/// **no handle at all** — a sheet with no visible affordance for the drag it
/// supports. Passing it explicitly is what makes the two tiers agree.
///
/// Interaction worth knowing: on the iOS tier [isDismissible] maps to
/// `enableDrag`, so `isDismissible: false` with the default handle would show a
/// grabber that cannot drag. Pass `showDragHandle: false` alongside it. (No
/// call site does this today — the only `barrierDismissible: false` in the kit
/// is on the dialog path, not a sheet.)
///
/// The public surface is **primitives only** ([builder], [context],
/// [isDismissible], [showDragHandle], [backgroundColor]) so hosts never import
/// either underlying dep. The generic return type is honored end-to-end: both
/// tiers return `Future<T?>`, so a host that closes the sheet with
/// `Navigator.pop(context, value)` receives `value` here.
Future<T?> appBoxKitShowSheet<T>({
  required WidgetBuilder builder,
  required BuildContext context,
  bool isDismissible = true,
  bool showDragHandle = true,
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
        showDragHandle: showDragHandle,
        backgroundColor: backgroundColor,
      );
    }
    // iOS / macOS / else → the framework's Cupertino sheet. It owns the
    // presentation: parent scale-back, top-corner clip, and the grabber.
    return await CNBottomSheet.showCupertino<T>(
      context: context,
      // The route has no dismissible barrier at all, so this is the only
      // dismiss affordance it can be mapped onto.
      enableDrag: isDismissible,
      showDragHandle: showDragHandle,
      pageBuilder: (_) => _CupertinoSheetBody(
        builder: builder,
        backgroundColor: backgroundColor,
      ),
    );
  } finally {
    // Future completes on pop → restore. `finally` keeps the depth balanced
    // even if the sheet route throws.
    CNTabBarRouteObserver.markAnyModalInactive();
  }
}

/// The iOS-tier sheet body — the *contents* of the Cupertino sheet, not its
/// chrome.
///
/// The route already supplies the shape (top-corner clip at r=12), the parent
/// scale-back and the grabber, so this deliberately adds none of those. It
/// contributes only the surface behind [builder]'s child.
///
/// `borderRadius: 0` on the frosted surface is load-bearing: the route clips
/// the corners itself, and a second radius here would show as a lighter seam
/// inside the clip.
class _CupertinoSheetBody extends StatelessWidget {
  const _CupertinoSheetBody({required this.builder, this.backgroundColor});

  final WidgetBuilder builder;

  /// Opt-out of glass into a flat surface of this colour.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    // Top: the route hands down `padding.top = 15` so content clears the
    // grabber it draws (`cupertino/sheet.dart:707,713`), so honouring the
    // padding here is what keeps the two from overlapping.
    // Bottom: the sheet reaches the screen edge, so the home indicator inset
    // is still ours to respect.
    final Widget content = SafeArea(child: Builder(builder: builder));

    final Color? flat = backgroundColor;
    if (flat != null) return ColoredBox(color: flat, child: content);

    return AppBoxKitFrostedSurface(
      borderRadius: 0,
      blur: 30,
      child: content,
    );
  }
}
