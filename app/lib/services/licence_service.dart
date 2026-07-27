import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/credential_service.dart';

/// The licence check is a **precondition, not a gate** (8.12).
///
/// It runs *before* the builder phase and, on failure, surfaces a licence
/// message. Brief non-negotiable #1: "Red must mean broken" — nothing goes red
/// for money. So this returns a precondition result the build surface shows
/// neutrally, never a hard error colour.
class LicenceService {
  Future<LicenceCheckResult> check() async {
    final creds = locator<CredentialService>();
    if (creds.hasLicence) {
      return const LicenceCheckResult(ok: true);
    }
    final config = locator<ConfigService>();
    return LicenceCheckResult(ok: false, message: config.licencePreconditionMessage);
  }
}

class LicenceCheckResult {
  final bool ok;
  final String? message;
  const LicenceCheckResult({required this.ok, this.message});
}
