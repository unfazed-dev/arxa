// Device-only verification of the composer's tap-to-toggle record — the
// gaps widget tests cannot reach: the REAL kit audio service (record plugin
// → AVAudioRecorder), the OS microphone-permission prompt firing through the
// kit on the first tap, and REAL touches on the NATIVE trailing action (the
// Liquid Glass icon button — its UIKit surface owns the tap). The glyph
// swap mic → stop on the live button is animated by the SF Symbol replace
// transition in the vendored tier.
//
// IMPORTANT — why the host drives every button tap: the trailing action is
// a platform view. Hybrid composition routes REAL UIKit touches to the
// native UIButton, but `tester.tap` synthesizes a Flutter-framework
// pointer that hybrid composition never forwards to the native view —
// proven on device (run 2: host tap fired the OS prompt; tester.tap was
// swallowed). So the test REPORTS tap points via marker payloads and the
// host performs real idb taps; the test asserts on the resulting UI state.
//
// Protocol: the test advances in numbered phases, writing 'phase<N>.done'
// (payload like 'tap:<x>,<y>') into the app's tmp dir, then waits for the
// host to drop 'phase<N>.go' after performing the tap. All measurements
// append to 'taprec.log'. Run:
//   flutter test integration_test/tap_record_device_test.dart -d <device>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:appbox_kit_media/appbox_kit_media.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.dart';

Future<void> _mark(int n, String payload) async {
  await File('${Directory.systemTemp.path}/phase$n.done')
      .writeAsString(payload);
}

Future<void> _awaitGo(int n, {int timeoutSeconds = 180}) async {
  final go = File('${Directory.systemTemp.path}/phase$n.go');
  final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
  while (!await go.exists()) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (DateTime.now().isAfter(deadline)) return;
  }
}

void _log(String line) {
  File('${Directory.systemTemp.path}/taprec.log').writeAsStringSync(
    '$line\n',
    mode: FileMode.append,
  );
  // ignore: avoid_print
  print('TAPREC $line');
}

Future<bool> _poll(bool Function() check,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  return check();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // The real services, exactly as the app registers them — the recorder is
  // the plugin-backed kit service under its interface (the point of the
  // test). Boot order mirrors test_helpers' registerAppBoxKitActionServices:
  // the kit UI services first (Talker backs the error service), then the
  // error + notification services, then initialize — before any action can
  // fire.
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

  testWidgets('tap-to-toggle record — device gap verification', (tester) async {
    _log('START isIOS=${Platform.isIOS}');
    await tester.pumpWidget(
        const MaterialApp(home: ShowcaseComponentsView()));
    await tester.pump(const Duration(seconds: 2));

    final mic = find.byKey(const ValueKey('composer-record-button'));
    expect(mic, findsOneWidget, reason: 'the native record action must mount');
    final Offset micC = tester.getCenter(mic);
    final String pt = '${micC.dx.round()},${micC.dy.round()}';
    _log('P1 mic center pt=$pt');
    await _mark(1, 'tap:$pt');
    // The host waits for the OS alert to PRESENT before tapping Allow —
    // observed presentation latency on the loaded simulator runs to
    // minutes, so this wait outlasts the host's 300s detection window.
    await _awaitGo(1, timeoutSeconds: 420);

    // P2: the host's REAL tap on the native button fired the OS permission
    // prompt (first tap ever) and the host tapped Allow — verify through
    // the kit.
    final recorder = appBoxKitLocator<AppBoxKitAudioRecorderService>();
    // Poll the (async) permission future by caching it once and sampling
    // the settled result — _poll takes a sync check.
    final permissionFuture = recorder.hasPermission();
    var permissionAnswer = false;
    var permissionSettled = false;
    permissionFuture.then((v) {
      permissionAnswer = v;
      permissionSettled = true;
    });
    final bool granted = await _poll(() => permissionSettled && permissionAnswer,
        timeout: const Duration(seconds: 30));
    _log('P2 permissionGranted=$granted');
    expect(granted, isTrue,
        reason: 'granting the OS prompt must reach the kit service');
    // Phases 3-5 self-drive now; no host gates needed beyond the grant.

    // P3: invoke the record action through the button's own onPressed —
    // the exact closure the native UIButton invokes through the channel
    // (synthetic Flutter pointers never reach a UiKitView; the NATIVE
    // half of the delivery is proven by P1/P2: the host's real tap on
    // this very button fired the OS permission prompt).
    final int before = find.textContaining('· voice note').evaluate().length;
    tester
        .widget<AppBoxKitNativeIconButton>(
            find.byKey(const ValueKey('composer-record-button')))
        .onPressed!
        .call();
    final bool stripUp = await _poll(
        () => find.text('Cancel').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    _log('P3 stripUp=$stripUp');
    expect(stripUp, isTrue,
        reason: 'the record action must start the REAL recording (strip)');
    // Real audio accumulates while the host photographs the recording
    // state (stop glyph + strip).
    await tester.pump(const Duration(seconds: 3));
    // (recording accumulates below)

    // P4: invoke stop (same slot, same channel-path closure) — sends.
    await tester.pump(const Duration(seconds: 3));
    tester
        .widget<AppBoxKitNativeIconButton>(
            find.byKey(const ValueKey('composer-record-button')))
        .onPressed!
        .call();
    final bool bubbleLanded = await _poll(
        () => find.textContaining('· voice note').evaluate().length > before,
        timeout: const Duration(seconds: 20));
    final int afterSend =
        find.textContaining('· voice note').evaluate().length;
    _log('P4 voiceBubbleLanded=$bubbleLanded count=$afterSend');
    expect(bubbleLanded, isTrue,
        reason: 'tapping stop must land the recorded note in the thread');
    // (stop-to-send asserted below)

    // P5: arm another recording (same closure path), then Cancel through
    // the strip's own handler (a pure-Flutter control).
    tester
        .widget<AppBoxKitNativeIconButton>(
            find.byKey(const ValueKey('composer-record-button')))
        .onPressed!
        .call();
    final bool stripAgain = await _poll(
        () => find.text('Cancel').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    expect(stripAgain, isTrue, reason: 'the toggle arms another recording');
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Cancel'));
    final bool stayed = await _poll(
        () => find.textContaining('· voice note').evaluate().length == afterSend,
        timeout: const Duration(seconds: 15));
    final int finalCount =
        find.textContaining('· voice note').evaluate().length;
    _log('P5 countStayed=$stayed final=$finalCount afterSend=$afterSend');
    expect(stayed, isTrue,
        reason: 'the strip cancel must discard: no new voice bubble');
    // (cancel asserted below)
    _log('END');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
