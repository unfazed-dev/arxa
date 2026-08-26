import 'arxa_kit_biometric_availability.dart';
import 'arxa_kit_biometric_result.dart';

/// Port for local biometric authentication.
///
/// The app depends on this seam and the [ArxaKitBiometricAvailability] /
/// [ArxaKitBiometricResult] value types; the production binding
/// (`LocalAuthArxaKitBiometricService`) wraps `local_auth`. Tests and demos use the
/// scriptable fake from `package:arxa_kit_security/arxa_kit_testing.dart`.
///
/// No plugin exception or enum crosses this boundary — every platform failure
/// is projected onto [ArxaKitBiometricFailureReason].
abstract interface class ArxaKitBiometricService {
  /// Reports whether biometrics can run and which modalities are enrolled,
  /// without prompting the user.
  Future<ArxaKitBiometricAvailability> availability();

  /// Prompts the user to authenticate, showing [reason] in the system dialog.
  ///
  /// Returns [ArxaKitBiometricSuccess] on success, or [ArxaKitBiometricFailure] with a
  /// typed [ArxaKitBiometricFailureReason] otherwise. Never throws for an ordinary
  /// authentication failure.
  Future<ArxaKitBiometricResult> authenticate({required String reason});
}
