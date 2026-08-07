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
