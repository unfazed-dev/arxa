// Memory gate test — verifies the Dart port matches the bash gate's behavior.
// Tests: happy path passes, each individual check fails when violated.

import 'dart:io';

import 'package:appboxd/gate_memory.dart';
import 'package:appboxd/gates.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late GateContext ctx;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate-memory-test-');
    _buildValidMemory(tmp);
    ctx = GateContext(repoRoot: tmp.path);
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('happy path — valid memory/ passes', () {
    final result = memoryGate(ctx);
    expect(result.passed, isTrue, reason: result.summary);
    expect(result.summary, contains('PASS'));
  });

  test('negative — index over 100 lines fails', () {
    final f = File('${tmp.path}/memory/MEMORY.md');
    f.writeAsStringSync(List.generate(101, (i) => 'line $i').join('\n'));
    final result = memoryGate(ctx);
    expect(result.passed, isFalse);
    expect(result.details.any((d) => d.contains('cap 100')), isTrue);
  });

  test('negative — malformed facts json fails', () {
    File('${tmp.path}/memory/facts/bad.json').writeAsStringSync('not json');
    final result = memoryGate(ctx);
    expect(result.passed, isFalse);
    expect(result.details.any((d) => d.contains('bad.json')), isTrue);
  });

  test('negative — wrong fact shape (missing keys) fails', () {
    File('${tmp.path}/memory/facts/bad.json')
        .writeAsStringSync('[{"lesson":"no fact/source/ts keys"}]');
    final result = memoryGate(ctx);
    expect(result.passed, isFalse);
    expect(result.details.any((d) => d.contains('bad.json')), isTrue);
  });

  test('negative — lessons over 200 lines fails', () {
    final f = File('${tmp.path}/memory/stages/intake.LESSONS.md');
    f.writeAsStringSync(
      '# stage — lessons\n\n## Lessons\n' +
      List.generate(199, (i) => '- lesson $i').join('\n'),
    );
    final result = memoryGate(ctx);
    expect(result.passed, isFalse);
    expect(result.details.any((d) => d.contains('cap 200')), isTrue);
  });

  test('negative — forbidden absolute path fails', () {
    File('${tmp.path}/memory/stages/intake.LESSONS.md')
        .writeAsStringSync('- see /noabs/x for details\n', mode: FileMode.append);
    final result = memoryGate(ctx);
    expect(result.passed, isFalse);
    expect(result.details.any((d) => d.contains('forbidden prefix')), isTrue);
  });

  test('negative — no facts files fails', () {
    Directory('${tmp.path}/memory/facts').deleteSync(recursive: true);
    final result = memoryGate(ctx);
    expect(result.passed, isFalse);
    expect(result.details.any((d) => d.contains('no memory/facts')), isTrue);
  });
}

void _buildValidMemory(Directory tmp) {
  // Create the structure
  Directory('${tmp.path}/memory/facts').createSync(recursive: true);
  Directory('${tmp.path}/memory/stages').createSync(recursive: true);
  Directory('${tmp.path}/config').createSync(recursive: true);

  File('${tmp.path}/memory/MEMORY.md').writeAsStringSync('# memory index\n');
  File('${tmp.path}/memory/facts/a.json')
      .writeAsStringSync('[{"fact":"f","source":"s","ts":"2026-07-30"}]\n');
  File('${tmp.path}/memory/stages/intake.LESSONS.md')
      .writeAsStringSync('# stage — lessons\n\n## Lessons\n- gate x failed because y; do z\n');
  File('${tmp.path}/config/forbidden_abs_prefixes.txt')
      .writeAsStringSync('# forbidden\n/noabs/\n/alsono/\n');
}
