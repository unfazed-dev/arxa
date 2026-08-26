/// Why a biometric authentication attempt did not succeed.
///
/// A lossy-but-actionable projection of the platform failure codes onto the
/// branches a UI reacts to. See `LocalAuthArxaKitBiometricService.mapExceptionCode`
/// for the exact mapping from `local_auth`'s `LocalAuthExceptionCode`.
enum ArxaKitBiometricFailureReason {
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

/// The typed outcome of [ArxaKitBiometricService.authenticate].
sealed class ArxaKitBiometricResult {
  const ArxaKitBiometricResult();

  /// True for [ArxaKitBiometricSuccess].
  bool get isSuccess => this is ArxaKitBiometricSuccess;
}

/// The user authenticated successfully.
final class ArxaKitBiometricSuccess extends ArxaKitBiometricResult {
  const ArxaKitBiometricSuccess();

  @override
  bool operator ==(Object other) => other is ArxaKitBiometricSuccess;

  @override
  int get hashCode => (ArxaKitBiometricSuccess).hashCode;

  @override
  String toString() => 'ArxaKitBiometricSuccess()';
}

/// Authentication did not succeed; [reason] says why.
final class ArxaKitBiometricFailure extends ArxaKitBiometricResult {
  const ArxaKitBiometricFailure(this.reason);

  /// The typed reason for the failure.
  final ArxaKitBiometricFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitBiometricFailure && reason == other.reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'ArxaKitBiometricFailure(${reason.name})';
}
