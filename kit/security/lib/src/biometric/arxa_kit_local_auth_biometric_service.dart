import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'arxa_kit_biometric_availability.dart';
import 'arxa_kit_biometric_result.dart';
import 'arxa_kit_biometric_service.dart';
import 'arxa_kit_biometric_type.dart';

/// Production [ArxaKitBiometricService] backed by `local_auth`.
///
/// A thin adapter: it queries the plugin for hardware/enrollment state and runs
/// a biometric-only prompt, projecting `local_auth`'s [BiometricType] onto
/// [ArxaKitBiometricType] and its [LocalAuthExceptionCode] onto
/// [ArxaKitBiometricFailureReason]. The plugin's types never leave this file.
class LocalAuthArxaKitBiometricService implements ArxaKitBiometricService {
  LocalAuthArxaKitBiometricService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<ArxaKitBiometricAvailability> availability() async {
    // `canCheckBiometrics` is the biometric-hardware gate. Without it, this
    // port has nothing to offer regardless of any passcode fallback.
    final canCheck = await _localAuth.canCheckBiometrics;
    if (!canCheck) return const ArxaKitBiometricAvailability.unsupported();

    final enrolled = await _localAuth.getAvailableBiometrics();
    if (enrolled.isEmpty) return const ArxaKitBiometricAvailability.notEnrolled();

    final types = enrolled
        .map(mapBiometricType)
        .whereType<ArxaKitBiometricType>()
        .toSet();
    return ArxaKitBiometricAvailability.available(types);
  }

  @override
  Future<ArxaKitBiometricResult> authenticate({required String reason}) async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        // This is the biometric seam; passcode fallback is the app-lock's job.
        biometricOnly: true,
      );
      // A `false` return is a failed challenge with no side effects — the user
      // simply did not authenticate.
      return ok
          ? const ArxaKitBiometricSuccess()
          : const ArxaKitBiometricFailure(ArxaKitBiometricFailureReason.error);
    } on LocalAuthException catch (e) {
      return ArxaKitBiometricFailure(mapExceptionCode(e.code));
    }
  }

  /// Projects a `local_auth` [BiometricType] onto a [ArxaKitBiometricType], or
  /// `null` for the coarse `strong` / `weak` Android classes (which name no
  /// specific modality).
  @visibleForTesting
  static ArxaKitBiometricType? mapBiometricType(BiometricType type) =>
      switch (type) {
        BiometricType.face => ArxaKitBiometricType.face,
        BiometricType.fingerprint => ArxaKitBiometricType.fingerprint,
        BiometricType.iris => ArxaKitBiometricType.iris,
        BiometricType.strong || BiometricType.weak => null,
      };

  /// Projects a `local_auth` [LocalAuthExceptionCode] onto the typed
  /// [ArxaKitBiometricFailureReason]. Unlisted / future codes collapse to
  /// [ArxaKitBiometricFailureReason.error] (the plugin documents its code enum as
  /// non-exhaustive, so callers must never assume otherwise).
  @visibleForTesting
  static ArxaKitBiometricFailureReason mapExceptionCode(
    LocalAuthExceptionCode code,
  ) =>
      switch (code) {
        LocalAuthExceptionCode.uiUnavailable =>
          ArxaKitBiometricFailureReason.unavailable,
        LocalAuthExceptionCode.userCanceled =>
          ArxaKitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.timeout => ArxaKitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.systemCanceled =>
          ArxaKitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.userRequestedFallback =>
          ArxaKitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.noCredentialsSet =>
          ArxaKitBiometricFailureReason.notEnrolled,
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          ArxaKitBiometricFailureReason.notEnrolled,
        LocalAuthExceptionCode.noBiometricHardware =>
          ArxaKitBiometricFailureReason.unavailable,
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          ArxaKitBiometricFailureReason.unavailable,
        LocalAuthExceptionCode.temporaryLockout =>
          ArxaKitBiometricFailureReason.lockedOut,
        LocalAuthExceptionCode.biometricLockout =>
          ArxaKitBiometricFailureReason.permanentlyLockedOut,
        // authInProgress, deviceError, unknownError, and any future code.
        _ => ArxaKitBiometricFailureReason.error,
      };
}
