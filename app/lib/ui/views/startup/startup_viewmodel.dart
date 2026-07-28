import 'package:stacked/stacked.dart';
import 'package:app_box/app/app.locator.dart';
import 'package:app_box/app/app.router.dart';
import 'package:app_box/app/app_data.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/credential_service.dart';
import 'package:app_box/services/launch_service.dart';
import 'package:stacked_services/stacked_services.dart';

class StartupViewModel extends BaseViewModel {
  final _routerService = locator<RouterService>();

  // Everything that must happen before the app is usable:
  //  1. load the bundled app config (R3 — values, not literals),
  //  2. boot stacked_kit_data (seed backend + fake auth),
  //  3. hydrate the credential vault — without this the in-memory list and the
  //     Keychain are two sources of truth that disagree after every restart,
  //     and a licence the user already paid for reads as absent,
  //  4. first-run auto-launch check (8.13 / J1 — Michelle sees output quality
  //     before typing anything),
  //  5. replace to the app shell.
  Future runStartupLogic() async {
    await locator<ConfigService>().load();
    await AppData.initialize();
    await locator<CredentialService>().hydrate();
    final launch = locator<LaunchService>();
    if (await launch.shouldAutoLaunchDemo()) {
      launch.markDemoLaunched();
    }
    await _routerService.replaceWith(AppShellViewRoute());
  }
}
