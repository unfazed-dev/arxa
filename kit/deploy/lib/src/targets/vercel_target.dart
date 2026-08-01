import '../kit_deploy_target.dart';
import '../models/kit_deploy_config.dart';
import '../models/kit_deploy_result.dart';
import '../process/kit_process_runner.dart';

/// Wired Vercel backend for static Flutter web builds:
///
/// 1. `flutter build web --release [--dart-define=...]`
/// 2. `vercel deploy build/web --prod --yes`
///
/// Auth comes from VERCEL_TOKEN in [KitDeployConfig.environment]. Vercel CLI
/// v55+ tightened non-interactive project linking — pin a CLI major version
/// (and set VERCEL_ORG_ID / VERCEL_PROJECT_ID to link non-interactively);
/// [doctor] surfaces the installed version so drift is visible.
class VercelTarget implements KitDeployTarget {
  const VercelTarget(this._runner);

  final KitProcessRunner _runner;

  static const String _outputDirectory = 'build/web';

  @override
  String get name => 'vercel';

  @override
  Future<List<KitDoctorCheck>> doctor(KitDeployConfig config) async {
    final vercel = await _runner.run(
      'vercel',
      const ['--version'],
      workingDirectory: config.workingDirectory,
    );
    final hasToken = config.environment.containsKey('VERCEL_TOKEN');
    return [
      KitDoctorCheck(
        name: 'vercel CLI',
        ok: vercel.ok,
        detail: vercel.ok
            ? vercel.stdout.trim()
            : 'vercel not found on PATH (npm i -g vercel — pin a major)',
      ),
      KitDoctorCheck(
        name: 'VERCEL_TOKEN',
        ok: hasToken,
        detail: hasToken
            ? 'provided via config.environment'
            : 'not set — vercel deploy will fail non-interactively',
      ),
    ];
  }

  @override
  Future<KitDeployResult> deploy(KitDeployConfig config) async {
    final commands = <String>[];

    final buildArgs = ['build', 'web', '--release', ...config.dartDefineArgs];
    commands.add('flutter ${buildArgs.join(' ')}');
    final build = await _runner.run(
      'flutter',
      buildArgs,
      workingDirectory: config.workingDirectory,
    );
    if (!build.ok) {
      return KitDeployResult(
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
    return KitDeployResult(
      target: name,
      ok: deploy.ok,
      commandsRun: commands,
      failureReason: deploy.ok
          ? null
          : 'vercel exited ${deploy.exitCode}: ${deploy.stderr.trim()}',
    );
  }
}
