import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart';

import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart'
    show abxPad8, abxPad12, abxPad16, abxPad80, abxRad8;
import 'package:appbox_kit_core/common/appbox_kit_colors.dart';
import 'package:appbox_kit_core/appbox_kit_locator.dart' show appBoxKitLocator;
import 'appbox_kit_snackbar_type.dart';

/// Registers a [SnackbarConfig] for every [AppBoxKitSnackbarType] variant using the
/// kit's default palette, so AppBoxKitAction's auto-process notifications (loading /
/// success / error / warning) render on-brand with no host setup.
///
/// Call once from `main()` after `setupLocator`:
/// ```dart
/// await setupLocator(...);
/// setupAppBoxKitSnackbars();
/// ```
///
/// Hosts can still register additional configs keyed by their own enum, and
/// AppBoxKitActionConfig's snackbar-type fields are `dynamic`, so a call site may pass
/// a host enum variant to override the kit default.
void setupAppBoxKitSnackbars() {
  final snackbarService = appBoxKitLocator<SnackbarService>();

  const duration = Duration(seconds: 5);
  const animationDuration = Duration(milliseconds: 300);
  const margin = EdgeInsets.symmetric(horizontal: abxPad12, vertical: abxPad80);
  const padding = EdgeInsets.symmetric(horizontal: abxPad8, vertical: abxPad16);
  const borderRadius = abxRad8;
  const position = SnackPosition.BOTTOM;
  // ADR 0010 amendment: the scrim is a REAL blur (sigma 20 ≈ Apple's regular
  // material, the AppBoxKitFrostedSurface default) + a plain-dim color fill. GetX
  // only mounts its scrim entry when overlayBlur > 0, always as a
  // BackdropFilter — which cannot cover iOS platform views, so the CN chrome
  // would bleed through the blur sharp. The notification seat
  // (AppBoxKitNotificationService.show) therefore wraps every stacked-snackbar
  // presentation in appBoxKitWithNativeChromeHidden: the native chrome dematerializes
  // (fade + scale) for the snackbar's full lifetime, the blur covers the
  // Flutter scene, and the scrim entry's gesture restores
  // tap-outside-to-dismiss. Callers using SnackbarService directly (bypassing
  // AppBoxKitNotificationService) get the blur WITHOUT the chrome hide — don't.
  const scrimBlur = 20.0;
  const scrimColor = Colors.black54;

  SnackbarConfig appBoxKitConfig({
    required Color backgroundColor,
    required Color foreground,
    required IconData icon,
  }) =>
      SnackbarConfig(
        snackPosition: position,
        backgroundColor: backgroundColor,
        overlayBlur: scrimBlur,
        overlayColor: scrimColor,
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
    variant: AppBoxKitSnackbarType.appBoxKitAutoProcessInfo,
    config: appBoxKitConfig(
      backgroundColor: AppBoxKitColors.surface2,
      foreground: AppBoxKitColors.muted,
      icon: Icons.info_outline,
    ),
  );
  snackbarService.registerCustomSnackbarConfig(
    variant: AppBoxKitSnackbarType.appBoxKitAutoProcessSuccess,
    config: appBoxKitConfig(
      backgroundColor: AppBoxKitColors.good,
      foreground: AppBoxKitColors.onAccent,
      icon: Icons.check_circle_outline,
    ),
  );
  snackbarService.registerCustomSnackbarConfig(
    variant: AppBoxKitSnackbarType.appBoxKitAutoProcessError,
    config: appBoxKitConfig(
      backgroundColor: AppBoxKitColors.danger,
      foreground: Colors.white,
      icon: Icons.error_outline_rounded,
    ),
  );
  snackbarService.registerCustomSnackbarConfig(
    variant: AppBoxKitSnackbarType.appBoxKitAutoProcessWarning,
    config: appBoxKitConfig(
      backgroundColor: const Color(0xFFFFF7ED),
      foreground: AppBoxKitColors.warn,
      icon: Icons.warning_amber_outlined,
    ),
  );
}
