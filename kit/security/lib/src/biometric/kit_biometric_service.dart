import 'kit_biometric_availability.dart';
import 'kit_biometric_result.dart';

/// Port for local biometric authentication.
///
/// The app depends on this seam and the [KitBiometricAvailability] /
/// [KitBiometricResult] value types; the production binding
/// (`LocalAuthKitBiometricService`) wraps `local_auth`. Tests and demos use the
/// scriptable fake from `package:appbox_kit_security/testing.dart`.
///
/// No plugin exception or enum crosses this boundary — every platform failure
/// is projected onto [KitBiometricFailureReason].
abstract interface class KitBiometricService {
  /// Reports whether biometrics can run and which modalities are enrolled,
  /// without prompting the user.
  Future<KitBiometricAvailability> availability();

  /// Prompts the user to authenticate, showing [reason] in the system dialog.
  ///
  /// Returns [KitBiometricSuccess] on success, or [KitBiometricFailure] with a
  /// typed [KitBiometricFailureReason] otherwise. Never throws for an ordinary
  /// authentication failure.
  Future<KitBiometricResult> authenticate({required String reason});
}
