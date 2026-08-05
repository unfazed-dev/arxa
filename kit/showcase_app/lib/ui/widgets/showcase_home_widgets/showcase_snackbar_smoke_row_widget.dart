import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Smoke-test row firing one notification per [KitNotificationKind]. Routed
/// through KitNotificationService so Android renders the M3E snackbar (variant
/// derived from kind, configs from setupKitSnackbars) and iOS renders CNToast
/// — no Material snackbar leaks on iOS.
/// KitNativeIconButton so each button shape-morphs on press (Android M3E)
/// and renders liquid glass on iOS 26 — matching every other kit icon
/// button. The semantic tint (muted/good/danger/warn) flows through `color`.
class ShowcaseSnackbarSmokeRowWidget extends StatelessWidget {
  const ShowcaseSnackbarSmokeRowWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Widget snackbarButton(
      KitGlyph glyph,
      Color color,
      KitNotificationKind kind,
      String label, {
      KitToastPosition position = KitToastPosition.top,
    }) =>
        KitNativeIconButton(
          glyph: glyph,
          color: color,
          onPressed: () => locator<KitNotificationService>().show(
            label,
            kind: kind,
            position: position,
            context: context,
          ),
        );

    return Row(
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
    );
  }
}
