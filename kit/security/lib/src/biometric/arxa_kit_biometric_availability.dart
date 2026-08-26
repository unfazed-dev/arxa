import 'package:flutter/foundation.dart';

import 'arxa_kit_biometric_type.dart';

/// Whether biometric authentication can run right now.
enum ArxaKitBiometricAvailabilityStatus {
  /// No biometric hardware, or the platform cannot check biometrics at all.
  unsupported,

  /// Hardware is present but the user has enrolled no biometrics (or has not
  /// granted the app access to them). Recoverable by enrolling in Settings.
  notEnrolled,

  /// Biometrics are enrolled and ready; see [ArxaKitBiometricAvailability.types].
  available,
}

/// The typed result of [ArxaKitBiometricService.availability].
///
/// [status] is the actionable state a UI branches on; [types] lists the
/// specific modalities the platform reported (may be empty on Android, which
/// often reports only a strong/weak class rather than a modality even when
/// [status] is [ArxaKitBiometricAvailabilityStatus.available]).
@immutable
class ArxaKitBiometricAvailability {
  const ArxaKitBiometricAvailability({
    required this.status,
    this.types = const <ArxaKitBiometricType>{},
  });

  /// Biometrics are ready; [types] are the reported modalities.
  const ArxaKitBiometricAvailability.available(this.types)
      : status = ArxaKitBiometricAvailabilityStatus.available;

  /// Hardware present, nothing enrolled.
  const ArxaKitBiometricAvailability.notEnrolled()
      : status = ArxaKitBiometricAvailabilityStatus.notEnrolled,
        types = const <ArxaKitBiometricType>{};

  /// No usable biometric capability.
  const ArxaKitBiometricAvailability.unsupported()
      : status = ArxaKitBiometricAvailabilityStatus.unsupported,
        types = const <ArxaKitBiometricType>{};

  /// The actionable availability state.
  final ArxaKitBiometricAvailabilityStatus status;

  /// The specific modalities reported by the platform. Possibly empty even
  /// when [status] is [ArxaKitBiometricAvailabilityStatus.available].
  final Set<ArxaKitBiometricType> types;

  /// True when [ArxaKitBiometricService.authenticate] may be attempted.
  bool get canAuthenticate =>
      status == ArxaKitBiometricAvailabilityStatus.available;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArxaKitBiometricAvailability &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          setEquals(types, other.types);

  @override
  int get hashCode => Object.hash(status, Object.hashAllUnordered(types));

  @override
  String toString() =>
      'ArxaKitBiometricAvailability(status: ${status.name}, types: $types)';
}
