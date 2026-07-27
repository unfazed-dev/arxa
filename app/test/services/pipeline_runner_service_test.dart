import 'package:flutter_test/flutter_test.dart';
import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/pipeline_runner_service.dart';

/// 8.8 — the pipeline runner shells out via a [ProcessRunner] seam, so command
/// shapes are unit-testable with a scripted runner and NO toolchain in CI.
class _ScriptedRunner implements ProcessRunner {
  RunnerResult next = const RunnerResult(0, '', '');
  String? lastExecutable;
  List<String>? lastArgs;
  Map<String, String>? lastEnv;

  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    lastExecutable = executable;
    lastArgs = args;
    lastEnv = environment;
    return next;
  }
}

void main() {
  setUp(() {
    final config = ConfigService()
      ..loadMap({
        'pipeline': {
          'command': 'bash',
          'args': ['pipeline/pipeline.sh'],
          'stateDir': 'pipeline/state',
        },
      });
    locator.registerSingleton<ConfigService>(config);
  });
  tearDown(() => locator.reset());

  test('invoke shells out with the configured command + stage, no toolchain', () async {
    final scripted = _ScriptedRunner()..next = const RunnerResult(0, 'ok', '');
    final service = PipelineRunnerService(scripted);

    final result = await service.invoke('build');

    expect(result.ok, isTrue);
    expect(scripted.lastExecutable, 'bash');
    // The stage is appended to the configured args — the command shape.
    expect(scripted.lastArgs, ['pipeline/pipeline.sh', 'build']);
  });

  test('a failing pipeline surfaces red honestly (exit != 0)', () async {
    final scripted = _ScriptedRunner()
      ..next = const RunnerResult(1, '', 'freeze failed: missing viewport');
    final service = PipelineRunnerService(scripted);

    final result = await service.invoke('freeze');

    expect(result.ok, isFalse);
    expect(result.stderr, contains('freeze failed'));
  });
}
