// Device-only VISUAL verification of the pending-attachment strip: the
// opaque base above the bar and the chromeless (plain) chip remove button,
// both on their REAL native tiers. The + action is invoked through the
// button's own onPressed closure — the exact closure the native UIButton
// invokes through the channel (synthetic pointers never reach a UiKitView;
// proven across tap_record runs). The host only screenshots.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

  testWidgets('pending strip — opaque base + plain chip remove', (tester) async {
    _log('START');
    await tester.pumpWidget(
        const MaterialApp(home: ShowcaseComponentsView()));
    await tester.pump(const Duration(seconds: 2));

    // Invoke the + action the way the native button would: through its own
    // onPressed closure (channel-path invocation — see file docs).
    final addFinder = find.byWidgetPredicate((w) =>
        w is AppBoxKitNativeIconButton &&
        w.glyph == AppBoxKitGlyphs.add);
    expect(addFinder, findsOneWidget);
    tester
        .widget<AppBoxKitNativeIconButton>(addFinder)
        .onPressed!
        .call();
    await tester.pumpAndSettle();

    final fileOption = find.text('Choose file');
    expect(fileOption, findsOneWidget, reason: 'the attach sheet opened');
    _log('P1 sheetUp=true');
    await tester.tap(fileOption);
    await tester.pumpAndSettle();

    expect(find.text('handoff-spec.pdf'), findsOneWidget,
        reason: 'the pick appears as a pending chip');
    final Finder removeButton = find.byWidgetPredicate(
        (w) => w is AppBoxKitNativeIconButton && w.plain);
    expect(removeButton, findsOneWidget,
        reason: 'the chip remove control is the plain button');
    _log('P2 chipUp=true plain=true — holding pose for host screenshot');

    // Hold the pose: the host screenshots the live native strip.
    await tester.pump(const Duration(seconds: 25));
    _log('END');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
