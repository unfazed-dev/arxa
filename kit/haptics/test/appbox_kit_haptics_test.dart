import 'package:appbox_kit_haptics/appbox_kit_haptics.dart';
import 'package:appbox_kit_haptics/appbox_kit_testing.dart';
import 'package:appbox_kit_haptics/src/appbox_kit_haptic_locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Behavior tests for appbox_kit_haptics.
///
/// Seams:
/// - `SharedPreferences.setMockInitialValues` scripts the persisted enable
///   state (the legacy store is fully in-memory and resets per call).
/// - The `haptic_feedback` plugin's `MethodChannel('haptic_feedback')` is
///   intercepted via [TestDefaultBinaryMessenger] — `canVibrate` is scripted,
///   vibrate calls are recorded.
/// - `FakeAppBoxKitHapticService` (from `appbox_kit_testing.dart`) stands in
///   for the real service at the locator seam the widget extension resolves.
const MethodChannel _hapticChannel = MethodChannel('haptic_feedback');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final channelCalls = <MethodCall>[];
  var deviceCanVibrate = true;

  setUp(() async {
    await appBoxKitLocator.reset();
    channelCalls.clear();
    deviceCanVibrate = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_hapticChannel, (MethodCall call) async {
      channelCalls.add(call);
      if (call.method == 'canVibrate') return deviceCanVibrate;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_hapticChannel, null);
  });

  group('AppBoxKitHapticService', () {
    test(
      'kit.haptics.enable-state — initialize restores the persisted enabled state',
      () async {
        // given
        SharedPreferences.setMockInitialValues(const {'haptic_enabled': true});
        final service = AppBoxKitHapticService();
        final expectation = expectLater(
          service.isHapticEnable$,
          emitsInOrder([isFalse, isTrue]),
        );
        // when
        await service.initialize();
        // then
        await expectation.timeout(const Duration(milliseconds: 500));
        expect(service.isHapticEnabled, isTrue);
        expect(service.canVibrate, isTrue);
      },
    );

    test(
      'kit.haptics.enable-state — enabled state persists across service instances',
      () async {
        // given
        SharedPreferences.setMockInitialValues(const {});
        final first = AppBoxKitHapticService();
        await first.initialize();
        // when
        await first.setHapticEnabled(true);
        // then — a fresh instance on the next launch restores it
        final second = AppBoxKitHapticService();
        await second.initialize();
        expect(second.isHapticEnabled, isTrue);
      },
    );

    test(
      'kit.haptics.enable-stream — enable/disable emits the seeded value then each change in order',
      () async {
        // given
        SharedPreferences.setMockInitialValues(const {});
        final service = AppBoxKitHapticService();
        final expectation = expectLater(
          service.isHapticEnable$,
          emitsInOrder([isFalse, isTrue, isFalse]),
        );
        // when
        await service.initialize();
        await service.setHapticEnabled(true);
        await service.toggleHaptic();
        // then
        await expectation.timeout(const Duration(milliseconds: 500));
      },
    );

    test(
      'kit.haptics.enable-state — setHapticEnabled before initialize is a no-op',
      () async {
        // given
        SharedPreferences.setMockInitialValues(const {});
        final service = AppBoxKitHapticService();
        // when
        await service.setHapticEnabled(true);
        // then — nothing is enabled and nothing is written to prefs
        expect(service.isHapticEnabled, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('haptic_enabled'), isNull);
      },
    );

    test(
      'kit.haptics.capability — a device without vibrate capability suppresses haptic calls',
      () async {
        // given
        deviceCanVibrate = false;
        SharedPreferences.setMockInitialValues(const {});
        final service = AppBoxKitHapticService();
        await service.initialize();
        await service.setHapticEnabled(true);
        // when
        await service.triggerSuccessHaptic();
        // then — no vibrate reached the platform and no event was recorded
        expect(channelCalls.map((c) => c.method), isNot(contains('success')));
        await expectLater(service.lastHapticEvent$, emits(isNull));
      },
    );

    test(
      'kit.haptics.capability — a capable, enabled device fires vibrate and records the event',
      () async {
        // given
        SharedPreferences.setMockInitialValues(const {});
        final service = AppBoxKitHapticService();
        await service.initialize();
        await service.setHapticEnabled(true);
        final expectation = expectLater(
          service.lastHapticEvent$,
          emitsInOrder([isNull, HapticsType.success]),
        );
        // when
        await service.triggerSuccessHaptic();
        // then
        await expectation.timeout(const Duration(milliseconds: 500));
        expect(channelCalls.map((c) => c.method), contains('success'));
      },
    );
  });

  group('AppBoxKitHapticExtension', () {
    testWidgets(
      'kit.haptics.locator — withSuccessHaptic resolves the registered service through the locator',
      (tester) async {
        // given
        final fake = FakeAppBoxKitHapticService();
        appBoxKitLocator.registerSingleton<AppBoxKitHapticService>(fake);
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: const SizedBox(key: Key('haptic-target'), width: 100, height: 100)
                  .withSuccessHaptic(onTap: () => tapped = true),
            ),
          ),
        );
        // when
        await tester.tap(
          find.byKey(const Key('haptic-target')),
          // The translucent Listener absorbs the hit above the SizedBox.
          warnIfMissed: false,
        );
        await tester.pump();
        // then
        expect(fake.triggeredHaptics, [HapticsType.success]);
        expect(tapped, isTrue);
      },
    );
  });
}
