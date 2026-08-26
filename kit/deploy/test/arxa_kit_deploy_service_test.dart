import 'package:arxa_kit_deploy/arxa_kit_deploy.dart';
import 'package:arxa_kit_deploy/arxa_kit_testing.dart';
import 'package:test/test.dart';

void main() {
  const config = ArxaKitDeployConfig(projectName: 'showcase');

  ArxaKitDeployService buildService(ScriptedArxaKitProcessRunner runner) =>
      ArxaKitDeployService(targets: [
        ArxaKitFastlaneTarget(runner, platform: 'android'),
        ArxaKitShorebirdTarget(runner, mode: ArxaKitShorebirdMode.release),
        ArxaKitCloudflarePagesTarget(runner),
        ArxaKitVercelTarget(runner),
      ]);

  test('kit.deploy.service — targetNames exposes registration order', () {
    final service = buildService(ScriptedArxaKitProcessRunner());
    expect(service.targetNames, [
      'fastlane-android',
      'shorebird-release',
      'cloudflare-pages',
      'vercel',
    ]);
  });

  test('kit.deploy.service — deployTo routes by name', () async {
    final runner = ScriptedArxaKitProcessRunner();
    final result =
        await buildService(runner).deployTo('cloudflare-pages', config);

    expect(result.target, 'cloudflare-pages');
    expect(runner.commandsRun.first, startsWith('flutter build web'));
  });

  test('kit.deploy.service — deployTo with unknown name throws with known targets listed', () {
    final service = buildService(ScriptedArxaKitProcessRunner());
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

  test('kit.deploy.service — doctor aggregates every target', () async {
    final report =
        await buildService(ScriptedArxaKitProcessRunner()).doctor(config);

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

  test('kit.deploy.service — ArxaKitDeployConfig.dartDefineArgs preserves insertion order', () {
    const config = ArxaKitDeployConfig(
      projectName: 'x',
      dartDefines: {'A': '1', 'B': '2'},
    );
    expect(config.dartDefineArgs, ['--dart-define=A=1', '--dart-define=B=2']);
  });
}
