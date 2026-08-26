import 'models/arxa_kit_deploy_config.dart';
import 'models/arxa_kit_deploy_result.dart';

/// Port every deploy backend implements.
abstract interface class ArxaKitDeployTarget {
  /// Stable identifier used by [ArxaKitDeployService.deployTo] and the CLI
  /// (e.g. `fastlane-android`, `shorebird-release`, `cloudflare-pages`).
  String get name;

  /// Non-destructive environment verification (CLI installed, tokens set).
  Future<List<ArxaKitDoctorCheck>> doctor(ArxaKitDeployConfig config);

  /// Runs the deployment. Never throws for tool failures — returns
  /// `ok: false` with [ArxaKitDeployResult.failureReason] instead. Stub targets
  /// may throw [UnimplementedError].
  Future<ArxaKitDeployResult> deploy(ArxaKitDeployConfig config);
}
