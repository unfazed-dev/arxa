import 'kit_integrity_report.dart';

/// Port for a device-integrity / anti-tamper check.
///
/// Phase 2 — native-first (see README). No production binding ships yet;
/// [UnimplementedKitDeviceIntegrityService] throws, and the scriptable fake in
/// `package:appbox_kit_security/testing.dart` drives UIs and tests. This kit
/// deliberately adds no root-detection plugin dependency.
abstract interface class KitDeviceIntegrityService {
  /// Collects the device-trust signals into a [KitIntegrityReport].
  Future<KitIntegrityReport> check();
}
