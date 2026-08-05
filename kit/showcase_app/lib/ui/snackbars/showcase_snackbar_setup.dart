import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:ui_library/ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/common/app_colors.dart';

/// The app's snackbar seat. The kit supplies the severity VARIANTS
/// (`setupKitSnackbars` — one SnackbarConfig per KitSnackbarType); what the
/// APP owns lives here: the default SnackbarConfig in the app's own palette,
/// and any future showcase-specific variants. Registration management sits in
/// the app's ui/ layer alongside bottom_sheets/ and dialogs/ — the kit removes
/// setup boilerplate, it does not take over app presentation.
///
/// Call once from `main()` after `setupLocator` (replaces the bare
/// `setupKitSnackbars()` call; the scaffold gate greps lib/ for that call,
/// which happens inside this function).
void setupShowcaseSnackbars() {
  setupKitSnackbars();

  locator<SnackbarService>().registerSnackbarConfig(
    SnackbarConfig(
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: kcDarkGreyColor,
      messageColor: kcWhite,
      messageTextAlign: TextAlign.center,
      titleColor: kcWhite,
      // stacked's _getMainButtonWidget falls back to white when null — keep
      // the accent visible on the dark default bg.
      mainButtonTextColor: kcSoftYellow,
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
