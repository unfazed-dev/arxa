import 'package:arxa_kit_deploy/arxa_kit_deploy.dart';
import 'package:arxa_kit_deploy/arxa_kit_testing.dart';
import 'package:test/test.dart';

void main() {
  const config = ArxaKitDeployConfig(
    projectName: 'showcase',
    workingDirectory: '/app',
    releaseVersion: '1.2.0+45',
    flutterVersion: '3.24.0',
    dartDefines: {'ENV': 'prod'},
    environment: {'CLOUDFLARE_API_TOKEN': 'cf-token'},
  );

  group('ArxaKitFastlaneTarget', () {
    test('kit.deploy.targets — deploy runs bundle exec fastlane <platform> <lane>', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final target = ArxaKitFastlaneTarget(runner, platform: 'ios', lane: 'beta');

      final result = await target.deploy(config);

      expect(result.ok, isTrue);
      expect(result.target, 'fastlane-ios');
      expect(result.commandsRun, ['bundle exec fastlane ios beta']);
      expect(runner.workingDirectories.single, '/app');
    });

    test('kit.deploy.targets — failure surfaces exit code and stderr', () async {
      final runner = ScriptedArxaKitProcessRunner(script: {
        'bundle exec fastlane android release':
            const ArxaKitProcessResult(exitCode: 2, stderr: 'lane failed'),
      });
      final target = ArxaKitFastlaneTarget(runner, platform: 'android');

      final result = await target.deploy(config);

      expect(result.ok, isFalse);
      expect(result.failureReason, contains('exited 2'));
      expect(result.failureReason, contains('lane failed'));
    });

    test('kit.deploy.targets — doctor checks fastlane --version', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final checks =
          await ArxaKitFastlaneTarget(runner, platform: 'android').doctor(config);

      expect(runner.commandsRun, ['fastlane --version']);
      expect(checks.single.ok, isTrue);
    });
  });

  group('ArxaKitShorebirdTarget', () {
    test('kit.deploy.targets — release shape includes --flutter-version and dart-defines',
        () async {
      final runner = ScriptedArxaKitProcessRunner();
      final target = ArxaKitShorebirdTarget(runner, mode: ArxaKitShorebirdMode.release);

      final result = await target.deploy(config);

      expect(result.target, 'shorebird-release');
      expect(result.commandsRun, [
        'shorebird release android --flutter-version=3.24.0 '
            '--dart-define=ENV=prod',
      ]);
    });

    test('kit.deploy.targets — patch shape includes --release-version', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final target = ArxaKitShorebirdTarget(
        runner,
        mode: ArxaKitShorebirdMode.patch,
        platform: 'ios',
      );

      final result = await target.deploy(config);

      expect(result.target, 'shorebird-patch');
      expect(result.commandsRun, [
        'shorebird patch ios --release-version=1.2.0+45 '
            '--dart-define=ENV=prod',
      ]);
    });

    test('kit.deploy.targets — doctor runs shorebird doctor', () async {
      final runner = ScriptedArxaKitProcessRunner(script: {
        'shorebird doctor':
            const ArxaKitProcessResult(exitCode: 1, stderr: 'not logged in'),
      });
      final checks = await ArxaKitShorebirdTarget(
        runner,
        mode: ArxaKitShorebirdMode.release,
      ).doctor(config);

      expect(checks.single.ok, isFalse);
      expect(checks.single.detail, 'not logged in');
    });
  });

  group('ArxaKitCloudflarePagesTarget', () {
    test('kit.deploy.targets — deploy builds web then wrangler pages deploy', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final target = ArxaKitCloudflarePagesTarget(runner);

      final result = await target.deploy(config);

      expect(result.ok, isTrue);
      expect(result.commandsRun, [
        'flutter build web --release --dart-define=ENV=prod',
        'wrangler pages deploy build/web --project-name=showcase',
      ]);
      expect(
        runner.environments.last,
        containsPair('CLOUDFLARE_API_TOKEN', 'cf-token'),
      );
    });

    test('kit.deploy.targets — stops after failed flutter build', () async {
      final runner = ScriptedArxaKitProcessRunner(script: {
        'flutter build web':
            const ArxaKitProcessResult(exitCode: 1, stderr: 'compile error'),
      });
      final result = await ArxaKitCloudflarePagesTarget(runner).deploy(config);

      expect(result.ok, isFalse);
      expect(result.commandsRun, hasLength(1));
      expect(result.failureReason, contains('compile error'));
      expect(
        runner.commandsRun.every((c) => !c.startsWith('wrangler')),
        isTrue,
        reason: 'must not deploy a broken build',
      );
    });

    test('kit.deploy.targets — doctor reports wrangler + token presence', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final checks = await ArxaKitCloudflarePagesTarget(runner).doctor(config);

      expect(checks, hasLength(2));
      expect(checks.every((c) => c.ok), isTrue);
    });
  });

  group('ArxaKitVercelTarget', () {
    const vercelConfig = ArxaKitDeployConfig(
      projectName: 'showcase',
      workingDirectory: '/app',
      dartDefines: {'ENV': 'prod'},
      environment: {'VERCEL_TOKEN': 'vercel-token'},
    );

    test('kit.deploy.targets — deploy builds web then vercel deploy --prod --yes', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final target = ArxaKitVercelTarget(runner);

      final result = await target.deploy(vercelConfig);

      expect(result.ok, isTrue);
      expect(result.target, 'vercel');
      expect(result.commandsRun, [
        'flutter build web --release --dart-define=ENV=prod',
        'vercel deploy build/web --prod --yes',
      ]);
      expect(
        runner.environments.last,
        containsPair('VERCEL_TOKEN', 'vercel-token'),
      );
    });

    test('kit.deploy.targets — stops after failed flutter build', () async {
      final runner = ScriptedArxaKitProcessRunner(script: {
        'flutter build web':
            const ArxaKitProcessResult(exitCode: 1, stderr: 'compile error'),
      });
      final result = await ArxaKitVercelTarget(runner).deploy(vercelConfig);

      expect(result.ok, isFalse);
      expect(result.commandsRun, hasLength(1));
      expect(result.failureReason, contains('compile error'));
      expect(
        runner.commandsRun.every((c) => !c.startsWith('vercel deploy')),
        isTrue,
        reason: 'must not deploy a broken build',
      );
    });

    test('kit.deploy.targets — doctor reports vercel CLI + token presence', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final checks = await ArxaKitVercelTarget(runner).doctor(vercelConfig);

      expect(runner.commandsRun, ['vercel --version']);
      expect(checks, hasLength(2));
      expect(checks.every((c) => c.ok), isTrue);
    });

    test('kit.deploy.targets — doctor flags a missing VERCEL_TOKEN', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final checks = await ArxaKitVercelTarget(runner).doctor(config);

      expect(checks[0].ok, isTrue);
      expect(checks[1].ok, isFalse);
      expect(checks[1].name, 'VERCEL_TOKEN');
    });
  });

  group('ArxaKitCloudflareWorkersTarget', () {
    const workersConfig = ArxaKitDeployConfig(
      projectName: 'showcase',
      workingDirectory: '/worker',
      environment: {
        'CLOUDFLARE_API_TOKEN': 'cf-token',
        'CLOUDFLARE_ACCOUNT_ID': 'cf-account',
      },
    );

    test('kit.deploy.targets — deploy runs wrangler deploy in the working directory', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final target = ArxaKitCloudflareWorkersTarget(runner);

      final result = await target.deploy(workersConfig);

      expect(result.ok, isTrue);
      expect(result.target, 'cloudflare-workers');
      expect(result.commandsRun, ['wrangler deploy']);
      expect(runner.workingDirectories.single, '/worker');
      expect(
        runner.environments.single,
        allOf(
          containsPair('CLOUDFLARE_API_TOKEN', 'cf-token'),
          containsPair('CLOUDFLARE_ACCOUNT_ID', 'cf-account'),
        ),
      );
    });

    test('kit.deploy.targets — fails without a workingDirectory (no wrangler.toml to read)',
        () async {
      final runner = ScriptedArxaKitProcessRunner();
      const noDir = ArxaKitDeployConfig(projectName: 'showcase');

      final result = await ArxaKitCloudflareWorkersTarget(runner).deploy(noDir);

      expect(result.ok, isFalse);
      expect(result.failureReason, contains('workingDirectory'));
      expect(runner.commandsRun, isEmpty);
    });

    test('kit.deploy.targets — deploy failure surfaces exit code and stderr', () async {
      final runner = ScriptedArxaKitProcessRunner(script: {
        'wrangler deploy':
            const ArxaKitProcessResult(exitCode: 1, stderr: 'missing wrangler.toml'),
      });
      final result = await ArxaKitCloudflareWorkersTarget(runner).deploy(workersConfig);

      expect(result.ok, isFalse);
      expect(result.failureReason, contains('exited 1'));
      expect(result.failureReason, contains('missing wrangler.toml'));
    });

    test('kit.deploy.targets — doctor reports wrangler + token + account id presence', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final checks = await ArxaKitCloudflareWorkersTarget(runner).doctor(workersConfig);

      expect(runner.commandsRun, ['wrangler --version']);
      expect(checks, hasLength(3));
      expect(checks.every((c) => c.ok), isTrue);
    });

    test('kit.deploy.targets — doctor flags a missing CLOUDFLARE_ACCOUNT_ID', () async {
      final runner = ScriptedArxaKitProcessRunner();
      final checks = await ArxaKitCloudflareWorkersTarget(runner).doctor(config);

      expect(checks[2].ok, isFalse);
      expect(checks[2].name, 'CLOUDFLARE_ACCOUNT_ID');
    });
  });
}
