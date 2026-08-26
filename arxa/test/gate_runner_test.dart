// Gate runner test — a gate run appends a gate_run memory event
// (memory.dart MemoryKinds.gateRun) to the EventLog under pipeline/state.

import 'dart:io';

import 'package:arxa/gate_runner.dart';
import 'package:arxa/gates.dart';
import 'package:arxa/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late GateContext ctx;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate-runner-test-');
    // minimal valid memory/ so the 'memory' gate passes
    Directory(p.join(tmp.path, 'memory', 'facts')).createSync(recursive: true);
    Directory(p.join(tmp.path, 'memory', 'stages')).createSync(recursive: true);
    Directory(p.join(tmp.path, 'config')).createSync(recursive: true);
    File(p.join(tmp.path, 'memory', 'MEMORY.md'))
        .writeAsStringSync('# memory index\n');
    File(p.join(tmp.path, 'memory', 'facts', 'a.json'))
        .writeAsStringSync('[{"fact":"f","source":"s","ts":"2026-07-30"}]\n');
    File(p.join(tmp.path, 'memory', 'stages', 'intake.LESSONS.md'))
        .writeAsStringSync(
            '# stage — lessons\n\n## Lessons\n- gate x failed because y; do z\n');
    File(p.join(tmp.path, 'config', 'forbidden_abs_prefixes.txt'))
        .writeAsStringSync('# forbidden\n/noabs/\n/alsono/\n');
    ctx = GateContext(repoRoot: tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('a gate run appends a gate_run event (gate, passed, duration)', () async {
    final result = await runGate('memory', ctx);
    expect(result, isNotNull);
    expect(result!.passed, isTrue, reason: result.summary);

    final read = await EventLog(p.join(tmp.path, 'pipeline', 'state'))
        .read(kind: MemoryKinds.gateRun);
    expect(read.events, hasLength(1));
    final ev = read.events.single;
    expect(ev.actor, 'gate-runner');
    expect(ev.payload['gate'], 'memory');
    expect(ev.payload['passed'], true);
    expect(ev.payload['exit_code'], passExit);
    expect(ev.payload['duration_ms'], isA<int>());
  });

  test('a failing gate run still appends the event (passed=false)', () async {
    File(p.join(tmp.path, 'memory', 'MEMORY.md'))
        .writeAsStringSync(List.generate(101, (i) => 'line $i').join('\n'));

    final result = await runGate('memory', ctx);
    expect(result!.passed, isFalse);

    final read = await EventLog(p.join(tmp.path, 'pipeline', 'state'))
        .read(kind: MemoryKinds.gateRun);
    expect(read.events.single.payload['passed'], false);
  });

  // The runner takes only a GateContext, so a gate's project had nowhere to
  // ride and `gate --all --project x` gated the studio instead — silently, with
  // a green summary for the wrong tree. The name guard is the cheapest proof
  // the value actually arrives: a project the gate refuses can only be refused
  // if the runner passed it on. Drop `project: ctx.project` in
  // gate_runner.dart and this goes red.
  test('runGate carries ctx.project into the intake gate', () async {
    final scoped = GateContext(repoRoot: tmp.path, project: 'Bad Name');
    final result = await runGate('intake', scoped);
    expect(result, isNotNull);
    expect(result!.summary, contains('bad project name'),
        reason: 'the runner dropped ctx.project: ${result.summary}');
  });

  test('an unknown gate writes no event', () async {
    final result = await runGate('not-a-gate', ctx);
    expect(result, isNull);

    final read = await EventLog(p.join(tmp.path, 'pipeline', 'state'))
        .read(kind: MemoryKinds.gateRun);
    expect(read.events, isEmpty);
  });
}
