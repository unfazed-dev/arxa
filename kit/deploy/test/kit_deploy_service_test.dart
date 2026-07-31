import 'package:appbox_kit_deploy/appbox_kit_deploy.dart';
import 'package:appbox_kit_deploy/testing.dart';
import 'package:test/test.dart';

void main() {
  const config = KitDeployConfig(projectName: 'showcase');

  KitDeployService buildService(ScriptedProcessRunner runner) =>
      KitDeployService(targets: [
        FastlaneTarget(runner, platform: 'android'),
        ShorebirdTarget(runner, mode: ShorebirdMode.release),
        CloudflarePagesTarget(runner),
        VercelTarget(runner),
      ]);

  test('targetNames exposes registration order', () {
    final service = buildService(ScriptedProcessRunner());
    expect(service.targetNames, [
      'fastlane-android',
      'shorebird-release',
      'cloudflare-pages',
      'vercel',
    ]);
  });

  test('deployTo routes by name', () async {
    final runner = ScriptedProcessRunner();
    final result =
        await buildService(runner).deployTo('cloudflare-pages', config);

    expect(result.target, 'cloudflare-pages');
    expect(runner.commandsRun.first, startsWith('flutter build web'));
  });

  test('deployTo with unknown name throws with known targets listed', () {
    final service = buildService(ScriptedProcessRunner());
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
        await buildService(ScriptedProcessRunner()).doctor(config);

    expect(report.keys, containsAll([
      'fastlane-android',
      'shorebird-release',
      'cloudflare-pages',
      'vercel',
    ]));
    expect(report['vercel']!.single.ok, isFalse, reason: 'stub');
  });

  test('KitDeployConfig.dartDefineArgs preserves insertion order', () {
    const config = KitDeployConfig(
      projectName: 'x',
      dartDefines: {'A': '1', 'B': '2'},
    );
    expect(config.dartDefineArgs, ['--dart-define=A=1', '--dart-define=B=2']);
  });
}
