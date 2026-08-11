import 'dart:math' as math;

import 'package:flutter/material.dart';

/// [FloatingActionButtonLocation] that clears a `Scaffold.bottomSheet` docked
/// at the bottom, instead of straddling it.
///
/// ## Why this exists
///
/// Material's float locations deliberately DOCK the FAB on a bottom sheet's
/// top edge — `FabFloatOffsetY.getOffsetY` ends with
///
/// ```dart
/// if (bottomSheetHeight > 0.0) {
///   fabY = math.min(fabY, contentBottom - bottomSheetHeight - fabHeight / 2.0);
/// }
/// ```
///
/// (`floating_action_button_location.dart:577-579`). The `fabHeight / 2.0` is
/// the straddle: half the button hangs over the sheet. That reads correctly for
/// a transient Material bottom sheet the FAB is anchored to, and incorrectly
/// for a **pinned dock** — a chat composer, a player bar — where it lands on
/// top of the dock's own controls.
///
/// Measured case this was written for: the showcase's Components gallery pins
/// an `AppBoxKitNativeInputBar` as its `bottomSheet`; the gallery FAB sat over
/// the composer's trailing mic button.
///
/// The FAB keeps its accustomed height: the same button previously floated
/// clear because a tab bar inflated `minViewPadding.bottom` (via
/// `AppBoxKitExtendBodyFabLift`), which fed `safeMargin`. When a route's own
/// dock replaces that tab bar, this location supplies the equivalent lift from
/// the dock's measured height instead of a constant.
///
/// ## Usage
///
/// ```dart
/// Scaffold(
///   bottomSheet: const MyComposer(),
///   floatingActionButtonLocation: AppBoxKitFabAboveDock.endFloat,
///   floatingActionButton: const MyFab(),
/// )
/// ```
///
/// With no bottom sheet present this is exactly
/// [FloatingActionButtonLocation.endFloat] — the sheet clause is the only
/// difference — so it is safe to set unconditionally on a scaffold whose dock
/// comes and goes.
class AppBoxKitFabAboveDock extends StandardFabLocation
    with FabEndOffsetX, FabFloatOffsetY {
  const AppBoxKitFabAboveDock._();

  /// End-aligned, floating, clearing any docked bottom sheet.
  static const FloatingActionButtonLocation endFloat =
      AppBoxKitFabAboveDock._();

  @override
  double getOffsetY(
    ScaffoldPrelayoutGeometry scaffoldGeometry,
    double adjustment,
  ) {
    // Take Material's answer first — it handles safe margins and snack bars,
    // neither of which we want to re-derive — then re-apply the bottom-sheet
    // clause without the half-height straddle.
    final double materialY = super.getOffsetY(scaffoldGeometry, adjustment);
    final double sheetHeight = scaffoldGeometry.bottomSheetSize.height;
    if (sheetHeight <= 0.0) return materialY;

    final double clearY = scaffoldGeometry.contentBottom -
        sheetHeight -
        scaffoldGeometry.floatingActionButtonSize.height -
        kFloatingActionButtonMargin +
        adjustment;
    // `min`, matching Material's own composition: each constraint may only
    // push the FAB further UP the screen, never back down over something it
    // has already cleared.
    return math.min(materialY, clearY);
  }

  @override
  String toString() => 'AppBoxKitFabAboveDock.endFloat';
}
