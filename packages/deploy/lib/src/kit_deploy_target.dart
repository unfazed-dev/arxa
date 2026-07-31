import 'models/kit_deploy_config.dart';
import 'models/kit_deploy_result.dart';

/// Port every deploy backend implements.
abstract interface class KitDeployTarget {
  /// Stable identifier used by [KitDeployService.deployTo] and the CLI
  /// (e.g. `fastlane-android`, `shorebird-release`, `cloudflare-pages`).
  String get name;

  /// Non-destructive environment verification (CLI installed, tokens set).
  Future<List<KitDoctorCheck>> doctor(KitDeployConfig config);

  /// Runs the deployment. Never throws for tool failures — returns
  /// `ok: false` with [KitDeployResult.failureReason] instead. Stub targets
  /// may throw [UnimplementedError].
  Future<KitDeployResult> deploy(KitDeployConfig config);
}
