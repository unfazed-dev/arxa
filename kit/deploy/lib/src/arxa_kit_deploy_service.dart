import 'arxa_kit_deploy_target.dart';
import 'models/arxa_kit_deploy_config.dart';
import 'models/arxa_kit_deploy_result.dart';

/// Facade over a set of [ArxaKitDeployTarget]s.
class ArxaKitDeployService {
  ArxaKitDeployService({required List<ArxaKitDeployTarget> targets})
      : _targets = {for (final target in targets) target.name: target};

  final Map<String, ArxaKitDeployTarget> _targets;

  List<String> get targetNames => _targets.keys.toList(growable: false);

  ArxaKitDeployTarget targetNamed(String name) {
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
  Future<Map<String, List<ArxaKitDoctorCheck>>> doctor(
    ArxaKitDeployConfig config,
  ) async {
    final report = <String, List<ArxaKitDoctorCheck>>{};
    for (final target in _targets.values) {
      report[target.name] = await target.doctor(config);
    }
    return report;
  }

  Future<ArxaKitDeployResult> deployTo(String name, ArxaKitDeployConfig config) =>
      targetNamed(name).deploy(config);
}
