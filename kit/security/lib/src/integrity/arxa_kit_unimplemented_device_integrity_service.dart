import 'arxa_kit_device_integrity_service.dart';
import 'arxa_kit_integrity_report.dart';

/// The phase-1 stub [ArxaKitDeviceIntegrityService].
///
/// [check] throws [UnsupportedError] — a real integrity check must be
/// native-first (see README) and no production binding ships yet. Wire the
/// scriptable fake from `arxa_kit_testing.dart` for UIs and tests until then.
class UnimplementedArxaKitDeviceIntegrityService
    implements ArxaKitDeviceIntegrityService {
  const UnimplementedArxaKitDeviceIntegrityService();

  @override
  Future<ArxaKitIntegrityReport> check() {
    throw UnsupportedError(
      'ArxaKitDeviceIntegrityService has no production binding yet. Device '
      'integrity is native-first (phase 2). Inject a real implementation, or '
      'use FakeArxaKitDeviceIntegrityService from '
      'package:arxa_kit_security/arxa_kit_testing.dart in tests and demos.',
    );
  }
}
