import 'dart:convert';
import 'dart:io';

import 'package:appboxd/memory.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late EventLog log;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('eventlog_test_');
    log = EventLog(tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  MemoryEvent ev(String kind,
          {String actor = 'tester', DateTime? ts, Map<String, dynamic>? payload}) =>
      MemoryEvent(
          kind: kind, actor: actor, ts: ts, payload: payload ?? {'n': 1});

  test('append/read round-trip, newest last', () async {
    await log.append(ev('gate_run', payload: {'gate': 'intake'}));
    await log.append(ev('note', actor: 'operator'));

    final res = await log.read();
    expect(res.corruptLines, 0);
    expect(res.events, hasLength(2));
    expect(res.events[0].kind, 'gate_run');
    expect(res.events[0].actor, 'tester');
    expect(res.events[0].payload['gate'], 'intake');
    expect(res.events[1].kind, 'note');
    expect(res.events[1].actor, 'operator');
    // Lines really are JSONL on disk.
    final lines = File('${tmp.path}/memory/events.jsonl').readAsLinesSync();
    expect(lines, hasLength(2));
    expect(jsonDecode(lines.first)['kind'], 'gate_run');
  });

  test('kind and since filters', () async {
    final t0 = DateTime.utc(2026, 1, 1);
    final t1 = DateTime.utc(2026, 1, 2);
    final t2 = DateTime.utc(2026, 1, 3);
    await log.append(ev('gate_run', ts: t0));
    await log.append(ev('llm_request', ts: t1));
    await log.append(ev('gate_run', ts: t2));

    expect((await log.read(kind: 'gate_run')).events.map((e) => e.ts),
        [t0, t2]);
    expect((await log.read(since: t1)).events.map((e) => e.ts), [t1, t2]);
    expect((await log.read(kind: 'gate_run', since: t1)).events.single.ts, t2);
  });

  test('limit keeps the most recent events', () async {
    for (var i = 0; i < 5; i++) {
      await log.append(ev('note', payload: {'i': i}));
    }
    final res = await log.read(limit: 2);
    expect(res.events.map((e) => e.payload['i']), [3, 4]);
  });

  test('rotation triggers and old events stay readable', () async {
    final small = EventLog(tmp.path, maxBytes: 120);
    await small.append(ev('gate_run', payload: {'seq': 'before-rotate'}));
    // Push the active file past the tiny limit; the next append rotates.
    await small.append(ev('note', payload: {'pad': 'x' * 200}));
    await small.append(ev('deploy', payload: {'seq': 'after-rotate'}));

    final dir = Directory('${tmp.path}/memory');
    final names = dir.listSync().map((f) => f.path.split('/').last).toList();
    expect(names.any((n) => n.startsWith('events.2') && n.endsWith('.jsonl')),
        isTrue,
        reason: 'a rotated events.<stamp>.jsonl exists');
    expect(names, contains('events.jsonl'));

    final res = await small.read(limit: 100);
    expect(res.events.map((e) => e.kind),
        ['gate_run', 'note', 'deploy']); // oldest → newest across files
    expect(await small.countByKind(),
        {'gate_run': 1, 'note': 1, 'deploy': 1});
  });

  test('corrupt lines are skipped and counted, never thrown', () async {
    await log.append(ev('gate_run'));
    final file = File('${tmp.path}/memory/events.jsonl');
    file.writeAsStringSync('this is not json\n{"broken": \n',
        mode: FileMode.append);
    await log.append(ev('note'));

    final res = await log.read();
    expect(res.corruptLines, 2);
    expect(res.events.map((e) => e.kind), ['gate_run', 'note']);
    expect(await log.countByKind(), {'gate_run': 1, 'note': 1});
  });

  test('reading an empty store yields nothing', () async {
    final res = await log.read();
    expect(res.events, isEmpty);
    expect(res.corruptLines, 0);
    expect(await log.countByKind(), isEmpty);
  });
}
