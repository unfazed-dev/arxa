import '../appbox_kit_deploy_target.dart';
import '../models/appbox_kit_deploy_config.dart';
import '../models/appbox_kit_deploy_result.dart';
import '../process/appbox_kit_process_runner.dart';

/// What a [AppBoxKitShorebirdTarget] does when deployed.
enum AppBoxKitShorebirdMode { release, patch }

/// Wired shorebird backend for over-the-air code push.
///
/// - release: `shorebird release <platform> [--flutter-version=X] [--dart-define=...]`
/// - patch:   `shorebird patch <platform> [--release-version=Y]`
class AppBoxKitShorebirdTarget implements AppBoxKitDeployTarget {
  const AppBoxKitShorebirdTarget(
    this._runner, {
    required this.mode,
    this.platform = 'android',
  });

  final AppBoxKitProcessRunner _runner;
  final AppBoxKitShorebirdMode mode;

  /// `android` or `ios`.
  final String platform;

  @override
  String get name => 'shorebird-${mode.name}';

  @override
  Future<List<AppBoxKitDoctorCheck>> doctor(AppBoxKitDeployConfig config) async {
    final result = await _runner.run(
      'shorebird',
      const ['doctor'],
      workingDirectory: config.workingDirectory,
    );
    return [
      AppBoxKitDoctorCheck(
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
  Future<AppBoxKitDeployResult> deploy(AppBoxKitDeployConfig config) async {
    final args = switch (mode) {
      AppBoxKitShorebirdMode.release => [
          'release',
          platform,
          if (config.flutterVersion != null)
            '--flutter-version=${config.flutterVersion}',
          ...config.dartDefineArgs,
        ],
      AppBoxKitShorebirdMode.patch => [
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
    return AppBoxKitDeployResult(
      target: name,
      ok: result.ok,
      commandsRun: ['shorebird ${args.join(' ')}'],
      failureReason: result.ok
          ? null
          : 'shorebird exited ${result.exitCode}: ${result.stderr.trim()}',
    );
  }
}
