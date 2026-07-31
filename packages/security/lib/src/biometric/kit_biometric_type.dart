/// A biometric modality the platform can authenticate with.
///
/// Deliberately platform-neutral. `local_auth` also reports coarse `strong` /
/// `weak` Android classifications; those carry no specific modality and are
/// dropped from this set (see `LocalAuthKitBiometricService`) — the availability
/// *status* still reflects that biometrics are usable.
enum KitBiometricType {
  /// Face recognition (Face ID / Android face unlock).
  face,

  /// Fingerprint (Touch ID / Android fingerprint).
  fingerprint,

  /// Iris scanning.
  iris,
}
