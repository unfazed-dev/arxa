import 'dart:async';

import '../biometric/arxa_kit_biometric_result.dart';
import '../biometric/arxa_kit_biometric_service.dart';
import 'arxa_kit_app_lock_config.dart';
import 'arxa_kit_app_lock_outcome.dart';
import 'arxa_kit_app_lock_state.dart';
import 'arxa_kit_pin_verifier.dart';

/// A pure-Dart app-lock state machine over [ArxaKitAppLockState].
///
/// Holds the current state plus a broadcast stream (the [ArxaKitStateNotifier] feel
/// from `arxa_kit_state`, without depending on it). Composes a
/// [ArxaKitBiometricService] and a [ArxaKitPinVerifier]:
///
/// - `maxAttempts` biometric failures (or a platform permanent lockout) lock
///   out the biometric path — [unlockWithBiometrics] then returns
///   [ArxaKitAppLockDenied] with [ArxaKitAppLockDenialReason.biometricLockedOut] and the
///   UI must fall back to the PIN.
/// - `maxAttempts` PIN failures start a `cooldown` window during which
///   [unlockWithPin] is refused with [ArxaKitAppLockDenialReason.inCooldown].
/// - Any successful unlock resets every counter and clears both lockouts.
///
/// Lifecycle is pushed in by the host (this class has no Flutter dependency):
/// call [didEnterBackground] / [didEnterForeground] from a
/// `WidgetsBindingObserver`. Re-lock triggers when the backgrounded duration
/// reaches [ArxaKitAppLockConfig.lockOnBackgroundAfter]. The clock is injectable for
/// deterministic tests.
class ArxaKitAppLockController {
  ArxaKitAppLockController({
    required ArxaKitBiometricService biometrics,
    required ArxaKitPinVerifier pinVerifier,
    this.config = const ArxaKitAppLockConfig(),
    ArxaKitAppLockState initialState = ArxaKitAppLockState.locked,
    DateTime Function()? clock,
  })  : _biometrics = biometrics,
        _pinVerifier = pinVerifier,
        _state = initialState,
        _now = clock ?? DateTime.now;

  final ArxaKitBiometricService _biometrics;
  final ArxaKitPinVerifier _pinVerifier;

  /// The tuning applied to this controller.
  final ArxaKitAppLockConfig config;

  final DateTime Function() _now;
  final StreamController<ArxaKitAppLockState> _controller =
      StreamController<ArxaKitAppLockState>.broadcast();

  ArxaKitAppLockState _state;
  int _biometricAttempts = 0;
  int _pinAttempts = 0;
  bool _biometricLockedOut = false;
  DateTime? _cooldownUntil;
  DateTime? _backgroundedAt;
  bool _disposed = false;

  /// The current lock state.
  ArxaKitAppLockState get state => _state;

  /// Broadcast stream of state changes. Does not replay the current value; read
  /// [state] for that.
  Stream<ArxaKitAppLockState> get stateChanges => _controller.stream;

  /// True whenever the app is not [ArxaKitAppLockState.unlocked].
  bool get isLocked => _state != ArxaKitAppLockState.unlocked;

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
    _setState(ArxaKitAppLockState.locked);
  }

  /// Attempts to unlock with biometrics.
  ///
  /// No-ops to [ArxaKitAppLockUnlocked] when already unlocked; [ArxaKitAppLockDenied]
  /// when an unlock is in flight or the biometric path is locked out; otherwise
  /// prompts and returns [ArxaKitAppLockUnlocked] / [ArxaKitAppLockFailed].
  Future<ArxaKitAppLockOutcome> unlockWithBiometrics({String? reason}) async {
    _requireNotDisposed();
    if (_state == ArxaKitAppLockState.unlocked) return const ArxaKitAppLockUnlocked();
    if (_state == ArxaKitAppLockState.unlocking) {
      return const ArxaKitAppLockDenied(ArxaKitAppLockDenialReason.busy);
    }
    if (_biometricLockedOut) {
      return const ArxaKitAppLockDenied(ArxaKitAppLockDenialReason.biometricLockedOut);
    }

    _setState(ArxaKitAppLockState.unlocking);
    final result =
        await _biometrics.authenticate(reason: reason ?? config.unlockReason);
    if (_disposed) {
      return const ArxaKitAppLockDenied(ArxaKitAppLockDenialReason.busy);
    }

    switch (result) {
      case ArxaKitBiometricSuccess():
        _resetOnSuccess();
        return const ArxaKitAppLockUnlocked();
      case ArxaKitBiometricFailure(:final reason):
        _biometricAttempts++;
        if (_biometricAttempts >= config.maxAttempts ||
            reason == ArxaKitBiometricFailureReason.permanentlyLockedOut) {
          _biometricLockedOut = true;
        }
        _setState(ArxaKitAppLockState.locked);
        return ArxaKitAppLockFailed(
          method: ArxaKitAppLockMethod.biometric,
          biometricReason: reason,
          lockedOut: _biometricLockedOut,
        );
    }
  }

  /// Attempts to unlock with [pin].
  ///
  /// No-ops to [ArxaKitAppLockUnlocked] when already unlocked; [ArxaKitAppLockDenied]
  /// when an unlock is in flight or a cooldown is active; otherwise verifies and
  /// returns [ArxaKitAppLockUnlocked] / [ArxaKitAppLockFailed]. The failure that reaches
  /// [ArxaKitAppLockConfig.maxAttempts] starts the cooldown and resets the PIN
  /// counter, so a fresh set of attempts is available once it elapses.
  Future<ArxaKitAppLockOutcome> unlockWithPin(String pin) async {
    _requireNotDisposed();
    if (_state == ArxaKitAppLockState.unlocked) return const ArxaKitAppLockUnlocked();
    if (_state == ArxaKitAppLockState.unlocking) {
      return const ArxaKitAppLockDenied(ArxaKitAppLockDenialReason.busy);
    }
    if (isInCooldown) {
      return const ArxaKitAppLockDenied(ArxaKitAppLockDenialReason.inCooldown);
    }

    _setState(ArxaKitAppLockState.unlocking);
    final ok = await _pinVerifier.verifyPin(pin);
    if (_disposed) {
      return const ArxaKitAppLockDenied(ArxaKitAppLockDenialReason.busy);
    }
    if (ok) {
      _resetOnSuccess();
      return const ArxaKitAppLockUnlocked();
    }

    _pinAttempts++;
    var cooldownStarted = false;
    if (_pinAttempts >= config.maxAttempts) {
      _cooldownUntil = _now().add(config.cooldown);
      _pinAttempts = 0;
      cooldownStarted = true;
    }
    _setState(ArxaKitAppLockState.locked);
    return ArxaKitAppLockFailed(
      method: ArxaKitAppLockMethod.pin,
      cooldownStarted: cooldownStarted,
    );
  }

  /// Records the moment the app was backgrounded (only while unlocked).
  void didEnterBackground() {
    _requireNotDisposed();
    if (_state == ArxaKitAppLockState.unlocked) {
      _backgroundedAt = _now();
    }
  }

  /// Re-locks if the app stayed backgrounded for at least
  /// [ArxaKitAppLockConfig.lockOnBackgroundAfter].
  void didEnterForeground() {
    _requireNotDisposed();
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null || _state != ArxaKitAppLockState.unlocked) return;
    if (_now().difference(backgroundedAt) >= config.lockOnBackgroundAfter) {
      _setState(ArxaKitAppLockState.locked);
    }
  }

  void _resetOnSuccess() {
    _biometricAttempts = 0;
    _pinAttempts = 0;
    _biometricLockedOut = false;
    _cooldownUntil = null;
    _backgroundedAt = null;
    _setState(ArxaKitAppLockState.unlocked);
  }

  void _setState(ArxaKitAppLockState next) {
    if (next == _state) return;
    _state = next;
    _controller.add(next);
  }

  void _requireNotDisposed() {
    if (_disposed) {
      throw StateError('Operation called on a disposed ArxaKitAppLockController');
    }
  }

  /// Releases the broadcast stream. Call from the host's `dispose`.
  Future<void> dispose() async {
    _disposed = true;
    await _controller.close();
  }
}
