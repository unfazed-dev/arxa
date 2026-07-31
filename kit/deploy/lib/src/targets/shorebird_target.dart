import '../kit_deploy_target.dart';
import '../models/kit_deploy_config.dart';
import '../models/kit_deploy_result.dart';
import '../process/kit_process_runner.dart';

/// What a [ShorebirdTarget] does when deployed.
enum ShorebirdMode { release, patch }

/// Wired shorebird backend for over-the-air code push.
///
/// - release: `shorebird release <platform> [--flutter-version=X] [--dart-define=...]`
/// - patch:   `shorebird patch <platform> [--release-version=Y]`
class ShorebirdTarget implements KitDeployTarget {
  const ShorebirdTarget(
    this._runner, {
    required this.mode,
    this.platform = 'android',
  });

  final KitProcessRunner _runner;
  final ShorebirdMode mode;

  /// `android` or `ios`.
  final String platform;

  @override
  String get name => 'shorebird-${mode.name}';

  @override
  Future<List<KitDoctorCheck>> doctor(KitDeployConfig config) async {
    final result = await _runner.run(
      'shorebird',
      const ['doctor'],
      workingDirectory: config.workingDirectory,
    );
    return [
      KitDoctorCheck(
        name: 'shorebird doctor',
        ok: result.ok,
        detail: result.ok
            ? 'toolchain healthy'
            : result.stderr.trim().isEmpty
                ? 'shorebird not found on PATH'
                : result.stderr.trim(),
      ),
    ];
  }

  @override
  Future<KitDeployResult> deploy(KitDeployConfig config) async {
    final args = switch (mode) {
      ShorebirdMode.release => [
          'release',
          platform,
          if (config.flutterVersion != null)
            '--flutter-version=${config.flutterVersion}',
          ...config.dartDefineArgs,
        ],
      ShorebirdMode.patch => [
          'patch',
          platform,
          if (config.releaseVersion != null)
            '--release-version=${config.releaseVersion}',
          ...config.dartDefineArgs,
        ],
    };
    final result = await _runner.run(
      'shorebird',
      args,
      workingDirectory: config.workingDirectory,
      environment: config.environment.isEmpty ? null : config.environment,
    );
    return KitDeployResult(
      target: name,
      ok: result.ok,
      commandsRun: ['shorebird ${args.join(' ')}'],
      failureReason: result.ok
          ? null
          : 'shorebird exited ${result.exitCode}: ${result.stderr.trim()}',
    );
  }
}
