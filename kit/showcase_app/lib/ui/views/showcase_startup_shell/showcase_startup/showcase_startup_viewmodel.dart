/// The startup leaf's viewmodel (route `/showcase/startup-shell/startup`). The
/// view calls actions in and reads streams out: when the view is ready, it
/// fires the one boot action, and nothing streams back — the route simply
/// replaces onward. The viewmodel never touches the view — swap the UI for any
/// other and this file stays unchanged.
///
/// This is the business logic for the screen the app shows while it boots. It
/// seeds the data layer and fake auth, then routes to the application shell —
/// and if the boot fails, it surfaces a message instead of stranding the app
/// on a spinner.
///
/// Requirements:
/// 1. [Boot] — shell-demos.startup-and-unknown-shells.boot-through-the-startup-shell
/// The data layer and fake auth are seeded, then the route replaces to the application shell.
/// 2. [Boot failure] — shell-demos.startup-and-unknown-shells.boot-through-the-startup-shell
/// A boot failure surfaces a message instead of stranding the app on a spinner.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │       startup view       │
///   └──────────────────────────┘
///   ACT ▼
///   [1]
///   ┌──────────────────────────┐
///   │    startup viewmodel     │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
///  actions (ACT)
///    1. runStartupLogic
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitViewModel, RouterService;
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/app/app.router.dart';
import 'package:appbox_kit_showcase_app/app/app_data.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_startup_enums/enums.dart';

class ShowcaseStartupViewModel extends AppBoxKitViewModel {
  // ── Setup ──────────────────────────────────────────────────────────────────

  final _routerService = locator<RouterService>();

  // ── Actions ──────────────────────────────────────────────────

  /// [1. Boot][2. Boot failure]
  /// Boots the kit's data (seed backend, persistence, fake auth), then swaps
  /// to the tab shell; a boot failure shows a snackbar, not a stuck spinner.
  Future runStartupLogic() => abxActionHub.send<void>(
        ShowcaseStartupOp.boot.name,
        () async {
          await AppData.initialize();
          await _routerService.replaceWith(ShowcaseApplicationShellViewRoute());
        },
        errorNotification: 'Startup failed — please restart the app',
        errorMessage: 'Startup failed',
      );
}
