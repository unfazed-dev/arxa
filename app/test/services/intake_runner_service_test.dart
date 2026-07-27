import 'package:flutter_test/flutter_test.dart';
import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/intake_runner_service.dart';
import 'package:app_box/services/pipeline_runner_service.dart';

/// 10.5 — the intake runner shells out via the same [ProcessRunner] seam as
/// [PipelineRunnerService], so the command shape is unit-testable with a
/// scripted runner and NO python3 in CI. The wizard and the headless phase
/// drive the ONE engine through this seam — if they can disagree, plan 10 has
/// failed (DW1).
class _ScriptedRunner implements ProcessRunner {
  RunnerResult next = const RunnerResult(0, '', '');
  String? lastExecutable;
  List<String>? lastArgs;

  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    lastExecutable = executable;
    lastArgs = args;
    return next;
  }
}

void main() {
  setUp(() {
    final config = ConfigService()
      ..loadMap({
        'intake': {
          'command': 'python3',
          'script': 'skills/app-box-intake/intake.py',
        },
      });
    locator.registerSingleton<ConfigService>(config);
  });
  tearDown(() => locator.reset());

  test('emit shells out to the engine with the configured command shape', () async {
    final scripted = _ScriptedRunner()..next = const RunnerResult(0, 'ok', '');
    final service = IntakeRunnerService(scripted);

    final result = await service.emit(
      answersPath: '/tmp/answers.json',
      briefOut: 'docs/design/brief.md',
      registryOut: 'docs/design/registry.json',
    );

    expect(result.ok, isTrue);
    expect(scripted.lastExecutable, 'python3');
    // The command shape: <script> emit --answers <path> --brief-out <p> --registry-out <p>
    expect(scripted.lastArgs, [
      'skills/app-box-intake/intake.py',
      'emit',
      '--answers', '/tmp/answers.json',
      '--brief-out', 'docs/design/brief.md',
      '--registry-out', 'docs/design/registry.json',
    ]);
  });

  test('emit works without explicit output paths (engine defaults apply)', () async {
    final scripted = _ScriptedRunner()..next = const RunnerResult(0, 'ok', '');
    final service = IntakeRunnerService(scripted);

    await service.emit(answersPath: '/tmp/answers.json');

    // No --brief-out / --registry-out when null — the engine uses its defaults.
    expect(scripted.lastArgs, [
      'skills/app-box-intake/intake.py',
      'emit',
      '--answers', '/tmp/answers.json',
    ]);
  });

  test('a failing engine surfaces red honestly (exit != 0)', () async {
    final scripted = _ScriptedRunner()
      ..next = const RunnerResult(1, '', 'audience: provenance guessed is not one of...');
    final service = IntakeRunnerService(scripted);

    final result = await service.emit(answersPath: '/tmp/bad.json');

    expect(result.ok, isFalse);
    expect(result.stderr, contains('provenance'));
  });
}
