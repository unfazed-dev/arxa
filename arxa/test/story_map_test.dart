// story_map_test — byte-identity + contract tests for the Dart port of
// skills/arxa-story-mapper/scripts/generate_story_map.py (Task 14).
//
// The goldens under test/fixtures/story_map_sample.* were captured from the
// Python original (see plan §14.1). The port must reproduce them byte-for-byte
// so the gate (intake, plan 10.7) sees identical surface ids + markup.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/intake.dart' show emitBrief;
import 'package:arxa/story_map.dart';
import 'package:arxa/story_map_cli.dart';
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

    test('explicit feature id wins over the slug (camelCase / cross-shell)', () {
      final r = deriveSurfaces({
        'project': 'x',
        'releases': [
          {'name': 'R1'}
        ],
        'epics': [
          {
            'name': 'App Shell',
            'features': [
              {
                'name': 'Media Rive',
                'id': 'app.mediaRive',
                'stories': [
                  {'name': 's', 'priority': 'could', 'release': 'R1'}
                ],
              },
            ],
          },
        ],
      });
      expect(r.surfaces.single.id, 'app.mediaRive');
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

  group('renderBrief — unified chain (answers:)', () {
    final answers = <String, dynamic>{
      'product': {'value': 'Chain App', 'provenance': 'client'},
      'audience': {'value': 'Devs', 'provenance': 'client'},
      'appMustDo': {'value': ['ship'], 'provenance': 'client'},
      'targets': {'value': ['macos'], 'provenance': 'client'},
      'brand': {'value': 'none stated', 'provenance': 'inferred'},
      'surfaces': [
        {
          'id': 'projects.home',
          'label': 'Home',
          'shell': 'projects',
          'states': ['empty', 'loading'],
          'provenance': 'client',
        },
        {
          'id': 'projects.new',
          'label': 'New',
          'shell': 'projects',
          'provenance': 'client',
        },
      ],
    };
    final data = <String, dynamic>{
      'project': 'Chain App',
      'releases': [
        {'name': 'Release 1'}
      ],
      'epics': [
        {
          'name': 'Projects',
          'features': [
            {
              'name': 'Home',
              'id': 'projects.home',
              'stories': [
                {'name': 'List', 'priority': 'must', 'release': 'Release 1'},
              ],
            },
            {
              'name': 'Search',
              'stories': [
                {'name': 'Find', 'priority': 'should', 'release': 'Release 1'},
              ],
            },
          ],
        },
      ],
    };

    test('intake sections render with provenance + [inferred] marks, then the story map', () {
      final brief = renderBrief(data, answers: answers);
      expect(brief.contains('Emitted by the intake → story-map chain'), isTrue);
      expect(brief.contains('## Audience\n\nDevs\n\n_provenance: client_'), isTrue);
      expect(brief.contains('**[inferred]**'), isTrue); // brand
      expect(brief.contains('## Releases\n\n- **Release 1**'), isTrue);
      expect(brief.contains('#### Home\n\n- [must/Release 1] List'), isTrue);
      // the standalone "## Product" intro line is NOT present — intake owns it
      expect(brief.contains('Elicited via arxa-story-mapper'), isFalse);
    });

    test('declared surfaces carry the attaching feature rollup + states', () {
      final brief = renderBrief(data, answers: answers);
      expect(
          brief.contains(
              '| `projects.home` | Home | empty, loading | must | Release 1 |'),
          isTrue);
      // no feature pins projects.new -> blank rollup
      expect(brief.contains('| `projects.new` | New | error [inferred] |  |  |'),
          isTrue);
    });

    test('the UNIFIED brief derives states exactly as emitBrief does', () {
      // Slice 3: emitBrief and the intake -> story-map chain must not disagree
      // about the states column. Two briefs off the same answers showing
      // different states would make the confirm step meaningless — the
      // operator could confirm against the stale one.
      final brief = renderBrief(data, answers: answers);
      final standalone = emitBrief(answers);
      for (final id in const ['projects.home', 'projects.new']) {
        final row = brief
            .split('\n')
            .firstWhere((l) => l.contains('`$id`') && l.startsWith('|'));
        final states = row.split('|')[3].trim();
        final soloRow = standalone
            .split('\n')
            .firstWhere((l) => l.contains('`$id`') && l.startsWith('|'));
        expect(states, soloRow.split('|')[5].trim(),
            reason: 'the two briefs disagree about $id states');
      }
    });

    test('an unattached feature is appended, flagged — [inferred]', () {
      final brief = renderBrief(data, answers: answers);
      expect(
          brief.contains(
              '| `projects.search` | Search — [inferred] |  | should | Release 1 |'),
          isTrue);
      // declared rows come before derived rows
      expect(brief.indexOf('`projects.new`') < brief.indexOf('`projects.search`'),
          isTrue);
    });

    test('standalone path is untouched when answers is null', () {
      final golden = File(_goldenBriefPath).readAsStringSync();
      expect(renderBrief(sample), golden);
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

    test('emits into non-existent nested dirs (from-scratch folders)', () async {
      final dir = await Directory.systemTemp.createTemp('sm_nested_');
      final out = '${dir.path}/docs/intake/story_map.html';
      final data = '${dir.path}/deep/nested/tree/o.data.json';
      final brief = '${dir.path}/docs/intake/brief.md';
      final rc = storyMapMain(
          ['-i', _sampleJsonPath, '-o', out, '--data-out', data, '--brief-out', brief]);
      expect(rc, 0, reason: 'emit must create parent dirs, not crash');
      expect(File(out).existsSync(), isTrue);
      expect(File(data).existsSync(), isTrue);
      expect(File(brief).existsSync(), isTrue);
      await dir.delete(recursive: true);
    });

  // F1 — elicited story-map strings (project, releases, epics, features,
  // stories, surface labels) are client input. They must not reach the
  // brief as active markdown/HTML: the gate parses these tables and the
  // designer renders this brief.
  group('renderBrief — client-string safety (markdown injection)', () {
    final hostile = <String, dynamic>{
      'project': 'P <script>alert(1)</script>',
      'releases': [
        {'name': 'R1 [x](https://evil.example)', 'description': 'd **bold** | pipe'}
      ],
      'epics': [
        {
          'name': 'E `code`',
          'features': [
            {
              'name': 'F\n# injected heading',
              'stories': [
                {
                  'name': 'S<b>raw</b>',
                  'priority': 'must',
                  'release': 'R1 [x](https://evil.example)',
                  'description': '[l](javascript:alert(2))',
                },
              ],
            },
          ],
        },
      ],
    };

    test('structure is fine — the payloads are values, not shape defects', () {
      expect(validateData(hostile), isEmpty);
    });

    test('brief renders the payloads escaped, never as active markup', () {
      final brief = renderBrief(hostile);
      expect(brief.contains('<script>'), isFalse);
      expect(brief.contains('<b>'), isFalse);
      expect(brief.contains('[x](https://evil.example)'), isFalse);
      expect(brief.contains('[l](javascript:'), isFalse);
      expect(brief.contains('**bold**'), isFalse);
      // the newline payload is FLATTENED into the heading text — it must
      // not become a line of its own document structure
      expect(brief.contains('F # injected heading'), isTrue);
      expect(
          brief.split('\n').any((l) => l.trimLeft().startsWith('# injected')),
          isFalse);
      expect(brief.contains('&lt;script&gt;'), isTrue);
      expect(brief.contains('\\[x\\]'), isTrue);
    });

    test('HTML path stays escaped (regression guard)', () {
      final html = renderHtml(hostile, now: '2024-01-01 00:00');
      expect(html.contains('<script>alert'), isFalse);
      expect(html.contains('&lt;script&gt;'), isTrue);
    });
  });

  // F3 — duplicate identifiers shadow downstream: duplicate release names
  // make relOrder last-write-wins, duplicate explicit feature ids collide
  // in the traceability table, duplicate story names in a feature are
  // indistinguishable in the map. All three must be validation errors.
  // Duplicate EPIC names stay legal — slug suffixing is the design (see
  // storyMapSelfTest's second User System epic).
  group('validateData — duplicate detection (F3)', () {
    test('duplicate release names are rejected and both indexes named', () {
      final dup = {
        'project': 'P',
        'releases': [
          {'name': 'R1'},
          {'name': 'R1'},
        ],
        'epics': [
          {
            'name': 'E',
            'features': [
              {'name': 'F', 'stories': []},
            ],
          },
        ],
      };
      final errs = validateData(dup);
      expect(errs.where((e) => e.contains("duplicate release name 'R1'")),
          isNotEmpty);
    });

    test('duplicate explicit feature ids are rejected document-wide', () {
      final dup = {
        'project': 'P',
        'releases': [
          {'name': 'R1'}
        ],
        'epics': [
          {
            'name': 'E1',
            'features': [
              {'name': 'F1', 'id': 'app.mediaRive', 'stories': []},
            ],
          },
          {
            'name': 'E2',
            'features': [
              {'name': 'F2', 'id': 'app.mediaRive', 'stories': []},
            ],
          },
        ],
      };
      expect(validateData(dup).any((e) => e.contains("duplicate feature id 'app.mediaRive'")),
          isTrue);
    });

    test('duplicate story names within one feature are rejected', () {
      final dup = {
        'project': 'P',
        'releases': [
          {'name': 'R1'}
        ],
        'epics': [
          {
            'name': 'E',
            'features': [
              {
                'name': 'F',
                'stories': [
                  {'name': 'Same', 'priority': 'must', 'release': 'R1'},
                  {'name': 'Same', 'priority': 'could', 'release': 'R1'},
                ],
              },
            ],
          },
        ],
      };
      expect(validateData(dup).any((e) => e.contains('duplicate story name')),
          isTrue);
    });

    test('same story name in DIFFERENT features stays legal', () {
      final ok = {
        'project': 'P',
        'releases': [
          {'name': 'R1'}
        ],
        'epics': [
          {
            'name': 'E',
            'features': [
              {
                'name': 'F1',
                'stories': [
                  {'name': 'Same', 'priority': 'must', 'release': 'R1'},
                ],
              },
              {
                'name': 'F2',
                'stories': [
                  {'name': 'Same', 'priority': 'could', 'release': 'R1'},
                ],
              },
            ],
          },
        ],
      };
      expect(validateData(ok), isEmpty);
    });

    test('explicit feature id sanity: pipe, backtick, space rejected', () {
      for (final bad in ['a|b', 'a\\`b', 'a b', '']) {
        final doc = {
          'project': 'P',
          'releases': [
            {'name': 'R1'}
          ],
          'epics': [
            {
              'name': 'E',
              'features': [
                {'name': 'F', 'id': bad, 'stories': []},
              ],
            },
          ],
        };
        expect(validateData(doc).any((e) => e.contains("feature id")), isTrue,
            reason: 'id "$bad" must be rejected');
      }
    });
  });

    test('--answers emits the unified brief; bad answers exit 1 writing nothing', () async {
      final dir = await Directory.systemTemp.createTemp('sm_chain_');
      final out = '${dir.path}/o.html';
      final brief = '${dir.path}/o.brief.md';
      final answersPath = '${dir.path}/answers.json';
      await File(answersPath).writeAsString(jsonEncode({
        'product': {'value': 'Chain App', 'provenance': 'client'},
        'audience': {'value': 'Devs', 'provenance': 'client'},
        'appMustDo': {'value': ['ship'], 'provenance': 'client'},
        'targets': {'value': ['macos'], 'provenance': 'client'},
        'surfaces': [
          {'id': 'user.registration', 'label': 'Registration', 'shell': 'user', 'provenance': 'client'},
        ],
      }));
      final rc = storyMapMain(
          ['-i', _sampleJsonPath, '-o', out, '--brief-out', brief, '--answers', answersPath]);
      expect(rc, 0);
      final md = File(brief).readAsStringSync();
      expect(md.contains('Emitted by the intake → story-map chain'), isTrue);
      expect(md.contains('## Audience'), isTrue);

      // invalid answers -> exit 1, NOTHING written
      final out2 = '${dir.path}/o2.html';
      final brief2 = '${dir.path}/o2.brief.md';
      final badPath = '${dir.path}/bad.json';
      await File(badPath).writeAsString(jsonEncode({
        'product': {'value': 'x', 'provenance': 'guessed'},
      }));
      final rc2 = storyMapMain(
          ['-i', _sampleJsonPath, '-o', out2, '--brief-out', brief2, '--answers', badPath]);
      expect(rc2, 1);
      expect(File(out2).existsSync(), isFalse);
      expect(File(brief2).existsSync(), isFalse);
      await dir.delete(recursive: true);
    });
  });
}
