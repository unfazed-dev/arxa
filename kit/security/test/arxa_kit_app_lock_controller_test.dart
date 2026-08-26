import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_security/arxa_kit_security.dart';
import 'package:arxa_kit_security/arxa_kit_testing.dart';

/// A mutable clock for deterministic cooldown / re-lock timing.
class _FakeClock {
  _FakeClock(this._now);
  DateTime _now;
  void advance(Duration d) => _now = _now.add(d);
  DateTime call() => _now;
}

ArxaKitAppLockController _build({
  required FakeArxaKitBiometricService biometrics,
  required FakeArxaKitPinVerifier pin,
  required _FakeClock clock,
  ArxaKitAppLockConfig config = const ArxaKitAppLockConfig(),
  ArxaKitAppLockState initialState = ArxaKitAppLockState.locked,
}) =>
    ArxaKitAppLockController(
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
    test('kit.security.app-lock — a biometric success unlocks and resets counters', () async {
      final bio = FakeArxaKitBiometricService(); // default: success
      final lock = _build(
        biometrics: bio,
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
      );
      expect(lock.state, ArxaKitAppLockState.locked);

      final outcome = await lock.unlockWithBiometrics();
      expect(outcome, isA<ArxaKitAppLockUnlocked>());
      expect(lock.state, ArxaKitAppLockState.unlocked);
      expect(lock.biometricAttempts, 0);
    });

    test('kit.security.app-lock — a PIN success unlocks', () async {
      final lock = _build(
        biometrics: FakeArxaKitBiometricService(),
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
      );
      final outcome = await lock.unlockWithPin('1234');
      expect(outcome, isA<ArxaKitAppLockUnlocked>());
      expect(lock.state, ArxaKitAppLockState.unlocked);
    });

    test('kit.security.app-lock — calling unlock while already unlocked is a no-op success', () async {
      final lock = _build(
        biometrics: FakeArxaKitBiometricService(),
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
        initialState: ArxaKitAppLockState.unlocked,
      );
      expect(await lock.unlockWithBiometrics(), isA<ArxaKitAppLockUnlocked>());
      expect(await lock.unlockWithPin('1234'), isA<ArxaKitAppLockUnlocked>());
    });
  });

  group('biometric lockout → PIN fallback', () {
    test('kit.security.app-lock — maxAttempts biometric failures lock out the biometric path', () async {
      final bio = FakeArxaKitBiometricService(
        defaultResult:
            const ArxaKitBiometricFailure(ArxaKitBiometricFailureReason.lockedOut),
      );
      final lock = _build(
        biometrics: bio,
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
      );

      for (var i = 1; i < ArxaKitAppLockConfig().maxAttempts; i++) {
        final f = await lock.unlockWithBiometrics();
        expect(f, isA<ArxaKitAppLockFailed>());
        expect(lock.biometricLockedOut, isFalse,
            reason: 'should not lock out before maxAttempts');
      }

      // The maxAttempts-th failure trips the lockout.
      final last = await lock.unlockWithBiometrics();
      expect(last, isA<ArxaKitAppLockFailed>());
      expect(lock.biometricLockedOut, isTrue);

      // Further biometric attempts are denied without prompting.
      final denied = await lock.unlockWithBiometrics();
      expect(denied, isA<ArxaKitAppLockDenied>());
      expect((denied as ArxaKitAppLockDenied).reason,
          ArxaKitAppLockDenialReason.biometricLockedOut);
    });

    test('kit.security.app-lock — a permanent platform lockout trips the lockout on the first failure',
        () async {
      final bio = FakeArxaKitBiometricService()
        ..script(const [
          ArxaKitBiometricFailure(ArxaKitBiometricFailureReason.permanentlyLockedOut),
        ]);
      final lock = _build(
        biometrics: bio,
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
      );

      await lock.unlockWithBiometrics();
      expect(lock.biometricLockedOut, isTrue);
    });

    test('kit.security.app-lock — the PIN still unlocks after the biometric path is locked out',
        () async {
      final bio = FakeArxaKitBiometricService(
        defaultResult:
            const ArxaKitBiometricFailure(ArxaKitBiometricFailureReason.lockedOut),
      );
      final lock = _build(
        biometrics: bio,
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
      );
      // Burn through maxAttempts to lock out biometrics.
      for (var i = 0; i < ArxaKitAppLockConfig().maxAttempts; i++) {
        await lock.unlockWithBiometrics();
      }
      expect(lock.biometricLockedOut, isTrue);

      final outcome = await lock.unlockWithPin('1234');
      expect(outcome, isA<ArxaKitAppLockUnlocked>());
      // A successful unlock clears the biometric lockout too.
      expect(lock.biometricLockedOut, isFalse);
    });
  });

  group('PIN cooldown', () {
    test('kit.security.app-lock — maxAttempts PIN failures start the cooldown', () async {
      final lock = _build(
        biometrics: FakeArxaKitBiometricService(),
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
      );

      ArxaKitAppLockFailed? triggering;
      for (var i = 0; i < ArxaKitAppLockConfig().maxAttempts; i++) {
        final f = await lock.unlockWithPin('0000');
        expect(f, isA<ArxaKitAppLockFailed>());
        triggering = f as ArxaKitAppLockFailed;
      }
      expect(triggering!.cooldownStarted, isTrue,
          reason: 'the final failure should start the cooldown');
      expect(lock.isInCooldown, isTrue);
    });

    test('kit.security.app-lock — PIN entry is refused while in cooldown, then works once it elapses',
        () async {
      final lock = _build(
        biometrics: FakeArxaKitBiometricService(),
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
      );
      for (var i = 0; i < ArxaKitAppLockConfig().maxAttempts; i++) {
        await lock.unlockWithPin('0000');
      }
      expect(lock.isInCooldown, isTrue);

      // Correct PIN, but cooldown refuses it outright.
      final denied = await lock.unlockWithPin('1234');
      expect(denied, isA<ArxaKitAppLockDenied>());
      expect((denied as ArxaKitAppLockDenied).reason,
          ArxaKitAppLockDenialReason.inCooldown);

      // Past the cooldown window the correct PIN unlocks.
      clock.advance(ArxaKitAppLockConfig().cooldown + const Duration(seconds: 1));
      expect(lock.isInCooldown, isFalse);
      final outcome = await lock.unlockWithPin('1234');
      expect(outcome, isA<ArxaKitAppLockUnlocked>());
    });
  });

  group('concurrency guard', () {
    test('kit.security.app-lock — a second unlock while one is in flight is denied as busy', () async {
      final bio = FakeArxaKitBiometricService()
        ..script(const [
          ArxaKitBiometricFailure(ArxaKitBiometricFailureReason.cancelled),
        ]);
      final hold = bio.pauseAuthentication();
      final lock = _build(
        biometrics: bio,
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
      );

      final first = lock.unlockWithBiometrics(); // held mid-flight
      final second = await lock.unlockWithBiometrics();
      expect(second, isA<ArxaKitAppLockDenied>());
      expect((second as ArxaKitAppLockDenied).reason, ArxaKitAppLockDenialReason.busy);

      // Release the held attempt; it resolves to the scripted failure.
      hold.complete();
      await first;
      expect(lock.state, ArxaKitAppLockState.locked);
      await lock.dispose();
    });
  });

  group('background / foreground re-lock', () {
    test('kit.security.app-lock — re-locks after the backgrounded duration crosses the threshold',
        () async {
      final lock = _build(
        biometrics: FakeArxaKitBiometricService(),
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
        config: const ArxaKitAppLockConfig(lockOnBackgroundAfter: Duration(seconds: 30)),
        initialState: ArxaKitAppLockState.unlocked,
      );

      lock.didEnterBackground();
      clock.advance(const Duration(seconds: 31));
      lock.didEnterForeground();

      expect(lock.state, ArxaKitAppLockState.locked);
    });

    test('kit.security.app-lock — does not re-lock when the backgrounded duration is under threshold',
        () async {
      final lock = _build(
        biometrics: FakeArxaKitBiometricService(),
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
        config: const ArxaKitAppLockConfig(lockOnBackgroundAfter: Duration(seconds: 30)),
        initialState: ArxaKitAppLockState.unlocked,
      );

      lock.didEnterBackground();
      clock.advance(const Duration(seconds: 10));
      lock.didEnterForeground();

      expect(lock.state, ArxaKitAppLockState.unlocked);
    });

    test('kit.security.app-lock — lock() seals the app on demand', () {
      final lock = _build(
        biometrics: FakeArxaKitBiometricService(),
        pin: FakeArxaKitPinVerifier(pin: '1234'),
        clock: clock,
        initialState: ArxaKitAppLockState.unlocked,
      );
      lock.lock();
      expect(lock.state, ArxaKitAppLockState.locked);
      expect(lock.isLocked, isTrue);
    });
  });
}
