import '../kit_deploy_target.dart';
import '../models/kit_deploy_config.dart';
import '../models/kit_deploy_result.dart';
import '../process/kit_process_runner.dart';

/// Wired fastlane backend: `bundle exec fastlane <platform> <lane>`.
class FastlaneTarget implements KitDeployTarget {
  const FastlaneTarget(
    this._runner, {
    required this.platform,
    this.lane = 'release',
  }) : assert(platform == 'android' || platform == 'ios',
            'platform must be android or ios');

  final KitProcessRunner _runner;

  /// `android` or `ios` — the fastlane platform namespace.
  final String platform;

  /// Lane to invoke, e.g. `release`, `beta`.
  final String lane;

  @override
  String get name => 'fastlane-$platform';

  @override
  Future<List<KitDoctorCheck>> doctor(KitDeployConfig config) async {
    final version = await _runner.run(
      'fastlane',
      const ['--version'],
      workingDirectory: config.workingDirectory,
    );
    return [
      KitDoctorCheck(
        name: 'fastlane CLI',
        ok: version.ok,
        detail: version.ok
            ? version.stdout.trim().split('\n').last
            : 'fastlane not found on PATH (gem install fastlane)',
      ),
    ];
  }

  @override
  Future<KitDeployResult> deploy(KitDeployConfig config) async {
    final args = ['exec', 'fastlane', platform, lane];
    final result = await _runner.run(
      'bundle',
      args,
      workingDirectory: config.workingDirectory,
      environment: config.environment.isEmpty ? null : config.environment,
    );
    final command = 'bundle ${args.join(' ')}';
    return KitDeployResult(
      target: name,
      ok: result.ok,
      commandsRun: [command],
      failureReason: result.ok
          ? null
          : 'fastlane exited ${result.exitCode}: ${result.stderr.trim()}',
    );
  }
}
