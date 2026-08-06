import 'models/appbox_kit_deploy_config.dart';
import 'models/appbox_kit_deploy_result.dart';

/// Port every deploy backend implements.
abstract interface class AppBoxKitDeployTarget {
  /// Stable identifier used by [AppBoxKitDeployService.deployTo] and the CLI
  /// (e.g. `fastlane-android`, `shorebird-release`, `cloudflare-pages`).
  String get name;

  /// Non-destructive environment verification (CLI installed, tokens set).
  Future<List<AppBoxKitDoctorCheck>> doctor(AppBoxKitDeployConfig config);

  /// Runs the deployment. Never throws for tool failures — returns
  /// `ok: false` with [AppBoxKitDeployResult.failureReason] instead. Stub targets
  /// may throw [UnimplementedError].
  Future<AppBoxKitDeployResult> deploy(AppBoxKitDeployConfig config);
}
