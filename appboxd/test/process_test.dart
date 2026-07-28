import 'package:appboxd/harness.dart';
import 'package:appboxd/intake.dart';
import 'package:appboxd/phases.dart';
import 'package:appboxd/process.dart';
import 'package:test/test.dart';

class FakeProcessRunner implements ProcessRunner {
  final calls = <List<String>>[];
  String? lastWorkingDirectory;
  RunnerResult Function(String executable, List<String> args)? handler;

  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    calls.add([executable, ...args]);
    lastWorkingDirectory = workingDirectory;
    return handler?.call(executable, args) ?? const RunnerResult(0, '', '');
  }
}

void main() {
  late FakeProcessRunner runner;
  setUp(() => runner = FakeProcessRunner());

  group('PipelineRunner', () {
    test('invoke resolves relative config args against the repo root', () async {
      final pipeline = PipelineRunner(
        repoRoot: '/repo',
        command: 'bash',
        args: ['pipeline/pipeline.sh'],
        runner: runner,
      );
      await pipeline.invoke('design');
      expect(runner.calls.single,
          ['bash', '/repo/pipeline/pipeline.sh', 'design']);
      expect(runner.lastWorkingDirectory, '/repo');
    });

    test('availability is honest: absent binary → absent, never faked green', () async {
      final pipeline = PipelineRunner(
        repoRoot: '/repo',
        command: 'bash',
        args: const [],
        runner: runner,
      );
      runner.handler = (_, _) => const RunnerResult(0, '/bin/bash', '');
      expect(await pipeline.availability(), PipelineAvailability.ready);
      runner.handler = (_, _) => const RunnerResult(1, '', 'not found');
      expect(await pipeline.availability(), PipelineAvailability.absent);
    });
  });

  group('runPhase', () {
    test('goes through the ProcessRunner seam', () async {
      runner.handler = (_, _) => const RunnerResult(0, 'gate output', 'warn');
      final result = await runPhase('/repo', 'build', runner: runner);
      expect(runner.calls.single,
          ['bash', '/repo/pipeline/pipeline.sh', 'gate', 'build']);
      expect(result.exitCode, 0);
      expect(result.stdout, 'gate output');
      expect(result.stderr, 'warn');
    });
  });

  group('IntakeRunner', () {
    test('emit invokes the ONE engine on the answers file', () async {
      final intake = IntakeRunner(
        command: 'python3',
        script: 'skills/app-box-intake/intake.py',
        runner: runner,
      );
      await intake.emit(
        answersPath: 'a.json',
        briefOut: 'brief.md',
        registryOut: 'registry.json',
      );
      expect(runner.calls.single, [
        'python3',
        'skills/app-box-intake/intake.py',
        'emit',
        '--answers', 'a.json',
        '--brief-out', 'brief.md',
        '--registry-out', 'registry.json',
      ]);
    });
  });

  group('HarnessAuth', () {
    test('presence probes PATH via the seam', () async {
      final harness = HarnessAuth(
        command: 'app-box-harness',
        envHint: 'APP_BOX_HARNESS_PATH_TEST_ABSENT',
        runner: runner,
      );
      runner.handler = (_, _) => const RunnerResult(1, '', '');
      expect(await harness.harnessPresent, isFalse);
      expect(runner.calls.single, ['command', '-v', 'app-box-harness']);
    });

    test('harnessAction shells out to the harness, holding no token', () async {
      final harness = HarnessAuth(
        command: 'app-box-harness',
        envHint: 'APP_BOX_HARNESS_PATH_TEST_ABSENT',
        runner: runner,
      );
      runner.handler = (_, _) => const RunnerResult(0, 'done', '');
      final res = await harness.harnessAction('generate');
      expect(res.ok, isTrue);
      expect(runner.calls.single, ['app-box-harness', 'generate']);
    });
  });
}
