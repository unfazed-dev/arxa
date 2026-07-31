import 'kit_deploy_target.dart';
import 'models/kit_deploy_config.dart';
import 'models/kit_deploy_result.dart';

/// Facade over a set of [KitDeployTarget]s.
class KitDeployService {
  KitDeployService({required List<KitDeployTarget> targets})
      : _targets = {for (final target in targets) target.name: target};

  final Map<String, KitDeployTarget> _targets;

  List<String> get targetNames => _targets.keys.toList(growable: false);

  KitDeployTarget targetNamed(String name) {
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
  Future<Map<String, List<KitDoctorCheck>>> doctor(
    KitDeployConfig config,
  ) async {
    final report = <String, List<KitDoctorCheck>>{};
    for (final target in _targets.values) {
      report[target.name] = await target.doctor(config);
    }
    return report;
  }

  Future<KitDeployResult> deployTo(String name, KitDeployConfig config) =>
      targetNamed(name).deploy(config);
}
