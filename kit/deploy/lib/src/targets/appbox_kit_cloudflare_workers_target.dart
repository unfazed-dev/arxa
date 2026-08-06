import '../appbox_kit_deploy_target.dart';
import '../models/appbox_kit_deploy_config.dart';
import '../models/appbox_kit_deploy_result.dart';
import '../process/appbox_kit_process_runner.dart';

/// Wired Cloudflare Workers backend: `wrangler deploy` from the working
/// directory's own `wrangler.toml`. Unlike Pages there is no flutter build
/// step — a Worker ships its own source, so [AppBoxKitDeployConfig.workingDirectory]
/// is required (that is where wrangler.toml lives).
///
/// Auth comes from CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID in
/// [AppBoxKitDeployConfig.environment] (or ambient `wrangler login` state).
class AppBoxKitCloudflareWorkersTarget implements AppBoxKitDeployTarget {
  const AppBoxKitCloudflareWorkersTarget(this._runner);

  final AppBoxKitProcessRunner _runner;

  @override
  String get name => 'cloudflare-workers';

  @override
  Future<List<AppBoxKitDoctorCheck>> doctor(AppBoxKitDeployConfig config) async {
    final wrangler = await _runner.run(
      'wrangler',
      const ['--version'],
      workingDirectory: config.workingDirectory,
    );
    final hasToken = config.environment.containsKey('CLOUDFLARE_API_TOKEN');
    final hasAccount = config.environment.containsKey('CLOUDFLARE_ACCOUNT_ID');
    return [
      AppBoxKitDoctorCheck(
        name: 'wrangler CLI',
        ok: wrangler.ok,
        detail: wrangler.ok
            ? wrangler.stdout.trim()
            : 'wrangler not found on PATH (npm i -g wrangler)',
      ),
      AppBoxKitDoctorCheck(
        name: 'CLOUDFLARE_API_TOKEN',
        ok: hasToken,
        detail: hasToken
            ? 'provided via config.environment'
            : 'not set — relying on ambient `wrangler login` credentials',
      ),
      AppBoxKitDoctorCheck(
        name: 'CLOUDFLARE_ACCOUNT_ID',
        ok: hasAccount,
        detail: hasAccount
            ? 'provided via config.environment'
            : 'not set — wrangler deploy needs it non-interactively',
      ),
    ];
  }

  @override
  Future<AppBoxKitDeployResult> deploy(AppBoxKitDeployConfig config) async {
    final workingDirectory = config.workingDirectory;
    if (workingDirectory == null) {
      return AppBoxKitDeployResult(
        target: name,
        ok: false,
        commandsRun: [],
        failureReason: 'workingDirectory is required — wrangler deploy reads '
            'wrangler.toml from the working directory',
      );
    }

    const deployArgs = ['deploy'];
    final deploy = await _runner.run(
      'wrangler',
      deployArgs,
      workingDirectory: workingDirectory,
      environment: config.environment.isEmpty ? null : config.environment,
    );
    return AppBoxKitDeployResult(
      target: name,
      ok: deploy.ok,
      commandsRun: ['wrangler ${deployArgs.join(' ')}'],
      failureReason: deploy.ok
          ? null
          : 'wrangler exited ${deploy.exitCode}: ${deploy.stderr.trim()}',
    );
  }
}
