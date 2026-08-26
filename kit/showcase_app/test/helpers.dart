// Shared harness for the showcase widget tests: disk-backed assets, the kit
// service registrations, data-layer boot over the real fixtures, and the
// router pump. Each test file was carrying its own copy of all four.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_showcase_app/app/app.locator.dart' show setupLocator;
import 'package:arxa_kit_showcase_app/app/app.router.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_showcase_app/app/app_data.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';

/// Package-asset keys map straight onto this package's source tree.
class DiskAssetReader implements ArxaKitAssetReader {
  static const _prefix = 'packages/arxa_kit_showcase_app/';
  @override
  Future<String> readString(String path) async {
    final stripped =
        path.startsWith(_prefix) ? path.substring(_prefix.length) : path;
    return File(stripped).readAsString();
  }
}

/// Registers the app's real services for widget tests — the generated
/// `setupLocator()` (from `@StackedApp` dependencies) plus the kit's UI
/// services, same wiring as `main()`.
Future<void> registerKitTestServices() async {
  await setupLocator(stackedRouter: stackedRouter);
  setupArxaKitUiServices();
}

/// Boots arxa_kit_data off the bundled fixtures (seed backend, fake auth).
Future<void> initShowcase({bool signedIn = false}) async {
  await AppData.initialize(
    config: const ArxaKitDataConfig(
      backend: ArxaKitDataBackend.seed,
      auth: ArxaKitAuthConfig(fakeUsersAsset: AppData.fakeUsersAsset),
    ),
    assetReader: DiskAssetReader(),
  );
  if (signedIn) await signInEvan();
}

Future<void> signInEvan() => arxaKitLocator<ShowcaseNotesFacadeService>()
    .auth
    .signInWithEmailPassword(email: 'evan@seed.local', password: 'x');

Future<void> teardownShowcase() async {
  ArxaKitData.resetForTesting();
  await arxaKitLocator.reset();
}

/// Router futures only complete when their route pops — never await them
/// inside testWidgets; pump frames instead.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps a fresh [StackedRouterWeb] app showing [ShowcaseApplicationHubView].
Future<StackedRouterWeb> bootShell(WidgetTester tester) async {
  // Phone-sized surface (390×844@3x): the default 800×600 test view makes
  // ScreenTypeLayout pick the TABLET variant — which is an intentional v1
  // stub. The implemented UI lives in the mobile variants.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = StackedRouterWeb();
  arxaKitLocator<RouterService>().setRouter(router);
  await tester.pumpWidget(
    MaterialApp.router(
      // Boot straight into the shell — ShowcaseStartupView (the app's real initial
      // route) would re-run AppData.initialize on its post-frame callback.
      routerDelegate: router.delegate(
        initialRoutes: [ShowcaseApplicationHubViewRoute()],
      ),
      routeInformationParser: router.defaultRouteParser(),
    ),
  );
  await settle(tester);
  return router;
}
