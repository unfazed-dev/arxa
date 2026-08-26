import 'dart:io';

import 'package:arxa/mem_b.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mem-b-test-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void seedRepo() {
    Directory('${tmp.path}/memory/facts').createSync(recursive: true);
    File('${tmp.path}/memory/facts/engine.json').writeAsStringSync(
        '[{"fact":"E2: loopback gateway on 127.0.0.1.","source":"x","ts":"2026-07-30"},'
        '{"fact":"E4: one model fabric catalog.","source":"x","ts":"2026-07-30"}]');
    Directory('${tmp.path}/memory/stages').createSync(recursive: true);
    File('${tmp.path}/memory/stages/review.LESSONS.md').writeAsStringSync(
        '# review — lessons\n\n## Lessons\n'
        '- gate review failed because Icons.* leaked; use ArxaKitGlyphs\n');
    File('${tmp.path}/memory/stages/intake.LESSONS.md').writeAsStringSync(
        '# intake — lessons\n\n## Lessons\n');
    Directory('${tmp.path}/pipeline/state').createSync(recursive: true);
    File('${tmp.path}/pipeline/state/scorecard.jsonl').writeAsStringSync(
        '{"stage":"intake","gate_pass":true}\n'
        '{"stage":"review","gate_pass":false}\n');
  }

  test('assembles facts, lessons, pipeline state, and the build section', () {
    seedRepo();
    final mem = assembleMemB(tmp.path,
        appName: 'demo_app',
        surfaces: ['home_view', 'settings_view'],
        targets: ['ios', 'android'],
        factors: ['mobile', 'tablet']);

    expect(mem, startsWith('# MEM-B — demo_app'));
    expect(mem, contains('- targets: ios, android'));
    expect(mem, contains('- surfaces scaffolded: 2 (home_view, settings_view)'));
    expect(mem, contains('- stage runs recorded: 2 (gate pass 1, gate fail 1)'));
    expect(mem, contains('- E2: loopback gateway on 127.0.0.1.'));
    expect(mem, contains('### review'));
    expect(mem, contains('- gate review failed because Icons.* leaked'));
    // A stage with no lessons gets no heading.
    expect(mem, isNot(contains('### intake')));
    // Readable without arxa: deterministic, no timestamps.
    expect(
        mem,
        assembleMemB(tmp.path,
            appName: 'demo_app',
            surfaces: ['home_view', 'settings_view'],
            targets: ['ios', 'android'],
            factors: ['mobile', 'tablet']));
  });

  test('an empty repo still assembles an honest file', () {
    final mem = assembleMemB(tmp.path, appName: 'blank');
    expect(mem, contains('no recorded stage runs'));
    expect(mem, contains('## Facts (MEM-A — memory/facts/)\n- (none recorded)'));
    expect(mem, contains('- surfaces scaffolded: 0'));
  });

  test('writeMemB is write-on-diff idempotent', () {
    seedRepo();
    final app = Directory('${tmp.path}/app')..createSync();
    final mem = assembleMemB(tmp.path, appName: 'demo_app');
    expect(writeMemB(app.path, mem), isTrue, reason: 'first write lands');
    expect(File('${app.path}/MEM-B.md').readAsStringSync(), mem);
    expect(writeMemB(app.path, mem), isFalse,
        reason: 'unchanged content is not rewritten');
    expect(writeMemB(app.path, '$mem\nextra'), isTrue,
        reason: 'changed content rewrites');
  });
}
