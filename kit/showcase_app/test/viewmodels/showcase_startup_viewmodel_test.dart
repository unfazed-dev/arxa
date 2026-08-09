import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitErrorService, AppBoxKitNotificationService, RouterService;
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/app/app.router.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_viewmodel.dart';

import '../helpers/test_helpers.dart';

void main() {
  // rootBundle (the default fixture reader) and the path_provider channel
  // mock both need the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  // PageRouteInfo needs a fallback for any()/captureAny() on replaceWith.
  registerFallbackValue(ShowcaseApplicationHubViewRoute());

  group('ShowcaseStartupViewModel Tests -', () {
    late MockRouterService router;
    late FakeAppBoxKitNotificationService notifications;

    setUp(() async {
      registerServices();
      registerAppBoxKitActionServices();
      // The real AppBoxKitAction error path logs through the error service's
      // late Talker — initialize it before any op can fail (ui_library
      // playbook).
      await locator<AppBoxKitErrorService>().initialize();
      router = locator<RouterService>() as MockRouterService;
      notifications = locator<AppBoxKitNotificationService>()
          as FakeAppBoxKitNotificationService;
      when(() => router.replaceWith(any())).thenAnswer((_) async => null);
    });
    tearDown(() async {
      AppBoxKitData.resetForTesting();
      await locator.reset();
    });

    test(
        'shell-demos.startup-and-unknown-shells.boot-through-the-startup-shell — boots the data layer and replaces to the application shell',
        () async {
      // given — the VM boots AppData with its default config (snapshot
      // persistence + rootBundle fixtures); point path_provider at a temp dir
      // so the real boot runs headless.
      final tempDir =
          await Directory.systemTemp.createTemp('showcase_startup_test');
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              pathProviderChannel, (call) async => tempDir.path);
      final vm = ShowcaseStartupViewModel();
      addTearDown(vm.dispose);
      // when
      await vm.runStartupLogic();
      // then
      final captured =
          verify(() => router.replaceWith(captureAny())).captured.single;
      expect(captured, isA<ShowcaseApplicationHubViewRoute>());
    });

    test(
        'shell-demos.startup-and-unknown-shells.boot-through-the-startup-shell — a failed boot shows the startup-failed snackbar',
        () async {
      // given — no path_provider channel handler: the default snapshot
      // persistence throws MissingPluginException headless, so the boot fails
      // and the AppBoxKitAction chain must surface it as a snackbar instead of
      // stranding the app on the spinner.
      final vm = ShowcaseStartupViewModel();
      addTearDown(vm.dispose);
      // when
      await vm.runStartupLogic();
      // then
      expect(notifications.messages,
          contains('Startup failed — please restart the app'));
    });
  });
}
