import '../biometric/appbox_kit_biometric_result.dart';

/// Which credential an unlock attempt used.
enum AppBoxKitAppLockMethod {
  /// A biometric prompt.
  biometric,

  /// A PIN entry.
  pin,
}

/// Why an unlock attempt was refused before any authenticator was consulted.
enum AppBoxKitAppLockDenialReason {
  /// An unlock is already in flight ([AppBoxKitAppLockState.unlocking]).
  busy,

  /// The biometric path is locked out after too many failures; use the PIN.
  biometricLockedOut,

  /// PIN entry is in a cooldown window after too many failures.
  inCooldown,
}

/// The typed result of a [AppBoxKitAppLockController] unlock attempt.
sealed class AppBoxKitAppLockOutcome {
  const AppBoxKitAppLockOutcome();

  /// True only for [AppBoxKitAppLockUnlocked].
  bool get didUnlock => this is AppBoxKitAppLockUnlocked;
}

/// The app is now unlocked (freshly authenticated, or already open).
final class AppBoxKitAppLockUnlocked extends AppBoxKitAppLockOutcome {
  const AppBoxKitAppLockUnlocked();

  @override
  bool operator ==(Object other) => other is AppBoxKitAppLockUnlocked;

  @override
  int get hashCode => (AppBoxKitAppLockUnlocked).hashCode;

  @override
  String toString() => 'AppBoxKitAppLockUnlocked()';
}

/// The attempt was refused up front, without consulting an authenticator.
final class AppBoxKitAppLockDenied extends AppBoxKitAppLockOutcome {
  const AppBoxKitAppLockDenied(this.reason);

  /// Why the attempt was refused.
  final AppBoxKitAppLockDenialReason reason;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitAppLockDenied && reason == other.reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'AppBoxKitAppLockDenied(${reason.name})';
}

/// An authenticator was consulted and rejected the credential.
final class AppBoxKitAppLockFailed extends AppBoxKitAppLockOutcome {
  const AppBoxKitAppLockFailed({
    required this.method,
    this.biometricReason,
    this.lockedOut = false,
    this.cooldownStarted = false,
  });

  /// Which credential was tried.
  final AppBoxKitAppLockMethod method;

  /// The underlying biometric reason, when [method] is
  /// [AppBoxKitAppLockMethod.biometric].
  final AppBoxKitBiometricFailureReason? biometricReason;

  /// True when this failure tripped the biometric lockout (PIN now required).
  final bool lockedOut;

  /// True when this failure tripped the PIN [AppBoxKitAppLockConfig.cooldown].
  final bool cooldownStarted;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitAppLockFailed &&
      method == other.method &&
      biometricReason == other.biometricReason &&
      lockedOut == other.lockedOut &&
      cooldownStarted == other.cooldownStarted;

  @override
  int get hashCode =>
      Object.hash(method, biometricReason, lockedOut, cooldownStarted);

  @override
  String toString() => 'AppBoxKitAppLockFailed(method: ${method.name}, '
      'biometricReason: ${biometricReason?.name}, lockedOut: $lockedOut, '
      'cooldownStarted: $cooldownStarted)';
}
