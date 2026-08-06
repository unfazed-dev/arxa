import 'appbox_kit_biometric_availability.dart';
import 'appbox_kit_biometric_result.dart';

/// Port for local biometric authentication.
///
/// The app depends on this seam and the [AppBoxKitBiometricAvailability] /
/// [AppBoxKitBiometricResult] value types; the production binding
/// (`LocalAuthAppBoxKitBiometricService`) wraps `local_auth`. Tests and demos use the
/// scriptable fake from `package:appbox_kit_security/appbox_kit_testing.dart`.
///
/// No plugin exception or enum crosses this boundary — every platform failure
/// is projected onto [AppBoxKitBiometricFailureReason].
abstract interface class AppBoxKitBiometricService {
  /// Reports whether biometrics can run and which modalities are enrolled,
  /// without prompting the user.
  Future<AppBoxKitBiometricAvailability> availability();

  /// Prompts the user to authenticate, showing [reason] in the system dialog.
  ///
  /// Returns [AppBoxKitBiometricSuccess] on success, or [AppBoxKitBiometricFailure] with a
  /// typed [AppBoxKitBiometricFailureReason] otherwise. Never throws for an ordinary
  /// authentication failure.
  Future<AppBoxKitBiometricResult> authenticate({required String reason});
}
