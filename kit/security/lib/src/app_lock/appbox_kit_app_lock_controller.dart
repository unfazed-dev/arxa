import 'dart:async';

import '../biometric/appbox_kit_biometric_result.dart';
import '../biometric/appbox_kit_biometric_service.dart';
import 'appbox_kit_app_lock_config.dart';
import 'appbox_kit_app_lock_outcome.dart';
import 'appbox_kit_app_lock_state.dart';
import 'appbox_kit_pin_verifier.dart';

/// A pure-Dart app-lock state machine over [AppBoxKitAppLockState].
///
/// Holds the current state plus a broadcast stream (the [AppBoxKitStateNotifier] feel
/// from `appbox_kit_state`, without depending on it). Composes a
/// [AppBoxKitBiometricService] and a [AppBoxKitPinVerifier]:
///
/// - `maxAttempts` biometric failures (or a platform permanent lockout) lock
///   out the biometric path — [unlockWithBiometrics] then returns
///   [AppBoxKitAppLockDenied] with [AppBoxKitAppLockDenialReason.biometricLockedOut] and the
///   UI must fall back to the PIN.
/// - `maxAttempts` PIN failures start a `cooldown` window during which
///   [unlockWithPin] is refused with [AppBoxKitAppLockDenialReason.inCooldown].
/// - Any successful unlock resets every counter and clears both lockouts.
///
/// Lifecycle is pushed in by the host (this class has no Flutter dependency):
/// call [didEnterBackground] / [didEnterForeground] from a
/// `WidgetsBindingObserver`. Re-lock triggers when the backgrounded duration
/// reaches [AppBoxKitAppLockConfig.lockOnBackgroundAfter]. The clock is injectable for
/// deterministic tests.
class AppBoxKitAppLockController {
  AppBoxKitAppLockController({
    required AppBoxKitBiometricService biometrics,
    required AppBoxKitPinVerifier pinVerifier,
    this.config = const AppBoxKitAppLockConfig(),
    AppBoxKitAppLockState initialState = AppBoxKitAppLockState.locked,
    DateTime Function()? clock,
  })  : _biometrics = biometrics,
        _pinVerifier = pinVerifier,
        _state = initialState,
        _now = clock ?? DateTime.now;

  final AppBoxKitBiometricService _biometrics;
  final AppBoxKitPinVerifier _pinVerifier;

  /// The tuning applied to this controller.
  final AppBoxKitAppLockConfig config;

  final DateTime Function() _now;
  final StreamController<AppBoxKitAppLockState> _controller =
      StreamController<AppBoxKitAppLockState>.broadcast();

  AppBoxKitAppLockState _state;
  int _biometricAttempts = 0;
  int _pinAttempts = 0;
  bool _biometricLockedOut = false;
  DateTime? _cooldownUntil;
  DateTime? _backgroundedAt;
  bool _disposed = false;

  /// The current lock state.
  AppBoxKitAppLockState get state => _state;

  /// Broadcast stream of state changes. Does not replay the current value; read
  /// [state] for that.
  Stream<AppBoxKitAppLockState> get stateChanges => _controller.stream;

  /// True whenever the app is not [AppBoxKitAppLockState.unlocked].
  bool get isLocked => _state != AppBoxKitAppLockState.unlocked;

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
    _setState(AppBoxKitAppLockState.locked);
  }

  /// Attempts to unlock with biometrics.
  ///
  /// No-ops to [AppBoxKitAppLockUnlocked] when already unlocked; [AppBoxKitAppLockDenied]
  /// when an unlock is in flight or the biometric path is locked out; otherwise
  /// prompts and returns [AppBoxKitAppLockUnlocked] / [AppBoxKitAppLockFailed].
  Future<AppBoxKitAppLockOutcome> unlockWithBiometrics({String? reason}) async {
    _requireNotDisposed();
    if (_state == AppBoxKitAppLockState.unlocked) return const AppBoxKitAppLockUnlocked();
    if (_state == AppBoxKitAppLockState.unlocking) {
      return const AppBoxKitAppLockDenied(AppBoxKitAppLockDenialReason.busy);
    }
    if (_biometricLockedOut) {
      return const AppBoxKitAppLockDenied(AppBoxKitAppLockDenialReason.biometricLockedOut);
    }

    _setState(AppBoxKitAppLockState.unlocking);
    final result =
        await _biometrics.authenticate(reason: reason ?? config.unlockReason);
    if (_disposed) {
      return const AppBoxKitAppLockDenied(AppBoxKitAppLockDenialReason.busy);
    }

    switch (result) {
      case AppBoxKitBiometricSuccess():
        _resetOnSuccess();
        return const AppBoxKitAppLockUnlocked();
      case AppBoxKitBiometricFailure(:final reason):
        _biometricAttempts++;
        if (_biometricAttempts >= config.maxAttempts ||
            reason == AppBoxKitBiometricFailureReason.permanentlyLockedOut) {
          _biometricLockedOut = true;
        }
        _setState(AppBoxKitAppLockState.locked);
        return AppBoxKitAppLockFailed(
          method: AppBoxKitAppLockMethod.biometric,
          biometricReason: reason,
          lockedOut: _biometricLockedOut,
        );
    }
  }

  /// Attempts to unlock with [pin].
  ///
  /// No-ops to [AppBoxKitAppLockUnlocked] when already unlocked; [AppBoxKitAppLockDenied]
  /// when an unlock is in flight or a cooldown is active; otherwise verifies and
  /// returns [AppBoxKitAppLockUnlocked] / [AppBoxKitAppLockFailed]. The failure that reaches
  /// [AppBoxKitAppLockConfig.maxAttempts] starts the cooldown and resets the PIN
  /// counter, so a fresh set of attempts is available once it elapses.
  Future<AppBoxKitAppLockOutcome> unlockWithPin(String pin) async {
    _requireNotDisposed();
    if (_state == AppBoxKitAppLockState.unlocked) return const AppBoxKitAppLockUnlocked();
    if (_state == AppBoxKitAppLockState.unlocking) {
      return const AppBoxKitAppLockDenied(AppBoxKitAppLockDenialReason.busy);
    }
    if (isInCooldown) {
      return const AppBoxKitAppLockDenied(AppBoxKitAppLockDenialReason.inCooldown);
    }

    _setState(AppBoxKitAppLockState.unlocking);
    final ok = await _pinVerifier.verifyPin(pin);
    if (_disposed) {
      return const AppBoxKitAppLockDenied(AppBoxKitAppLockDenialReason.busy);
    }
    if (ok) {
      _resetOnSuccess();
      return const AppBoxKitAppLockUnlocked();
    }

    _pinAttempts++;
    var cooldownStarted = false;
    if (_pinAttempts >= config.maxAttempts) {
      _cooldownUntil = _now().add(config.cooldown);
      _pinAttempts = 0;
      cooldownStarted = true;
    }
    _setState(AppBoxKitAppLockState.locked);
    return AppBoxKitAppLockFailed(
      method: AppBoxKitAppLockMethod.pin,
      cooldownStarted: cooldownStarted,
    );
  }

  /// Records the moment the app was backgrounded (only while unlocked).
  void didEnterBackground() {
    _requireNotDisposed();
    if (_state == AppBoxKitAppLockState.unlocked) {
      _backgroundedAt = _now();
    }
  }

  /// Re-locks if the app stayed backgrounded for at least
  /// [AppBoxKitAppLockConfig.lockOnBackgroundAfter].
  void didEnterForeground() {
    _requireNotDisposed();
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null || _state != AppBoxKitAppLockState.unlocked) return;
    if (_now().difference(backgroundedAt) >= config.lockOnBackgroundAfter) {
      _setState(AppBoxKitAppLockState.locked);
    }
  }

  void _resetOnSuccess() {
    _biometricAttempts = 0;
    _pinAttempts = 0;
    _biometricLockedOut = false;
    _cooldownUntil = null;
    _backgroundedAt = null;
    _setState(AppBoxKitAppLockState.unlocked);
  }

  void _setState(AppBoxKitAppLockState next) {
    if (next == _state) return;
    _state = next;
    _controller.add(next);
  }

  void _requireNotDisposed() {
    if (_disposed) {
      throw StateError('Operation called on a disposed AppBoxKitAppLockController');
    }
  }

  /// Releases the broadcast stream. Call from the host's `dispose`.
  Future<void> dispose() async {
    _disposed = true;
    await _controller.close();
  }
}
