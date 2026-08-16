// Device-only VISUAL verification of the pending-attachment chip in DARK
// mode — reproduces the user's screenshot (02:17.06): the chip must be a
// fully OPAQUE rounded fill with no left-side luminance artifact.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:appbox_kit_core/appbox_kit_core.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.dart';

void _log(String line) {
  File('${Directory.systemTemp.path}/chips.log').writeAsStringSync(
    '$line\n',
    mode: FileMode.append,
  );
  // ignore: avoid_print
  print('CHIPS $line');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setupAppBoxKitUiServices();
  if (!appBoxKitLocator.isRegistered<AppBoxKitAudioRecorderService>()) {
    appBoxKitLocator.registerLazySingleton<AppBoxKitAudioRecorderService>(
        () => AppBoxKitRecordAudioRecorderService());
  }
  if (!appBoxKitLocator.isRegistered<AppBoxKitErrorService>()) {
    appBoxKitLocator
        .registerLazySingleton<AppBoxKitErrorService>(() => AppBoxKitErrorService());
  }
  if (!appBoxKitLocator.isRegistered<AppBoxKitNotificationService>()) {
    appBoxKitLocator.registerLazySingleton<AppBoxKitNotificationService>(
        () => AppBoxKitNotificationService());
  }
  appBoxKitLocator<AppBoxKitErrorService>().initialize();

  testWidgets('dark-mode chip — opaque fill, no luminance artifact',
      (tester) async {
    _log('START dark');
    await tester.pumpWidget(MaterialApp(
      theme: appBoxKitDarkTheme(),
      darkTheme: appBoxKitDarkTheme(),
      themeMode: ThemeMode.dark,
      home: const ShowcaseComponentsView(),
    ));
    await tester.pump(const Duration(seconds: 2));

    final addFinder = find.byWidgetPredicate(
        (w) => w is AppBoxKitNativeIconButton && w.glyph == AppBoxKitGlyphs.add);
    tester.widget<AppBoxKitNativeIconButton>(addFinder).onPressed!.call();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('handoff-spec.pdf'), findsOneWidget,
        reason: 'the pick appears as a pending chip');
    _log('P2 chipUp=true (dark) — holding pose');

    await tester.pump(const Duration(seconds: 25));
    _log('END');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
