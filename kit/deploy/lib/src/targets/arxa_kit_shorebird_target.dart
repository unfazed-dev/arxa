import '../arxa_kit_deploy_target.dart';
import '../models/arxa_kit_deploy_config.dart';
import '../models/arxa_kit_deploy_result.dart';
import '../process/arxa_kit_process_runner.dart';

/// What a [ArxaKitShorebirdTarget] does when deployed.
enum ArxaKitShorebirdMode { release, patch }

/// Wired shorebird backend for over-the-air code push.
///
/// - release: `shorebird release <platform> [--flutter-version=X] [--dart-define=...]`
/// - patch:   `shorebird patch <platform> [--release-version=Y]`
class ArxaKitShorebirdTarget implements ArxaKitDeployTarget {
  const ArxaKitShorebirdTarget(
    this._runner, {
    required this.mode,
    this.platform = 'android',
  });

  final ArxaKitProcessRunner _runner;
  final ArxaKitShorebirdMode mode;

  /// `android` or `ios`.
  final String platform;

  @override
  String get name => 'shorebird-${mode.name}';

  @override
  Future<List<ArxaKitDoctorCheck>> doctor(ArxaKitDeployConfig config) async {
    final result = await _runner.run(
      'shorebird',
      const ['doctor'],
      workingDirectory: config.workingDirectory,
    );
    return [
      ArxaKitDoctorCheck(
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
  Future<ArxaKitDeployResult> deploy(ArxaKitDeployConfig config) async {
    final args = switch (mode) {
      ArxaKitShorebirdMode.release => [
          'release',
          platform,
          if (config.flutterVersion != null)
            '--flutter-version=${config.flutterVersion}',
          ...config.dartDefineArgs,
        ],
      ArxaKitShorebirdMode.patch => [
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
    return ArxaKitDeployResult(
      target: name,
      ok: result.ok,
      commandsRun: ['shorebird ${args.join(' ')}'],
      failureReason: result.ok
          ? null
          : 'shorebird exited ${result.exitCode}: ${result.stderr.trim()}',
    );
  }
}
