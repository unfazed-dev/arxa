/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for the startup loading screen. It shows the
/// brand icon, the app title and a spinner while the app initializes.
///
/// Requirements:
/// 1. [Startup loading]
/// Displays a branded loading screen during app startup.
/// 2. [Brand icon]
/// The brand icon (abxImgBrandIcon, the same master that drives the
/// launcher icons and native splash) is the first element on the screen,
/// giving a seamless hand-off from the native splash to the Flutter frame.
/// It renders at the standard 80x80 logical size — the same size the native
/// splash shows the icon (flutter_native_splash.yaml, 320px 4x source).
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_startup_widgets/showcase_startup_loading_widget.dart
library;

import 'package:appbox_kit_showcase_app/ui/common/appbox_kit_app_strings.dart'
    show abxStrStartupAppTitle, abxStrStartupLoading;
import 'package:appbox_kit_showcase_app/ui/common/appbox_kit_assets.dart'
    show abxImgBrandIcon;
import 'package:appbox_kit_showcase_app/ui/common/appbox_kit_ui_helpers.dart'
    show appBoxKitHorizontalSpaceSmall, appBoxKitVerticalSpaceMedium;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitNativeLoadingIndicator;
import 'package:flutter/material.dart';

class ShowcaseStartupLoadingWidget extends StatelessWidget {
  const ShowcaseStartupLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage(abxImgBrandIcon),
              width: 80,
              height: 80,
            ),
            appBoxKitVerticalSpaceMedium,
            Text(
              abxStrStartupAppTitle,
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(abxStrStartupLoading, style: TextStyle(fontSize: 16)),
                appBoxKitHorizontalSpaceSmall,
                // Native-first: the kit's adaptive indicator — M3E morphing
                // loader on Android, Cupertino spinner on iOS (never a stock
                // Material spinner on an iOS surface).
                AppBoxKitNativeLoadingIndicator(size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
