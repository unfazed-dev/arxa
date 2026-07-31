import 'package:flutter/foundation.dart';

import 'kit_biometric_type.dart';

/// Whether biometric authentication can run right now.
enum KitBiometricAvailabilityStatus {
  /// No biometric hardware, or the platform cannot check biometrics at all.
  unsupported,

  /// Hardware is present but the user has enrolled no biometrics (or has not
  /// granted the app access to them). Recoverable by enrolling in Settings.
  notEnrolled,

  /// Biometrics are enrolled and ready; see [KitBiometricAvailability.types].
  available,
}

/// The typed result of [KitBiometricService.availability].
///
/// [status] is the actionable state a UI branches on; [types] lists the
/// specific modalities the platform reported (may be empty on Android, which
/// often reports only a strong/weak class rather than a modality even when
/// [status] is [KitBiometricAvailabilityStatus.available]).
@immutable
class KitBiometricAvailability {
  const KitBiometricAvailability({
    required this.status,
    this.types = const <KitBiometricType>{},
  });

  /// Biometrics are ready; [types] are the reported modalities.
  const KitBiometricAvailability.available(this.types)
      : status = KitBiometricAvailabilityStatus.available;

  /// Hardware present, nothing enrolled.
  const KitBiometricAvailability.notEnrolled()
      : status = KitBiometricAvailabilityStatus.notEnrolled,
        types = const <KitBiometricType>{};

  /// No usable biometric capability.
  const KitBiometricAvailability.unsupported()
      : status = KitBiometricAvailabilityStatus.unsupported,
        types = const <KitBiometricType>{};

  /// The actionable availability state.
  final KitBiometricAvailabilityStatus status;

  /// The specific modalities reported by the platform. Possibly empty even
  /// when [status] is [KitBiometricAvailabilityStatus.available].
  final Set<KitBiometricType> types;

  /// True when [KitBiometricService.authenticate] may be attempted.
  bool get canAuthenticate =>
      status == KitBiometricAvailabilityStatus.available;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KitBiometricAvailability &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          setEquals(types, other.types);

  @override
  int get hashCode => Object.hash(status, Object.hashAllUnordered(types));

  @override
  String toString() =>
      'KitBiometricAvailability(status: ${status.name}, types: $types)';
}
