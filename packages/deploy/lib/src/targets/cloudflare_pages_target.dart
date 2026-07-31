import '../kit_deploy_target.dart';
import '../models/kit_deploy_config.dart';
import '../models/kit_deploy_result.dart';
import '../process/kit_process_runner.dart';

/// Wired Cloudflare Pages backend for static Flutter web builds:
///
/// 1. `flutter build web --release [--dart-define=...]`
/// 2. `wrangler pages deploy build/web --project-name=<projectName>`
///
/// Auth comes from CLOUDFLARE_API_TOKEN in [KitDeployConfig.environment]
/// (or ambient `wrangler login` state).
class CloudflarePagesTarget implements KitDeployTarget {
  const CloudflarePagesTarget(this._runner);

  final KitProcessRunner _runner;

  static const String _outputDirectory = 'build/web';

  @override
  String get name => 'cloudflare-pages';

  @override
  Future<List<KitDoctorCheck>> doctor(KitDeployConfig config) async {
    final wrangler = await _runner.run(
      'wrangler',
      const ['--version'],
      workingDirectory: config.workingDirectory,
    );
    final hasToken = config.environment.containsKey('CLOUDFLARE_API_TOKEN');
    return [
      KitDoctorCheck(
        name: 'wrangler CLI',
        ok: wrangler.ok,
        detail: wrangler.ok
            ? wrangler.stdout.trim()
            : 'wrangler not found on PATH (npm i -g wrangler)',
      ),
      KitDoctorCheck(
        name: 'CLOUDFLARE_API_TOKEN',
        ok: hasToken,
        detail: hasToken
            ? 'provided via config.environment'
            : 'not set — relying on ambient `wrangler login` credentials',
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

    final deployArgs = [
      'pages',
      'deploy',
      _outputDirectory,
      '--project-name=${config.projectName}',
    ];
    commands.add('wrangler ${deployArgs.join(' ')}');
    final deploy = await _runner.run(
      'wrangler',
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
          : 'wrangler exited ${deploy.exitCode}: ${deploy.stderr.trim()}',
    );
  }
}
