import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'kit_biometric_availability.dart';
import 'kit_biometric_result.dart';
import 'kit_biometric_service.dart';
import 'kit_biometric_type.dart';

/// Production [KitBiometricService] backed by `local_auth`.
///
/// A thin adapter: it queries the plugin for hardware/enrollment state and runs
/// a biometric-only prompt, projecting `local_auth`'s [BiometricType] onto
/// [KitBiometricType] and its [LocalAuthExceptionCode] onto
/// [KitBiometricFailureReason]. The plugin's types never leave this file.
class LocalAuthKitBiometricService implements KitBiometricService {
  LocalAuthKitBiometricService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<KitBiometricAvailability> availability() async {
    // `canCheckBiometrics` is the biometric-hardware gate. Without it, this
    // port has nothing to offer regardless of any passcode fallback.
    final canCheck = await _localAuth.canCheckBiometrics;
    if (!canCheck) return const KitBiometricAvailability.unsupported();

    final enrolled = await _localAuth.getAvailableBiometrics();
    if (enrolled.isEmpty) return const KitBiometricAvailability.notEnrolled();

    final types = enrolled
        .map(mapBiometricType)
        .whereType<KitBiometricType>()
        .toSet();
    return KitBiometricAvailability.available(types);
  }

  @override
  Future<KitBiometricResult> authenticate({required String reason}) async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        // This is the biometric seam; passcode fallback is the app-lock's job.
        biometricOnly: true,
      );
      // A `false` return is a failed challenge with no side effects — the user
      // simply did not authenticate.
      return ok
          ? const KitBiometricSuccess()
          : const KitBiometricFailure(KitBiometricFailureReason.error);
    } on LocalAuthException catch (e) {
      return KitBiometricFailure(mapExceptionCode(e.code));
    }
  }

  /// Projects a `local_auth` [BiometricType] onto a [KitBiometricType], or
  /// `null` for the coarse `strong` / `weak` Android classes (which name no
  /// specific modality).
  @visibleForTesting
  static KitBiometricType? mapBiometricType(BiometricType type) =>
      switch (type) {
        BiometricType.face => KitBiometricType.face,
        BiometricType.fingerprint => KitBiometricType.fingerprint,
        BiometricType.iris => KitBiometricType.iris,
        BiometricType.strong || BiometricType.weak => null,
      };

  /// Projects a `local_auth` [LocalAuthExceptionCode] onto the typed
  /// [KitBiometricFailureReason]. Unlisted / future codes collapse to
  /// [KitBiometricFailureReason.error] (the plugin documents its code enum as
  /// non-exhaustive, so callers must never assume otherwise).
  @visibleForTesting
  static KitBiometricFailureReason mapExceptionCode(
    LocalAuthExceptionCode code,
  ) =>
      switch (code) {
        LocalAuthExceptionCode.uiUnavailable =>
          KitBiometricFailureReason.unavailable,
        LocalAuthExceptionCode.userCanceled =>
          KitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.timeout => KitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.systemCanceled =>
          KitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.userRequestedFallback =>
          KitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.noCredentialsSet =>
          KitBiometricFailureReason.notEnrolled,
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          KitBiometricFailureReason.notEnrolled,
        LocalAuthExceptionCode.noBiometricHardware =>
          KitBiometricFailureReason.unavailable,
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          KitBiometricFailureReason.unavailable,
        LocalAuthExceptionCode.temporaryLockout =>
          KitBiometricFailureReason.lockedOut,
        LocalAuthExceptionCode.biometricLockout =>
          KitBiometricFailureReason.permanentlyLockedOut,
        // authInProgress, deviceError, unknownError, and any future code.
        _ => KitBiometricFailureReason.error,
      };
}
