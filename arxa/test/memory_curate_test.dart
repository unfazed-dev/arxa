import 'dart:io';

import 'package:arxa/memory_curate.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late MemoryCurator curator;

  const stage = 'scaffold';

  List<String> header() => [
        '# $stage — lessons',
        '',
        'Appended ONLY on observed gate failure. Hard cap 200 lines.',
        '',
        '## Lessons',
      ];

  File lessonsFile() => File('${tmp.path}/stages/$stage.LESSONS.md');

  void writeLessons(List<String> lines) =>
      lessonsFile().writeAsStringSync('${lines.join('\n')}\n');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('memory_curate_test');
    Directory('${tmp.path}/stages').createSync(recursive: true);
    Directory('${tmp.path}/facts').createSync(recursive: true);
    curator = MemoryCurator(tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('appendLesson', () {
    test('refuses to write without an observed gate failure', () {
      writeLessons(header());
      expect(
        () => curator.appendLesson(stage, 'unsolicited note',
            gateFailed: false),
        throwsStateError,
      );
      // Nothing was written — the refusal is not partial.
      expect(curator.lessonsFor(stage), isEmpty);
    });

    test('appends one "- " line on gate failure', () {
      writeLessons(header());
      curator.appendLesson(stage, 'gate scaffold failed because X; do Y',
          gateFailed: true);
      expect(curator.lessonsFor(stage),
          ['- gate scaffold failed because X; do Y']);
    });

    test('unknown stage throws', () {
      expect(
        () => curator.appendLesson('zxspectrum', 'l', gateFailed: true),
        throwsArgumentError,
      );
    });

    test('cap enforcement drops the oldest lessons, keeps the header', () {
      // Exactly at the cap: 5 header lines + 195 lessons = 200.
      writeLessons(
          [...header(), for (var i = 1; i <= 195; i++) '- lesson $i']);
      expect(lessonsFile().readAsLinesSync(), hasLength(200));

      curator.appendLesson(stage, 'newest', gateFailed: true);

      final raw = lessonsFile().readAsLinesSync();
      expect(raw, hasLength(MemoryCurator.lessonsCap));
      expect(raw.sublist(0, 5), header()); // header intact
      final lessons = curator.lessonsFor(stage);
      expect(lessons, hasLength(195));
      expect(lessons.first, '- lesson 2'); // oldest dropped
      expect(lessons.last, '- newest');
    });
  });

  group('lessonsFor', () {
    test('returns empty for a stage with no lessons file', () {
      expect(curator.lessonsFor('deploy'), isEmpty);
    });
  });

  group('readFacts', () {
    test('round-trips {fact, source, ts} entries', () {
      File('${tmp.path}/facts/engine.json').writeAsStringSync('[\n'
          '  {"fact": "keys live in the vault",'
          ' "source": "docs/plans/x.md", "ts": "2026-07-30"},\n'
          '  {"fact": "gateway is loopback-only",'
          ' "source": "docs/plans/x.md", "ts": "2026-07-30"}\n'
          ']\n');
      final facts = curator.readFacts('engine');
      expect(facts, hasLength(2));
      expect(facts[0], {
        'fact': 'keys live in the vault',
        'source': 'docs/plans/x.md',
        'ts': '2026-07-30',
      });
      expect(facts[1]['fact'], 'gateway is loopback-only');
    });
  });
}
