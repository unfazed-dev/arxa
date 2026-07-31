import '../biometric/kit_biometric_result.dart';

/// Which credential an unlock attempt used.
enum KitAppLockMethod {
  /// A biometric prompt.
  biometric,

  /// A PIN entry.
  pin,
}

/// Why an unlock attempt was refused before any authenticator was consulted.
enum KitAppLockDenialReason {
  /// An unlock is already in flight ([KitAppLockState.unlocking]).
  busy,

  /// The biometric path is locked out after too many failures; use the PIN.
  biometricLockedOut,

  /// PIN entry is in a cooldown window after too many failures.
  inCooldown,
}

/// The typed result of a [KitAppLockController] unlock attempt.
sealed class KitAppLockOutcome {
  const KitAppLockOutcome();

  /// True only for [KitAppLockUnlocked].
  bool get didUnlock => this is KitAppLockUnlocked;
}

/// The app is now unlocked (freshly authenticated, or already open).
final class KitAppLockUnlocked extends KitAppLockOutcome {
  const KitAppLockUnlocked();

  @override
  bool operator ==(Object other) => other is KitAppLockUnlocked;

  @override
  int get hashCode => (KitAppLockUnlocked).hashCode;

  @override
  String toString() => 'KitAppLockUnlocked()';
}

/// The attempt was refused up front, without consulting an authenticator.
final class KitAppLockDenied extends KitAppLockOutcome {
  const KitAppLockDenied(this.reason);

  /// Why the attempt was refused.
  final KitAppLockDenialReason reason;

  @override
  bool operator ==(Object other) =>
      other is KitAppLockDenied && reason == other.reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'KitAppLockDenied(${reason.name})';
}

/// An authenticator was consulted and rejected the credential.
final class KitAppLockFailed extends KitAppLockOutcome {
  const KitAppLockFailed({
    required this.method,
    this.biometricReason,
    this.lockedOut = false,
    this.cooldownStarted = false,
  });

  /// Which credential was tried.
  final KitAppLockMethod method;

  /// The underlying biometric reason, when [method] is
  /// [KitAppLockMethod.biometric].
  final KitBiometricFailureReason? biometricReason;

  /// True when this failure tripped the biometric lockout (PIN now required).
  final bool lockedOut;

  /// True when this failure tripped the PIN [KitAppLockConfig.cooldown].
  final bool cooldownStarted;

  @override
  bool operator ==(Object other) =>
      other is KitAppLockFailed &&
      method == other.method &&
      biometricReason == other.biometricReason &&
      lockedOut == other.lockedOut &&
      cooldownStarted == other.cooldownStarted;

  @override
  int get hashCode =>
      Object.hash(method, biometricReason, lockedOut, cooldownStarted);

  @override
  String toString() => 'KitAppLockFailed(method: ${method.name}, '
      'biometricReason: ${biometricReason?.name}, lockedOut: $lockedOut, '
      'cooldownStarted: $cooldownStarted)';
}
