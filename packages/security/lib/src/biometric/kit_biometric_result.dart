/// Why a biometric authentication attempt did not succeed.
///
/// A lossy-but-actionable projection of the platform failure codes onto the
/// branches a UI reacts to. See `LocalAuthKitBiometricService.mapExceptionCode`
/// for the exact mapping from `local_auth`'s `LocalAuthExceptionCode`.
enum KitBiometricFailureReason {
  /// The user (or a system event, e.g. backgrounding) dismissed the prompt, or
  /// chose a fallback authentication method instead of biometrics.
  cancelled,

  /// Too many failed attempts; locked out temporarily. Retriable after a delay.
  lockedOut,

  /// Locked out until a stronger authentication (device passcode) succeeds. Not
  /// retriable with biometrics alone.
  permanentlyLockedOut,

  /// No biometrics (or device credentials) are enrolled to authenticate with.
  notEnrolled,

  /// The device has no biometric hardware, or it is temporarily unavailable.
  unavailable,

  /// A failed challenge or an unclassified device/plugin error.
  error,
}

/// The typed outcome of [KitBiometricService.authenticate].
sealed class KitBiometricResult {
  const KitBiometricResult();

  /// True for [KitBiometricSuccess].
  bool get isSuccess => this is KitBiometricSuccess;
}

/// The user authenticated successfully.
final class KitBiometricSuccess extends KitBiometricResult {
  const KitBiometricSuccess();

  @override
  bool operator ==(Object other) => other is KitBiometricSuccess;

  @override
  int get hashCode => (KitBiometricSuccess).hashCode;

  @override
  String toString() => 'KitBiometricSuccess()';
}

/// Authentication did not succeed; [reason] says why.
final class KitBiometricFailure extends KitBiometricResult {
  const KitBiometricFailure(this.reason);

  /// The typed reason for the failure.
  final KitBiometricFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is KitBiometricFailure && reason == other.reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'KitBiometricFailure(${reason.name})';
}
