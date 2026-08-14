import 'package:cupertino_native_better/cupertino_native_better.dart'
    show
        CNBottomSheet,
        CNSheetGeometryProbe,
        CNTabBarRouteObserver,
        showCNDetentSheet;
import 'package:flutter/cupertino.dart'
    show CupertinoColors, CupertinoDynamicColor, kCupertinoModalBarrierColor;
import 'package:flutter/foundation.dart' show ValueListenable;
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
/// **Overlay: on by default on BOTH tiers.** [showOverlay] dims the page behind
/// the sheet and makes a tap there dismiss it. Android already did this
/// (Material's barrier); iOS did not, because `CupertinoSheetRoute` hardcodes a
/// transparent, non-dismissible barrier (`cupertino/sheet.dart:777,780`) on the
/// reasoning that the scaled-back parent card supplies the separation. That
/// reasoning holds at full height and breaks at a short one, where the
/// uncovered page reads as still live — and iOS itself dims behind *every*
/// detent of a `UISheetPresentationController` unless
/// `largestUndimmedDetentIdentifier` opts out. The iOS tier gets it from a
/// route subclass in the vendor; the barrier resolves
/// [kCupertinoModalBarrierColor] per brightness.
///
/// This also restores the honest reading of [isDismissible] on iOS. The
/// previous pass had to document that it could only map to `enableDrag`,
/// because the route offered no tappable barrier to map it onto; now it means
/// both, and `isDismissible: false` withholds both.
///
/// **Height: [heightFactor] resizes a live sheet.** Null (default) leaves the
/// height to each framework — Material sizes to content, Cupertino to
/// `1 - topGap` (92%). Supply a listenable and the sheet is instead
/// bottom-anchored at that fraction of screen height, **re-reading the value
/// every time it changes**, so a control inside the sheet can grow and shrink
/// it under the user's finger.
///
/// It has to work that way: `CupertinoSheetRoute._topGap` is `final` and read
/// once at construction (`cupertino/sheet.dart:686,689`), so the route's own
/// height is fixed the moment it is pushed. `topGap` can express a height
/// chosen at present-time and nothing else. Owning the height in the *body*,
/// inside a route left at its default size, is what makes it live.
///
/// The cost, on the iOS tier only, is chrome ownership: the route's top clip
/// and grabber sit at the route's edge (92%), not the body's, so in this path
/// the body draws both itself — top-only r=12 corners matching the route's own
/// `ClipRSuperellipse`, and the framework's 36×5 grabber geometry
/// (`cupertino/sheet.dart:704-708`). The route's grabber is switched off so
/// there is exactly one.
///
/// The space left above a short sheet is an [Align] with no child there, which
/// deliberately does **not** hit-test, so taps in it reach the barrier. Filling
/// it with a transparent `ColoredBox` instead would look identical and be
/// inert: `_RenderColoredBox` passes `HitTestBehavior.opaque` to its
/// superclass unconditionally, alpha 0 included (`widgets/basic.dart:8528-8532`).
///
/// The public surface is **primitives only** ([builder], [context],
/// [isDismissible], [showDragHandle], [showOverlay], [heightFactor],
/// [backgroundColor]) so hosts never import either underlying dep. The generic
/// return type is honored end-to-end: both tiers return `Future<T?>`, so a host
/// that closes the sheet with `Navigator.pop(context, value)` receives `value`
/// here.
Future<T?> appBoxKitShowSheet<T>({
  required WidgetBuilder builder,
  required BuildContext context,
  bool isDismissible = true,
  bool showDragHandle = true,
  bool showOverlay = true,
  ValueListenable<double>? heightFactor,
  Color? backgroundColor,
  bool opaqueGlass = false,
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
        builder: heightFactor == null
            ? builder
            : (_) => _SizedSheetBody(heightFactor: heightFactor, child: Builder(builder: builder)),
        isDismissible: isDismissible,
        showDragHandle: showDragHandle,
        backgroundColor: backgroundColor,
        // Material sizes to its child, so an explicit height only survives if
        // the sheet is allowed past the 9/16 scroll-controlled cap.
        isScrollControlled: heightFactor != null,
        // Material's default barrier is already a dim; null keeps it.
        barrierColor: showOverlay ? null : Colors.transparent,
      );
    }
    // iOS / macOS / else, unsized → the UIKit-shaped detent sheet: opens at
    // medium (half screen), drags to large, grabber and top-corner clip owned
    // by the route. This is the apple-solution path — the framework's
    // full-height Cupertino sheet is wrong for browse surfaces.
    if (heightFactor == null) {
      return await showCNDetentSheet<T>(
        context: context,
        enableDrag: isDismissible,
        barrierDismissible: isDismissible,
        showDragHandle: showDragHandle,
        barrierColor: showOverlay ? kCupertinoModalBarrierColor : null,
        // The route probes the *detent-sized* box itself, so the automatic
        // probe is correct here (unlike the sized legacy path below).
        injectGeometryProbe: true,
        builder: (_) => _CupertinoSheetBody(
          builder: builder,
          backgroundColor: backgroundColor,
          opaqueGlass: opaqueGlass,
          heightFactor: null,
          // Route draws the grabber; a second one in the body would double up.
          showDragHandle: false,
        ),
      );
    }
    // iOS / macOS sized path → the framework's Cupertino sheet. The detent
    // route only knows medium/large, so a live [heightFactor] still rides the
    // legacy body-sized presentation.
    return await CNBottomSheet.showCupertino<T>(
      context: context,
      // Now genuinely both affordances: drag, and (via the barrier below) tap
      // outside.
      enableDrag: isDismissible,
      // This branch is now sized-only (the unsized case returned above), so
      // the body owns its own edge and the route grabber stays off.
      showDragHandle: false,
      barrierColor: showOverlay ? kCupertinoModalBarrierColor : null,
      // In the sized path the body does not fill the route, so the automatic
      // probe would publish the route box and hide host-page native widgets
      // that nothing covers. The body places its own probe on the sized box.
      injectGeometryProbe: false,
      pageBuilder: (_) => _CupertinoSheetBody(
        builder: builder,
        backgroundColor: backgroundColor,
        opaqueGlass: opaqueGlass,
        heightFactor: heightFactor,
        showDragHandle: showDragHandle,
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
  const _CupertinoSheetBody({
    required this.builder,
    this.backgroundColor,
    this.opaqueGlass = false,
    this.heightFactor,
    this.showDragHandle = true,
  });

  final WidgetBuilder builder;

  /// Opt-out of glass into a flat surface of this colour.
  final Color? backgroundColor;

  /// Keep the frosted-glass styling (rim, saturation, blur) but ground it on a
  /// fully opaque base, so nothing behind the sheet shows through. Ignored
  /// when [backgroundColor] is set (flat always wins).
  final bool opaqueGlass;

  /// Live fraction of screen height, or null to fill the route.
  final ValueListenable<double>? heightFactor;

  /// Only consulted in the sized path — otherwise the route draws the grabber.
  final bool showDragHandle;

  /// Top-corner radius the route clips itself to (`cupertino/sheet.dart`), which
  /// the sized body has to reproduce at its own edge.
  static const double _sheetCornerRadius = 12;

  @override
  Widget build(BuildContext context) {
    final ValueListenable<double>? factor = heightFactor;

    if (factor == null) {
      // Top: the route hands down `padding.top = 15` so content clears the
      // grabber it draws (`cupertino/sheet.dart:707,713`), so honouring the
      // padding here is what keeps the two from overlapping.
      // Bottom: the sheet reaches the screen edge, so the home indicator inset
      // is still ours to respect.
      return _surface(SafeArea(child: Builder(builder: builder)));
    }

    // Built once and passed through `ValueListenableBuilder.child`, so a drag on
    // a slider inside the sheet resizes a box rather than rebuilding a
    // `BackdropFilter` subtree sixty times a second.
    final Widget surface = ClipRSuperellipse(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(_sheetCornerRadius),
      ),
      child: _surface(
        Column(
          children: <Widget>[
            if (showDragHandle) const _SheetGrabber(),
            // SafeArea belongs *inside* the sized box: outside it, the bottom
            // inset would shrink the Align and float the sheet off the screen
            // edge. `top: false` because this edge is mid-screen, not the notch.
            Expanded(
              child: SafeArea(top: false, child: Builder(builder: builder)),
            ),
          ],
        ),
      ),
    );

    return Align(
      alignment: Alignment.bottomCenter,
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints constraints) {
          final double screenHeight = MediaQuery.sizeOf(ctx).height;
          return ValueListenableBuilder<double>(
            valueListenable: factor,
            child: surface,
            // The probe belongs here, around the box that actually carries the
            // height — not around the Align, which fills the route.
            // `ModalHideMixin` widgets on the host page use the published rect
            // to decide whether they are covered, so measuring the route would
            // tear down native chrome sitting in the clear space above a short
            // sheet. Rebuilt each frame but at a fixed position in the tree, so
            // the probe's State (and its rect) survives the resize.
            builder: (_, double value, Widget? child) => CNSheetGeometryProbe(
              child: SizedBox(
                // The route's box is `(1 - topGap) * screenHeight` — 92% by
                // default, measured. Clamping to the incoming constraint keeps a
                // caller asking for more than the route can give from
                // overflowing instead of simply filling it.
                height: (value * screenHeight).clamp(0.0, constraints.maxHeight),
                // Load-bearing. Align passes loose constraints, so a
                // height-only SizedBox collapses to its content's intrinsic
                // width and the sheet renders as a centered floating card —
                // the exact shape the Cupertino route was adopted to remove.
                width: double.infinity,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _surface(Widget content) {
    final Color? flat = backgroundColor;
    if (flat != null) return ColoredBox(color: flat, child: content);
    if (opaqueGlass) {
      // Same frosted material, opaque base: the tint token at alpha 1.0
      // instead of the translucent default — glass styling without see-through.
      return Builder(
        builder: (BuildContext context) => AppBoxKitFrostedSurface(
          borderRadius: 0,
          blur: 30,
          tint: Theme.of(context)
              .colorScheme
              .surfaceContainerLowest
              .withValues(alpha: 1.0),
          child: content,
        ),
      );
    }
    return AppBoxKitFrostedSurface(borderRadius: 0, blur: 30, child: content);
  }
}

/// The kit's stand-in for the route's grabber, drawn only in the sized path
/// where the route's own would land at the route's top edge instead of the
/// sheet's.
///
/// Geometry and colour are the framework's (`cupertino/sheet.dart:704-708`,
/// values Apple-derived), so the two are visually interchangeable. The [key] is
/// what tells them apart in tests — matching on the 36×5 box alone cannot,
/// which would let a "there is exactly one grabber" assertion pass while both
/// were on screen.
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  /// Identifies a kit-drawn grabber, as opposed to the route's.
  static const Key grabberKey = Key('appbox_kit_sheet_grabber');

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `dragHandleTopPadding` (5) above, `dragHandlePadding` (15) below —
      // the framework's own spacing, which it applies as MediaQuery padding.
      padding: const EdgeInsets.only(top: 5, bottom: 10),
      child: SizedBox(
        key: grabberKey,
        width: 36,
        height: 5,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            // Resolved explicitly: a CupertinoDynamicColor handed straight to a
            // DecoratedBox paints its light variant in both themes.
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.tertiaryLabel,
              context,
            ),
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
  }
}

/// Android-tier equivalent of the sized path: Material sizes its sheet to the
/// child, so resizing the child *is* resizing the sheet.
///
/// The Material drag handle sits above this box rather than inside it, so the
/// presented sheet is its height taller than [heightFactor] asks for. Left as
/// is: the handle's height is a private Material constant, and subtracting a
/// guess at it would drift the moment the theme changes it.
class _SizedSheetBody extends StatelessWidget {
  const _SizedSheetBody({required this.heightFactor, required this.child});

  final ValueListenable<double> heightFactor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.sizeOf(context).height;
    return ValueListenableBuilder<double>(
      valueListenable: heightFactor,
      child: child,
      builder: (_, double value, Widget? built) => SizedBox(
        height: value * screenHeight,
        width: double.infinity,
        child: built,
      ),
    );
  }
}
