import 'package:stacked/stacked.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/app/app.router.dart';
import 'package:appbox_kit_showcase_app/app/app_data.dart';
import 'package:stacked_services/stacked_services.dart';

class ShowcaseStartupViewModel extends BaseViewModel {
  final _routerService = locator<RouterService>();

  // Everything that must happen before the app is usable: boots
  // appbox_kit_data (seed backend + snapshot persistence + fake auth), then
  // replaces to the tab shell — the canonical Stacked startup flow.
  Future runStartupLogic() async {
    await AppData.initialize();
    await _routerService.replaceWith(ShowcaseApplicationShellViewRoute());
  }
}
