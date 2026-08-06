import 'package:flutter/foundation.dart';

import 'appbox_kit_biometric_type.dart';

/// Whether biometric authentication can run right now.
enum AppBoxKitBiometricAvailabilityStatus {
  /// No biometric hardware, or the platform cannot check biometrics at all.
  unsupported,

  /// Hardware is present but the user has enrolled no biometrics (or has not
  /// granted the app access to them). Recoverable by enrolling in Settings.
  notEnrolled,

  /// Biometrics are enrolled and ready; see [AppBoxKitBiometricAvailability.types].
  available,
}

/// The typed result of [AppBoxKitBiometricService.availability].
///
/// [status] is the actionable state a UI branches on; [types] lists the
/// specific modalities the platform reported (may be empty on Android, which
/// often reports only a strong/weak class rather than a modality even when
/// [status] is [AppBoxKitBiometricAvailabilityStatus.available]).
@immutable
class AppBoxKitBiometricAvailability {
  const AppBoxKitBiometricAvailability({
    required this.status,
    this.types = const <AppBoxKitBiometricType>{},
  });

  /// Biometrics are ready; [types] are the reported modalities.
  const AppBoxKitBiometricAvailability.available(this.types)
      : status = AppBoxKitBiometricAvailabilityStatus.available;

  /// Hardware present, nothing enrolled.
  const AppBoxKitBiometricAvailability.notEnrolled()
      : status = AppBoxKitBiometricAvailabilityStatus.notEnrolled,
        types = const <AppBoxKitBiometricType>{};

  /// No usable biometric capability.
  const AppBoxKitBiometricAvailability.unsupported()
      : status = AppBoxKitBiometricAvailabilityStatus.unsupported,
        types = const <AppBoxKitBiometricType>{};

  /// The actionable availability state.
  final AppBoxKitBiometricAvailabilityStatus status;

  /// The specific modalities reported by the platform. Possibly empty even
  /// when [status] is [AppBoxKitBiometricAvailabilityStatus.available].
  final Set<AppBoxKitBiometricType> types;

  /// True when [AppBoxKitBiometricService.authenticate] may be attempted.
  bool get canAuthenticate =>
      status == AppBoxKitBiometricAvailabilityStatus.available;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBoxKitBiometricAvailability &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          setEquals(types, other.types);

  @override
  int get hashCode => Object.hash(status, Object.hashAllUnordered(types));

  @override
  String toString() =>
      'AppBoxKitBiometricAvailability(status: ${status.name}, types: $types)';
}
