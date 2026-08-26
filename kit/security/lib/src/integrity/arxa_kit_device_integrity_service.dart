import 'arxa_kit_integrity_report.dart';

/// Port for a device-integrity / anti-tamper check.
///
/// Phase 2 — native-first (see README). No production binding ships yet;
/// [UnimplementedArxaKitDeviceIntegrityService] throws, and the scriptable fake in
/// `package:arxa_kit_security/arxa_kit_testing.dart` drives UIs and tests. This kit
/// deliberately adds no root-detection plugin dependency.
abstract interface class ArxaKitDeviceIntegrityService {
  /// Collects the device-trust signals into a [ArxaKitIntegrityReport].
  Future<ArxaKitIntegrityReport> check();
}
