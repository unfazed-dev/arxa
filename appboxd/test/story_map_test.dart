// story_map_test — byte-identity + contract tests for the Dart port of
// skills/appbox-story-mapper/scripts/generate_story_map.py (Task 14).
//
// The goldens under test/fixtures/story_map_sample.* were captured from the
// Python original (see plan §14.1). The port must reproduce them byte-for-byte
// so the gate (intake, plan 10.7) sees identical surface ids + markup.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/story_map.dart';
import 'package:appboxd/story_map_cli.dart';
import 'package:test/test.dart';

final _fixtures = 'test/fixtures';
final _sampleJsonPath = '$_fixtures/story_map_sample.json';
final _goldenHtmlPath = '$_fixtures/story_map_sample.html';
final _goldenDataPath = '$_fixtures/story_map_sample.data.json';
final _goldenBriefPath = '$_fixtures/story_map_sample.brief.md';

Map<String, dynamic> _loadSample() =>
    jsonDecode(File(_sampleJsonPath).readAsStringSync()) as Map<String, dynamic>;

void main() {
  late Map<String, dynamic> sample;
  setUpAll(() {
    sample = _loadSample();
  });

  group('validateData', () {
    test('valid sample yields no errors', () {
      expect(validateData(sample), isEmpty);
    });

    test('missing top-level fields enumerated', () {
      final errs = validateData(<String, dynamic>{});
      expect(errs, contains("Missing required field: 'project'"));
      expect(errs, contains("Missing or empty 'releases' array"));
      expect(errs, contains("Missing or empty 'epics' array"));
    });

    test('invalid priority and unknown release path strings', () {
      final broken = {
        'project': 'P',
        'releases': [
          {'name': 'R1'}
        ],
        'epics': [
          {
            'name': 'EpicA',
            'features': [
              {
                'name': 'FeatA',
                'stories': [
                  {'name': 'StoryA', 'priority': 'x', 'release': 'Nope'},
                ]
              },
            ]
          },
        ]
      };
      expect(validateData(broken), equals([
        "'FeatA' story[0] 'StoryA': invalid priority 'x'",
        "'FeatA' story[0] 'StoryA': unknown release 'Nope'",
      ]));
    });

    test('non-object input', () {
      expect(validateData(<String, dynamic>{}), isNotEmpty);
    });
  });

  group('deriveSurfaces', () {
    test('ids match gate pattern, are unique, and follow slug rules', () {
      final r = deriveSurfaces(sample);
      final ids = r.surfaces.map((s) => s.id).toList();
      for (final id in ids) {
        expect(idRe.hasMatch(id), isTrue, reason: 'id "$id" fails gate pattern');
      }
      expect(ids.toSet().length, ids.length, reason: 'duplicate ids: $ids');
      expect(ids[0], 'user.registration',
          reason: 'first ascii word slug: ${ids[0]}');
    });

    test('all-wont feature is out-of-scope, not a surface', () {
      final r = deriveSurfaces(sample);
      expect(r.surfaces.any((s) => s.id.contains('legacy')), isFalse);
      expect(
          r.outOfScope,
          contains(OutOfScope('User System', 'Legacy SSO')));
    });

    test('CJK-only feature slug falls back to "s"', () {
      final r = deriveSurfaces(sample);
      expect(r.surfaces.map((s) => s.id), contains('user.s'));
    });

    test('rollup = strongest live priority + earliest live release', () {
      final r = deriveSurfaces(sample);
      final byId = {for (final s in r.surfaces) s.id: s};
      expect(byId['user.registration']!.priority, 'must');
      expect(byId['user.registration']!.release, 'Release 1');
    });

    test('storyless feature stays a surface with a blank rollup', () {
      final r = deriveSurfaces(sample);
      final byId = {for (final s in r.surfaces) s.id: s};
      final empty = byId['user2.registration2'];
      expect(empty, isNotNull);
      expect(empty!.priority, '');
      expect(empty.release, '');
    });
  });

  group('byte-identity vs Python goldens', () {
    test('renderBrief == golden brief.md', () {
      final golden = File(_goldenBriefPath).readAsStringSync();
      expect(renderBrief(sample), golden);
    });

    test('renderHtml == golden html (timestamp pinned to the golden)', () {
      final golden = File(_goldenHtmlPath).readAsStringSync();
      // The only non-deterministic field is the "Generated YYYY-MM-DD HH:MM"
      // stamp; pin it to whatever the golden captured so the rest must match.
      final m = RegExp(r'Generated (\d{4}-\d{2}-\d{2} \d{2}:\d{2})')
          .firstMatch(golden)!;
      expect(renderHtml(sample, now: m.group(1)), golden);
    });

    test('serializeDataJson == golden data.json', () {
      final golden = File(_goldenDataPath).readAsStringSync();
      expect(serializeDataJson(sample), golden);
    });
  });

  group('storyMapMain (CLI contract)', () {
    test('--self-test prints "self-test OK" and returns 0', () {
      final rc = storyMapMain(const ['--self-test']);
      expect(rc, 0);
    });

    test('missing --output is a usage error (exit 64)', () {
      final rc = storyMapMain(['-i', _sampleJsonPath]);
      expect(rc, 64);
    });

    test('validation failure exits 1', () async {
      final tmpIn = await File('${Directory.systemTemp.path}/sm_bad.json')
          .writeAsString('{"project":"P","releases":[],"epics":[]}');
      final rc = storyMapMain(['-i', tmpIn.path, '-o',
        '${Directory.systemTemp.path}/sm_out.html']);
      expect(rc, 1);
    });

    test('emits all three artifacts from the fixture', () async {
      final dir = await Directory.systemTemp.createTemp('sm_cli_');
      final out = '${dir.path}/o.html';
      final data = '${dir.path}/o.data.json';
      final brief = '${dir.path}/o.brief.md';
      final rc = storyMapMain(
          ['-i', _sampleJsonPath, '-o', out, '--data-out', data, '--brief-out', brief]);
      expect(rc, 0, reason: 'emit must succeed');
      // HTML matches golden byte-for-byte once the timestamp is pinned.
      final goldenHtml = File(_goldenHtmlPath).readAsStringSync();
      final m = RegExp(r'Generated (\d{4}-\d{2}-\d{2} \d{2}:\d{2})')
          .firstMatch(goldenHtml)!;
      final produced = File(out).readAsStringSync();
      final pinned = produced.replaceFirst(
          RegExp(r'Generated \d{4}-\d{2}-\d{2} \d{2}:\d{2}'),
          'Generated ${m.group(1)}');
      expect(pinned, goldenHtml);
      expect(File(data).readAsStringSync(),
          File(_goldenDataPath).readAsStringSync());
      expect(File(brief).readAsStringSync(),
          File(_goldenBriefPath).readAsStringSync());
      await dir.delete(recursive: true);
    });
  });
}
