import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Smoke-test rows for the kit's transient-feedback surface, routed through
/// KitNotificationService so Android renders the M3E snackbar (variant
/// derived from kind, configs from setupKitSnackbars) and iOS renders CNToast
/// — no Material snackbar leaks on iOS.
///
/// Row 1: one notification per [KitNotificationKind] (warning rides
/// `position: center` to demo the kit-owned center pill overlay).
///
/// Row 2: the stacked-SnackbarService tiers. `actionLabel` is the ONLY thing
/// that promotes iOS from CNToast to the stacked snackbar (CNToast is
/// fire-and-forget and cannot host an action), so the Undo button shows the
/// real `showCustomSnackBar` path on both platforms; Titled adds `title:`;
/// Bottom pins to `KitToastPosition.bottom`.
/// KitNativeIconButton so each button shape-morphs on press (Android M3E)
/// and renders liquid glass on iOS 26 — matching every other kit icon
/// button. The semantic tint (muted/good/danger/warn) flows through `color`.
class ShowcaseSnackbarSmokeRowWidget extends StatelessWidget {
  const ShowcaseSnackbarSmokeRowWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = locator<KitNotificationService>();
    Widget snackbarButton(
      KitGlyph glyph,
      Color color,
      KitNotificationKind kind,
      String label, {
      KitToastPosition position = KitToastPosition.top,
      String? title,
      String? actionLabel,
    }) =>
        KitNativeIconButton(
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
                    kind: KitNotificationKind.info, context: context),
            context: context,
          ),
        );

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            snackbarButton(KitGlyphs.info, KitColors.muted,
                KitNotificationKind.info, 'Info'),
            horizontalSpaceSmall,
            snackbarButton(KitGlyphs.success, KitColors.good,
                KitNotificationKind.success, 'Success'),
            horizontalSpaceSmall,
            snackbarButton(KitGlyphs.error, KitColors.danger,
                KitNotificationKind.error, 'Error'),
            horizontalSpaceSmall,
            snackbarButton(KitGlyphs.warning, KitColors.warn,
                KitNotificationKind.warning, 'Warning',
                position: KitToastPosition.center),
          ],
        ),
        verticalSpaceSmall,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            snackbarButton(KitGlyphs.compose, KitColors.muted,
                KitNotificationKind.success, 'Changes saved',
                title: 'Notes'),
            horizontalSpaceSmall,
            snackbarButton(KitGlyphs.error, KitColors.danger,
                KitNotificationKind.error, 'Note deleted',
                actionLabel: 'Undo'),
            horizontalSpaceSmall,
            snackbarButton(KitGlyphs.info, KitColors.muted,
                KitNotificationKind.info, 'Bottom',
                position: KitToastPosition.bottom),
          ],
        ),
      ],
    );
  }
}
