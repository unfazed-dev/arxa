import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'appbox_kit_biometric_availability.dart';
import 'appbox_kit_biometric_result.dart';
import 'appbox_kit_biometric_service.dart';
import 'appbox_kit_biometric_type.dart';

/// Production [AppBoxKitBiometricService] backed by `local_auth`.
///
/// A thin adapter: it queries the plugin for hardware/enrollment state and runs
/// a biometric-only prompt, projecting `local_auth`'s [BiometricType] onto
/// [AppBoxKitBiometricType] and its [LocalAuthExceptionCode] onto
/// [AppBoxKitBiometricFailureReason]. The plugin's types never leave this file.
class LocalAuthAppBoxKitBiometricService implements AppBoxKitBiometricService {
  LocalAuthAppBoxKitBiometricService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<AppBoxKitBiometricAvailability> availability() async {
    // `canCheckBiometrics` is the biometric-hardware gate. Without it, this
    // port has nothing to offer regardless of any passcode fallback.
    final canCheck = await _localAuth.canCheckBiometrics;
    if (!canCheck) return const AppBoxKitBiometricAvailability.unsupported();

    final enrolled = await _localAuth.getAvailableBiometrics();
    if (enrolled.isEmpty) return const AppBoxKitBiometricAvailability.notEnrolled();

    final types = enrolled
        .map(mapBiometricType)
        .whereType<AppBoxKitBiometricType>()
        .toSet();
    return AppBoxKitBiometricAvailability.available(types);
  }

  @override
  Future<AppBoxKitBiometricResult> authenticate({required String reason}) async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        // This is the biometric seam; passcode fallback is the app-lock's job.
        biometricOnly: true,
      );
      // A `false` return is a failed challenge with no side effects — the user
      // simply did not authenticate.
      return ok
          ? const AppBoxKitBiometricSuccess()
          : const AppBoxKitBiometricFailure(AppBoxKitBiometricFailureReason.error);
    } on LocalAuthException catch (e) {
      return AppBoxKitBiometricFailure(mapExceptionCode(e.code));
    }
  }

  /// Projects a `local_auth` [BiometricType] onto a [AppBoxKitBiometricType], or
  /// `null` for the coarse `strong` / `weak` Android classes (which name no
  /// specific modality).
  @visibleForTesting
  static AppBoxKitBiometricType? mapBiometricType(BiometricType type) =>
      switch (type) {
        BiometricType.face => AppBoxKitBiometricType.face,
        BiometricType.fingerprint => AppBoxKitBiometricType.fingerprint,
        BiometricType.iris => AppBoxKitBiometricType.iris,
        BiometricType.strong || BiometricType.weak => null,
      };

  /// Projects a `local_auth` [LocalAuthExceptionCode] onto the typed
  /// [AppBoxKitBiometricFailureReason]. Unlisted / future codes collapse to
  /// [AppBoxKitBiometricFailureReason.error] (the plugin documents its code enum as
  /// non-exhaustive, so callers must never assume otherwise).
  @visibleForTesting
  static AppBoxKitBiometricFailureReason mapExceptionCode(
    LocalAuthExceptionCode code,
  ) =>
      switch (code) {
        LocalAuthExceptionCode.uiUnavailable =>
          AppBoxKitBiometricFailureReason.unavailable,
        LocalAuthExceptionCode.userCanceled =>
          AppBoxKitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.timeout => AppBoxKitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.systemCanceled =>
          AppBoxKitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.userRequestedFallback =>
          AppBoxKitBiometricFailureReason.cancelled,
        LocalAuthExceptionCode.noCredentialsSet =>
          AppBoxKitBiometricFailureReason.notEnrolled,
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          AppBoxKitBiometricFailureReason.notEnrolled,
        LocalAuthExceptionCode.noBiometricHardware =>
          AppBoxKitBiometricFailureReason.unavailable,
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          AppBoxKitBiometricFailureReason.unavailable,
        LocalAuthExceptionCode.temporaryLockout =>
          AppBoxKitBiometricFailureReason.lockedOut,
        LocalAuthExceptionCode.biometricLockout =>
          AppBoxKitBiometricFailureReason.permanentlyLockedOut,
        // authInProgress, deviceError, unknownError, and any future code.
        _ => AppBoxKitBiometricFailureReason.error,
      };
}
