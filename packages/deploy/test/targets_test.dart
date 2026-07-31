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
    test('deploy throws UnimplementedError naming the planned shape',
        () async {
      final target = VercelTarget(ScriptedProcessRunner());
      expect(
        () => target.deploy(config),
        throwsA(
          isA<UnimplementedError>().having(
            (e) => e.message,
            'message',
            contains('vercel deploy build/web --prod'),
          ),
        ),
      );
    });

    test('doctor flags the stub', () async {
      final checks = await VercelTarget(ScriptedProcessRunner())
          .doctor(config);
      expect(checks.single.ok, isFalse);
      expect(checks.single.detail, contains('stub'));
    });
  });
}
