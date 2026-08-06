/// Why a biometric authentication attempt did not succeed.
///
/// A lossy-but-actionable projection of the platform failure codes onto the
/// branches a UI reacts to. See `LocalAuthAppBoxKitBiometricService.mapExceptionCode`
/// for the exact mapping from `local_auth`'s `LocalAuthExceptionCode`.
enum AppBoxKitBiometricFailureReason {
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

/// The typed outcome of [AppBoxKitBiometricService.authenticate].
sealed class AppBoxKitBiometricResult {
  const AppBoxKitBiometricResult();

  /// True for [AppBoxKitBiometricSuccess].
  bool get isSuccess => this is AppBoxKitBiometricSuccess;
}

/// The user authenticated successfully.
final class AppBoxKitBiometricSuccess extends AppBoxKitBiometricResult {
  const AppBoxKitBiometricSuccess();

  @override
  bool operator ==(Object other) => other is AppBoxKitBiometricSuccess;

  @override
  int get hashCode => (AppBoxKitBiometricSuccess).hashCode;

  @override
  String toString() => 'AppBoxKitBiometricSuccess()';
}

/// Authentication did not succeed; [reason] says why.
final class AppBoxKitBiometricFailure extends AppBoxKitBiometricResult {
  const AppBoxKitBiometricFailure(this.reason);

  /// The typed reason for the failure.
  final AppBoxKitBiometricFailureReason reason;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitBiometricFailure && reason == other.reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() => 'AppBoxKitBiometricFailure(${reason.name})';
}
