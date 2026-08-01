import 'package:appbox_kit_deploy/appbox_kit_deploy.dart';
import 'package:appbox_kit_deploy/testing.dart';
import 'package:test/test.dart';

void main() {
  const config = KitDeployConfig(
    projectName: 'showcase',
    workingDirectory: '/app',
    releaseVersion: '1.2.0+45',
    flutterVersion: '3.24.0',
    dartDefines: {'ENV': 'prod'},
    environment: {'CLOUDFLARE_API_TOKEN': 'cf-token'},
  );

  group('FastlaneTarget', () {
    test('deploy runs bundle exec fastlane <platform> <lane>', () async {
      final runner = ScriptedProcessRunner();
      final target = FastlaneTarget(runner, platform: 'ios', lane: 'beta');

      final result = await target.deploy(config);

      expect(result.ok, isTrue);
      expect(result.target, 'fastlane-ios');
      expect(result.commandsRun, ['bundle exec fastlane ios beta']);
      expect(runner.workingDirectories.single, '/app');
    });

    test('failure surfaces exit code and stderr', () async {
      final runner = ScriptedProcessRunner(script: {
        'bundle exec fastlane android release':
            const KitProcessResult(exitCode: 2, stderr: 'lane failed'),
      });
      final target = FastlaneTarget(runner, platform: 'android');

      final result = await target.deploy(config);

      expect(result.ok, isFalse);
      expect(result.failureReason, contains('exited 2'));
      expect(result.failureReason, contains('lane failed'));
    });

    test('doctor checks fastlane --version', () async {
      final runner = ScriptedProcessRunner();
      final checks =
          await FastlaneTarget(runner, platform: 'android').doctor(config);

      expect(runner.commandsRun, ['fastlane --version']);
      expect(checks.single.ok, isTrue);
    });
  });

  group('ShorebirdTarget', () {
    test('release shape includes --flutter-version and dart-defines',
        () async {
      final runner = ScriptedProcessRunner();
      final target = ShorebirdTarget(runner, mode: ShorebirdMode.release);

      final result = await target.deploy(config);

      expect(result.target, 'shorebird-release');
      expect(result.commandsRun, [
        'shorebird release android --flutter-version=3.24.0 '
            '--dart-define=ENV=prod',
      ]);
    });

    test('patch shape includes --release-version', () async {
      final runner = ScriptedProcessRunner();
      final target = ShorebirdTarget(
        runner,
        mode: ShorebirdMode.patch,
        platform: 'ios',
      );

      final result = await target.deploy(config);

      expect(result.target, 'shorebird-patch');
      expect(result.commandsRun, [
        'shorebird patch ios --release-version=1.2.0+45 '
            '--dart-define=ENV=prod',
      ]);
    });

    test('doctor runs shorebird doctor', () async {
      final runner = ScriptedProcessRunner(script: {
        'shorebird doctor':
            const KitProcessResult(exitCode: 1, stderr: 'not logged in'),
      });
      final checks = await ShorebirdTarget(
        runner,
        mode: ShorebirdMode.release,
      ).doctor(config);

      expect(checks.single.ok, isFalse);
      expect(checks.single.detail, 'not logged in');
    });
  });

  group('CloudflarePagesTarget', () {
    test('deploy builds web then wrangler pages deploy', () async {
      final runner = ScriptedProcessRunner();
      final target = CloudflarePagesTarget(runner);

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

    test('stops after failed flutter build', () async {
      final runner = ScriptedProcessRunner(script: {
        'flutter build web':
            const KitProcessResult(exitCode: 1, stderr: 'compile error'),
      });
      final result = await CloudflarePagesTarget(runner).deploy(config);

      expect(result.ok, isFalse);
      expect(result.commandsRun, hasLength(1));
      expect(result.failureReason, contains('compile error'));
      expect(
        runner.commandsRun.every((c) => !c.startsWith('wrangler')),
        isTrue,
        reason: 'must not deploy a broken build',
      );
    });

    test('doctor reports wrangler + token presence', () async {
      final runner = ScriptedProcessRunner();
      final checks = await CloudflarePagesTarget(runner).doctor(config);

      expect(checks, hasLength(2));
      expect(checks.every((c) => c.ok), isTrue);
    });
  });

  group('VercelTarget', () {
    const vercelConfig = KitDeployConfig(
      projectName: 'showcase',
      workingDirectory: '/app',
      dartDefines: {'ENV': 'prod'},
      environment: {'VERCEL_TOKEN': 'vercel-token'},
    );

    test('deploy builds web then vercel deploy --prod --yes', () async {
      final runner = ScriptedProcessRunner();
      final target = VercelTarget(runner);

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

    test('stops after failed flutter build', () async {
      final runner = ScriptedProcessRunner(script: {
        'flutter build web':
            const KitProcessResult(exitCode: 1, stderr: 'compile error'),
      });
      final result = await VercelTarget(runner).deploy(vercelConfig);

      expect(result.ok, isFalse);
      expect(result.commandsRun, hasLength(1));
      expect(result.failureReason, contains('compile error'));
      expect(
        runner.commandsRun.every((c) => !c.startsWith('vercel deploy')),
        isTrue,
        reason: 'must not deploy a broken build',
      );
    });

    test('doctor reports vercel CLI + token presence', () async {
      final runner = ScriptedProcessRunner();
      final checks = await VercelTarget(runner).doctor(vercelConfig);

      expect(runner.commandsRun, ['vercel --version']);
      expect(checks, hasLength(2));
      expect(checks.every((c) => c.ok), isTrue);
    });

    test('doctor flags a missing VERCEL_TOKEN', () async {
      final runner = ScriptedProcessRunner();
      final checks = await VercelTarget(runner).doctor(config);

      expect(checks[0].ok, isTrue);
      expect(checks[1].ok, isFalse);
      expect(checks[1].name, 'VERCEL_TOKEN');
    });
  });

  group('CloudflareWorkersTarget', () {
    const workersConfig = KitDeployConfig(
      projectName: 'showcase',
      workingDirectory: '/worker',
      environment: {
        'CLOUDFLARE_API_TOKEN': 'cf-token',
        'CLOUDFLARE_ACCOUNT_ID': 'cf-account',
      },
    );

    test('deploy runs wrangler deploy in the working directory', () async {
      final runner = ScriptedProcessRunner();
      final target = CloudflareWorkersTarget(runner);

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

    test('fails without a workingDirectory (no wrangler.toml to read)',
        () async {
      final runner = ScriptedProcessRunner();
      const noDir = KitDeployConfig(projectName: 'showcase');

      final result = await CloudflareWorkersTarget(runner).deploy(noDir);

      expect(result.ok, isFalse);
      expect(result.failureReason, contains('workingDirectory'));
      expect(runner.commandsRun, isEmpty);
    });

    test('deploy failure surfaces exit code and stderr', () async {
      final runner = ScriptedProcessRunner(script: {
        'wrangler deploy':
            const KitProcessResult(exitCode: 1, stderr: 'missing wrangler.toml'),
      });
      final result = await CloudflareWorkersTarget(runner).deploy(workersConfig);

      expect(result.ok, isFalse);
      expect(result.failureReason, contains('exited 1'));
      expect(result.failureReason, contains('missing wrangler.toml'));
    });

    test('doctor reports wrangler + token + account id presence', () async {
      final runner = ScriptedProcessRunner();
      final checks = await CloudflareWorkersTarget(runner).doctor(workersConfig);

      expect(runner.commandsRun, ['wrangler --version']);
      expect(checks, hasLength(3));
      expect(checks.every((c) => c.ok), isTrue);
    });

    test('doctor flags a missing CLOUDFLARE_ACCOUNT_ID', () async {
      final runner = ScriptedProcessRunner();
      final checks = await CloudflareWorkersTarget(runner).doctor(config);

      expect(checks[2].ok, isFalse);
      expect(checks[2].name, 'CLOUDFLARE_ACCOUNT_ID');
    });
  });
}
