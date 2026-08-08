import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// The app's snackbar seat. The kit supplies the severity VARIANTS
/// (`setupAppBoxKitSnackbars` — one SnackbarConfig per AppBoxKitSnackbarType); what the
/// APP owns lives here: the default SnackbarConfig in the app's own palette,
/// and any future showcase-specific variants. Registration management sits in
/// the app's ui/ layer alongside bottom_sheets/ and dialogs/ — the kit removes
/// setup boilerplate, it does not take over app presentation.
///
/// Call once from `main()` after `setupLocator` (replaces the bare
/// `setupAppBoxKitSnackbars()` call; the scaffold gate greps lib/ for that call,
/// which happens inside this function).
void setupShowcaseSnackbars() {
  setupAppBoxKitSnackbars();

  appBoxKitLocator<SnackbarService>().registerSnackbarConfig(
    SnackbarConfig(
      snackPosition: SnackPosition.BOTTOM,

      overlayBlur: 20,
      overlayColor: Colors.black54,
      messageTextAlign: TextAlign.center,
      // stacked's _getMainButtonWidget falls back to white when null — keep
      // the accent visible on the dark default bg.
      borderRadius: 10,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 80),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      duration: const Duration(seconds: 5),
      animationDuration: const Duration(milliseconds: 300),
      isDismissible: true,
      dismissDirection: DismissDirection.vertical,
      forwardAnimationCurve: Curves.easeInCubic,
      reverseAnimationCurve: Curves.easeOutCubic,
    ),
  );
}
