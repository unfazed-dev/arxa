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
/// Fires every notification kind and snackbar tier via ArxaKitNotificationService.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_home_widgets/showcase_snackbar_smoke_row_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseSnackbarSmokeRowWidget extends StatelessWidget {
  const ShowcaseSnackbarSmokeRowWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = arxaKitLocator<ArxaKitNotificationService>();
    // Resolve per theme: the fixed light ramp reads dim-to-invisible on the
    // dark glass after a theme flip (the colour crosses to the native tier
    // as the glyph/tint).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? ArxaKitDarkColors.ink3 : ArxaKitColors.muted;
    final good = dark ? ArxaKitDarkColors.good : ArxaKitColors.good;
    final danger = dark ? ArxaKitDarkColors.danger : ArxaKitColors.danger;
    final warn = dark ? ArxaKitDarkColors.warn : ArxaKitColors.warn;
    Widget snackbarButton(
      ArxaKitGlyph glyph,
      Color color,
      ArxaKitNotificationKind kind,
      String label, {
      ArxaKitToastPosition position = ArxaKitToastPosition.top,
      String? title,
      String? actionLabel,
    }) =>
        ArxaKitNativeIconButton(
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
                    kind: ArxaKitNotificationKind.info, context: context),
            context: context,
          ),
        );

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            snackbarButton(ArxaKitGlyphs.info, muted,
                ArxaKitNotificationKind.info, 'Info'),
            arxaKitHorizontalSpaceSmall,
            snackbarButton(ArxaKitGlyphs.success, good,
                ArxaKitNotificationKind.success, 'Success'),
            arxaKitHorizontalSpaceSmall,
            snackbarButton(ArxaKitGlyphs.error, danger,
                ArxaKitNotificationKind.error, 'Error'),
            arxaKitHorizontalSpaceSmall,
            snackbarButton(ArxaKitGlyphs.warning, warn,
                ArxaKitNotificationKind.warning, 'Warning',
                position: ArxaKitToastPosition.center),
          ],
        ),
        arxaKitVerticalSpaceSmall,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            snackbarButton(ArxaKitGlyphs.compose, muted,
                ArxaKitNotificationKind.success, 'Changes saved',
                title: 'Notes'),
            arxaKitHorizontalSpaceSmall,
            snackbarButton(ArxaKitGlyphs.error, danger,
                ArxaKitNotificationKind.error, 'Note deleted',
                actionLabel: 'Undo'),
            arxaKitHorizontalSpaceSmall,
            snackbarButton(ArxaKitGlyphs.info, muted,
                ArxaKitNotificationKind.info, 'Bottom',
                position: ArxaKitToastPosition.bottom),
          ],
        ),
      ],
    );
  }
}
