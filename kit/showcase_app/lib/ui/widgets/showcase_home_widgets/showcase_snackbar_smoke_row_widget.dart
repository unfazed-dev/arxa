/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for a snackbar smoke-test. It lays out two rows
/// of icon buttons that fire the kit's notification surface across every kind
/// (info, success, error, warning) and every stacked-snackbar tier (titled,
/// action, bottom).
///
/// Requirements:
/// 1. [Notification smoke test]
/// Fires every notification kind and snackbar tier via AppBoxKitNotificationService.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_home_widgets/showcase_snackbar_smoke_row_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseSnackbarSmokeRowWidget extends StatelessWidget {
  const ShowcaseSnackbarSmokeRowWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = appBoxKitLocator<AppBoxKitNotificationService>();
    // Resolve per theme: the fixed light ramp reads dim-to-invisible on the
    // dark glass after a theme flip (the colour crosses to the native tier
    // as the glyph/tint).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? AppBoxKitDarkColors.ink3 : AppBoxKitColors.muted;
    final good = dark ? AppBoxKitDarkColors.good : AppBoxKitColors.good;
    final danger = dark ? AppBoxKitDarkColors.danger : AppBoxKitColors.danger;
    final warn = dark ? AppBoxKitDarkColors.warn : AppBoxKitColors.warn;
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
            snackbarButton(AppBoxKitGlyphs.info, muted,
                AppBoxKitNotificationKind.info, 'Info'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.success, good,
                AppBoxKitNotificationKind.success, 'Success'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.error, danger,
                AppBoxKitNotificationKind.error, 'Error'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.warning, warn,
                AppBoxKitNotificationKind.warning, 'Warning',
                position: AppBoxKitToastPosition.center),
          ],
        ),
        appBoxKitVerticalSpaceSmall,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            snackbarButton(AppBoxKitGlyphs.compose, muted,
                AppBoxKitNotificationKind.success, 'Changes saved',
                title: 'Notes'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.error, danger,
                AppBoxKitNotificationKind.error, 'Note deleted',
                actionLabel: 'Undo'),
            appBoxKitHorizontalSpaceSmall,
            snackbarButton(AppBoxKitGlyphs.info, muted,
                AppBoxKitNotificationKind.info, 'Bottom',
                position: AppBoxKitToastPosition.bottom),
          ],
        ),
      ],
    );
  }
}
