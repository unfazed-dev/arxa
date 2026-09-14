// Slice B1/B2 — the four extra intake artifacts and the personas question.
//
// Every assertion here is written to FAIL if the behaviour it names is removed.
// That is not decoration: this module has been bitten repeatedly by tests that
// passed either way (an idempotence check passes whether or not a key is
// carried forward; a hardcoded-id check passes whether ids are content-derived
// or sequential). Where an assertion could be satisfied by the broken version,
// the test uses a DISCRIMINATING setup instead — see the comments on the
// story-id, registry-merge and statuses-merge groups.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/intake.dart';
import 'package:arxa/intake_artifacts.dart';
import 'package:arxa/project.dart';
import 'package:test/test.dart';

Map<String, dynamic> _mapAnswers(List<Map<String, dynamic>> epics,
        {List<Map<String, dynamic>>? releases}) =>
    <String, dynamic>{
      'map': {
        'releases': ?releases,
        'epics': epics,
      }
    };

Map<String, dynamic> _story(String name, {String? priority, String? release}) =>
    <String, dynamic>{
      'name': name,
      'priority': ?priority,
      'release': ?release,
    };

/// The real answers of a project created BEFORE Slice B: no personas, no map,
/// no moodboard. Snapshotted rather than read from ~/.arxa at test time —
/// a test that depends on the developer's home dir proves nothing on CI.
Map<String, dynamic> _preSliceB() => (jsonDecode(
        File('test/fixtures/pre_slice_b_answers.json').readAsStringSync())
    as Map)
    .cast<String, dynamic>();

void main() {
  group('emitPersonas — variable N (B2)', () {
    test('an absent group degrades to [], not to an error', () {
      expect(emitPersonas(<String, dynamic>{}), isEmpty);
      expect(validatePersonas(<String, dynamic>{}), isEmpty);
    });

    test('a REAL pre-Slice-B project validates and emits [] for all four', () {
      // The regression this exists for: making personas required (or letting an
      // emitter throw on the absent group) turns `intake emit` into a hard
      // failure on every project that already exists on disk.
      final answers = _preSliceB();
      expect(answers.containsKey('personas'), isFalse,
          reason: 'fixture must be a genuine pre-Slice-B document');
      expect(validateIntake(answers).errors, isEmpty);
      expect(emitPersonas(answers), isEmpty);
      expect(emitStoryMap(answers)['epics'], isEmpty);
      expect(emitMoodboard(answers)['boards'], isEmpty);
      // direction IS present in this project, so it must survive the promotion.
      expect(emitDirection(answers)['adjectives'], isNotEmpty);
    });

    test('N is whatever the client named — one persona stays one', () {
      final one = emitPersonas({
        'personas': [
          {'name': 'Shop owner', 'provenance': 'client'}
        ]
      });
      expect(one, hasLength(1), reason: 'no padding to three');
      expect(one.single['id'], 'persona-shop-owner');
    });

    test('the 9-key shape: absent lists become [], unstated provenance inferred',
        () {
      final p = emitPersonas({
        'personas': [
          {'name': 'The Client', 'role': 'Founder'}
        ]
      }).single;
      expect(p.keys.toSet().containsAll(personaKeys), isTrue);
      expect(p['goals'], isEmpty);
      expect(p['frustrations'], isEmpty);
      expect(p['contexts'], isEmpty);
      expect(p['accessibility'], isNull);
      expect(p['provenance'], 'inferred',
          reason: 'not elicited IS inferred — there is no fourth value');
    });

    test('an authored key this emitter does not own still reaches the card', () {
      // Task #29: the literal that enumerated keys dropped `element` and
      // `feedback`. A persona emitter that enumerated 9 keys would drop the
      // 10th the same way.
      final p = emitPersonas({
        'personas': [
          {'name': 'Ops', 'provenance': 'client', 'quote': 'I live in the inbox'}
        ]
      }).single;
      expect(p['quote'], 'I live in the inbox');
    });

    test('validatePersonas names the offending field', () {
      expect(validatePersonas({'personas': 'nope'}).single, contains('personas:'));
      expect(validatePersonas({
        'personas': [
          {'provenance': 'client'}
        ]
      }).single, contains("personas[0]: missing 'name'"));
      expect(
          validatePersonas({
            'personas': [
              {'name': 'A', 'provenance': 'guessed'}
            ]
          }).single,
          contains('is not one of'));
      expect(
          validatePersonas({
            'personas': [
              {'name': 'A', 'provenance': 'client'},
              {'name': 'A', 'provenance': 'client'}
            ]
          }).single,
          contains('duplicate name'));
    });
  });

  group('emitStoryMap — content-derived ids', () {
    test('id shape is slug(epic).slug(feature).slug(story)', () {
      final m = emitStoryMap(_mapAnswers([
        {
          'name': 'Intake & Story Mapping',
          'features': [
            {
              'name': 'Mapping',
              'stories': [_story('Evan turns a brief into a map')]
            }
          ]
        }
      ]));
      final epic = (m['epics'] as List).single as Map;
      expect(epic['id'], 'intake-story-mapping');
      final feature = (epic['features'] as List).single as Map;
      expect(feature['id'], 'intake-story-mapping.mapping');
      expect(((feature['stories'] as List).single as Map)['id'],
          'intake-story-mapping.mapping.evan-turns-a-brief-into-a-map');
      expect(feature.containsKey('surfaceId'), isFalse,
          reason: 'Slice B decision: omitted, no reader and no test');
    });

    test('INSERTING a story leaves every pre-existing id untouched', () {
      // THE discriminating test. A hardcoded-string assertion passes whether
      // ids are content-derived or sequential; this one does not. With the
      // seed's s-1..s-34 scheme, inserting at the FRONT shifts every later id
      // by one and moves statuses onto the wrong rows.
      List<Map<String, dynamic>> epicsWith(List<Map<String, dynamic>> stories) => [
            {
              'name': 'Design',
              'features': [
                {'name': 'Canvas', 'stories': stories}
              ]
            }
          ];
      final before = emitStoryMap(_mapAnswers(epicsWith([
        _story('Drag a tile'),
        _story('Snap to grid'),
        _story('Undo a move'),
      ])));
      final after = emitStoryMap(_mapAnswers(epicsWith([
        _story('Zoom the canvas'), // inserted at the FRONT
        _story('Drag a tile'),
        _story('Snap to grid'),
        _story('Undo a move'),
      ])));
      // NAME -> id, not a bare id list. A set-containment check would pass
      // under sequential numbering too (s-1..s-3 is a subset of s-1..s-4);
      // only asking "does THIS story still have THAT id" tells them apart.
      Map<String, String> idByName(Map<String, dynamic> m) => {
            for (final s in ((((m['epics'] as List).single as Map)['features']
                    as List)
                .single as Map)['stories'] as List)
              (s as Map)['name'] as String: s['id'] as String
          };
      final kept = idByName(before);
      final moved = idByName(after);
      for (final name in kept.keys) {
        expect(moved[name], kept[name],
            reason: "inserting a story renamed '$name' — a content-derived id "
                'moves only when its own text changes');
      }
      expect(moved['Zoom the canvas'], 'design.canvas.zoom-the-canvas');
    });

    test('only genuinely colliding entries get a -2 suffix', () {
      final m = emitStoryMap(_mapAnswers([
        {
          'name': 'Design',
          'features': [
            {
              'name': 'Canvas',
              'stories': [_story('Drag a tile'), _story('Drag a tile')]
            }
          ]
        }
      ]));
      final stories = ((((m['epics'] as List).single as Map)['features'] as List)
          .single as Map)['stories'] as List;
      expect((stories[0] as Map)['id'], 'design.canvas.drag-a-tile');
      expect((stories[1] as Map)['id'], 'design.canvas.drag-a-tile-2');
    });

    test('counts, including a priority word outside MoSCoW', () {
      final m = emitStoryMap(_mapAnswers([
        {
          'name': 'A',
          'features': [
            {
              'name': 'F',
              'stories': [
                _story('one', priority: 'must', release: 'R1'),
                _story('two', priority: 'should', release: 'R1'),
                _story('three', priority: 'wont', release: 'R2'),
              ]
            }
          ]
        }
      ]));
      final counts = m['counts'] as Map;
      expect(counts['epics'], 1);
      expect(counts['features'], 1);
      expect(counts['stories'], 3);
      expect(counts['must'], 1);
      expect(counts['should'], 1);
      expect(counts['could'], 0, reason: 'zero, not absent');
      expect(counts['wont'], 1, reason: 'an unowned bucket is reported, not hidden');
      expect(counts['byRelease'], {'R1': 2, 'R2': 1});
      expect(((m['epics'] as List).single as Map)['storyCount'], 3);
    });

    test('a release keeps its authored description and gains a story count', () {
      // The spec's release field list is {name, stories, provenance}. Emitting
      // exactly those three would DELETE `description` — task #29 in miniature.
      final m = emitStoryMap(_mapAnswers([
        {
          'name': 'A',
          'features': [
            {
              'name': 'F',
              'stories': [_story('one', release: 'R1 Dogfood')]
            }
          ]
        }
      ], releases: [
        {'name': 'R1 Dogfood', 'description': 'arxa ships itself'}
      ]));
      final r = (m['releases'] as List).single as Map;
      expect(r['description'], 'arxa ships itself');
      expect(r['stories'], 1);
      expect(r['provenance'], 'inferred');
    });

    test('an absent or malformed group yields the empty shape, never a throw', () {
      for (final bad in [<String, dynamic>{}, {'map': 'nonsense'}, {'map': {'epics': 7}}]) {
        final m = emitStoryMap(bad.cast<String, dynamic>());
        expect(m['epics'], isEmpty);
        expect((m['counts'] as Map)['stories'], 0);
        expect(m['statuses'], isEmpty);
      }
    });
  });

  group('mergeStoryMap — statuses are authored, never emitted', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('arxa-map-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a prior status survives a re-emit', () {
      // Discriminating on purpose: emitStoryMap always yields statuses:{}, so
      // an overwrite would leave {} and this expectation would fail. An
      // idempotence-over-own-output check would NOT catch that.
      final path = '${tmp.path}/map.json';
      File(path).writeAsStringSync(jsonEncode({
        'epics': [],
        'statuses': {'design.canvas.drag-a-tile': 'done'},
        'reviewedBy': 'evan',
      }));
      final merged = mergeStoryMap(emitStoryMap(_mapAnswers([])), path);
      expect((merged['statuses'] as Map)['design.canvas.drag-a-tile'], 'done');
      expect(merged['reviewedBy'], 'evan',
          reason: 'a top-level key this emitter does not own is carried across');
    });

    test('an orphan status is kept when its story is renamed away', () {
      final path = '${tmp.path}/map.json';
      File(path).writeAsStringSync(jsonEncode({
        'statuses': {'a.f.old-name': 'done'}
      }));
      final merged = mergeStoryMap(
          emitStoryMap(_mapAnswers([
            {
              'name': 'A',
              'features': [
                {
                  'name': 'F',
                  'stories': [_story('new name')]
                }
              ]
            }
          ])),
          path);
      expect((merged['statuses'] as Map)['a.f.old-name'], 'done',
          reason: 'a typo fix must not be silent data loss');
    });

    test('a corrupt prior map never blocks a re-emit', () {
      final path = '${tmp.path}/map.json';
      File(path).writeAsStringSync('{ not json');
      expect(mergeStoryMap(emitStoryMap(_mapAnswers([])), path)['epics'], isEmpty);
    });

    test('statuses are key-sorted so bytes depend on content, not order', () {
      final path = '${tmp.path}/map.json';
      File(path).writeAsStringSync(jsonEncode({
        'statuses': {'z.f.s': 'done', 'a.f.s': 'blocked'}
      }));
      final merged = mergeStoryMap(emitStoryMap(_mapAnswers([])), path);
      expect((merged['statuses'] as Map).keys.toList(), ['a.f.s', 'z.f.s']);
    });
  });

  group('emitMoodboard', () {
    Map<String, dynamic> board() => <String, dynamic>{
          'moodboard': {
            'curated': '2026-07-28',
            'provenance': 'arxa lens captures · every shot verified on disk',
            'boards': [
              {
                'id': 'builders',
                'title': 'AI App Builders',
                'file': 'ai-builders.md',
                'references': [
                  {
                    'name': 'Dreamflow',
                    'grade': 'hot',
                    'shot': {
                      'file': 'dreamflow__tri-surface.png',
                      'caption': 'tri-surface editor'
                    },
                    'why': 'closest sibling',
                  }
                ]
              }
            ]
          }
        };

    test('shot id and src are precomputed at emit time', () {
      final b = (emitMoodboard(board())['boards'] as List).single as Map;
      final shot = ((b['references'] as List).single as Map)['shot'] as Map;
      expect(shot['id'], 'builders--dreamflow__tri-surface');
      expect(shot['src'], '/assets/images/moodboard/builders/dreamflow__tri-surface.png');
      expect(shot['caption'], 'tri-surface editor', reason: 'authored key kept');
    });

    test('provenance is renamed method; curated and board.file are dropped', () {
      final m = emitMoodboard(board());
      expect(m['method'], startsWith('arxa lens captures'));
      expect(m.containsKey('curated'), isFalse,
          reason: 'a date would break byte-identical re-emit (project.dart:13)');
      expect(m.containsKey('provenance'), isFalse,
          reason: 'the seed value is prose, not the client|founder|inferred enum');
      expect(((m['boards'] as List).single as Map).containsKey('file'), isFalse);
    });

    test('a reference with no stated provenance is marked inferred', () {
      final ref = (((emitMoodboard(board())['boards'] as List).single
          as Map)['references'] as List).single as Map;
      expect(ref['provenance'], 'inferred');
      expect(ref['why'], 'closest sibling', reason: 'authored key kept');
    });

    test('counts: shots is not assumed equal to references', () {
      final a = board();
      (((a['moodboard'] as Map)['boards'] as List).first as Map)['references'] = [
        {'name': 'With shot', 'shot': {'file': 'a.png'}},
        {'name': 'No capture yet'},
      ];
      expect(emitMoodboard(a)['counts'], {'boards': 1, 'references': 2, 'shots': 1});
    });

    test('an absent group yields the empty shape', () {
      final m = emitMoodboard(<String, dynamic>{});
      expect(m['boards'], isEmpty);
      expect(m['method'], isNull);
      expect(m['counts'], {'boards': 0, 'references': 0, 'shots': 0});
    });
  });

  group('emitDirection — provenance promoted per item', () {
    test('the field provenance lands on every item', () {
      final d = emitDirection({
        'direction': {
          'value': {
            'adjectives': ['calm', 'curated'],
            'avoids': ['clutter']
          },
          'provenance': 'founder'
        }
      });
      expect(d['adjectives'],
          [{'value': 'calm', 'provenance': 'founder'},
           {'value': 'curated', 'provenance': 'founder'}]);
      expect(d['avoids'], [{'value': 'clutter', 'provenance': 'founder'}]);
      expect(d['references'], isEmpty,
          reason: 'guessing which board informed which adjective is §22 fiction');
    });

    test("an item's OWN provenance beats the field's", () {
      // Otherwise a later edit to the field would silently re-stamp an item a
      // reviewer had already confirmed.
      final d = emitDirection({
        'direction': {
          'value': {
            'adjectives': [
              {'value': 'tactile', 'provenance': 'client'}
            ]
          },
          'provenance': 'inferred'
        }
      });
      expect((d['adjectives'] as List).single, {'value': 'tactile', 'provenance': 'client'});
    });

    test('an absent group yields empty lists, not null', () {
      final d = emitDirection(<String, dynamic>{});
      expect(d['adjectives'], isEmpty);
      expect(d['avoids'], isEmpty);
      expect(d['references'], isEmpty);
    });
  });

  group('emitBrandColors — the reseed slot (palette-plane Q6)', () {
    test('an absent group degrades to [], never an error', () {
      expect(emitBrandColors(<String, dynamic>{}), isEmpty);
      expect(validateBrandColors(<String, dynamic>{}), isEmpty);
    });

    test('entries pass through VERBATIM — no normalization, no re-stamping', () {
      // '#'less stays '#'less, case kept: digit-level normalization is
      // palette_derive's one home (Q10), and 3-digit doubling happened at
      // ELICITATION, before the answers were recorded (the schema's hex law).
      expect(emitBrandColors({
        'brandColors': [
          {'hex': '1b3a4b', 'role': 'dark', 'provenance': 'client'},
          {'hex': '#F5EFE0', 'provenance': 'inferred'},
        ]
      }), [
        {'hex': '1b3a4b', 'role': 'dark', 'provenance': 'client'},
        {'hex': '#F5EFE0', 'provenance': 'inferred'},
      ]);
    });

    test('an explicitly-null role is emitted as absent', () {
      // One spelling of "no pin": the reseed treats absent role as
      // "unhinted — the Q5 lightness-rank law assigns it".
      expect(emitBrandColors({
        'brandColors': [
          {'hex': '#1b3a4b', 'role': null, 'provenance': 'client'}
        ]
      }).single.containsKey('role'), isFalse);
    });

    test('an authored key the emitter does not own still rides along', () {
      // Task #29: the literal that enumerated keys dropped `element` and
      // `feedback`. brandColorKeys closes the group at VALIDATION; passing
      // the entry through whole keeps a future legal key from being
      // silently dropped HERE.
      final c = emitBrandColors({
        'brandColors': [
          {'hex': '#1b3a4b', 'provenance': 'client', 'note': 'from the logo'}
        ]
      }).single;
      expect(c['note'], 'from the logo');
    });
  });

  group('registry — additive priority/release columns', () {
    Map<String, dynamic> answersWith(String priority) => <String, dynamic>{
          'surfaces': [
            {
              'id': 'shop.cart',
              'label': 'Cart',
              'shell': 'shop',
              'provenance': 'client',
              'priority': priority,
              'release': 'R1',
            }
          ]
        };

    test('they land on the entry', () {
      final e = emitRegistry(answersWith('must')).single;
      expect(e['priority'], 'must');
      expect(e['release'], 'R1');
    });

    test('a surface with no ranking gets no keys at all', () {
      final e = emitRegistry({
        'surfaces': [
          {'id': 'shop.cart', 'label': 'Cart', 'shell': 'shop', 'provenance': 'client'}
        ]
      }).single;
      expect(e.containsKey('priority'), isFalse);
      expect(e.containsKey('release'), isFalse);
    });

    test('re-emitting after an EDIT writes the new priority, not the stale one',
        () {
      // THE discriminating test for registryEmittedKeys. mergeRegistry spreads
      // the prior entry after the emitted one for every key it does not
      // recognise, so an emitted-but-unlisted key is overwritten by its own
      // stale value. Emit-then-re-emit-unchanged (idempotence) passes either
      // way; changing the answer in between is what tells them apart.
      final tmp = Directory.systemTemp.createTempSync('arxa-reg-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final path = '${tmp.path}/registry.json';
      File(path).writeAsStringSync(jsonEncode([
        {'id': 'shop.cart', 'priority': 'must', 'kits': ['payments']}
      ]));
      final merged = mergeRegistry(emitRegistry(answersWith('should')), path).single;
      expect(merged['priority'], 'should',
          reason: 'the answers are the SSOT; the file must not win');
      expect(merged['kits'], ['payments'],
          reason: 'a foreign key is still carried forward');
    });
  });

  group('IntakeEngine.emit — the four land in the project shell', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('arxa-emit-');
      arxaHomeOverride = tmp.path;
    });
    tearDown(() {
      arxaHomeOverride = null;
      tmp.deleteSync(recursive: true);
    });

    test('a PRE-Slice-B project still emits, and the four are empty shapes', () {
      // The whole point of B2's degrade rule: this is a real answers document
      // with no personas/map/moodboard group. Emit must succeed, not fail.
      final res = const IntakeEngine().emit(_preSliceB(), project: 'legacy');
      expect(res.ok, isTrue, reason: res.errors.join('; '));
      final dir = shellDir('legacy', 'intake');
      for (final f in const [
        'answers.json', 'brief.md', 'registry.json', 'flows.json',
        'personas.json', 'map.json', 'moodboard.json', 'direction.json',
        'brandcolors.json',
      ]) {
        expect(File('$dir/$f').existsSync(), isTrue, reason: 'missing $f');
      }
      expect(jsonDecode(File('$dir/personas.json').readAsStringSync()), isEmpty);
      expect(
          (jsonDecode(File('$dir/map.json').readAsStringSync())
              as Map)['epics'],
          isEmpty);
    });

    test('brandcolors.json lands VERBATIM — hexes not normalized', () {
      final answers = _preSliceB()
        ..['brandColors'] = [
          {'hex': '1b3a4b', 'role': 'dark', 'provenance': 'client'},
          {'hex': '#C9A227', 'provenance': 'inferred'},
        ];
      final res = const IntakeEngine().emit(answers, project: 'brand');
      expect(res.ok, isTrue, reason: res.errors.join('; '));
      final slot = jsonDecode(File(
              '${shellDir('brand', 'intake')}/brandcolors.json')
          .readAsStringSync());
      expect(slot, [
        {'hex': '1b3a4b', 'role': 'dark', 'provenance': 'client'},
        {'hex': '#C9A227', 'provenance': 'inferred'},
      ], reason: "verbatim — normalization is palette_derive's one home (Q10)");
    });

    test('a status written between emits survives the next emit', () {
      // The end-to-end form of the mergeStoryMap unit test: this is the path
      // that actually destroyed portalo's `kits` column via registry.json.
      final answers = _preSliceB()
        ..['map'] = {
          'epics': [
            {
              'name': 'Browse',
              'features': [
                {'name': 'Catalog', 'stories': [_story('See a product')]}
              ]
            }
          ]
        };
      const engine = IntakeEngine();
      expect(engine.emit(answers, project: 'p').ok, isTrue);
      final path = '${shellDir('p', 'intake')}/map.json';
      final map = (jsonDecode(File(path).readAsStringSync()) as Map)
          .cast<String, dynamic>();
      (map['statuses'] as Map)['browse.catalog.see-a-product'] = 'done';
      File(path).writeAsStringSync(jsonEncode(map));

      expect(engine.emit(answers, project: 'p').ok, isTrue);
      final after = jsonDecode(File(path).readAsStringSync()) as Map;
      expect((after['statuses'] as Map)['browse.catalog.see-a-product'], 'done');
    });
  });

  group('schema drift — the input contract must declare what emit reads', () {
    test('personas/map/moodboard are declared top-level properties', () {
      // intake.schema.json is additionalProperties:false at the top level and
      // NOTHING loads it (intake.dart:70), so a group the Dart validator
      // accepts but the schema omits is illegal-yet-passing: the two front ends
      // disagree and neither says so. SKILL.md tells authors to conform to the
      // schema, so the drift lands on the producer skills — story-mapper and
      // moodboarder would have nowhere legal to deposit their document and
      // map.json would emit the empty shape forever.
      final schema = (jsonDecode(
              File('../skills/arxa-intake/intake.schema.json').readAsStringSync())
          as Map)['properties'] as Map;
      expect(schema['additionalProperties'], isNull);
      for (final group in const ['personas', 'map', 'moodboard', 'brandColors']) {
        expect(schema.containsKey(group), isTrue,
            reason: '$group is read by an emitter but undeclared in the schema');
      }
    });
  });

  group('determinism — the contract this module inherits', () {
    test('same answers in, same bytes out, and idempotent over its own output',
        () {
      final answers = _preSliceB()
        ..['personas'] = [
          {'name': 'Shop owner', 'provenance': 'client', 'goals': ['Sell']}
        ]
        ..['map'] = {
          'epics': [
            {
              'name': 'Browse',
              'features': [
                {
                  'name': 'Catalog',
                  'stories': [_story('See a product', priority: 'must')]
                }
              ]
            }
          ]
        };
      String bytes(Map<String, dynamic> a) => jsonEncode([
            emitPersonas(a),
            emitStoryMap(a),
            emitMoodboard(a),
            emitDirection(a),
            emitBrandColors(a),
          ]);
      expect(bytes(answers), bytes(answers));
      // Idempotence over own output: feeding an emitted direction back in as
      // per-item objects must not change it.
      final once = emitDirection(answers);
      final twice = emitDirection({
        'direction': {
          'value': {'adjectives': once['adjectives'], 'avoids': once['avoids']},
          'provenance': 'inferred'
        }
      });
      expect(twice['adjectives'], once['adjectives']);
      expect(twice['avoids'], once['avoids']);
    });
  });
}
