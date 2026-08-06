import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart' show AppBoxKitViewModel;
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/app/app.router.dart';
import 'package:appbox_kit_showcase_app/app/app_data.dart';
import 'package:stacked_services/stacked_services.dart';

class ShowcaseStartupViewModel extends AppBoxKitViewModel {
  final _routerService = locator<RouterService>();

  // Everything that must happen before the app is usable: boots
  // appbox_kit_data (seed backend + snapshot persistence + fake auth), then
  // replaces to the tab shell — the canonical Stacked startup flow. Through
  // AppBoxKitAction so a boot failure (bad seed fixture, backend init) surfaces as
  // a snackbar on the startup view instead of stranding the app on a spinner
  // with an unhandled async error.
  Future runStartupLogic() => action<void>(
        'boot',
        () async {
          await AppData.initialize();
          await _routerService.replaceWith(ShowcaseApplicationShellViewRoute());
        },
      )
          .withErrorSnackbar('Startup failed — please restart the app')
          .completeOnError('Startup failed');
}
