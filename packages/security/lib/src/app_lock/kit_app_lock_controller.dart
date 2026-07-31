import 'dart:async';

import '../biometric/kit_biometric_result.dart';
import '../biometric/kit_biometric_service.dart';
import 'kit_app_lock_config.dart';
import 'kit_app_lock_outcome.dart';
import 'kit_app_lock_state.dart';
import 'kit_pin_verifier.dart';

/// A pure-Dart app-lock state machine over [KitAppLockState].
///
/// Holds the current state plus a broadcast stream (the [KitStateNotifier] feel
/// from `appbox_kit_state`, without depending on it). Composes a
/// [KitBiometricService] and a [KitPinVerifier]:
///
/// - `maxAttempts` biometric failures (or a platform permanent lockout) lock
///   out the biometric path — [unlockWithBiometrics] then returns
///   [KitAppLockDenied] with [KitAppLockDenialReason.biometricLockedOut] and the
///   UI must fall back to the PIN.
/// - `maxAttempts` PIN failures start a `cooldown` window during which
///   [unlockWithPin] is refused with [KitAppLockDenialReason.inCooldown].
/// - Any successful unlock resets every counter and clears both lockouts.
///
/// Lifecycle is pushed in by the host (this class has no Flutter dependency):
/// call [didEnterBackground] / [didEnterForeground] from a
/// `WidgetsBindingObserver`. Re-lock triggers when the backgrounded duration
/// reaches [KitAppLockConfig.lockOnBackgroundAfter]. The clock is injectable for
/// deterministic tests.
class KitAppLockController {
  KitAppLockController({
    required KitBiometricService biometrics,
    required KitPinVerifier pinVerifier,
    this.config = const KitAppLockConfig(),
    KitAppLockState initialState = KitAppLockState.locked,
    DateTime Function()? clock,
  })  : _biometrics = biometrics,
        _pinVerifier = pinVerifier,
        _state = initialState,
        _now = clock ?? DateTime.now;

  final KitBiometricService _biometrics;
  final KitPinVerifier _pinVerifier;

  /// The tuning applied to this controller.
  final KitAppLockConfig config;

  final DateTime Function() _now;
  final StreamController<KitAppLockState> _controller =
      StreamController<KitAppLockState>.broadcast();

  KitAppLockState _state;
  int _biometricAttempts = 0;
  int _pinAttempts = 0;
  bool _biometricLockedOut = false;
  DateTime? _cooldownUntil;
  DateTime? _backgroundedAt;
  bool _disposed = false;

  /// The current lock state.
  KitAppLockState get state => _state;

  /// Broadcast stream of state changes. Does not replay the current value; read
  /// [state] for that.
  Stream<KitAppLockState> get stateChanges => _controller.stream;

  /// True whenever the app is not [KitAppLockState.unlocked].
  bool get isLocked => _state != KitAppLockState.unlocked;

  /// Consecutive biometric failures since the last success.
  int get biometricAttempts => _biometricAttempts;

  /// Consecutive PIN failures since the last success or cooldown.
  int get pinAttempts => _pinAttempts;

  /// True once the biometric path is locked out; only the PIN can unlock.
  bool get biometricLockedOut => _biometricLockedOut;

  /// True while PIN entry is in its post-failure cooldown window.
  bool get isInCooldown => cooldownRemaining > Duration.zero;

  /// How much of the PIN cooldown window remains ([Duration.zero] when none).
  Duration get cooldownRemaining {
    final until = _cooldownUntil;
    if (until == null) return Duration.zero;
    final remaining = until.difference(_now());
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  /// True after [dispose].
  bool get isDisposed => _disposed;

  /// Seals the app. Attempt counters and any active lockout/cooldown persist.
  void lock() {
    _requireNotDisposed();
    _setState(KitAppLockState.locked);
  }

  /// Attempts to unlock with biometrics.
  ///
  /// No-ops to [KitAppLockUnlocked] when already unlocked; [KitAppLockDenied]
  /// when an unlock is in flight or the biometric path is locked out; otherwise
  /// prompts and returns [KitAppLockUnlocked] / [KitAppLockFailed].
  Future<KitAppLockOutcome> unlockWithBiometrics({String? reason}) async {
    _requireNotDisposed();
    if (_state == KitAppLockState.unlocked) return const KitAppLockUnlocked();
    if (_state == KitAppLockState.unlocking) {
      return const KitAppLockDenied(KitAppLockDenialReason.busy);
    }
    if (_biometricLockedOut) {
      return const KitAppLockDenied(KitAppLockDenialReason.biometricLockedOut);
    }

    _setState(KitAppLockState.unlocking);
    final result =
        await _biometrics.authenticate(reason: reason ?? config.unlockReason);
    if (_disposed) {
      return const KitAppLockDenied(KitAppLockDenialReason.busy);
    }

    switch (result) {
      case KitBiometricSuccess():
        _resetOnSuccess();
        return const KitAppLockUnlocked();
      case KitBiometricFailure(:final reason):
        _biometricAttempts++;
        if (_biometricAttempts >= config.maxAttempts ||
            reason == KitBiometricFailureReason.permanentlyLockedOut) {
          _biometricLockedOut = true;
        }
        _setState(KitAppLockState.locked);
        return KitAppLockFailed(
          method: KitAppLockMethod.biometric,
          biometricReason: reason,
          lockedOut: _biometricLockedOut,
        );
    }
  }

  /// Attempts to unlock with [pin].
  ///
  /// No-ops to [KitAppLockUnlocked] when already unlocked; [KitAppLockDenied]
  /// when an unlock is in flight or a cooldown is active; otherwise verifies and
  /// returns [KitAppLockUnlocked] / [KitAppLockFailed]. The failure that reaches
  /// [KitAppLockConfig.maxAttempts] starts the cooldown and resets the PIN
  /// counter, so a fresh set of attempts is available once it elapses.
  Future<KitAppLockOutcome> unlockWithPin(String pin) async {
    _requireNotDisposed();
    if (_state == KitAppLockState.unlocked) return const KitAppLockUnlocked();
    if (_state == KitAppLockState.unlocking) {
      return const KitAppLockDenied(KitAppLockDenialReason.busy);
    }
    if (isInCooldown) {
      return const KitAppLockDenied(KitAppLockDenialReason.inCooldown);
    }

    _setState(KitAppLockState.unlocking);
    final ok = await _pinVerifier.verifyPin(pin);
    if (_disposed) {
      return const KitAppLockDenied(KitAppLockDenialReason.busy);
    }
    if (ok) {
      _resetOnSuccess();
      return const KitAppLockUnlocked();
    }

    _pinAttempts++;
    var cooldownStarted = false;
    if (_pinAttempts >= config.maxAttempts) {
      _cooldownUntil = _now().add(config.cooldown);
      _pinAttempts = 0;
      cooldownStarted = true;
    }
    _setState(KitAppLockState.locked);
    return KitAppLockFailed(
      method: KitAppLockMethod.pin,
      cooldownStarted: cooldownStarted,
    );
  }

  /// Records the moment the app was backgrounded (only while unlocked).
  void didEnterBackground() {
    _requireNotDisposed();
    if (_state == KitAppLockState.unlocked) {
      _backgroundedAt = _now();
    }
  }

  /// Re-locks if the app stayed backgrounded for at least
  /// [KitAppLockConfig.lockOnBackgroundAfter].
  void didEnterForeground() {
    _requireNotDisposed();
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null || _state != KitAppLockState.unlocked) return;
    if (_now().difference(backgroundedAt) >= config.lockOnBackgroundAfter) {
      _setState(KitAppLockState.locked);
    }
  }

  void _resetOnSuccess() {
    _biometricAttempts = 0;
    _pinAttempts = 0;
    _biometricLockedOut = false;
    _cooldownUntil = null;
    _backgroundedAt = null;
    _setState(KitAppLockState.unlocked);
  }

  void _setState(KitAppLockState next) {
    if (next == _state) return;
    _state = next;
    _controller.add(next);
  }

  void _requireNotDisposed() {
    if (_disposed) {
      throw StateError('Operation called on a disposed KitAppLockController');
    }
  }

  /// Releases the broadcast stream. Call from the host's `dispose`.
  Future<void> dispose() async {
    _disposed = true;
    await _controller.close();
  }
}
