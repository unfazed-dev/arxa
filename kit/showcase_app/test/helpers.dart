// Shared harness for the showcase widget tests: disk-backed assets, the kit
// service registrations, data-layer boot over the real fixtures, and the
// router pump. Each test file was carrying its own copy of all four.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart'
    show setupLocator;
import 'package:appbox_kit_showcase_app/app/app.router.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_showcase_app/app/app_data.dart';
import 'package:appbox_kit_showcase_app/services/facades/showcase_notes_facade.dart';
import 'package:stacked_services/stacked_services.dart';

/// Package-asset keys map straight onto this package's source tree.
class DiskAssetReader implements KitAssetReader {
  static const _prefix = 'packages/appbox_kit_showcase_app/';
  @override
  Future<String> readString(String path) async {
    final stripped =
        path.startsWith(_prefix) ? path.substring(_prefix.length) : path;
    return File(stripped).readAsString();
  }
}

/// Registers the app's real services for widget tests — the generated
/// `setupLocator()` (from `@StackedApp` dependencies), same wiring as `main()`.
Future<void> registerKitTestServices() =>
    setupLocator(stackedRouter: stackedRouter);

/// Boots appbox_kit_data off the bundled fixtures (seed backend, fake auth).
Future<void> initShowcase({bool signedIn = false}) async {
  await AppData.initialize(
    config: const KitDataConfig(
      backend: KitDataBackend.seed,
      auth: KitAuthConfig(fakeUsersAsset: AppData.fakeUsersAsset),
    ),
    assetReader: DiskAssetReader(),
  );
  if (signedIn) await signInEvan();
}

Future<void> signInEvan() => locator<ShowcaseNotesFacade>()
    .auth
    .signInWithEmailPassword(email: 'evan@seed.local', password: 'x');

Future<void> teardownShowcase() async {
  KitData.resetForTesting();
  await locator.reset();
}

/// Router futures only complete when their route pops — never await them
/// inside testWidgets; pump frames instead.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps a fresh [StackedRouterWeb] app showing [ShowcaseApplicationShellView].
Future<StackedRouterWeb> bootShell(WidgetTester tester) async {
  // Phone-sized surface (390×844@3x): the default 800×600 test view makes
  // ScreenTypeLayout pick the TABLET variant — which is an intentional v1
  // stub. The implemented UI lives in the mobile variants.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = StackedRouterWeb();
  locator<RouterService>().setRouter(router);
  await tester.pumpWidget(
    MaterialApp.router(
      // Boot straight into the shell — ShowcaseStartupView (the app's real initial
      // route) would re-run AppData.initialize on its post-frame callback.
      routerDelegate: router.delegate(
        initialRoutes: [ShowcaseApplicationShellViewRoute()],
      ),
      routeInformationParser: router.defaultRouteParser(),
    ),
  );
  await settle(tester);
  return router;
}
