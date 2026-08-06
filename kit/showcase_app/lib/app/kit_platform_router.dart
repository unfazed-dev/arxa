import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart' show AppBoxKitPlatformPagesMixin;
import 'package:stacked_services/stacked_services.dart' show StackedService;

import 'package:appbox_kit_showcase_app/app/app.router.dart' show StackedRouterWeb;

/// Per-platform native route pages for the showcase — cupertino on iOS (slide
/// + edge-swipe-back), material on Android (→ predictive back), no-animation on
/// web. All logic lives in the kit's [AppBoxKitPlatformPagesMixin]; this is just the
/// app-specific shell (it must extend the showcase's generated
/// `StackedRouterWeb`, which is per-app, so it can't live in the kit itself).
class AppBoxKitPlatformRouter extends StackedRouterWeb with AppBoxKitPlatformPagesMixin {
  AppBoxKitPlatformRouter({super.navigatorKey});
}

/// The single router instance the app uses, in place of the generated
/// `stackedRouter` global.
final AppBoxKitPlatformRouter kitPlatformRouter =
    AppBoxKitPlatformRouter(navigatorKey: StackedService.navigatorKey);
