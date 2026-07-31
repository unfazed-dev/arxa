import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_security/appbox_kit_security.dart';
import 'package:appbox_kit_security/testing.dart';

/// A mutable clock for deterministic cooldown / re-lock timing.
class _FakeClock {
  _FakeClock(this._now);
  DateTime _now;
  void advance(Duration d) => _now = _now.add(d);
  DateTime call() => _now;
}

KitAppLockController _build({
  required FakeKitBiometricService biometrics,
  required FakeKitPinVerifier pin,
  required _FakeClock clock,
  KitAppLockConfig config = const KitAppLockConfig(),
  KitAppLockState initialState = KitAppLockState.locked,
}) =>
    KitAppLockController(
      biometrics: biometrics,
      pinVerifier: pin,
      config: config,
      initialState: initialState,
      clock: clock.call,
    );

void main() {
  late _FakeClock clock;

  setUp(() {
    clock = _FakeClock(DateTime(2026, 7, 14, 12));
  });

  group('happy path', () {
    test('a biometric success unlocks and resets counters', () async {
      final bio = FakeKitBiometricService(); // default: success
      final lock = _build(
        biometrics: bio,
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
      );
      expect(lock.state, KitAppLockState.locked);

      final outcome = await lock.unlockWithBiometrics();
      expect(outcome, isA<KitAppLockUnlocked>());
      expect(lock.state, KitAppLockState.unlocked);
      expect(lock.biometricAttempts, 0);
    });

    test('a PIN success unlocks', () async {
      final lock = _build(
        biometrics: FakeKitBiometricService(),
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
      );
      final outcome = await lock.unlockWithPin('1234');
      expect(outcome, isA<KitAppLockUnlocked>());
      expect(lock.state, KitAppLockState.unlocked);
    });

    test('calling unlock while already unlocked is a no-op success', () async {
      final lock = _build(
        biometrics: FakeKitBiometricService(),
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
        initialState: KitAppLockState.unlocked,
      );
      expect(await lock.unlockWithBiometrics(), isA<KitAppLockUnlocked>());
      expect(await lock.unlockWithPin('1234'), isA<KitAppLockUnlocked>());
    });
  });

  group('biometric lockout → PIN fallback', () {
    test('maxAttempts biometric failures lock out the biometric path', () async {
      final bio = FakeKitBiometricService(
        defaultResult:
            const KitBiometricFailure(KitBiometricFailureReason.lockedOut),
      );
      final lock = _build(
        biometrics: bio,
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
      );

      for (var i = 1; i < KitAppLockConfig().maxAttempts; i++) {
        final f = await lock.unlockWithBiometrics();
        expect(f, isA<KitAppLockFailed>());
        expect(lock.biometricLockedOut, isFalse,
            reason: 'should not lock out before maxAttempts');
      }

      // The maxAttempts-th failure trips the lockout.
      final last = await lock.unlockWithBiometrics();
      expect(last, isA<KitAppLockFailed>());
      expect(lock.biometricLockedOut, isTrue);

      // Further biometric attempts are denied without prompting.
      final denied = await lock.unlockWithBiometrics();
      expect(denied, isA<KitAppLockDenied>());
      expect((denied as KitAppLockDenied).reason,
          KitAppLockDenialReason.biometricLockedOut);
    });

    test('a permanent platform lockout trips the lockout on the first failure',
        () async {
      final bio = FakeKitBiometricService()
        ..script(const [
          KitBiometricFailure(KitBiometricFailureReason.permanentlyLockedOut),
        ]);
      final lock = _build(
        biometrics: bio,
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
      );

      await lock.unlockWithBiometrics();
      expect(lock.biometricLockedOut, isTrue);
    });

    test('the PIN still unlocks after the biometric path is locked out',
        () async {
      final bio = FakeKitBiometricService(
        defaultResult:
            const KitBiometricFailure(KitBiometricFailureReason.lockedOut),
      );
      final lock = _build(
        biometrics: bio,
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
      );
      // Burn through maxAttempts to lock out biometrics.
      for (var i = 0; i < KitAppLockConfig().maxAttempts; i++) {
        await lock.unlockWithBiometrics();
      }
      expect(lock.biometricLockedOut, isTrue);

      final outcome = await lock.unlockWithPin('1234');
      expect(outcome, isA<KitAppLockUnlocked>());
      // A successful unlock clears the biometric lockout too.
      expect(lock.biometricLockedOut, isFalse);
    });
  });

  group('PIN cooldown', () {
    test('maxAttempts PIN failures start the cooldown', () async {
      final lock = _build(
        biometrics: FakeKitBiometricService(),
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
      );

      KitAppLockFailed? triggering;
      for (var i = 0; i < KitAppLockConfig().maxAttempts; i++) {
        final f = await lock.unlockWithPin('0000');
        expect(f, isA<KitAppLockFailed>());
        triggering = f as KitAppLockFailed;
      }
      expect(triggering!.cooldownStarted, isTrue,
          reason: 'the final failure should start the cooldown');
      expect(lock.isInCooldown, isTrue);
    });

    test('PIN entry is refused while in cooldown, then works once it elapses',
        () async {
      final lock = _build(
        biometrics: FakeKitBiometricService(),
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
      );
      for (var i = 0; i < KitAppLockConfig().maxAttempts; i++) {
        await lock.unlockWithPin('0000');
      }
      expect(lock.isInCooldown, isTrue);

      // Correct PIN, but cooldown refuses it outright.
      final denied = await lock.unlockWithPin('1234');
      expect(denied, isA<KitAppLockDenied>());
      expect((denied as KitAppLockDenied).reason,
          KitAppLockDenialReason.inCooldown);

      // Past the cooldown window the correct PIN unlocks.
      clock.advance(KitAppLockConfig().cooldown + const Duration(seconds: 1));
      expect(lock.isInCooldown, isFalse);
      final outcome = await lock.unlockWithPin('1234');
      expect(outcome, isA<KitAppLockUnlocked>());
    });
  });

  group('concurrency guard', () {
    test('a second unlock while one is in flight is denied as busy', () async {
      final bio = FakeKitBiometricService()
        ..script(const [
          KitBiometricFailure(KitBiometricFailureReason.cancelled),
        ]);
      final hold = bio.pauseAuthentication();
      final lock = _build(
        biometrics: bio,
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
      );

      final first = lock.unlockWithBiometrics(); // held mid-flight
      final second = await lock.unlockWithBiometrics();
      expect(second, isA<KitAppLockDenied>());
      expect((second as KitAppLockDenied).reason, KitAppLockDenialReason.busy);

      // Release the held attempt; it resolves to the scripted failure.
      hold.complete();
      await first;
      expect(lock.state, KitAppLockState.locked);
      await lock.dispose();
    });
  });

  group('background / foreground re-lock', () {
    test('re-locks after the backgrounded duration crosses the threshold',
        () async {
      final lock = _build(
        biometrics: FakeKitBiometricService(),
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
        config: const KitAppLockConfig(lockOnBackgroundAfter: Duration(seconds: 30)),
        initialState: KitAppLockState.unlocked,
      );

      lock.didEnterBackground();
      clock.advance(const Duration(seconds: 31));
      lock.didEnterForeground();

      expect(lock.state, KitAppLockState.locked);
    });

    test('does not re-lock when the backgrounded duration is under threshold',
        () async {
      final lock = _build(
        biometrics: FakeKitBiometricService(),
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
        config: const KitAppLockConfig(lockOnBackgroundAfter: Duration(seconds: 30)),
        initialState: KitAppLockState.unlocked,
      );

      lock.didEnterBackground();
      clock.advance(const Duration(seconds: 10));
      lock.didEnterForeground();

      expect(lock.state, KitAppLockState.unlocked);
    });

    test('lock() seals the app on demand', () {
      final lock = _build(
        biometrics: FakeKitBiometricService(),
        pin: FakeKitPinVerifier(pin: '1234'),
        clock: clock,
        initialState: KitAppLockState.unlocked,
      );
      lock.lock();
      expect(lock.state, KitAppLockState.locked);
      expect(lock.isLocked, isTrue);
    });
  });
}
