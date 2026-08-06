import '../appbox_kit_deploy_target.dart';
import '../models/appbox_kit_deploy_config.dart';
import '../models/appbox_kit_deploy_result.dart';
import '../process/appbox_kit_process_runner.dart';

/// Wired Vercel backend for static Flutter web builds:
///
/// 1. `flutter build web --release [--dart-define=...]`
/// 2. `vercel deploy build/web --prod --yes`
///
/// Auth comes from VERCEL_TOKEN in [AppBoxKitDeployConfig.environment]. Vercel CLI
/// v55+ tightened non-interactive project linking — pin a CLI major version
/// (and set VERCEL_ORG_ID / VERCEL_PROJECT_ID to link non-interactively);
/// [doctor] surfaces the installed version so drift is visible.
class AppBoxKitVercelTarget implements AppBoxKitDeployTarget {
  const AppBoxKitVercelTarget(this._runner);

  final AppBoxKitProcessRunner _runner;

  static const String _outputDirectory = 'build/web';

  @override
  String get name => 'vercel';

  @override
  Future<List<AppBoxKitDoctorCheck>> doctor(AppBoxKitDeployConfig config) async {
    final vercel = await _runner.run(
      'vercel',
      const ['--version'],
      workingDirectory: config.workingDirectory,
    );
    final hasToken = config.environment.containsKey('VERCEL_TOKEN');
    return [
      AppBoxKitDoctorCheck(
        name: 'vercel CLI',
        ok: vercel.ok,
        detail: vercel.ok
            ? vercel.stdout.trim()
            : 'vercel not found on PATH (npm i -g vercel — pin a major)',
      ),
      AppBoxKitDoctorCheck(
        name: 'VERCEL_TOKEN',
        ok: hasToken,
        detail: hasToken
            ? 'provided via config.environment'
            : 'not set — vercel deploy will fail non-interactively',
      ),
    ];
  }

  @override
  Future<AppBoxKitDeployResult> deploy(AppBoxKitDeployConfig config) async {
    final commands = <String>[];

    final buildArgs = ['build', 'web', '--release', ...config.dartDefineArgs];
    commands.add('flutter ${buildArgs.join(' ')}');
    final build = await _runner.run(
      'flutter',
      buildArgs,
      workingDirectory: config.workingDirectory,
    );
    if (!build.ok) {
      return AppBoxKitDeployResult(
        target: name,
        ok: false,
        commandsRun: commands,
        failureReason:
            'flutter build web exited ${build.exitCode}: ${build.stderr.trim()}',
      );
    }

    final deployArgs = ['deploy', _outputDirectory, '--prod', '--yes'];
    commands.add('vercel ${deployArgs.join(' ')}');
    final deploy = await _runner.run(
      'vercel',
      deployArgs,
      workingDirectory: config.workingDirectory,
      environment: config.environment.isEmpty ? null : config.environment,
    );
    return AppBoxKitDeployResult(
      target: name,
      ok: deploy.ok,
      commandsRun: commands,
      failureReason: deploy.ok
          ? null
          : 'vercel exited ${deploy.exitCode}: ${deploy.stderr.trim()}',
    );
  }
}
