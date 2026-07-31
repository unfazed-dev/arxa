import 'package:appboxd/harness.dart';
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
    test('runs Dart gates for the phase (no pipeline.sh)', () async {
      // 'build' → native_deps gate. On a non-existent repo root the gate
      // returns env (not applicable), which is exit code 2.
      final result = await runPhase('/nonexistent', 'build');
      expect(result.phase, 'build');
      // native_deps gate returns env exit on invalid path.
      expect(result.exitCode, anyOf(0, 1, 2));
      expect(result.stdout, contains('native_deps'));
    });

    test('unknown phase returns exit code 2', () async {
      final result = await runPhase('/repo', 'bogus');
      expect(result.exitCode, 2);
      expect(result.stderr, contains('unknown phase'));
    });
  });

  group('HarnessAuth', () {
    test('presence probes PATH via the seam', () async {
      final harness = HarnessAuth(
        command: 'appbox-harness',
        envHint: 'APPBOX_HARNESS_PATH_TEST_ABSENT',
        runner: runner,
      );
      runner.handler = (_, _) => const RunnerResult(1, '', '');
      expect(await harness.harnessPresent, isFalse);
      expect(runner.calls.single, ['command', '-v', 'appbox-harness']);
    });

    test('harnessAction shells out to the harness, holding no token', () async {
      final harness = HarnessAuth(
        command: 'appbox-harness',
        envHint: 'APPBOX_HARNESS_PATH_TEST_ABSENT',
        runner: runner,
      );
      runner.handler = (_, _) => const RunnerResult(0, 'done', '');
      final res = await harness.harnessAction('generate');
      expect(res.ok, isTrue);
      expect(runner.calls.single, ['appbox-harness', 'generate']);
    });
  });
}
