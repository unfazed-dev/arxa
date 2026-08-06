import 'appbox_kit_deploy_target.dart';
import 'models/appbox_kit_deploy_config.dart';
import 'models/appbox_kit_deploy_result.dart';

/// Facade over a set of [AppBoxKitDeployTarget]s.
class AppBoxKitDeployService {
  AppBoxKitDeployService({required List<AppBoxKitDeployTarget> targets})
      : _targets = {for (final target in targets) target.name: target};

  final Map<String, AppBoxKitDeployTarget> _targets;

  List<String> get targetNames => _targets.keys.toList(growable: false);

  AppBoxKitDeployTarget targetNamed(String name) {
    final target = _targets[name];
    if (target == null) {
      throw ArgumentError.value(
        name,
        'name',
        'Unknown deploy target. Known: ${targetNames.join(', ')}',
      );
    }
    return target;
  }

  /// Runs doctor checks for every registered target.
  Future<Map<String, List<AppBoxKitDoctorCheck>>> doctor(
    AppBoxKitDeployConfig config,
  ) async {
    final report = <String, List<AppBoxKitDoctorCheck>>{};
    for (final target in _targets.values) {
      report[target.name] = await target.doctor(config);
    }
    return report;
  }

  Future<AppBoxKitDeployResult> deployTo(String name, AppBoxKitDeployConfig config) =>
      targetNamed(name).deploy(config);
}
