import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:appbox_kit_core/common/kit_app_constants.dart'
    show kPad8, kPad12, kPad16, kPad80, kRad8;
import 'package:appbox_kit_core/common/kit_colors.dart';
import 'package:appbox_kit_core/kit_locator.dart' show locator;
import 'kit_snackbar_type.dart';

/// Registers a [SnackbarConfig] for every [KitSnackbarType] variant using the
/// kit's default palette, so KitAction's auto-process notifications (loading /
/// success / error / warning) render on-brand with no host setup.
///
/// Call once from `main()` after `setupLocator`:
/// ```dart
/// await setupLocator(...);
/// setupKitSnackbars();
/// ```
///
/// Hosts can still register additional configs keyed by their own enum, and
/// KitActionConfig's snackbar-type fields are `dynamic`, so a call site may pass
/// a host enum variant to override the kit default.
void setupKitSnackbars() {
  final snackbarService = locator<SnackbarService>();

  const duration = Duration(seconds: 5);
  const animationDuration = Duration(milliseconds: 300);
  const margin = EdgeInsets.symmetric(horizontal: kPad12, vertical: kPad80);
  const padding = EdgeInsets.symmetric(horizontal: kPad8, vertical: kPad16);
  const borderRadius = kRad8;
  const position = SnackPosition.BOTTOM;
  // ADR 0010 (plain-dim scrims): no blur scrim. GetX renders its scrim entry
  // only when overlayBlur > 0 and always as a BackdropFilter — which cannot
  // cover iOS platform views (the original bleed bug) and forces chrome to
  // hide. With no scrim, native chrome can stay mounted behind the snackbar.
  // Cost: tap-outside-to-dismiss goes away (swipe + auto-dismiss remain).

  SnackbarConfig kitConfig({
    required Color backgroundColor,
    required Color foreground,
    required IconData icon,
  }) =>
      SnackbarConfig(
        snackPosition: position,
        backgroundColor: backgroundColor,
        messageColor: foreground,
        messageTextAlign: TextAlign.center,
        titleColor: foreground,
        // stacked's _getMainButtonWidget falls back to white when this is null —
        // invisible on the pale warning bg. Reuse the per-variant foreground
        // (already chosen for contrast against this background).
        mainButtonTextColor: foreground,
        borderRadius: borderRadius,
        margin: margin,
        padding: padding,
        duration: duration,
        animationDuration: animationDuration,
        isDismissible: true,
        dismissDirection: DismissDirection.vertical,
        forwardAnimationCurve: Curves.easeInCubic,
        reverseAnimationCurve: Curves.easeOutCubic,
        icon: Icon(icon, color: foreground),
      );

  snackbarService.registerCustomSnackbarConfig(
    variant: KitSnackbarType.kitAutoProcessInfo,
    config: kitConfig(
      backgroundColor: KitColors.surface2,
      foreground: KitColors.muted,
      icon: Icons.info_outline,
    ),
  );
  snackbarService.registerCustomSnackbarConfig(
    variant: KitSnackbarType.kitAutoProcessSuccess,
    config: kitConfig(
      backgroundColor: KitColors.good,
      foreground: KitColors.onAccent,
      icon: Icons.check_circle_outline,
    ),
  );
  snackbarService.registerCustomSnackbarConfig(
    variant: KitSnackbarType.kitAutoProcessError,
    config: kitConfig(
      backgroundColor: KitColors.danger,
      foreground: Colors.white,
      icon: Icons.error_outline_rounded,
    ),
  );
  snackbarService.registerCustomSnackbarConfig(
    variant: KitSnackbarType.kitAutoProcessWarning,
    config: kitConfig(
      backgroundColor: const Color(0xFFFFF7ED),
      foreground: KitColors.warn,
      icon: Icons.warning_amber_outlined,
    ),
  );
}
