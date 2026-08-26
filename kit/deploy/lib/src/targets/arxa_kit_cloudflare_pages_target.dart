import '../arxa_kit_deploy_target.dart';
import '../models/arxa_kit_deploy_config.dart';
import '../models/arxa_kit_deploy_result.dart';
import '../process/arxa_kit_process_runner.dart';

/// Wired Cloudflare Pages backend for static Flutter web builds:
///
/// 1. `flutter build web --release [--dart-define=...]`
/// 2. `wrangler pages deploy build/web --project-name=<projectName>`
///
/// Auth comes from CLOUDFLARE_API_TOKEN in [ArxaKitDeployConfig.environment]
/// (or ambient `wrangler login` state).
class ArxaKitCloudflarePagesTarget implements ArxaKitDeployTarget {
  const ArxaKitCloudflarePagesTarget(this._runner);

  final ArxaKitProcessRunner _runner;

  static const String _outputDirectory = 'build/web';

  @override
  String get name => 'cloudflare-pages';

  @override
  Future<List<ArxaKitDoctorCheck>> doctor(ArxaKitDeployConfig config) async {
    final wrangler = await _runner.run(
      'wrangler',
      const ['--version'],
      workingDirectory: config.workingDirectory,
    );
    final hasToken = config.environment.containsKey('CLOUDFLARE_API_TOKEN');
    return [
      ArxaKitDoctorCheck(
        name: 'wrangler CLI',
        ok: wrangler.ok,
        detail: wrangler.ok
            ? wrangler.stdout.trim()
            : 'wrangler not found on PATH (npm i -g wrangler)',
      ),
      ArxaKitDoctorCheck(
        name: 'CLOUDFLARE_API_TOKEN',
        ok: hasToken,
        detail: hasToken
            ? 'provided via config.environment'
            : 'not set — relying on ambient `wrangler login` credentials',
      ),
    ];
  }

  @override
  Future<ArxaKitDeployResult> deploy(ArxaKitDeployConfig config) async {
    final commands = <String>[];

    final buildArgs = ['build', 'web', '--release', ...config.dartDefineArgs];
    commands.add('flutter ${buildArgs.join(' ')}');
    final build = await _runner.run(
      'flutter',
      buildArgs,
      workingDirectory: config.workingDirectory,
    );
    if (!build.ok) {
      return ArxaKitDeployResult(
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
    return ArxaKitDeployResult(
      target: name,
      ok: deploy.ok,
      commandsRun: commands,
      failureReason: deploy.ok
          ? null
          : 'wrangler exited ${deploy.exitCode}: ${deploy.stderr.trim()}',
    );
  }
}
