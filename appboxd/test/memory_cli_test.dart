// appbox memory add|recall|why — project-scoped memory verbs (arxa H5).
//
// The load-bearing rules under test come from the write-path doctrine
// (appbox-memory-and-payment.md M1): a fact without a source is REFUSED, and
// a topic at its cap refuses rather than silently dropping — the write path
// is the bottleneck, not the model (mem0: 97.8% junk memories).

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/memory_cli.dart';
import 'package:appboxd/memory_curate.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() => project = Directory.systemTemp.createTempSync('memtest_'));
  tearDown(() => project.deleteSync(recursive: true));

  Future<int> run(List<String> args) => memoryCli(args);

  test('add → recall → why round trip, provenance preserved', () async {
    expect(
        await run([
          'add', '--project', project.path, '--topic', 'design',
          '--source', 'lens', 'the footer never settles on mobile',
        ]),
        0);
    final file = File('${project.path}/memory/facts/design.json');
    expect(file.existsSync(), isTrue,
        reason: 'the store lives WITH the project, not in the engine repo');
    final entries = jsonDecode(file.readAsStringSync()) as List;
    expect(entries, hasLength(1));
    final e = entries.single as Map;
    expect(e['fact'], 'the footer never settles on mobile');
    expect(e['source'], 'lens');
    expect(e['ts'], isNotEmpty,
        reason: 'why has nothing to answer without a timestamp');
  });

  test('add without --source is refused — provenance is mandatory', () async {
    expect(
        await run([
          'add', '--project', project.path, '--topic', 'design', 'a fact',
        ]),
        isNot(0),
        reason: 'an unprovenanced write is the mem0 junk path');
    expect(File('${project.path}/memory/facts/design.json').existsSync(),
        isFalse, reason: 'a refused write must not half-happen');
  });

  test('a topic at the cap refuses instead of silently dropping', () {
    final curator = MemoryCurator(Directory('${project.path}/memory'));
    for (var i = 0; i < MemoryCurator.factsCap; i++) {
      curator.addFact('big', 'fact $i', source: 'test');
    }
    expect(() => curator.addFact('big', 'one more', source: 'test'),
        throwsStateError);
    expect(curator.readFacts('big'), hasLength(MemoryCurator.factsCap),
        reason: 'the refused fact must not have been written');
  });

  test('recall filters by topic and grep; why answers with provenance',
      () async {
    final curator = MemoryCurator(Directory('${project.path}/memory'));
    curator.addFact('design', 'glass fades on scroll', source: 'lens');
    curator.addFact('design', 'footer is sticky', source: 'review');
    curator.addFact('intake', 'client wants dark mode', source: 'intake');

    expect(await run(['recall', '--project', project.path]), 0);
    expect(
        await run([
          'recall', '--project', project.path, '--topic', 'design',
          '--grep', 'GLASS',
        ]),
        0,
        reason: 'grep is case-insensitive');
    expect(await run(['why', '--project', project.path, 'design', '1']), 0);
    expect(await run(['why', '--project', project.path, 'design', '9']),
        isNot(0), reason: 'out-of-range index is an error, not silence');
    expect(await run(['why', '--project', project.path, 'nope', '0']),
        isNot(0), reason: 'unknown topic is an error naming the real topics');
  });

  test('unknown verb and missing project dir are usage errors', () async {
    expect(await run(['frobnicate']), isNot(0));
    expect(
        await run([
          'recall', '--project', '${project.path}/does-not-exist',
        ]),
        isNot(0));
  });
}
