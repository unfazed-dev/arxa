import 'package:stacked/stacked.dart';
import 'package:app_box/app/app.locator.dart';
import 'package:app_box/app/app.router.dart';
import 'package:app_box/app/app_data.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/launch_service.dart';
import 'package:stacked_services/stacked_services.dart';

class ShowcaseStartupViewModel extends BaseViewModel {
  final _routerService = locator<RouterService>();

  // Everything that must happen before the app is usable:
  //  1. load the bundled app config (R3 — values, not literals),
  //  2. boot stacked_kit_data (seed backend + fake auth),
  //  3. first-run auto-launch check (8.13 / J1 — Michelle sees output quality
  //     before typing anything),
  //  4. replace to the app shell.
  Future runStartupLogic() async {
    await locator<ConfigService>().load();
    await AppData.initialize();
    final launch = locator<LaunchService>();
    if (await launch.shouldAutoLaunchShowcase()) {
      launch.markShowcaseLaunched();
    }
    await _routerService.replaceWith(AppShellViewRoute());
  }
}
