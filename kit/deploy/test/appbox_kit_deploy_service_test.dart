import 'package:appbox_kit_deploy/appbox_kit_deploy.dart';
import 'package:appbox_kit_deploy/appbox_kit_testing.dart';
import 'package:test/test.dart';

void main() {
  const config = AppBoxKitDeployConfig(projectName: 'showcase');

  AppBoxKitDeployService buildService(ScriptedAppBoxKitProcessRunner runner) =>
      AppBoxKitDeployService(targets: [
        AppBoxKitFastlaneTarget(runner, platform: 'android'),
        AppBoxKitShorebirdTarget(runner, mode: AppBoxKitShorebirdMode.release),
        AppBoxKitCloudflarePagesTarget(runner),
        AppBoxKitVercelTarget(runner),
      ]);

  test('targetNames exposes registration order', () {
    final service = buildService(ScriptedAppBoxKitProcessRunner());
    expect(service.targetNames, [
      'fastlane-android',
      'shorebird-release',
      'cloudflare-pages',
      'vercel',
    ]);
  });

  test('deployTo routes by name', () async {
    final runner = ScriptedAppBoxKitProcessRunner();
    final result =
        await buildService(runner).deployTo('cloudflare-pages', config);

    expect(result.target, 'cloudflare-pages');
    expect(runner.commandsRun.first, startsWith('flutter build web'));
  });

  test('deployTo with unknown name throws with known targets listed', () {
    final service = buildService(ScriptedAppBoxKitProcessRunner());
    expect(
      () => service.deployTo('heroku', config),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('cloudflare-pages'),
        ),
      ),
    );
  });

  test('doctor aggregates every target', () async {
    final report =
        await buildService(ScriptedAppBoxKitProcessRunner()).doctor(config);

    expect(report.keys, containsAll([
      'fastlane-android',
      'shorebird-release',
      'cloudflare-pages',
      'vercel',
    ]));
    expect(
      report['vercel']!.any((c) => !c.ok),
      isTrue,
      reason: 'VERCEL_TOKEN is not set in this config',
    );
  });

  test('AppBoxKitDeployConfig.dartDefineArgs preserves insertion order', () {
    const config = AppBoxKitDeployConfig(
      projectName: 'x',
      dartDefines: {'A': '1', 'B': '2'},
    );
    expect(config.dartDefineArgs, ['--dart-define=A=1', '--dart-define=B=2']);
  });
}
