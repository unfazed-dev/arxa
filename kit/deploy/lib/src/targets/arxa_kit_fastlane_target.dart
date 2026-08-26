import '../arxa_kit_deploy_target.dart';
import '../models/arxa_kit_deploy_config.dart';
import '../models/arxa_kit_deploy_result.dart';
import '../process/arxa_kit_process_runner.dart';

/// Wired fastlane backend: `bundle exec fastlane <platform> <lane>`.
class ArxaKitFastlaneTarget implements ArxaKitDeployTarget {
  const ArxaKitFastlaneTarget(
    this._runner, {
    required this.platform,
    this.lane = 'release',
  }) : assert(platform == 'android' || platform == 'ios',
            'platform must be android or ios');

  final ArxaKitProcessRunner _runner;

  /// `android` or `ios` — the fastlane platform namespace.
  final String platform;

  /// Lane to invoke, e.g. `release`, `beta`.
  final String lane;

  @override
  String get name => 'fastlane-$platform';

  @override
  Future<List<ArxaKitDoctorCheck>> doctor(ArxaKitDeployConfig config) async {
    final version = await _runner.run(
      'fastlane',
      const ['--version'],
      workingDirectory: config.workingDirectory,
    );
    return [
      ArxaKitDoctorCheck(
        name: 'fastlane CLI',
        ok: version.ok,
        detail: version.ok
            ? version.stdout.trim().split('\n').last
            : 'fastlane not found on PATH (gem install fastlane)',
      ),
    ];
  }

  @override
  Future<ArxaKitDeployResult> deploy(ArxaKitDeployConfig config) async {
    final args = ['exec', 'fastlane', platform, lane];
    final result = await _runner.run(
      'bundle',
      args,
      workingDirectory: config.workingDirectory,
      environment: config.environment.isEmpty ? null : config.environment,
    );
    final command = 'bundle ${args.join(' ')}';
    return ArxaKitDeployResult(
      target: name,
      ok: result.ok,
      commandsRun: [command],
      failureReason: result.ok
          ? null
          : 'fastlane exited ${result.exitCode}: ${result.stderr.trim()}',
    );
  }
}
