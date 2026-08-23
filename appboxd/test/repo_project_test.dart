// repo_project + moodboard_check — the appbox law tests.
//
// repo mode: marker resolution, 8-stage skeleton, README authorship, the
// ~/.appbox shadow hard error, kind validation, sync. moodboard: totals
// arithmetic, floors, the locked-criterion rule, green-empty records.
// Every assertion fails if the behaviour it names is removed.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/commission.dart';
import 'package:appboxd/moodboard_check.dart';
import 'package:appboxd/project.dart' show appboxHomeOverride;
import 'package:appboxd/repo_project.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Directory home; // isolated APPBOX_HOME

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('appbox_repo_law');
    home = Directory('${tmp.path}/home')..createSync();
    appboxHomeOverride = home.path;
  });

  tearDown(() {
    appboxHomeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  group('ensureRepoProject', () {
    test('creates marker + all 8 stage folders + READMEs', () {
      final p = ensureRepoProject('${tmp.path}/landing', kind: 'site');
      expect(p.name, 'landing');
      expect(p.kind, 'site');
      final marker = jsonDecode(File('${tmp.path}/landing/appbox.json').readAsStringSync());
      expect(marker, isA<Map>());
      expect((marker as Map)['kind'], 'site');
      for (final stage in repoStages) {
        final readme = File('${tmp.path}/landing/$stage/README.md');
        expect(readme.existsSync(), isTrue, reason: '$stage README missing');
        expect(readme.readAsStringSync(), contains('landing — $stage'));
      }
      // kind-awareness is visible in the scaffold README text
      final siteScaffold = File('${tmp.path}/landing/scaffold/README.md').readAsStringSync();
      expect(siteScaffold, contains('htmx'));
      final app = ensureRepoProject('${tmp.path}/studio', kind: 'app');
      expect(File('${tmp.path}/studio/scaffold/README.md').readAsStringSync(),
          contains('Flutter'));
      expect(app.kind, 'app');
    });

    test('re-run refreshes READMEs and keeps the name', () {
      ensureRepoProject('${tmp.path}/studio', kind: 'app', name: 'studio');
      final readme = File('${tmp.path}/studio/design/README.md');
      readme.writeAsStringSync('hand-edited');
      final p = ensureRepoProject('${tmp.path}/studio', kind: 'app');
      expect(p.name, 'studio'); // existing marker name wins
      expect(readme.readAsStringSync(), contains('commission.md'));
    });

    test('rejects a bad kind and a bad name', () {
      expect(() => ensureRepoProject('${tmp.path}/x', kind: 'web'),
          throwsArgumentError);
      expect(() => ensureRepoProject('${tmp.path}/y', kind: 'site', name: 'Bad_Name'),
          throwsArgumentError);
    });

    test('HARD ERROR when a ~/.appbox shadow exists — the law', () {
      Directory('${home.path}/projects/landing').createSync(recursive: true);
      expect(() => ensureRepoProject('${tmp.path}/landing', kind: 'site'),
          throwsA(isA<StateError>()));
      // and resolution polices it too, not just init
      Directory('${tmp.path}/landing').createSync();
      File('${tmp.path}/landing/appbox.json').writeAsStringSync(
          '{"name": "landing", "kind": "site", "targets": [], "locales": []}');
      expect(() => resolveRepoProject('${tmp.path}/landing'),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('appbox law'))));
    });
  });

  group('findRepoProject', () {
    test('walks up from a nested dir to the nearest marker', () {
      ensureRepoProject('${tmp.path}/landing', kind: 'site');
      Directory('${tmp.path}/landing/intake/deep').createSync(recursive: true);
      final p = findRepoProject('${tmp.path}/landing/intake/deep');
      expect(p, isNotNull);
      expect(p!.name, 'landing');
    });

    test('returns null with no marker anywhere', () {
      Directory('${tmp.path}/nowhere').createSync();
      expect(findRepoProject('${tmp.path}/nowhere'), isNull);
    });

    test('a corrupt marker is skipped, not fatal', () {
      Directory('${tmp.path}/broken').createSync();
      File('${tmp.path}/broken/appbox.json').writeAsStringSync('not json');
      expect(findRepoProject('${tmp.path}/broken'), isNull);
    });
  });

  group('updateRepoProject', () {
    test('syncs kind/targets/locales and preserves the name', () {
      ensureRepoProject('${tmp.path}/landing', kind: 'site');
      updateRepoProject('${tmp.path}/landing',
          targets: ['web'], locales: ['en', 'fr']);
      final m = jsonDecode(File('${tmp.path}/landing/appbox.json').readAsStringSync()) as Map;
      expect(m['name'], 'landing');
      expect(m['targets'], ['web']);
      expect(m['locales'], ['en', 'fr']);
    });

    test('sync rewrites the stage READMEs to the synced kind (tool-owned)',
        () {
      final tmp = Directory.systemTemp.createTempSync('repo_sync_readmes');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final proj =
          ensureRepoProject('${tmp.path}/landing', name: 'probe', kind: 'app');
      // App-kind scaffold text: no site-root language yet.
      expect(File('${tmp.path}/landing/scaffold/README.md').readAsStringSync(),
          isNot(contains('site source root')));

      updateRepoProject(proj.dir, kind: 'site');

      // The kind change must reach the stage READMEs, not just the marker —
      // and generator improvements land on existing projects: the energize
      // repo carried pre-ADR-0009 "zero custom client-side JavaScript" stage
      // text until sync started rewriting READMEs.
      expect(File('${tmp.path}/landing/scaffold/README.md').readAsStringSync(),
          contains('site source root'),
          reason: 'a kind sync must refresh the per-kind stage READMEs');
      expect(File('${tmp.path}/landing/design/README.md').readAsStringSync(),
          contains('ADR-0009'),
          reason: 'a README-generator fix must reach existing projects');
    });

    test('refuses to sync without a marker', () {
      expect(() => updateRepoProject('${tmp.path}/ghost', kind: 'site'),
          throwsArgumentError);
    });
  });

  group('checkMoodboardRecord', () {
    Map<String, dynamic> rec({List<Map<String, dynamic>>? boards}) =>
        <String, dynamic>{
          'criteria': [
            {'id': 'animated-3d', 'weight': 3, 'locked': true},
            {'id': 'premium', 'weight': 1},
          ],
          'selectionStatus': 'approved',
          'boards': boards ?? const [],
        };

    test('green-empty: no boards is a pipeline position, not corruption', () {
      expect(checkMoodboardRecord(rec()), isEmpty);
    });

    test('PENDING record: scoring validated, selection NOT required', () {
      final r = rec(boards: [
        {
          'id': 'motion',
          'references': [
            {
              'name': 'Stripe',
              'scores': {'animated-3d': 5, 'premium': 4},
              'total': 4.75,
              'selected': false, // scored, not yet picked — honest pending
            }
          ],
        }
      ])
        ..['selectionStatus'] = 'pending';
      expect(checkMoodboardRecord(r), isEmpty);
    });

    test('PENDING record still refuses an infeasible locked criterion', () {
      final r = rec(boards: [
        {
          'id': 'motion',
          'references': [
            {
              'name': 'Static',
              'scores': {'animated-3d': 1, 'premium': 5},
              'total': 2.0,
              'selected': false,
            }
          ],
        }
      ])
        ..['selectionStatus'] = 'pending';
      expect(checkMoodboardRecord(r),
          anyElement(contains('re-gather')));
    });

    test('green on a coherent scored+selected record', () {
      final r = rec(boards: [
        {
          'id': 'motion',
          'references': [
            {
              'name': 'Stripe',
              'scores': {'animated-3d': 5, 'premium': 4},
              // (5*3 + 4*1) / 4 = 4.75
              'total': 4.75,
              'selected': true,
            }
          ],
        }
      ]);
      expect(checkMoodboardRecord(r), isEmpty);
    });

    test('recorded total that lies is caught', () {
      final r = rec(boards: [
        {
          'id': 'motion',
          'references': [
            {
              'name': 'Stripe',
              'scores': {'animated-3d': 5, 'premium': 4},
              'total': 1.0, // lie
              'selected': true,
            }
          ],
        }
      ]);
      expect(checkMoodboardRecord(r),
          everyElement(contains('recorded total')));
    });

    test('selected below floor fails; unselected low score does not', () {
      Map<String, dynamic> mk(bool selected) => rec(boards: [
            {
              'id': 'motion',
              'references': [
                {
                  'name': 'Ref',
                  'scores': {'animated-3d': 1, 'premium': 1},
                  'total': 1.0,
                  'selected': selected,
                },
                {
                  'name': 'Good',
                  'scores': {'animated-3d': 5, 'premium': 5},
                  'total': 5.0,
                  'selected': true,
                }
              ],
            }
          ]);
      expect(checkMoodboardRecord(mk(true)), anyElement(contains('< floor')));
      expect(checkMoodboardRecord(mk(false)), isEmpty);
    });

    test('locked criterion with no selected reference scoring >=3 fails — the energize lesson', () {
      final r = rec(boards: [
        {
          'id': 'motion',
          'references': [
            {
              'name': 'Static',
              'scores': {'animated-3d': 1, 'premium': 5},
              'total': 2.0,
              'selected': true,
            }
          ],
        }
      ]);
      final failures = checkMoodboardRecord(r);
      // fails BOTH the floor and the locked-criterion rule
      expect(failures, anyElement(contains('locked criterion "animated-3d"')));
    });

    test('approved with ZERO selections anywhere fails; one selected board alone satisfies', () {
      final none = rec(boards: [
        {
          'id': 'motion',
          'references': [
            {
              'name': 'Stripe',
              'scores': {'animated-3d': 5, 'premium': 4},
              'total': 4.75,
              'selected': false,
            }
          ],
        }
      ]);
      expect(checkMoodboardRecord(none),
          anyElement(contains('no references at all')));
      // a second board carrying the selection makes the record green even
      // though board 'motion' contributes nothing — the human's global pick
      final withOther = rec(boards: [
        ...(none['boards'] as List),
        {
          'id': 'other',
          'references': [
            {
              'name': 'Linear',
              'scores': {'animated-3d': 5, 'premium': 4},
              'total': 4.75,
              'selected': true,
            }
          ],
        }
      ]);
      expect(checkMoodboardRecord(withOther), isEmpty);
    });

    test('out-of-range score fails', () {
      final r = rec(boards: [
        {
          'id': 'motion',
          'references': [
            {
              'name': 'Ref',
              'scores': {'animated-3d': 7, 'premium': 4},
              'total': 5.0,
              'selected': true,
            }
          ],
        }
      ]);
      expect(checkMoodboardRecord(r), anyElement(contains('not an int 0..5')));
    });
  });

  group('commissionMain', () {
    Directory seedApp() {
      final app = Directory('${tmp.path}/site')..createSync();
      Directory('${app.path}/intake').createSync();
      File('${app.path}/appbox.json').writeAsStringSync(jsonEncode({
        'name': 'site',
        'kind': 'site',
        'targets': ['web'],
        'locales': ['en', 'fr'],
      }));
      File('${app.path}/intake/answers.json').writeAsStringSync(jsonEncode({
        'product': {'value': 'A marketing site', 'provenance': 'founder'},
        'constraints': [
          {'value': 'no custom client JS in the design layer'}
        ],
      }));
      File('${app.path}/intake/direction.json').writeAsStringSync(jsonEncode({
        'adjectives': [
          {'value': 'premium', 'provenance': 'founder'},
          {'value': 'cinematic (animated 3D backgrounds)', 'provenance': 'founder'},
        ],
        'avoids': [
          {'value': 'cheap', 'provenance': 'founder'},
        ],
      }));
      File('${app.path}/intake/moodboard.json').writeAsStringSync(jsonEncode({
        'method': 'appbox lens captures',
        'criteria': [
          {'id': 'animated-3d', 'weight': 3, 'locked': true},
          {'id': 'premium', 'weight': 1},
        ],
        'selectionStatus': 'approved',
        'tokenSynthesis': {
          'palette': 'sand base with lagoon ink and teal accent',
          'motion': 'time-driven gradient-through-type; poster first',
        },
        'boards': [
          {
            'id': 'motion',
            'references': [
              {
                'name': 'Stripe',
                'url': 'https://stripe.com',
                'scores': {'animated-3d': 5, 'premium': 4},
                'total': 4.75,
                'why': 'gradient through letters, poster fallback',
                'selected': true,
                'tokens': {
                  'palette': 'white with ink and blurple accent',
                  'type': 'grotesk cap/text pairing',
                  'radius': '8-10px cards and pill CTAs',
                  'motion': 'dual-H1 gradient-through-letters driven by time',
                },
                'shot': {'file': 'stripe__hero.png'},
              }
            ],
          }
        ],
        'counts': {'boards': 1, 'references': 1, 'shots': 1},
      }));
      return app;
    }

    test('compiles commission.md + prompt from an approved record', () {
      final app = seedApp();
      final code = commissionMain([app.path]);
      expect(code, 0);
      final md = File('${app.path}/design/commission.md').readAsStringSync();
      expect(md, contains('Design commission — site'));
      expect(md, contains('Kind **site**'));
      expect(md, contains('cinematic (animated 3D backgrounds)'));
      expect(md, contains('**animated-3d** — required by intake'));
      expect(md, contains('**Stripe** — https://stripe.com — total 4.75'));
      expect(md, contains('shot: ../moodboard/shots/motion/stripe__hero.png'));
      expect(md, contains('why: gradient through letters'));
      expect(md, contains('## Style tokens'));
      expect(md, contains('palette: white with ink and blurple accent'));
      expect(md, contains('### Synthesis'));
      expect(md, contains('**motion**: time-driven gradient-through-type; poster first'));
      // The pre-repo-mode constraints shape (bare list of {value} maps) renders.
      expect(md, contains('- no custom client JS in the design layer'));
      final prompt = File('${app.path}/design/commission-prompt.md').readAsStringSync();
      expect(prompt, contains('?variant=b'));
      expect(prompt, contains('data-screen-label'));
      expect(prompt, contains('44px'));
      expect(prompt, contains('Designer entry prompt — site'));
      expect(prompt, contains('NON-DEFERRABLE'));
      expect(prompt, contains('baoyu-design'));
    });

    test('renders the emitted intake shapes — bare arrays and envelopes', () {
      final app = seedApp();
      // The intake engine emits personas.json and v1 registry.json as BARE
      // arrays, constraints as a {value: [...]} envelope, and layoutTemplate
      // as a {value: {category, archetype, ...}} envelope. The compiler must
      // read what the pipeline actually writes (the energize-studio defect:
      // personas, registry, constraints and layout all silently dropped).
      File('${app.path}/intake/personas.json').writeAsStringSync(jsonEncode([
        {'id': 'guest', 'name': 'Resort guest', 'role': 'client', 'provenance': 'founder'},
      ]));
      File('${app.path}/intake/registry.json').writeAsStringSync(jsonEncode([
        {'id': 'home', 'surface': 'client'},
        {'id': 'tickets', 'surface': 'staff'},
      ]));
      final answersFile = File('${app.path}/intake/answers.json');
      final answers = jsonDecode(answersFile.readAsStringSync()) as Map;
      answers['constraints'] = {
        'value': ['Payslip math uses MRA statutory rates'],
        'provenance': 'founder',
      };
      answers['layoutTemplate'] = {
        'value': {
          'category': 'dashboard',
          'archetype': 'dashboard',
          'areas': {
            'compact': ['app-bar', 'card-grid', 'tab-bar'],
            'medium': ['app-bar app-bar', 'nav-rail toolbar', 'nav-rail card-grid'],
          },
          'containers': {
            'app-bar': {'type': 'chrome', 'hints': 'title, primary actions'},
          },
        },
        'provenance': 'founder',
      };
      answersFile.writeAsStringSync(jsonEncode(answers));
      final code = commissionMain([app.path]);
      expect(code, 0);
      final md = File('${app.path}/design/commission.md').readAsStringSync();
      expect(md, contains('- Resort guest — client'));
      expect(md, contains('- Surfaces in the registry: 2'));
      expect(md, contains('- Payslip math uses MRA statutory rates'));
      // The founder-signed template binds: grid areas per rung + containers.
      expect(md, contains('## Layout template — founder-signed'));
      expect(md, contains('- category: dashboard'));
      expect(md, contains('"nav-rail card-grid"'));
      expect(md, contains('- `app-bar` — chrome: title, primary actions'));
    });

    test('REFUSES an unapproved selection — the human gate', () {
      final app = seedApp();
      final f = File('${app.path}/intake/moodboard.json');
      final rec = jsonDecode(f.readAsStringSync()) as Map;
      rec['selectionStatus'] = 'pending';
      f.writeAsStringSync(jsonEncode(rec));
      final code = commissionMain([app.path]);
      expect(code, 2);
      expect(File('${app.path}/design/commission.md').existsSync(), isFalse);
    });

    test('REFUSES a record failing the moodboard law', () {
      final app = seedApp();
      final f = File('${app.path}/intake/moodboard.json');
      final rec = jsonDecode(f.readAsStringSync()) as Map;
      final boards = rec['boards'] as List;
      final refs = (boards[0] as Map)['references'] as List;
      (refs[0] as Map)['scores'] = {'animated-3d': 1, 'premium': 5};
      (refs[0] as Map)['total'] = 2.0;
      f.writeAsStringSync(jsonEncode(rec));
      final code = commissionMain([app.path]);
      expect(code, 2);
      expect(File('${app.path}/design/commission.md').existsSync(), isFalse);
    });
  });
}
