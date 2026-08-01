// `appbox intake` — CLI entry for the elicitation engine.
//
// Port of `intake.py main()`. Returns process exit codes (the caller —
// `bin/appbox.dart` — wraps the return in `exit(...)`):
//   0 ok · 1 invalid input · 2 usage / self-test error.
//
// Usage:
//   appbox intake emit    --answers <answers.json> [--brief-out p] [--registry-out p]
//   appbox intake seed    --brief <brief.md> [--registry-out p]
//   appbox intake validate <answers.json>
//   appbox intake --self-test

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/intake.dart';

int intakeMain(List<String> args) {
  if (args.isEmpty) {
    _usage();
    return 2;
  }
  if (args.first == '--self-test') {
    return _selfTest();
  }
  final cmd = args.first;
  final rest = args.sublist(1);
  switch (cmd) {
    case 'validate':
      return _cmdValidate(rest);
    case 'emit':
      return _cmdEmit(rest);
    case 'seed':
      return _cmdSeed(rest);
    default:
      stderr.writeln('appbox intake: unknown subcommand "$cmd"');
      _usage();
      return 2;
  }
}

void _usage() {
  stderr.writeln('''
Usage: appbox intake <subcommand> [options]

Subcommands:
  emit --answers <f> [--brief-out p] [--registry-out p]
                        Emit brief.md + seeded registry.json from answers
  seed --brief <f> [--registry-out p]
                        Derive registry.json from a hand-written brief (10.7)
  validate <answers>    Validate an answers document
  --self-test           Run the embedded negative-case self-test

Exit codes: 0 ok · 1 invalid input · 2 usage/self-test error''');
}

// -- validate ---------------------------------------------------------------

int _cmdValidate(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('appbox intake validate: missing <answers> path');
    return 2;
  }
  final answersPath = args.first;
  final Map<String, dynamic> answers;
  try {
    answers = _loadAnswers(answersPath);
  } on _LoadError catch (e) {
    stderr.writeln('ERROR ${e.message}');
    stderr.writeln('\nintake validate: 1 error(s)');
    return 1;
  }
  final errs = validateIntake(answers).errors;
  for (final e in errs) {
    print('ERROR $e');
  }
  print('\nintake validate: ${errs.length} error(s)');
  return errs.isNotEmpty ? 1 : 0;
}

// -- emit -------------------------------------------------------------------

int _cmdEmit(List<String> args) {
  String? answersPath;
  String? briefOut;
  String? registryOut;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--answers':
        if (i + 1 >= args.length) return _emitMissingValue('--answers');
        answersPath = args[++i];
        break;
      case '--brief-out':
        if (i + 1 >= args.length) return _emitMissingValue('--brief-out');
        briefOut = args[++i];
        break;
      case '--registry-out':
        if (i + 1 >= args.length) return _emitMissingValue('--registry-out');
        registryOut = args[++i];
        break;
      default:
        stderr.writeln('appbox intake emit: unknown flag ${args[i]}');
        return 2;
    }
  }
  if (answersPath == null) {
    stderr.writeln('appbox intake emit: --answers <f> is required');
    return 2;
  }
  final Map<String, dynamic> answers;
  try {
    answers = _loadAnswers(answersPath);
  } on _LoadError catch (e) {
    stderr.writeln('ERROR ${e.message}');
    stderr.writeln('\nintake emit: 1 error(s) — nothing written');
    return 1;
  }
  final res = const IntakeEngine().emit(answers,
      briefOut: briefOut, registryOut: registryOut);
  if (!res.ok) {
    for (final e in res.errors) {
      stderr.writeln('ERROR $e');
    }
    stderr.writeln('\nintake emit: ${res.errors.length} error(s) — nothing written');
    return 1;
  }
  print('intake emit: brief -> ${res.briefPath}, registry '
      '(${res.entries} entries, surface null) -> ${res.registryPath}');
  if (res.inferredCount > 0) {
    print('  ${res.inferredCount} inferred field(s) marked in the brief '
        '— confirm before design.');
  }
  return 0;
}

int _emitMissingValue(String flag) {
  stderr.writeln('appbox intake emit: $flag requires a value');
  return 2;
}

// -- seed -------------------------------------------------------------------

int _cmdSeed(List<String> args) {
  String? briefPath;
  String? registryOut;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--brief':
        if (i + 1 >= args.length) {
          stderr.writeln('appbox intake seed: --brief requires a value');
          return 2;
        }
        briefPath = args[++i];
        break;
      case '--registry-out':
        if (i + 1 >= args.length) {
          stderr.writeln('appbox intake seed: --registry-out requires a value');
          return 2;
        }
        registryOut = args[++i];
        break;
      default:
        stderr.writeln('appbox intake seed: unknown flag ${args[i]}');
        return 2;
    }
  }
  if (briefPath == null) {
    stderr.writeln('appbox intake seed: --brief <f> is required');
    return 2;
  }
  final res =
      const IntakeEngine().seed(briefPath, registryOut: registryOut);
  final note = res.entries > 0
      ? '${res.entries} entries'
      : 'no surface table found — empty seed (designer authors registry)';
  print('intake seed: brief passed through unmodified; registry ($note) -> ${res.registryPath}');
  return 0;
}

// -- self-test --------------------------------------------------------------

/// Negative-case self-test (R5: a check that has never failed is not a check).
/// Mirrors `intake.py _self_test`. Returns 0 on PASS, 2 on FAIL.
int _selfTest() {
  try {
    final good = goodAnswers();
    // 1. valid -> no errors
    if (validateIntake(good).errors.isNotEmpty) {
      throw 'valid answers rejected';
    }
    // 2. unknown provenance rejected and named
    final bad2 = goodAnswers()..['audience'] = {'value': 'Indie devs', 'provenance': 'guessed'};
    final e2 = validateIntake(bad2).errors;
    if (!e2.any((e) => e.contains('audience') && e.contains('guessed'))) {
      throw 'missed bad provenance: $e2';
    }
    // 3. malformed surface id rejected and named
    final bad3 = goodAnswers();
    ((bad3['surfaces'] as List)[0] as Map)['id'] = 'Projects.Home';
    final e3 = validateIntake(bad3).errors;
    if (!e3.any((e) => e.contains('surfaces[0]') && e.contains('Projects.Home'))) {
      throw 'missed bad id: $e3';
    }
    // 4. shell must equal id prefix
    final bad4 = goodAnswers();
    ((bad4['surfaces'] as List)[1] as Map)['shell'] = 'build';
    final e4 = validateIntake(bad4).errors;
    if (!e4.any((e) => e.contains('surfaces[1]') && e.contains('first segment'))) {
      throw 'missed shell mismatch: $e4';
    }
    // 5. duplicate id rejected
    final bad5 = goodAnswers();
    ((bad5['surfaces'] as List)[1] as Map)['id'] = 'projects.home';
    final e5 = validateIntake(bad5).errors;
    if (!e5.any((e) => e.contains('duplicate'))) {
      throw 'missed duplicate id: $e5';
    }
    // 6. elicits-never-generates: registry has exactly the input surfaces
    final reg = emitRegistry(good);
    if (reg.length != (good['surfaces'] as List).length) {
      throw 'registry invented or dropped entries';
    }
    if (reg.any((e) => e['surface'] != null)) {
      throw 'a seed surface is non-null (intake must not design)';
    }
    // 6b. states round-trip into the registry as an additive key
    if (!_listEq((reg[0]['states'] as List).cast<String>(), ['empty', 'loading'])) {
      throw 'states not carried into the registry: ${reg[0]}';
    }
    if (reg[1].containsKey('states')) {
      throw 'states key must be omitted when absent (additive only)';
    }
    // 7. bad direction shape rejected and named
    final badDir = goodAnswers()
      ..['direction'] = {'value': 'minimal', 'provenance': 'client'};
    final eDir = validateIntake(badDir).errors;
    if (!eDir.any((e) => e.contains('direction'))) {
      throw 'missed bad direction value: $eDir';
    }
    final badDir2 = goodAnswers()
      ..['direction'] = {
        'value': {'adjectives': [1, 2]},
        'provenance': 'client',
      };
    final eDir2 = validateIntake(badDir2).errors;
    if (!eDir2.any((e) => e.contains('direction') && e.contains('adjectives'))) {
      throw 'missed bad direction.adjectives: $eDir2';
    }
    // 7b. bad locales/contentAnchors/states shapes rejected and named
    final badLoc = goodAnswers()
      ..['locales'] = {'value': 'en', 'provenance': 'client'};
    if (!validateIntake(badLoc).errors.any((e) => e.contains('locales'))) {
      throw 'missed bad locales value';
    }
    final badStates = goodAnswers();
    ((badStates['surfaces'] as List)[0] as Map)['states'] = 'empty';
    if (!validateIntake(badStates).errors.any((e) => e.contains('states'))) {
      throw 'missed bad states value';
    }
    // 8. comp derivation by convention
    if (deriveComp('shop.cart') != 'ShopCart') throw 'comp derivation wrong';
    // 9. inferred field is visibly marked; client field is not
    final brief = emitBrief(good);
    if (!brief.contains('**[inferred]**')) throw 'inferred field not marked';
    // 10. new sections render: locales, direction, content anchors, states col
    if (!brief.contains('## Locales') || !brief.contains('- en')) {
      throw 'locales section missing from the brief';
    }
    if (!brief.contains('## Design direction') ||
        !brief.contains('- adjectives: calm, dense') ||
        !brief.contains('- avoids: playful gradients')) {
      throw 'direction section missing from the brief';
    }
    if (!brief.contains('## Content anchors')) {
      throw 'content anchors section missing from the brief';
    }
    if (!brief.contains('| id | shell | comp | label | states | surface |') ||
        !brief.contains('| `projects.home` | projects | ProjectsHome | Home | empty, loading | _null_ |')) {
      throw 'states column missing from the brief surface table';
    }
    // 12. a brief with no surface table -> empty seed
    if (seedFromBrief('# Just prose\n\nNo table here.\n').isNotEmpty) {
      throw 'empty brief should seed nothing';
    }
  } on Object catch (e) {
    stderr.writeln('self-test: FAIL: $e');
    return 2;
  }
  print('self-test: PASS');
  return 0;
}

Map<String, dynamic> goodAnswers() => {
      'product': {'value': 'Demo app', 'provenance': 'client'},
      'audience': {
        'value': 'When I have a client brief, I want to scaffold the app, so I can skip boilerplate',
        'provenance': 'client',
      },
      'appMustDo': {
        'value': ['list projects', 'run a build'],
        'provenance': 'client',
      },
      'targets': {
        'value': ['macos'],
        'provenance': 'client',
      },
      'locales': {
        'value': ['en', 'pl'],
        'provenance': 'client',
      },
      'brand': {'value': 'none stated', 'provenance': 'inferred'},
      'direction': {
        'value': {
          'adjectives': ['calm', 'dense'],
          'avoids': ['playful gradients'],
        },
        'provenance': 'client',
      },
      'contentAnchors': {
        'value': ['Q3 roadmap', 'invoice #1042'],
        'provenance': 'client',
      },
      'surfaces': [
        {
          'id': 'projects.home',
          'label': 'Home',
          'shell': 'projects',
          'states': ['empty', 'loading'],
          'provenance': 'client',
        },
        {'id': 'projects.new', 'label': 'New', 'shell': 'projects', 'provenance': 'client'},
      ],
    };

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// -- io ---------------------------------------------------------------------

class _LoadError implements Exception {
  const _LoadError(this.message);
  final String message;
}

Map<String, dynamic> _loadAnswers(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw _LoadError('answers: file not found: $path');
  }
  Object decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    throw _LoadError('answers: JSON parse error — ${e.message}');
  }
  if (decoded is! Map) {
    throw _LoadError('answers: expected a JSON object at the top level');
  }
  return decoded.cast<String, dynamic>();
}
