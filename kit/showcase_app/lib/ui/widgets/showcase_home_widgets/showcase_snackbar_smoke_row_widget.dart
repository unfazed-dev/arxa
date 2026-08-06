import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Smoke-test rows for the kit's transient-feedback surface, routed through
/// AppBoxKitNotificationService so Android renders the M3E snackbar (variant
/// derived from kind, configs from setupAppBoxKitSnackbars) and iOS renders CNToast
/// — no Material snackbar leaks on iOS.
///
/// Row 1: one notification per [AppBoxKitNotificationKind] (warning rides
/// `position: center` to demo the kit-owned center pill overlay).
///
/// Row 2: the stacked-SnackbarService tiers. `actionLabel` is the ONLY thing
/// that promotes iOS from CNToast to the stacked snackbar (CNToast is
/// fire-and-forget and cannot host an action), so the Undo button shows the
/// real `showCustomSnackBar` path on both platforms; Titled adds `title:`;
/// Bottom pins to `AppBoxKitToastPosition.bottom`.
/// AppBoxKitNativeIconButton so each button shape-morphs on press (Android M3E)
/// and renders liquid glass on iOS 26 — matching every other kit icon
/// button. The semantic tint (muted/good/danger/warn) flows through `color`.
class ShowcaseSnackbarSmokeRowWidget extends StatelessWidget {
  const ShowcaseSnackbarSmokeRowWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = appBoxKitLocator<AppBoxKitNotificationService>();
    Widget snackbarButton(
      AppBoxKitGlyph glyph,
      Color color,
      AppBoxKitNotificationKind kind,
      String label, {
      AppBoxKitToastPosition position = AppBoxKitToastPosition.top,
      String? title,
      String? actionLabel,
    }) =>
        AppBoxKitNativeIconButton(
          glyph: glyph,
          color: color,
          onPressed: () => notifications.show(
            label,
            kind: kind,
            position: position,
            title: title,
            actionLabel: actionLabel,
            onAction: actionLabel == null
                ? null
                : () => notifications.show('Undo tapped',
                    kind: AppBoxKitNotificationKind.info, context: context),
            context: context,
          ),
        );

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            snackbarButton(AppBoxKitGlyphs.info, AppBoxKitColors.muted,
                AppBoxKitNotificationKind.info, 'Info'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.success, AppBoxKitColors.good,
                AppBoxKitNotificationKind.success, 'Success'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.error, AppBoxKitColors.danger,
                AppBoxKitNotificationKind.error, 'Error'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.warning, AppBoxKitColors.warn,
                AppBoxKitNotificationKind.warning, 'Warning',
                position: AppBoxKitToastPosition.center),
          ],
        ),
        appBoxKitVerticalSpaceSmall,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            snackbarButton(AppBoxKitGlyphs.compose, AppBoxKitColors.muted,
                AppBoxKitNotificationKind.success, 'Changes saved',
                title: 'Notes'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.error, AppBoxKitColors.danger,
                AppBoxKitNotificationKind.error, 'Note deleted',
                actionLabel: 'Undo'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.info, AppBoxKitColors.muted,
                AppBoxKitNotificationKind.info, 'Bottom',
                position: AppBoxKitToastPosition.bottom),
          ],
        ),
      ],
    );
  }
}
