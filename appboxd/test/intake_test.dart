// Tests for the Dart intake engine — port of skills/appbox-intake/intake.py.
//
// The brief/registry goldens below were captured byte-for-byte from the Python
// engine (`emit_brief` / `emit_registry`) on the `goodAnswers()` fixture; the
// byte-identity must hold or the port has drifted.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/intake.dart';
import 'package:appboxd/intake_cli.dart';
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

// The exact bytes the Python engine emits for goodAnswers() — the contract.
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

## Brand

> **[inferred]** — not stated by the client; confirm or correct.

none stated

_provenance: inferred_

## Constraints

_Not stated._
## Out of scope

_Not stated._
## Layout template

_Not stated._
## Surface inventory — the registry seed

| id | shell | comp | label | surface |
|---|---|---|---|---|
| `projects.home` | projects | ProjectsHome | Home | _null_ |
| `projects.new` | projects | ProjectsNew | New | _null_ |

Every `surface` is `null` — intake names what the client asked for; design binds a surface to each.
''';

const expectedRegistry = '''[
  {
    "id": "projects.home",
    "label": "Home",
    "shell": "projects",
    "comp": "ProjectsHome",
    "surface": null
  },
  {
    "id": "projects.new",
    "label": "New",
    "shell": "projects",
    "comp": "ProjectsNew",
    "surface": null
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
    "surface": null
  },
  {
    "id": "shop.home",
    "label": "Home",
    "shell": "shop",
    "comp": "ShopHome",
    "surface": null
  }
]
''';

void main() {
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

    test('emitBrief is byte-identical to the Python golden', () {
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
          ['id', 'label', 'shell', 'comp', 'surface', 'priority', 'release']);
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
}
