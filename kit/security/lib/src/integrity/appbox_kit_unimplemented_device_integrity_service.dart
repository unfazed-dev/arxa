import 'appbox_kit_device_integrity_service.dart';
import 'appbox_kit_integrity_report.dart';

/// The phase-1 stub [AppBoxKitDeviceIntegrityService].
///
/// [check] throws [UnsupportedError] — a real integrity check must be
/// native-first (see README) and no production binding ships yet. Wire the
/// scriptable fake from `appbox_kit_testing.dart` for UIs and tests until then.
class UnimplementedAppBoxKitDeviceIntegrityService
    implements AppBoxKitDeviceIntegrityService {
  const UnimplementedAppBoxKitDeviceIntegrityService();

  @override
  Future<AppBoxKitIntegrityReport> check() {
    throw UnsupportedError(
      'AppBoxKitDeviceIntegrityService has no production binding yet. Device '
      'integrity is native-first (phase 2). Inject a real implementation, or '
      'use FakeAppBoxKitDeviceIntegrityService from '
      'package:appbox_kit_security/appbox_kit_testing.dart in tests and demos.',
    );
  }
}
