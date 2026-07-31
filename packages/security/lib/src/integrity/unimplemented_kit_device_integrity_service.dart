import 'kit_device_integrity_service.dart';
import 'kit_integrity_report.dart';

/// The phase-1 stub [KitDeviceIntegrityService].
///
/// [check] throws [UnsupportedError] — a real integrity check must be
/// native-first (see README) and no production binding ships yet. Wire the
/// scriptable fake from `testing.dart` for UIs and tests until then.
class UnimplementedKitDeviceIntegrityService
    implements KitDeviceIntegrityService {
  const UnimplementedKitDeviceIntegrityService();

  @override
  Future<KitIntegrityReport> check() {
    throw UnsupportedError(
      'KitDeviceIntegrityService has no production binding yet. Device '
      'integrity is native-first (phase 2). Inject a real implementation, or '
      'use FakeKitDeviceIntegrityService from '
      'package:appbox_kit_security/testing.dart in tests and demos.',
    );
  }
}
