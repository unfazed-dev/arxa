import '../biometric/arxa_kit_biometric_result.dart';

/// Which credential an unlock attempt used.
enum ArxaKitAppLockMethod {
  /// A biometric prompt.
  biometric,

  /// A PIN entry.
  pin,
}

/// Why an unlock attempt was refused before any authenticator was consulted.
enum ArxaKitAppLockDenialReason {
  /// An unlock is already in flight ([ArxaKitAppLockState.unlocking]).
  busy,

  /// The biometric path is locked out after too many failures; use the PIN.
  biometricLockedOut,

  /// PIN entry is in a cooldown window after too many failures.
  inCooldown,
}

/// The typed result of a [ArxaKitAppLockController] unlock attempt.
sealed class ArxaKitAppLockOutcome {
  const ArxaKitAppLockOutcome();

  /// True only for [ArxaKitAppLockUnlocked].
  bool get didUnlock => this is ArxaKitAppLockUnlocked;
}

/// The app is now unlocked (freshly authenticated, or already open).
final class ArxaKitAppLockUnlocked extends ArxaKitAppLockOutcome {
  const ArxaKitAppLockUnlocked();

  @override
  bool operator ==(Object other) => other is ArxaKitAppLockUnlocked;

  @override
  int get hashCode => (ArxaKitAppLockUnlocked).hashCode;

  @override
  String toString() => 'ArxaKitAppLockUnlocked()';
}

/// The attempt was refused up front, without consulting an authenticator.
final class ArxaKitAppLockDenied extends ArxaKitAppLockOutcome {
  const ArxaKitAppLockDenied(this.reason);

  /// Why the attempt was refused.
  final ArxaKitAppLockDenialReason reason;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitAppLockDenied && reason == other.reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'ArxaKitAppLockDenied(${reason.name})';
}

/// An authenticator was consulted and rejected the credential.
final class ArxaKitAppLockFailed extends ArxaKitAppLockOutcome {
  const ArxaKitAppLockFailed({
    required this.method,
    this.biometricReason,
    this.lockedOut = false,
    this.cooldownStarted = false,
  });

  /// Which credential was tried.
  final ArxaKitAppLockMethod method;

  /// The underlying biometric reason, when [method] is
  /// [ArxaKitAppLockMethod.biometric].
  final ArxaKitBiometricFailureReason? biometricReason;

  /// True when this failure tripped the biometric lockout (PIN now required).
  final bool lockedOut;

  /// True when this failure tripped the PIN [ArxaKitAppLockConfig.cooldown].
  final bool cooldownStarted;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitAppLockFailed &&
      method == other.method &&
      biometricReason == other.biometricReason &&
      lockedOut == other.lockedOut &&
      cooldownStarted == other.cooldownStarted;

  @override
  int get hashCode =>
      Object.hash(method, biometricReason, lockedOut, cooldownStarted);

  @override
  String toString() => 'ArxaKitAppLockFailed(method: ${method.name}, '
      'biometricReason: ${biometricReason?.name}, lockedOut: $lockedOut, '
      'cooldownStarted: $cooldownStarted)';
}
