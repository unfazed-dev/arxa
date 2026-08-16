// Tests for the Dart intake engine — port of skills/appbox-intake/intake.py.
//
// The registry golden below was captured byte-for-byte from the Python engine
// (`emit_registry`) on the `goodAnswers()` fixture. The brief golden DIVERGES
// deliberately: the merged chain added Locales / Design direction / Content
// anchors sections and a states column the Python engine does not emit.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/intake.dart';
import 'package:appboxd/intake_cli.dart';
import 'package:appboxd/project.dart';
import 'package:test/test.dart';

Map<String, dynamic> goodAnswers() => {
      'product': {'value': 'Demo app', 'provenance': 'client'},
      'audience': {'value': 'Indie devs', 'provenance': 'client'},
      'appMustDo': {
        'value': ['list projects', 'run a build'],
        'provenance': 'client',
      },
      'targets': {
        'value': ['macos'],
        'provenance': 'client',
      },
      'brand': {'value': 'none stated', 'provenance': 'inferred'},
      'surfaces': [
        {
          'id': 'projects.home',
          'label': 'Home',
          'shell': 'projects',
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

/// goodAnswers + a well-formed layoutTemplate pick (self-test case 15).
Map<String, dynamic> goodWithLayout() {
  final a = goodAnswers();
  a['layoutTemplate'] = {
    'value': {
      'category': 'productivity',
      'archetype': 'list-detail',
      'areas': {
        'compact': ['app-bar', 'list', 'tab-bar'],
        'medium': ['app-bar app-bar app-bar', 'nav-rail list detail'],
        'expanded': ['app-bar app-bar app-bar', 'nav-rail list detail'],
      },
      'containers': {
        'list': {
          'type': 'content',
          'hints': 'the collection; source of selection',
        },
        'detail': {
          'type': 'content',
          'hints': 'the selected item; a pushed route at compact',
        },
      },
    },
    'provenance': 'client',
  };
  return a;
}

// The exact bytes the Dart engine emits for goodAnswers(). Sections through
// "Existing systems" are byte-identical to the Python golden; from "Locales"
// on the merged chain diverges deliberately (new field groups + states column).
const expectedBrief = '''# Demo app — design brief

> Emitted by appbox-intake from elicited answers.
> **Intake elicits; it does not generate** (architecture §22).
> Fields marked **[inferred]** were not stated by the client and MUST
> be confirmed before design consumes this brief.

## Product

Demo app

_provenance: client_

## Audience

Indie devs

_provenance: client_

## What the app must do

- list projects
- run a build

_provenance: client_

## Existing systems

_Not stated._
## Targets

- macos

_provenance: client_

## Locales

_Not stated._
## Brand

> **[inferred]** — not stated by the client; confirm or correct.

none stated

_provenance: inferred_

## Design direction

_Not stated._
## Content anchors

_Not stated._
## Constraints

_Not stated._
## Out of scope

_Not stated._
## Layout template

_Not stated._
## Surface inventory — the registry seed

| id | shell | comp | label | states | surface |
|---|---|---|---|---|---|
| `projects.home` | projects | ProjectsHome | Home | loading, empty [inferred] | _null_ |
| `projects.new` | projects | ProjectsNew | New | error [inferred] | _null_ |

Every `surface` is `null` — intake names what the client asked for; design binds a surface to each.
''';

// Slice 3 (D3): neither fixture surface DECLARES states, so both are derived
// from shape and stamped `statesProvenance: inferred` — "home" is a collection
// (loading, empty), "new" is a create form (error). The stamp is what keeps
// this legal under §22: the confirm step can strike either row.
const expectedRegistry = '''[
  {
    "id": "projects.home",
    "label": "Home",
    "shell": "projects",
    "comp": "ProjectsHome",
    "route": "/home",
    "surface": null,
    "states": [
      "loading",
      "empty"
    ],
    "statesProvenance": "inferred"
  },
  {
    "id": "projects.new",
    "label": "New",
    "shell": "projects",
    "comp": "ProjectsNew",
    "route": "/new",
    "surface": null,
    "states": [
      "error"
    ],
    "statesProvenance": "inferred"
  }
]
''';

const handwrittenBrief = '''# Widget shop

## Surface inventory

| id | shell | label |
|---|---|---|
| `shop.cart` | shop | Cart |
| `shop.home` | shop | Home |
''';

const expectedSeed = '''[
  {
    "id": "shop.cart",
    "label": "Cart",
    "shell": "shop",
    "comp": "ShopCart",
    "route": "/cart",
    "surface": null
  },
  {
    "id": "shop.home",
    "label": "Home",
    "shell": "shop",
    "comp": "ShopHome",
    "route": "/home",
    "surface": null
  }
]
''';

void main() {
  _mergeRegistryTests();

  group('deriveComp', () {
    test('PascalCase(shell) + PascalCase(short) by the declare-structure convention', () {
      expect(deriveComp('shop.cart'), 'ShopCart');
      expect(deriveComp('projects.home'), 'ProjectsHome');
      expect(deriveComp('settings.kits'), 'SettingsKits');
    });

    test('rejects a malformed id', () {
      expect(() => deriveComp('nope'), throwsArgumentError);
    });
  });

  group('validate', () {
    test('valid input -> no errors', () {
      expect(validateIntake(goodAnswers()).errors, isEmpty);
    });

    test('rejects an unknown provenance and names it', () {
      final bad = goodAnswers();
      (bad['audience'] as Map)['provenance'] = 'guessed';
      final errs = validateIntake(bad).errors;
      expect(errs.any((e) => e.contains('audience') && e.contains('guessed')), isTrue);
    });
  });

  group('validate — negative cases (mirror the Python self-test)', () {
    test('malformed surface id (case) is rejected and named', () {
      final bad = goodAnswers();
      final surfaces = bad['surfaces'] as List;
      (surfaces[0] as Map)['id'] = 'Projects.Home';
      final errs = validateIntake(bad).errors;
      expect(errs.any((e) => e.contains('surfaces[0]') && e.contains('Projects.Home')),
          isTrue);
    });

    test('shell must equal the id prefix', () {
      final bad = goodAnswers();
      ((bad['surfaces'] as List)[1] as Map)['shell'] = 'build';
      final errs = validateIntake(bad).errors;
      expect(errs.any((e) => e.contains('surfaces[1]') && e.contains('first segment')),
          isTrue);
    });

    test('duplicate surface id is rejected (ids are permanent)', () {
      final bad = goodAnswers();
      ((bad['surfaces'] as List)[1] as Map)['id'] = 'projects.home';
      final errs = validateIntake(bad).errors;
      expect(errs.any((e) => e.contains('duplicate')), isTrue);
    });

    test('missing required fields are each named', () {
      final errs = validateIntake({'surfaces': []}).errors;
      expect(errs.any((e) => e.contains('product: required field is missing')), isTrue);
      expect(errs.any((e) => e.contains('audience: required field is missing')), isTrue);
      expect(errs.any((e) => e.contains('appMustDo: required field is missing')), isTrue);
      expect(errs.any((e) => e.contains('targets: required field is missing')), isTrue);
    });

    test('a non-dict layoutTemplate value is rejected', () {
      final bad = goodAnswers();
      bad['layoutTemplate'] = {'value': 'feed', 'provenance': 'client'};
      final errs = validateIntake(bad).errors;
      expect(errs.any((e) => e.contains('layoutTemplate')), isTrue);
    });

    test('a layoutTemplate missing a rung is rejected', () {
      final bad = goodWithLayout();
      ((bad['layoutTemplate'] as Map)['value'] as Map)['areas']
          .remove('expanded');
      final errs = validateIntake(bad).errors;
      expect(errs.any((e) => e.contains('expanded')), isTrue);
    });

    test('a well-formed layoutTemplate is accepted', () {
      expect(validateIntake(goodWithLayout()).errors, isEmpty);
    });
  });

  group('emit — elicits, never generates', () {
    test('registry has exactly the input surfaces; every surface null', () {
      final ans = goodAnswers();
      final reg = emitRegistry(ans);
      expect(reg.length, (ans['surfaces'] as List).length);
      expect(reg.map((e) => e['id']).toSet(),
          (ans['surfaces'] as List).map((s) => (s as Map)['id']).toSet());
      expect(reg.every((e) => e['surface'] == null), isTrue);
    });

    test('emitBrief matches the golden (chain sections included)', () {
      expect(emitBrief(goodAnswers()), expectedBrief);
    });

    test('emitRegistry is byte-identical to the Python golden', () {
      expect('${const JsonEncoder.withIndent('  ').convert(emitRegistry(goodAnswers()))}\n',
          expectedRegistry);
    });

    test('an inferred field is visibly marked; a client field is not', () {
      final brief = emitBrief(goodAnswers());
      expect(brief.contains('**[inferred]**'), isTrue);
      final audienceStart = brief.indexOf('## Audience');
      final audienceSection = brief.substring(
          audienceStart, brief.indexOf('##', audienceStart + 2));
      expect(audienceSection.contains('**[inferred]**'), isFalse);
    });

    test('field values pass through verbatim (no rewording)', () {
      final brief = emitBrief(goodAnswers());
      expect(brief.contains('Indie devs'), isTrue);
      expect(brief.contains('list projects'), isTrue);
    });
  });

  group('emit — layoutTemplate rendering', () {
    test('renders its own section before the surface inventory', () {
      final brief = emitBrief(goodWithLayout());
      expect(brief.contains('## Layout template'), isTrue);
      final lt = brief.substring(
          brief.indexOf('## Layout template'), brief.indexOf('## Surface inventory'));
      expect(lt.contains('list-detail'), isTrue);
      expect(lt.contains('"nav-rail list detail"'), isTrue);
      expect(lt.contains('- `detail` — content:'), isTrue);
      expect(lt.contains('_provenance: client_'), isTrue);
      // The section carries no markdown table rows — the surface-table parsers
      // (gate + seedFromBrief) see nothing new.
      expect(lt.split('\n').every((l) => !l.trim().startsWith('|')), isTrue);
    });
  });

  group('seedFromBrief — hand-written brief (10.7)', () {
    test('parses a surface table into a registry seed; surface null', () {
      final seed = seedFromBrief(handwrittenBrief);
      expect('${const JsonEncoder.withIndent('  ').convert(seed)}\n', expectedSeed);
      expect(seed.every((e) => e['surface'] == null), isTrue);
    });

    test('a brief with no surface table yields an empty seed (not an error)', () {
      expect(seedFromBrief('# Just prose\n\nNo table here.\n'), isEmpty);
    });

    test('a row that is not a valid id is skipped, not crashed', () {
      const mixed = '| id | shell |\n|---|---|\n| `shop.cart` | shop |\n| not-an-id | x |\n';
      expect(seedFromBrief(mixed).map((e) => e['id']).toList(), ['shop.cart']);
    });

    test('optional priority/release columns pass through as sibling metadata', () {
      const prio =
          '| id | label | priority | release |\n|---|---|---|---|\n| `shop.cart` | Cart | must | Release 1 |\n';
      final s = seedFromBrief(prio);
      expect(s[0]['priority'], 'must');
      expect(s[0]['release'], 'Release 1');
      expect(s[0]['comp'], 'ShopCart');
      expect(s[0]['surface'], null);
    });

    test('key order: id, label, shell, comp, surface, priority, release', () {
      const prio =
          '| id | label | priority | release |\n|---|---|---|---|\n| `shop.cart` | Cart | must | Release 1 |\n';
      expect(seedFromBrief(prio)[0].keys.toList(),
          ['id', 'label', 'shell', 'comp', 'route', 'surface', 'priority', 'release']);
    });
  });

  group('IntakeEngine', () {
    late Directory tmp;
    late IntakeEngine engine;

    setUp(() {
      engine = const IntakeEngine();
      tmp = Directory.systemTemp.createTempSync('appbox_intake_test');
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('emit writes both artefacts and the bytes match the goldens', () {
      final briefPath = '${tmp.path}/out/brief.md';
      final registryPath = '${tmp.path}/out/registry.json';
      final res = engine.emit(goodAnswers(),
          briefOut: briefPath, registryOut: registryPath);
      expect(res.ok, isTrue);
      expect(res.errors, isEmpty);
      expect(res.entries, 2);
      expect(res.inferredCount, 1); // brand
      expect(File(briefPath).readAsStringSync(), expectedBrief);
      expect(File(registryPath).readAsStringSync(), expectedRegistry);
    });

    test('invalid input writes nothing — no partial artefacts', () {
      final bad = {'product': {'value': 'x', 'provenance': 'guessed'}};
      final briefPath = '${tmp.path}/out2/brief.md';
      final registryPath = '${tmp.path}/out2/registry.json';
      final res =
          engine.emit(bad, briefOut: briefPath, registryOut: registryPath);
      expect(res.ok, isFalse);
      expect(res.errors, isNotEmpty);
      expect(File(briefPath).existsSync(), isFalse);
      expect(File(registryPath).existsSync(), isFalse);
      expect(Directory('${tmp.path}/out2').existsSync(), isFalse);
    });

    test('seed derives the registry from a hand-written brief', () {
      final briefPath = '${tmp.path}/brief.md';
      File(briefPath).writeAsStringSync(handwrittenBrief);
      final registryPath = '${tmp.path}/out/registry.json';
      final res = engine.seed(briefPath, registryOut: registryPath);
      expect(res.registry.length, 2);
      expect(File(registryPath).readAsStringSync(), expectedSeed);
    });
  });

  group('validate — new field groups', () {
    Map<String, dynamic> withNewFields() {
      final a = goodAnswers();
      a['locales'] = {'value': ['en', 'pl'], 'provenance': 'client'};
      a['direction'] = {
        'value': {'adjectives': ['calm'], 'avoids': ['noisy']},
        'provenance': 'client',
      };
      a['contentAnchors'] = {'value': ['Q3 roadmap'], 'provenance': 'client'};
      return a;
    }

    test('direction/contentAnchors/locales validate when well-formed', () {
      expect(validateIntake(withNewFields()).errors, isEmpty);
    });

    test('direction value that is not an object is rejected and named', () {
      final bad = withNewFields()
        ..['direction'] = {'value': 'minimal', 'provenance': 'client'};
      final errs = validateIntake(bad).errors;
      expect(errs.any((e) => e.contains('direction')), isTrue);
    });

    test('direction.adjectives that is not a string list is rejected and named', () {
      final bad = withNewFields()
        ..['direction'] = {
          'value': {'adjectives': [1, 2]},
          'provenance': 'client',
        };
      final errs = validateIntake(bad).errors;
      expect(
          errs.any((e) => e.contains('direction') && e.contains('adjectives')),
          isTrue);
    });

    test('locales that is not a string list is rejected and named', () {
      final bad = withNewFields()
        ..['locales'] = {'value': 'en', 'provenance': 'client'};
      expect(validateIntake(bad).errors.any((e) => e.contains('locales')), isTrue);
    });

    test('contentAnchors that is not a string list is rejected and named', () {
      final bad = withNewFields()
        ..['contentAnchors'] = {'value': 'roadmap', 'provenance': 'client'};
      expect(validateIntake(bad).errors.any((e) => e.contains('contentAnchors')),
          isTrue);
    });

    test('surface states that is not a string list is rejected and named', () {
      final bad = goodAnswers();
      ((bad['surfaces'] as List)[0] as Map)['states'] = 'empty';
      final errs = validateIntake(bad).errors;
      expect(errs.any((e) => e.contains('surfaces[0]') && e.contains('states')),
          isTrue);
    });
  });

  group('states — validate → registry → brief round-trip', () {
    Map<String, dynamic> withStates() {
      final a = goodAnswers();
      // Replace the surfaces wholesale — the fixture's literal maps are
      // reified Map<String, String> and reject a List value on mutation.
      a['surfaces'] = [
        {
          'id': 'projects.home',
          'label': 'Home',
          'shell': 'projects',
          'states': ['empty', 'loading'],
          'provenance': 'client',
        },
        // Slice 3: this row carries the additive-only assertion, so it must be
        // a surface with NO shape signal — "credits" is neither a collection
        // nor a form, so nothing is derived and no key appears.
        {
          'id': 'projects.credits',
          'label': 'Credits',
          'shell': 'projects',
          'provenance': 'client',
        },
      ];
      return a;
    }

    test('states validate and land in the registry as an additive key', () {
      final a = withStates();
      expect(validateIntake(a).errors, isEmpty);
      final reg = emitRegistry(a);
      expect(reg[0]['states'], ['empty', 'loading']);
      // DECLARED states are stamped with the surface's own provenance, never
      // with 'inferred' — that stamp is reserved for what intake derived.
      expect(reg[0]['statesProvenance'], 'client');
      expect(reg[0].keys.toList(), [
        'id', 'label', 'shell', 'comp', 'route', 'surface', 'states',
        'statesProvenance',
      ]);
      // no declared states AND no shape signal -> no key at all (additive only)
      expect(reg[1].containsKey('states'), isFalse);
      expect(reg[1].containsKey('statesProvenance'), isFalse);
    });

    test('the brief surface table carries the states column', () {
      final brief = emitBrief(withStates());
      expect(brief.contains('| id | shell | comp | label | states | surface |'),
          isTrue);
      expect(
          brief.contains(
              '| `projects.home` | projects | ProjectsHome | Home | empty, loading | _null_ |'),
          isTrue);
    });

    test('seedFromBrief passes a states column through as sibling metadata', () {
      const tbl =
          '| id | label | states |\n|---|---|---|\n| `shop.cart` | Cart | empty, loading |\n';
      final s = seedFromBrief(tbl);
      expect(s[0]['states'], 'empty, loading');
      expect(s[0]['surface'], null);
    });
  });

  group('defaultRegistryOut — mirrors the gate resolver', () {
    late Directory tmp;
    late Directory prevDir;

    setUp(() {
      // resolveSymbolicLinksSync: Directory.current is symlink-resolved on
      // macOS (/var -> /private/var), so compare resolved paths.
      tmp = Directory(Directory.systemTemp
          .createTempSync('appbox_registry_out')
          .resolveSymbolicLinksSync());
      prevDir = Directory.current;
      File('${tmp.path}/config/appbox.config.json').createSync(recursive: true);
      Directory.current = tmp;
    });
    tearDown(() {
      Directory.current = prevDir;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('no design root -> docs/intake/registry.json fallback', () {
      expect(defaultRegistryOut(), '${tmp.path}/docs/intake/registry.json');
    });

    test('design root without structure.json -> models/screens_model default', () {
      Directory('${tmp.path}/designs/appbox-studio').createSync(recursive: true);
      expect(defaultRegistryOut(),
          '${tmp.path}/designs/appbox-studio/models/screens_model/registry.json');
    });

    test('structure.json "registry" field wins', () {
      Directory('${tmp.path}/designs/appbox-studio').createSync(recursive: true);
      File('${tmp.path}/designs/appbox-studio/structure.json')
          .writeAsStringSync('{"registry": "custom/reg.json"}');
      expect(defaultRegistryOut(),
          '${tmp.path}/designs/appbox-studio/custom/reg.json');
    });
  });

  group('intakeMain — exit codes', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('appbox_intake_cli'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('validate good -> 0', () {
      final p = '${tmp.path}/answers.json';
      File(p).writeAsStringSync(jsonEncode(goodAnswers()));
      expect(intakeMain(['validate', p]), 0);
    });

    test('validate bad -> 1', () {
      final p = '${tmp.path}/bad.json';
      File(p).writeAsStringSync(
          jsonEncode({'product': {'value': 'x', 'provenance': 'guessed'}}));
      expect(intakeMain(['validate', p]), 1);
    });

    test('emit good -> 0 and writes both artefacts', () {
      final p = '${tmp.path}/answers.json';
      File(p).writeAsStringSync(jsonEncode(goodAnswers()));
      final briefPath = '${tmp.path}/out/brief.md';
      final registryPath = '${tmp.path}/out/registry.json';
      expect(
          intakeMain([
            'emit', '--answers', p,
            '--brief-out', briefPath,
            '--registry-out', registryPath,
          ]),
          0);
      expect(File(briefPath).readAsStringSync(), expectedBrief);
      expect(File(registryPath).readAsStringSync(), expectedRegistry);
    });

    test('emit bad -> 1 and writes nothing', () {
      final p = '${tmp.path}/bad.json';
      File(p).writeAsStringSync(
          jsonEncode({'product': {'value': 'x', 'provenance': 'guessed'}}));
      final briefPath = '${tmp.path}/out2/brief.md';
      final registryPath = '${tmp.path}/out2/registry.json';
      expect(
          intakeMain([
            'emit', '--answers', p,
            '--brief-out', briefPath,
            '--registry-out', registryPath,
          ]),
          1);
      expect(Directory('${tmp.path}/out2').existsSync(), isFalse);
    });

    test('seed -> 0 and writes the registry', () {
      final briefPath = '${tmp.path}/brief.md';
      File(briefPath).writeAsStringSync(handwrittenBrief);
      final registryPath = '${tmp.path}/out/registry.json';
      expect(
          intakeMain(['seed', '--brief', briefPath, '--registry-out', registryPath]),
          0);
      expect(File(registryPath).readAsStringSync(), expectedSeed);
    });

    test('no subcommand -> 2', () {
      expect(intakeMain([]), 2);
    });

    test('unknown subcommand -> 2', () {
      expect(intakeMain(['bogus']), 2);
    });

    test('emit without --answers -> 2', () {
      expect(intakeMain(['emit']), 2);
    });

    test('--self-test -> 0', () {
      expect(intakeMain(['--self-test']), 0);
    });
  });

  // ------------------------------------------------- Slice 3: the two axes
  //
  // `states` is screen-level and CLOSED (loading|empty|error). `feedback` is
  // EDGE-level, because a toast is a consequence of a transition, not a way a
  // screen can look. Mirrors kit/state vs kit/ui_library.

  group('states — closed vocabulary (D2)', () {
    Map<String, dynamic> withSurfaceStates(List<String> states) {
      final a = goodAnswers();
      a['surfaces'] = [
        {
          'id': 'projects.home',
          'label': 'Home',
          'shell': 'projects',
          'states': states,
          'provenance': 'client',
        },
      ];
      return a;
    }

    test('every in-vocabulary state passes (portalo declares only these)', () {
      expect(validateIntake(withSurfaceStates(surfaceStates)).errors, isEmpty);
    });

    test('an out-of-vocabulary state is rejected and the message names the '
        'allowed set', () {
      final errs = validateIntake(withSurfaceStates(['loading', 'skeleton'])).errors;
      expect(errs.any((e) => e.contains('surfaces[0]') && e.contains('skeleton')),
          isTrue,
          reason: 'the offending value must be named');
      expect(
          errs.any((e) =>
              e.contains('loading') && e.contains('empty') && e.contains('error')),
          isTrue,
          reason: 'the message must carry the fix — the whole allowed set');
    });

    test('a non-string states list is still rejected', () {
      final a = goodAnswers();
      ((a['surfaces'] as List)[0] as Map)['states'] = 'empty';
      expect(
          validateIntake(a).errors.any(
              (e) => e.contains('surfaces[0]') && e.contains('states')),
          isTrue);
    });
  });

  group('states — derivation is marked and confirmable (D3)', () {
    Map<String, dynamic> surfacesOnly(List<Map<String, dynamic>> surfaces) {
      final a = goodAnswers();
      a['surfaces'] = surfaces;
      return a;
    }

    test('a collection surface with no declared states emits [loading, empty] '
        "stamped statesProvenance 'inferred'", () {
      final reg = emitRegistry(surfacesOnly([
        {
          'id': 'projects.list',
          'label': 'All projects',
          'shell': 'projects',
          'provenance': 'client',
        },
      ]));
      expect(reg[0]['states'], ['loading', 'empty']);
      expect(reg[0]['statesProvenance'], 'inferred');
    });

    test('a form/auth surface with no declared states adds error', () {
      final reg = emitRegistry(surfacesOnly([
        {
          'id': 'account.login',
          'label': 'Sign in',
          'shell': 'account',
          'provenance': 'client',
        },
      ]));
      expect(reg[0]['states'], ['error']);
      expect(reg[0]['statesProvenance'], 'inferred');
    });

    test('requiresAuth alone marks a surface as network-shaped (adds error)', () {
      final reg = emitRegistry(surfacesOnly([
        {
          'id': 'billing.overview',
          'label': 'Overview',
          'shell': 'billing',
          'requiresAuth': true,
          'provenance': 'client',
        },
      ]));
      expect(reg[0]['states'], ['error']);
      expect(reg[0]['statesProvenance'], 'inferred');
    });

    test('a surface that is both collection- and form-shaped emits all three '
        'in vocabulary order', () {
      final reg = emitRegistry(surfacesOnly([
        {
          'id': 'shop.checkout',
          'label': 'Checkout',
          'shell': 'shop',
          'requiresAuth': true,
          'provenance': 'client',
        },
      ]));
      expect(reg[0]['states'], ['error']);
      // A single id short segment is one token (`_idRe` forbids separators),
      // so "both buckets" is reachable only as collection-word + requiresAuth.
      final reg2 = emitRegistry(surfacesOnly([
        {
          'id': 'orders.history',
          'label': 'Order history',
          'shell': 'orders',
          'requiresAuth': true,
          'provenance': 'client',
        },
      ]));
      expect(reg2[0]['states'], ['loading', 'empty', 'error']);
    });

    test('DECLARED states are never overwritten and keep the surface provenance',
        () {
      final reg = emitRegistry(surfacesOnly([
        {
          'id': 'projects.list',
          'label': 'All projects',
          'shell': 'projects',
          // a collection surface: the heuristic WOULD say [loading, empty]
          'states': ['error'],
          'provenance': 'founder',
        },
      ]));
      expect(reg[0]['states'], ['error'], reason: 'the client declared this');
      expect(reg[0]['statesProvenance'], 'founder');
    });

    test('a surface with no shape signal gets no states key at all '
        '(additive only)', () {
      final reg = emitRegistry(surfacesOnly([
        {
          'id': 'about.credits',
          'label': 'Credits',
          'shell': 'about',
          'provenance': 'client',
        },
      ]));
      expect(reg[0].containsKey('states'), isFalse);
      expect(reg[0].containsKey('statesProvenance'), isFalse);
    });

    test('derivation is deterministic across runs', () {
      final a = surfacesOnly([
        {
          'id': 'projects.list',
          'label': 'All',
          'shell': 'projects',
          'provenance': 'client',
        },
        {
          'id': 'account.login',
          'label': 'Sign in',
          'shell': 'account',
          'provenance': 'client',
        },
      ]);
      expect(jsonEncode(emitRegistry(a)), jsonEncode(emitRegistry(a)));
    });
  });

  group('feedback — an edge key, never a screen key (D2)', () {
    Map<String, dynamic> withEdge(Map<String, dynamic> extra) {
      final a = goodAnswers();
      a['flows'] = [
        {
          'id': 'flow-main',
          'name': 'Main',
          'provenance': 'client',
          'edges': [
            {
              'from': 'projects.home',
              'to': 'projects.new',
              'trigger': 'Save project',
              ...extra,
            },
          ],
        },
      ];
      return a;
    }

    test('a well-formed feedback passes', () {
      final a = withEdge({
        'feedback': {'kind': 'success', 'text': 'Project saved'},
      });
      expect(validateIntake(a).errors, isEmpty);
    });

    test('a feedback.kind outside the enum is rejected and names the set', () {
      final errs = validateIntake(withEdge({
        'feedback': {'kind': 'warning', 'text': 'Careful'},
      })).errors;
      expect(errs.any((e) => e.contains('warning')), isTrue);
      expect(
          errs.any((e) =>
              e.contains('success') && e.contains('error') && e.contains('info')),
          isTrue,
          reason: 'the message must name the allowed kinds');
    });

    test('a feedback with an empty or non-string text is rejected', () {
      expect(
          validateIntake(withEdge({
            'feedback': {'kind': 'success', 'text': ''},
          })).errors.any((e) => e.contains('text')),
          isTrue);
      expect(
          validateIntake(withEdge({
            'feedback': {'kind': 'success', 'text': 42},
          })).errors.any((e) => e.contains('text')),
          isTrue);
    });

    test('an unknown edge key is rejected and names the allowed set', () {
      // The closed set is the GATE that makes the spread safe: emitFlows now
      // carries every authored key through, so a typo'd key would otherwise
      // ride along into flows.json and be silently honoured by nobody.
      final errs = validateIntake(withEdge({'elment': 'button:Continue'})).errors;
      expect(errs.any((e) => e.contains('elment')), isTrue,
          reason: 'the typo must be named');
      expect(
          errs.any((e) =>
              e.contains('element') && e.contains('trigger') && e.contains('feedback')),
          isTrue,
          reason: 'the message must carry the fix — the whole allowed set');
    });

    test('an unknown key INSIDE feedback is rejected', () {
      // The schema closes feedback to {kind, text, inferred}; the Dart
      // validator is what actually enforces it. The two must agree or the
      // schema is decoration.
      final errs = validateIntake(withEdge({
        'feedback': {'kind': 'success', 'text': 'Saved', 'icon': 'check'},
      })).errors;
      expect(errs.any((e) => e.contains('icon')), isTrue);
    });

    test('an unknown FLOW key is rejected', () {
      final a = withEdge(const {});
      (a['flows'] as List)[0]['persona'] = 'shopper';
      expect(
          validateIntake(a)
              .errors
              .any((e) => e.contains('flows[0]') && e.contains('persona')),
          isTrue);
    });

    test('a non-string element is rejected at intake, not downstream', () {
      // emitFlows now EMITS element, so intake must type-check it. Without
      // this the bad value reaches flows.json and only emit_structure fails,
      // naming a file the author never edited.
      final errs = validateIntake(withEdge({'element': 42})).errors;
      expect(errs.any((e) => e.contains('element')), isTrue);
    });

    test('a feedback that is not an object is rejected', () {
      expect(
          validateIntake(withEdge({'feedback': 'Saved!'}))
              .errors
              .any((e) => e.contains('feedback')),
          isTrue);
    });

    test('feedback on a SURFACE is rejected — a toast is not a screen state', () {
      final a = goodAnswers();
      // Replace the surfaces wholesale — the fixture's literal maps are
      // reified Map<String, String> and reject a Map value on mutation.
      a['surfaces'] = [
        {
          'id': 'projects.home',
          'label': 'Home',
          'shell': 'projects',
          'provenance': 'client',
          'feedback': {'kind': 'success', 'text': 'Saved'},
        },
      ];
      final errs = validateIntake(a).errors;
      expect(errs.any((e) => e.contains('surfaces[0]') && e.contains('feedback')),
          isTrue);
      expect(errs.any((e) => e.contains('edge')), isTrue,
          reason: 'the message must say where feedback DOES belong');
    });

    test('feedback on a FLOW (not an edge) is rejected', () {
      final a = withEdge(const {});
      (a['flows'] as List)[0]['feedback'] = {'kind': 'info', 'text': 'Done'};
      expect(
          validateIntake(a)
              .errors
              .any((e) => e.contains('flows[0]') && e.contains('feedback')),
          isTrue);
    });
  });

  group('feedback — derived on mutation edges, stamped inferred (D3)', () {
    Map<String, dynamic> withFlow(List<Map<String, dynamic>> edges) {
      final a = goodAnswers();
      a['flows'] = [
        {
          'id': 'flow-main',
          'name': 'Main',
          'provenance': 'client',
          'edges': edges,
        },
      ];
      return a;
    }

    test('a mutation edge gets a derived feedback stamped inferred', () {
      final flows = emitFlows(withFlow([
        {'from': 'projects.home', 'to': 'projects.new', 'trigger': 'Save project'},
      ]));
      final fb = flows[0]['edges'][0]['feedback'] as Map;
      expect(fb['kind'], 'success');
      expect(fb['text'], 'Save project',
          reason: 'text is a mechanical transform of the trigger, never invented '
              'copy — §22');
      expect(fb['inferred'], isTrue);
    });

    test('a non-mutation edge gets NO feedback', () {
      final flows = emitFlows(withFlow([
        {'from': 'projects.home', 'to': 'projects.new', 'trigger': 'Category tile'},
      ]));
      expect((flows[0]['edges'][0] as Map).containsKey('feedback'), isFalse);
    });

    test('an authored element survives emitFlows verbatim', () {
      // `element` is the EXACT join from a flow edge to a `data-el` on the
      // surface. flowwalk.js matches it exactly and falls back to a FUZZY
      // trigger match without it, and the drawer's Logic tab resolves each
      // widget's wiring through it. Dropping it on re-emit degrades
      // an exact join to a guess, silently.
      final flows = emitFlows(withFlow([
        {
          'from': 'projects.home',
          'to': 'projects.new',
          'trigger': 'continue',
          'element': 'button:Continue',
        },
      ]));
      expect(flows[0]['edges'][0]['element'], 'button:Continue');
    });

    test('an absent element stays absent — no invented empty string', () {
      final flows = emitFlows(withFlow([
        {'from': 'projects.home', 'to': 'projects.new', 'trigger': 'continue'},
      ]));
      expect((flows[0]['edges'][0] as Map).containsKey('element'), isFalse);
    });

    test('every key the validator accepts on an edge survives emitFlows', () {
      // Regression net for the WHOLE passthrough, not just today's gap:
      // `element` and `feedback` were each found by accident. This fails the
      // moment a new authorable edge key is added without being carried.
      final flows = emitFlows(withFlow([
        {
          'from': 'projects.home',
          'to': 'projects.new',
          'trigger': 'continue',
          'action': 'replace',
          'element': 'button:Continue',
          'feedback': {'kind': 'info', 'text': 'On your way'},
        },
      ]));
      final edge = flows[0]['edges'][0] as Map;
      expect(edge['from'], 'projects.home');
      expect(edge['to'], 'projects.new');
      expect(edge['trigger'], 'continue');
      expect(edge['action'], 'replace');
      expect(edge['element'], 'button:Continue');
      expect(edge['feedback'], {'kind': 'info', 'text': 'On your way'});
    });

    test('a DECLARED feedback passes through unstamped and unmodified', () {
      final flows = emitFlows(withFlow([
        {
          'from': 'projects.home',
          'to': 'projects.new',
          'trigger': 'Save project',
          'feedback': {'kind': 'info', 'text': 'Queued for review'},
        },
      ]));
      final fb = flows[0]['edges'][0]['feedback'] as Map;
      expect(fb['kind'], 'info');
      expect(fb['text'], 'Queued for review');
      expect(fb.containsKey('inferred'), isFalse);
    });

    test('feedback derivation is deterministic across runs', () {
      final a = withFlow([
        {'from': 'projects.home', 'to': 'projects.new', 'trigger': 'Add to bag'},
      ]);
      expect(jsonEncode(emitFlows(a)), jsonEncode(emitFlows(a)));
    });
  });

  group('brief — derived states and feedback are visibly marked', () {
    test('a derived states cell carries the [inferred] mark', () {
      final a = goodAnswers();
      a['surfaces'] = [
        {
          'id': 'projects.list',
          'label': 'All',
          'shell': 'projects',
          'provenance': 'client',
        },
      ];
      final brief = emitBrief(a);
      expect(brief.contains('loading, empty [inferred]'), isTrue,
          reason: 'the confirm step needs something to confirm');
    });

    test('a DECLARED states cell carries no mark', () {
      final a = goodAnswers();
      a['surfaces'] = [
        {
          'id': 'projects.list',
          'label': 'All',
          'shell': 'projects',
          'states': ['empty'],
          'provenance': 'client',
        },
      ];
      final brief = emitBrief(a);
      expect(brief.contains('| empty |'), isTrue);
      expect(brief.contains('empty [inferred]'), isFalse);
    });

    test('no declared flows -> no phantom feedback section', () {
      // _feedbackSection runs over emitFlows, which DERIVES a draft flow per
      // shell when none is declared. Those derived edges carry trigger
      // 'continue' — no mutation — so nothing may be reported. Three surfaces
      // in one shell, so emitFlows really does emit a derived flow.
      final a = goodAnswers();
      a['surfaces'] = [
        {'id': 'shop.home', 'label': 'Home', 'shell': 'shop', 'provenance': 'client'},
        {'id': 'shop.cart', 'label': 'Cart', 'shell': 'shop', 'provenance': 'client'},
        {'id': 'shop.pay', 'label': 'Pay', 'shell': 'shop', 'provenance': 'client'},
      ];
      expect(emitFlows(a), hasLength(1),
          reason: 'the fixture must actually exercise the derived-flow path');
      final brief = emitBrief(a);
      expect(brief.contains('Transition feedback'), isFalse,
          reason: 'deriving a toast on top of an already-derived edge would be '
              'inventing on top of inventing');
    });

    test('a derived edge feedback is listed and marked', () {
      final a = goodAnswers();
      a['flows'] = [
        {
          'id': 'flow-main',
          'name': 'Main',
          'provenance': 'client',
          'edges': [
            {
              'from': 'projects.home',
              'to': 'projects.new',
              'trigger': 'Save project',
            },
          ],
        },
      ];
      final brief = emitBrief(a);
      expect(brief.contains('Save project'), isTrue);
      expect(brief.contains('[inferred]'), isTrue);
    });
  });

  // Every closed Dart set above has a twin in intake.schema.json, and NOTHING
  // loads that schema at runtime — so when the two drift, the drift is
  // invisible. This group is the only thing in the repo that reads both and
  // compares them. It is deliberately mechanical: a new closed set gets a new
  // case here, or it drifts silently like `states` did.
  group('contract pairs — schema vs the Dart closed sets', () {
    final schema = jsonDecode(File(_schemaPath()).readAsStringSync()) as Map<String, dynamic>;
    Map<String, dynamic> def(String name) =>
        (schema['definitions'] as Map)[name] as Map<String, dynamic>;
    Map<String, dynamic> props(Map<String, dynamic> node) =>
        (node['properties'] as Map).cast<String, dynamic>();

    final edge = def('edge');
    final feedback = props(edge)['feedback'] as Map<String, dynamic>;

    test('surfaceStates == surface.states.items.enum, in order', () {
      // Ordered, not a set: [surfaceStates]'s doc comment makes emission order
      // load-bearing (deriveStates emits in this order).
      final states = props(def('surface'))['states'] as Map<String, dynamic>;
      expect((states['items'] as Map)['enum'], surfaceStates,
          reason: 'the schema leaves `states` an open string list while Dart '
              'closes it — the drift this pair exists to catch');
    });

    test('feedbackKinds == feedback.kind.enum', () {
      expect(((props(feedback)['kind'] as Map)['enum'] as List).toSet(), feedbackKinds.toSet());
    });

    test('feedbackKeys == the feedback object\'s properties', () {
      expect(props(feedback).keys.toSet(), feedbackKeys.toSet());
      expect(feedback['additionalProperties'], isFalse,
          reason: 'a listed property set only closes the object when '
              'additionalProperties is false');
    });

    test('edgeKeys == the edge object\'s properties', () {
      expect(props(edge).keys.toSet(), edgeKeys.toSet());
      expect(edge['additionalProperties'], isFalse);
    });

    test('feedbackActionKeys == the feedback.action object\'s properties', () {
      final action = props(feedback)['action'] as Map<String, dynamic>;
      expect(props(action).keys.toSet(), feedbackActionKeys.toSet());
      expect(action['additionalProperties'], isFalse);
    });
  });

  // D18: a snackbar's action is its defining feature, so `feedback` carries an
  // optional one. Declared feedback wins outright — `_edgeFeedback` only fires
  // when NOTHING is declared — so the action must survive emit untouched.
  group('feedback.action — optional, elicited, survives emit (D18)', () {
    Map<String, dynamic> withFeedback(Object fb) {
      final a = goodAnswers();
      a['flows'] = [
        <String, dynamic>{
          'id': 'flow-main',
          'name': 'Main',
          'provenance': 'client',
          'edges': [
            <String, dynamic>{
              'from': 'projects.home',
              'to': 'projects.new',
              'trigger': 'Open new',
              'feedback': fb,
            },
          ],
        },
      ];
      return a;
    }

    test('an absent action stays absent — existing data is still valid', () {
      final a = withFeedback({'kind': 'success', 'text': 'Saved'});
      expect(validateIntake(a).errors, isEmpty);
      final fb = emitFlows(a)[0]['edges'][0]['feedback'] as Map;
      expect(fb.containsKey('action'), isFalse);
    });

    test('a declared error+action survives emitFlows verbatim', () {
      // The Retry case: `error` is CORE snackbar material, not a kind to
      // narrow away, and Retry is exactly why `action` had to exist.
      const fb = {
        'kind': 'error',
        'text': 'Upload failed',
        'action': {'label': 'Retry', 'trigger': 'Retry the upload'},
      };
      final a = withFeedback(fb);
      expect(validateIntake(a).errors, isEmpty);
      expect(emitFlows(a)[0]['edges'][0]['feedback'], fb,
          reason: 'a declared feedback passes through untouched, action and all');
    });

    test('a declared feedback still suppresses derivation', () {
      // `Save` is a mutation word: with nothing declared this edge would get a
      // derived toast. Declaring one — action included — must silence that.
      const fb = {
        'kind': 'info',
        'text': 'Queued',
        'action': {'label': 'View', 'trigger': 'Open the queue'},
      };
      final a = withFeedback(fb);
      (a['flows'] as List)[0]['edges'][0]['trigger'] = 'Save project';
      final emitted = emitFlows(a)[0]['edges'][0]['feedback'] as Map;
      expect(emitted, fb);
      expect(emitted.containsKey('inferred'), isFalse,
          reason: '_edgeFeedback must not fire over a declared feedback');
    });

    test('a malformed action is rejected and names the closed key set', () {
      for (final bad in [
        'Retry',
        {'label': 'Retry'},
        {'label': 'Retry', 'trigger': ''},
        {'label': 'Retry', 'trigger': 'again', 'icon': 'refresh'},
      ]) {
        final errs = validateIntake(withFeedback({
          'kind': 'error',
          'text': 'Upload failed',
          'action': bad,
        })).errors;
        expect(errs.any((e) => e.contains('feedback.action')), isTrue,
            reason: 'must be rejected and say where: $bad');
      }
    });

    test('an action on a SURFACE state is still not a thing', () {
      // feedback lives on the edge; adding `action` changes nothing about that.
      final a = goodAnswers();
      a['surfaces'] = [
        <String, dynamic>{
          'id': 'projects.home',
          'label': 'Home',
          'shell': 'projects',
          'provenance': 'client',
          'feedback': {
            'kind': 'error',
            'text': 'Failed',
            'action': {'label': 'Retry', 'trigger': 'again'},
          },
        },
      ];
      expect(validateIntake(a).errors.any((e) => e.contains('surfaces[0]')), isTrue);
    });
  });

  // D2 site 7: answers.json is the flows SSOT. confirmFlow writing only
  // flows.json means the next emit regenerates from answers and REVERTS the
  // confirmation — so it must dual-write.
  group('confirmFlow — dual-writes answers.json (D2 site 7)', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('appbox-intake-confirm-');
      appboxHomeOverride = tmp.path;
    });
    tearDown(() {
      appboxHomeOverride = null;
      tmp.deleteSync(recursive: true);
    });

    const project = 'confirmfixture';
    const engine = IntakeEngine();

    List<dynamic> readJson(String file) =>
        jsonDecode(File('${shellDir(project, 'intake')}/$file').readAsStringSync()) as List;

    Map<String, dynamic> readAnswers() =>
        jsonDecode(File('${shellDir(project, 'intake')}/answers.json').readAsStringSync())
            as Map<String, dynamic>;

    test('a confirmed DERIVED flow survives the next re-emit', () {
      // goodAnswers declares no flows, so emit derives `flow-projects`
      // provenance inferred — exactly what the confirm step is for.
      expect(engine.emit(goodAnswers(), project: project).ok, isTrue);
      expect(readJson('flows.json')[0]['provenance'], 'inferred');

      expect(engine.confirmFlow(project, 'flow-projects', 'client'), isNull);

      final answers = readAnswers();
      expect(validateIntake(answers).errors, isEmpty,
          reason: 'a dual-write that writes INVALID answers is worse than the '
              'revert it fixes — the next emit would write nothing at all');
      expect(emitFlows(answers), readJson('flows.json'),
          reason: 'answers.json is the SSOT: re-emitting it must reproduce the '
              'flows.json confirmFlow just wrote, not revert to inferred');
      expect(engine.emit(answers, project: project).ok, isTrue);
      expect(readJson('flows.json')[0]['provenance'], 'client',
          reason: 'the confirmation must not be undone by a plain re-emit');
    });

    test('a confirmed DECLARED flow keeps its edges, feedback and all', () {
      final a = goodAnswers();
      a['flows'] = [
        {
          'id': 'flow-main',
          'name': 'Main',
          'provenance': 'inferred',
          'edges': [
            {
              'from': 'projects.home',
              'to': 'projects.new',
              'trigger': 'Save project',
              'feedback': {
                'kind': 'error',
                'text': 'Save failed',
                'action': {'label': 'Retry', 'trigger': 'Save project'},
              },
            },
          ],
        },
      ];
      expect(engine.emit(a, project: project).ok, isTrue);
      expect(engine.confirmFlow(project, 'flow-main', 'founder'), isNull);

      final answers = readAnswers();
      expect(validateIntake(answers).errors, isEmpty);
      expect(emitFlows(answers), readJson('flows.json'));
      expect(
        (answers['flows'] as List)[0]['edges'][0]['feedback']['action'],
        {'label': 'Retry', 'trigger': 'Save project'},
        reason: 'the dual-write persists the flow, it does not rewrite it',
      );
    });

    test('an unknown flow id changes neither file', () {
      expect(engine.emit(goodAnswers(), project: project).ok, isTrue);
      final before = readAnswers();
      expect(engine.confirmFlow(project, 'flow-nope', 'client'), isNotNull);
      expect(readAnswers(), before);
      expect(readJson('flows.json')[0]['provenance'], 'inferred');
    });
  });
}

/// mergeRegistry — a re-emit must not delete what emit does not own.
///
/// Regression guard for a REAL data loss: `intake emit` regenerated portalo's
/// registry.json and dropped `kits` from all 10 entries. `kits` appears nowhere
/// in answers.json and nowhere in emitRegistry, so it lived only in the
/// generated file and nothing could restore it. gate_intake's repair message
/// tells users to run that exact command, so the tool's own advice destroyed
/// data.
void _mergeRegistryTests() {
  group('mergeRegistry — foreign keys survive a re-emit', () {
    late Directory tmp;
    late String path;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('appbox_merge_reg');
      path = '${tmp.path}/registry.json';
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('carries kits forward per id', () {
      File(path).writeAsStringSync(jsonEncode([
        {'id': 'p.auth', 'label': 'stale', 'kits': ['auth']},
        {'id': 'p.home', 'label': 'stale', 'kits': ['data', 'media']},
      ]));
      final merged = mergeRegistry([
        {'id': 'p.auth', 'label': 'Sign In', 'states': ['error']},
        {'id': 'p.home', 'label': 'Home', 'states': <String>[]},
      ], path);
      expect(merged[0]['kits'], ['auth']);
      expect(merged[1]['kits'], ['data', 'media']);
    });

    test("emit's OWN keys always win over the stale file", () {
      File(path).writeAsStringSync(jsonEncode([
        {'id': 'p.auth', 'label': 'stale', 'states': ['loading'], 'kits': ['auth']},
      ]));
      final merged = mergeRegistry([
        {'id': 'p.auth', 'label': 'Sign In', 'states': ['error']},
      ], path);
      expect(merged[0]['label'], 'Sign In', reason: 'emit owns label');
      expect(merged[0]['states'], ['error'], reason: 'emit owns states');
      expect(merged[0]['kits'], ['auth'], reason: 'but not kits');
    });

    test('an id absent from the old file gains nothing', () {
      File(path).writeAsStringSync(jsonEncode([
        {'id': 'p.gone', 'kits': ['ghost']},
      ]));
      final merged = mergeRegistry([
        {'id': 'p.new', 'label': 'New'},
      ], path);
      expect(merged.single.containsKey('kits'), isFalse);
    });

    test('no file, or a corrupt one, returns the pure result unchanged', () {
      final pure = [
        {'id': 'p.auth', 'label': 'Sign In'}
      ];
      expect(mergeRegistry(pure, '${tmp.path}/does-not-exist.json'), pure);
      File(path).writeAsStringSync('{ not json');
      expect(mergeRegistry(pure, path), pure,
          reason: 'a mangled registry must never block a re-emit');
      File(path).writeAsStringSync(jsonEncode({'not': 'a list'}));
      expect(mergeRegistry(pure, path), pure);
    });
  });

  // F1 — client strings are neutralized before they land in generated
  // markdown. The brief is consumed downstream (designer, story-map chain,
  // gate parse); raw script tags, links, emphasis, pipes and newlines from
  // an elicited value must never reach the artifact as active markup.
  group('brief — client-string safety (markdown injection neutralized)', () {
    test('script/link/bold/pipe/newline payloads do not survive raw', () {
      final a = goodAnswers();
      a['product'] = {
        'value': 'Demo <script>alert(1)</script>',
        'provenance': 'client',
      };
      a['contentAnchors'] = {
        'value': [
          '[click](https://evil.example)',
          'bold **injection** | pipe',
          'line1\nline2',
        ],
        'provenance': 'client',
      };
      ((a['surfaces'] as List)[0] as Map)['label'] =
          'Home <b>raw</b> [l](javascript:alert(2))';
      final brief = emitBrief(a);
      expect(brief.contains('<script>'), isFalse);
      expect(brief.contains('<b>'), isFalse);
      expect(brief.contains('[click](https://evil.example)'), isFalse);
      expect(brief.contains('[l](javascript:'), isFalse);
      expect(brief.contains('**injection**'), isFalse);
      expect(brief.contains('line1\nline2'), isFalse);
      // the payload is still VISIBLE (escaped), never silently dropped —
      // intake elicits verbatim, it just refuses to emit active markup
      expect(brief.contains('&lt;script&gt;'), isTrue);
      expect(brief.contains('\\[click\\]'), isTrue);
    });

    test('benign values render byte-identically (escape is a no-op)', () {
      expect(emitBrief(goodAnswers()), expectedBrief);
    });
  });

  // F2 — intake emit with neither --project nor --brief-out used to
  // silently overwrite repoRoot/docs/design/brief.md, a TRACKED file when
  // run inside any appbox repo. It must refuse instead.
  group('emit — no silent default-path write (F2)', () {
    test('no project and no brief-out refuses with an actionable error', () {
      final res = const IntakeEngine().emit(goodAnswers());
      expect(res.ok, isFalse);
      expect(res.errors, isNotEmpty);
      expect(res.errors.first, contains('--project'));
      expect(res.errors.first, contains('--brief-out'));
      expect(res.errors.first, contains('refus'), reason: 'say why');
    });

    test('explicit --brief-out still works (opt-in, not banned)', () async {
      final dir = await Directory.systemTemp.createTemp('f2_out_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final res = const IntakeEngine().emit(goodAnswers(),
          briefOut: '${dir.path}/brief.md',
          registryOut: '${dir.path}/registry.json');
      expect(res.ok, isTrue);
      expect(File('${dir.path}/brief.md').existsSync(), isTrue);
    });
  });

  // F6 — a missing surfaces key reported as "must be a list" pointed the
  // author at a type error that did not exist. Absent means "none named at
  // intake" (the designer authors the registry); only a PRESENT non-list is
  // a type defect.
  group('validate — surfaces absent vs mistyped wording (F6)', () {
    test('absent surfaces is legal: designer authors the registry', () {
      final a = goodAnswers()..remove('surfaces');
      expect(validateIntake(a).errors, isEmpty);
      expect(emitBrief(a).contains('No surfaces named at intake'), isTrue);
    });

    test('present-but-not-a-list names the actual type', () {
      final a = goodAnswers()..['surfaces'] = 'home, settings';
      final errs = validateIntake(a).errors;
      expect(errs, hasLength(1));
      expect(errs.single, contains('must be a list of surface objects'));
      expect(errs.single, contains('str'));
    });
  });
}

/// The published schema, found from wherever `dart test` was invoked. Mirrors
/// `_skillDir()` in design_selftest_test.dart: walk up to the repo root marker.
String _schemaPath() {
  var dir = Directory.current;
  while (dir.parent.path != dir.path) {
    if (File('${dir.path}/config/appbox.config.json').existsSync()) break;
    dir = dir.parent;
  }
  return '${dir.path}/skills/appbox-intake/intake.schema.json';
}
