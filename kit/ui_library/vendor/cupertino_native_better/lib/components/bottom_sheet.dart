import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tab_bar.dart' show CNTabBarRouteObserver;

/// Drop-in wrappers for Flutter's modal sheets that opt the CN-widget
/// family into **position-aware hide-on-modal** behavior.
///
/// **What it does.** When you open a sheet with `CNBottomSheet.show` (or
/// `CNBottomSheet.showCupertino`), a tiny invisible probe is injected into
/// the sheet's builder. The probe captures the sheet body's live global
/// rect each frame and publishes it to [CNTabBarRouteObserver.topModalRect].
/// Any CN-widget on the host page consuming `ModalHideMixin` then only
/// destroys its native PlatformView IF its own rect geometrically
/// intersects that published sheet rect.
///
/// **Why this matters.** Without geometry, every CN-widget on the host
/// page has to assume the worst and destroy itself while any sheet is up
/// (the only way to keep the iOS hybrid-composition bleed bug from
/// triggering — Issue #53). That's fine for sheets that cover most of the
/// screen, but for a small 30% sheet it wastefully destroys widgets in
/// your AppBar that are clearly not behind it. The geometry probe gives
/// each CN-widget a way to ask "am I actually behind the sheet?" and only
/// hide when the answer is yes.
///
/// **API parity.** Every parameter of `showModalBottomSheet` /
/// `showCupertinoSheet` is forwarded unchanged. Your `builder` receives a
/// regular `BuildContext` and can return any Flutter widget tree you
/// want — exactly like the underlying APIs. The probe is invisible: it
/// neither adds UI nor changes layout.
///
/// **Fallback for raw sheets.** If you use raw `showModalBottomSheet`
/// instead of `CNBottomSheet.show`, `topModalRect` stays null and
/// `ModalHideMixin` falls back to destroying every CN-widget on the host
/// page (safe but blunt). Migrate your sheet call sites to `CNBottomSheet`
/// to get position-aware behavior.
class CNBottomSheet {
  CNBottomSheet._();

  /// Position-aware wrapper for [showModalBottomSheet].
  ///
  /// All parameters are forwarded verbatim. Inside the sheet's builder the
  /// only change is that your widget is wrapped in an invisible probe
  /// publishing live geometry — no impact on appearance, layout, or
  /// gestures.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? backgroundColor,
    String? barrierLabel,
    double? elevation,
    ShapeBorder? shape,
    Clip? clipBehavior,
    BoxConstraints? constraints,
    Color? barrierColor,
    bool isScrollControlled = false,
    double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
    bool useRootNavigator = false,
    bool isDismissible = true,
    bool enableDrag = true,
    bool? showDragHandle,
    bool useSafeArea = false,
    RouteSettings? routeSettings,
    AnimationController? transitionAnimationController,
    Offset? anchorPoint,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: backgroundColor,
      barrierLabel: barrierLabel,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      barrierColor: barrierColor,
      isScrollControlled: isScrollControlled,
      scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      routeSettings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      builder: (ctx) => CNSheetGeometryProbe(child: builder(ctx)),
    );
  }

  /// Position-aware wrapper for [showCupertinoSheet] — the iOS 26
  /// native-style stacked-card sheet. Same probe injection.
  ///
  /// [showDragHandle] draws the framework's own grabber (36x5 at
  /// `CupertinoColors.tertiaryLabel`, values derived from Apple's Figma files
  /// — `sheet.dart:704-708`) and insets the content's top padding to clear it.
  /// Prefer it over painting a grabber inside [pageBuilder]: doing both yields
  /// two pills.
  ///
  /// **Upstream bug this works around (Flutter 3.44.9).**
  /// `showCupertinoSheet` declares `showDragHandle` (`cupertino/sheet.dart:190`)
  /// and documents it (`:143`), but **never forwards it** to the
  /// `CupertinoSheetRoute` it builds — neither the plain branch (`:202-208`)
  /// nor the nested-navigation branch (`:242-250`) passes it along. The
  /// argument is silently accepted and dropped, so calling that function with
  /// `showDragHandle: true` produces no handle.
  ///
  /// `CupertinoSheetRoute` implements the flag correctly (`:645`, `:697`, used
  /// at `:700`), so the non-nested path below pushes the route directly —
  /// exactly what `showCupertinoSheet` does, `rootNavigator: true` included,
  /// minus the dropped argument. Verified by test: the 36x5 grabber is absent
  /// via the convenience function and present via the route.
  ///
  /// [barrierColor] is the one thing the framework route cannot express at all:
  /// `CupertinoSheetRoute` hardcodes `barrierColor` to transparent and
  /// `barrierDismissible` to false (`cupertino/sheet.dart:777,780`), so a sheet
  /// shown through it has no dim and no tap-to-dismiss. Pass a colour to get
  /// both (see [_CNDimmedSheetRoute]); leave it null for the framework's
  /// undimmed presentation. Ignored when [useNestedNavigation] is true.
  static Future<T?> showCupertino<T>({
    required BuildContext context,
    required WidgetBuilder pageBuilder,
    bool useNestedNavigation = false,
    bool enableDrag = true,
    bool showDragHandle = false,
    double? topGap,
    Color? barrierColor,
  }) {
    // `builder:` rather than `scrollableBuilder:` deliberately, on both paths.
    // `scrollableBuilder` doesn't exist on Flutter 3.35 – 3.41.x and using it
    // there hard-breaks the package (Issue #61). `builder:` compiles on every
    // Flutter that has these APIs and stays fully functional on 3.44+ (a
    // compile-time deprecation warning only).
    Widget probed(BuildContext ctx) =>
        CNSheetGeometryProbe(child: pageBuilder(ctx));

    if (useNestedNavigation) {
      // Nested navigation is reachable only through `showCupertinoSheet`, so
      // this path inherits the bug above and cannot show a handle, nor accept a
      // barrier. Stated rather than silently swallowed.
      return showCupertinoSheet<T>(
        context: context,
        useNestedNavigation: true,
        enableDrag: enableDrag,
        topGap: topGap,
        // ignore: deprecated_member_use
        builder: probed,
      );
    }

    final CupertinoSheetRoute<T> route = barrierColor == null
        ? CupertinoSheetRoute<T>(
            // ignore: deprecated_member_use
            builder: probed,
            enableDrag: enableDrag,
            showDragHandle: showDragHandle,
            topGap: topGap,
          )
        : _CNDimmedSheetRoute<T>(
            builder: probed,
            dimColor: barrierColor,
            enableDrag: enableDrag,
            showDragHandle: showDragHandle,
            topGap: topGap,
          );
    return Navigator.of(context, rootNavigator: true).push<T>(route);
  }

  /// Position-aware wrapper for [showCupertinoModalPopup] — the iOS
  /// action-sheet style popup that animates up from the bottom. Same
  /// probe injection. Even though the popup is short, it's still a
  /// PlatformView container conflict source, so wrapping is worth it.
  static Future<T?> showModalPopup<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    ImageFilter? filter,
    Color? barrierColor,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
    bool semanticsDismissible = false,
    RouteSettings? routeSettings,
    Offset? anchorPoint,
  }) {
    return showCupertinoModalPopup<T>(
      context: context,
      filter: filter,
      barrierColor: barrierColor ?? kCupertinoModalBarrierColor,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      semanticsDismissible: semanticsDismissible,
      routeSettings: routeSettings,
      anchorPoint: anchorPoint,
      builder: (ctx) => CNSheetGeometryProbe(child: builder(ctx)),
    );
  }
}

/// [CupertinoSheetRoute] with a real modal barrier.
///
/// The framework route paints no dim and cannot be tapped out of: it overrides
/// `barrierColor` to [CupertinoColors.transparent] and `barrierDismissible` to
/// `false` (`cupertino/sheet.dart:777,780`), on the reasoning that the scaled-
/// back parent card is itself the separation. That holds for a full-height
/// sheet; it does not for a short one, where the uncovered page reads as still
/// interactive. iOS itself dims behind *every* detent of a
/// `UISheetPresentationController` unless `largestUndimmedDetentIdentifier`
/// opts out, so a dim is the platform-correct default, not an embellishment.
///
/// Both of those members are plain `@override` getters on a class carrying no
/// `final`/`base`/`sealed` modifier (`:634`), so re-overriding them in a
/// subclass is the supported extension point — no forking of the route, and the
/// transition, drag-to-dismiss and stacking behaviour are inherited untouched.
class _CNDimmedSheetRoute<T> extends CupertinoSheetRoute<T> {
  _CNDimmedSheetRoute({
    // ignore: deprecated_member_use
    required super.builder,
    required this.dimColor,
    super.enableDrag,
    super.showDragHandle,
    super.topGap,
  });

  /// Barrier fill. Resolved against the ambient brightness by the barrier
  /// itself when this is a [CupertinoDynamicColor].
  final Color dimColor;

  @override
  Color? get barrierColor => dimColor;

  /// Tied to [enableDrag] rather than hardcoded: a sheet the user is forbidden
  /// to drag away must not become dismissible through the back door of a
  /// barrier tap.
  @override
  bool get barrierDismissible => enableDrag;

  /// Must be non-null whenever [barrierDismissible] is true — `ModalRoute`
  /// dereferences it to label the barrier for screen readers. Localized when a
  /// [CupertinoLocalizations] is in scope, with a literal fallback so a host
  /// that ships none still gets a described barrier instead of an assertion.
  @override
  String? get barrierLabel {
    final BuildContext? navContext = navigator?.context;
    if (navContext == null) return 'Dismiss';
    return Localizations.of<CupertinoLocalizations>(
          navContext,
          CupertinoLocalizations,
        )?.modalBarrierDismissLabel ??
        'Dismiss';
  }
}

/// Invisible probe that lives at the root of a `CNBottomSheet` builder and
/// publishes the sheet body's live global rect every frame.
///
/// Implementation: `findRenderObject` -> `RenderBox.localToGlobal` each
/// frame via a self-rescheduling post-frame callback. Drag-to-dismiss
/// updates the rect within one frame (post-frame schedules at end of
/// layout, fires after paint — the rect published reflects the just-
/// rendered frame; consumers via `ValueNotifier` see it on the next
/// frame). On dispose, clears the published rect to null.
/// Invisible widget that publishes its own global rect to
/// [CNTabBarRouteObserver.topModalRect] each frame, then clears it on
/// dispose. Use this manually inside any sheet/popup builder that
/// [CNBottomSheet] doesn't wrap (e.g. `Scaffold.showBottomSheet` for
/// persistent sheets) to opt that sheet into position-aware host-page
/// CN-widget hiding.
class CNSheetGeometryProbe extends StatefulWidget {
  /// Wraps [child] with a transparent per-frame geometry publisher.
  const CNSheetGeometryProbe({super.key, required this.child});

  /// The sheet body. Untouched — the probe adds no UI, constraints, or
  /// gestures.
  final Widget child;

  @override
  State<CNSheetGeometryProbe> createState() => _CNSheetGeometryProbeState();
}

class _CNSheetGeometryProbeState extends State<CNSheetGeometryProbe> {
  Rect? _lastPublished;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void dispose() {
    // Clear the published rect so host-page CN-widgets re-evaluate (and
    // remount, if appropriate) once the sheet is gone.
    if (CNTabBarRouteObserver.topModalRect.value == _lastPublished) {
      CNTabBarRouteObserver.publishTopModalRect(null);
    }
    super.dispose();
  }

  void _scheduleMeasure() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _measure();
      // Re-arm for the next frame so we keep tracking drag updates.
      _scheduleMeasure();
    });
  }

  void _measure() {
    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final rect = ro.localToGlobal(Offset.zero) & ro.size;
    if (rect != _lastPublished) {
      _lastPublished = rect;
      CNTabBarRouteObserver.publishTopModalRect(rect);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
