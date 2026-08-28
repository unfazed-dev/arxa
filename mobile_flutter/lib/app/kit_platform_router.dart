import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitPlatformPagesMixin, StackedService;

import 'package:arxa_studio_mobile/app/app.router.dart' show StackedRouterWeb;

/// Per-platform native route pages — cupertino on iOS (slide +
/// edge-swipe-back), material on Android (predictive back). Logic lives in
/// the kit's [ArxaKitPlatformPagesMixin]; this shell extends the app's
/// generated [StackedRouterWeb] (per-app, so it can't live in the kit).
class ArxaKitPlatformRouter extends StackedRouterWeb
    with ArxaKitPlatformPagesMixin {
  ArxaKitPlatformRouter({super.navigatorKey});
}

/// The single router instance, in place of the generated `stackedRouter`.
final ArxaKitPlatformRouter kitPlatformRouter =
    ArxaKitPlatformRouter(navigatorKey: StackedService.navigatorKey);
