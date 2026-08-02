// `appbox intake` — CLI entry for the elicitation engine.
//
// Port of `intake.py main()`. Returns process exit codes (the caller —
// `bin/appbox.dart` — wraps the return in `exit(...)`):
//   0 ok · 1 invalid input · 2 usage / self-test error.
//
// Usage:
//   appbox intake emit    --answers <answers.json> [--project <name>]
//                         [--brief-out p] [--registry-out p]
//   appbox intake seed    --brief <brief.md> [--registry-out p]
//   appbox intake flows confirm --project <name> --flow <id> --as founder|client
//   appbox intake validate <answers.json>
//   appbox intake --self-test

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/intake.dart';
import 'package:appboxd/project.dart';

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
    case 'flows':
      return _cmdFlows(rest);
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
  emit --answers <f> [--project <name>] [--brief-out p] [--registry-out p]
                        Emit brief.md + seeded registry.json from answers;
                        with --project every output lands in the project's
                        ~/.appbox intake/ dir (answers/brief/registry/flows)
  seed --brief <f> [--registry-out p]
                        Derive registry.json from a hand-written brief (10.7)
  flows confirm --project <name> --flow <id> --as founder|client
                        Flip a flow's provenance (derive + confirm)
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
  String? project;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--answers':
        if (i + 1 >= args.length) return _emitMissingValue('--answers');
        answersPath = args[++i];
        break;
      case '--project':
        if (i + 1 >= args.length) return _emitMissingValue('--project');
        project = args[++i];
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
      briefOut: briefOut, registryOut: registryOut, project: project);
  if (!res.ok) {
    for (final e in res.errors) {
      stderr.writeln('ERROR $e');
    }
    stderr.writeln('\nintake emit: ${res.errors.length} error(s) — nothing written');
    return 1;
  }
  print('intake emit: brief -> ${res.briefPath}, registry '
      '(${res.entries} entries, surface null) -> ${res.registryPath}');
  if (res.flowsPath != null) {
    print('  flows -> ${res.flowsPath}');
  }
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

// -- flows ------------------------------------------------------------------

int _cmdFlows(List<String> args) {
  if (args.isEmpty || args.first != 'confirm') {
    stderr.writeln('appbox intake flows: only subcommand is "confirm"');
    return 2;
  }
  String? project, flowId, as;
  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--project':
        if (i + 1 >= args.length) return _flowsMissing('--project');
        project = args[++i];
        break;
      case '--flow':
        if (i + 1 >= args.length) return _flowsMissing('--flow');
        flowId = args[++i];
        break;
      case '--as':
        if (i + 1 >= args.length) return _flowsMissing('--as');
        as = args[++i];
        break;
      default:
        stderr.writeln('appbox intake flows confirm: unknown flag ${args[i]}');
        return 2;
    }
  }
  if (project == null || flowId == null || as == null) {
    stderr.writeln('appbox intake flows confirm: --project, --flow and --as are required');
    return 2;
  }
  final err = const IntakeEngine().confirmFlow(project, flowId, as);
  if (err != null) {
    stderr.writeln('ERROR $err');
    return 1;
  }
  print('flows confirm: $flowId -> provenance $as (${shellDir(project, 'intake')}/flows.json)');
  return 0;
}

int _flowsMissing(String flag) {
  stderr.writeln('appbox intake flows confirm: $flag requires a value');
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
    // 6c. DECLARED states keep the surface's provenance — 'inferred' is
    // reserved for what intake derived (§22).
    if (reg[0]['statesProvenance'] != 'client') {
      throw 'declared states must keep the surface provenance: ${reg[0]}';
    }
    // 6d. no declared states AND no shape signal -> no key at all.
    if (reg[1].containsKey('states') || reg[1].containsKey('statesProvenance')) {
      throw 'states key must be omitted when there is no signal (additive only)';
    }
    // 6e. UNdeclared states ARE derived from shape and stamped, so the confirm
    // step has something to confirm (§22). Built standalone so the shared
    // fixture's derived draft flow stays a two-surface, one-edge chain.
    final derivedStates = emitRegistry({
      'surfaces': [
        {'id': 'shop.list', 'label': 'All', 'shell': 'shop', 'provenance': 'client'},
        {'id': 'shop.login', 'label': 'Sign in', 'shell': 'shop', 'provenance': 'client'},
      ],
    });
    if (!_listEq((derivedStates[0]['states'] as List).cast<String>(),
        ['loading', 'empty'])) {
      throw 'states not derived for a collection surface: ${derivedStates[0]}';
    }
    if (!_listEq((derivedStates[1]['states'] as List).cast<String>(), ['error'])) {
      throw 'states not derived for a form surface: ${derivedStates[1]}';
    }
    if (derivedStates.any((e) => e['statesProvenance'] != 'inferred')) {
      throw 'derived states must be stamped inferred: $derivedStates';
    }
    // 6f. feedback is an EDGE key — derived on a mutation trigger, stamped.
    final fbFlows = emitFlows({
      'surfaces': (good['surfaces'] as List),
      'flows': [
        {
          'id': 'flow-x',
          'name': 'X',
          'provenance': 'client',
          'edges': [
            {'from': 'projects.home', 'to': 'projects.credits', 'trigger': 'Save project'},
          ],
        },
      ],
    });
    final fb = (fbFlows[0]['edges'] as List)[0]['feedback'] as Map?;
    if (fb == null || fb['kind'] != 'success' || fb['inferred'] != true) {
      throw 'feedback not derived on a mutation edge: ${fbFlows[0]}';
    }
    if (fb['text'] != 'Save project') {
      throw 'feedback.text must be the trigger verbatim, not invented copy: $fb';
    }
    // 6g. feedback is rejected on a SURFACE — a toast is not a screen state.
    final fbOnSurface = goodAnswers();
    fbOnSurface['surfaces'] = [
      {
        'id': 'projects.home',
        'label': 'Home',
        'shell': 'projects',
        'provenance': 'client',
        'feedback': {'kind': 'success', 'text': 'Saved'},
      },
    ];
    if (!validateIntake(fbOnSurface).errors.any((e) => e.contains('feedback'))) {
      throw 'feedback on a surface must be rejected';
    }
    // 6h. the states vocabulary is CLOSED.
    final badVocab = goodAnswers();
    badVocab['surfaces'] = [
      {
        'id': 'projects.home',
        'label': 'Home',
        'shell': 'projects',
        'provenance': 'client',
        'states': ['skeleton'],
      },
    ];
    if (!validateIntake(badVocab).errors.any((e) => e.contains('skeleton'))) {
      throw 'an out-of-vocabulary state must be rejected';
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
    // 13. route derivation + additive flags
    if (deriveRoute('shop.cart') != '/cart') throw 'route derivation wrong';
    final regRoute = emitRegistry(good);
    if (regRoute[0]['route'] != '/home') throw 'route missing from registry: ${regRoute[0]}';
    final flagged = goodAnswers();
    ((flagged['surfaces'] as List)[0] as Map)['requiresAuth'] = true;
    ((flagged['surfaces'] as List)[0] as Map)['tab'] = true;
    final regFlags = emitRegistry(flagged);
    if (regFlags[0]['requiresAuth'] != true || regFlags[0]['tab'] != true) {
      throw 'requiresAuth/tab not carried: ${regFlags[0]}';
    }
    if (regFlags[1].containsKey('requiresAuth')) {
      throw 'requiresAuth key must be omitted when false (additive only)';
    }
    // 14. flows: declared pass through with default action; bad shapes named
    final withFlows = goodAnswers()
      ..['flows'] = [
        {
          'id': 'flow-projects',
          'name': 'Projects journey',
          'provenance': 'founder',
          'edges': [
            {'from': 'projects.home', 'to': 'projects.credits', 'trigger': 'New project'},
          ],
        },
      ];
    if (validateIntake(withFlows).errors.isNotEmpty) {
      throw 'valid flows rejected: ${validateIntake(withFlows).errors}';
    }
    final emittedFlows = emitFlows(withFlows);
    if (emittedFlows.length != 1 ||
        (emittedFlows[0]['edges'] as List)[0]['action'] != 'push') {
      throw 'declared flows did not pass through with default action: $emittedFlows';
    }
    final badAction = goodAnswers()
      ..['flows'] = [
        {
          'id': 'flow-projects',
          'name': 'x',
          'provenance': 'founder',
          'edges': [
            {'from': 'projects.home', 'to': 'projects.credits', 'trigger': 'x', 'action': 'teleport'},
          ],
        },
      ];
    if (!validateIntake(badAction).errors.any((e) => e.contains('teleport'))) {
      throw 'missed bad edge action';
    }
    final badEndpoint = goodAnswers()
      ..['flows'] = [
        {
          'id': 'flow-projects',
          'name': 'x',
          'provenance': 'founder',
          'edges': [
            {'from': 'projects.home', 'to': 'projects.ghost', 'trigger': 'x'},
          ],
        },
      ];
    if (!validateIntake(badEndpoint).errors.any((e) => e.contains('projects.ghost'))) {
      throw 'missed undeclared edge endpoint';
    }
    final branched = goodAnswers()
      ..['flows'] = [
        {
          'id': 'flow-projects',
          'name': 'x',
          'provenance': 'founder',
          'edges': [
            {'from': 'projects.home', 'to': 'projects.credits', 'trigger': 'a'},
            {'from': 'projects.home', 'to': 'projects.credits', 'trigger': 'b'},
          ],
        },
      ];
    if (!validateIntake(branched).errors.any((e) => e.contains('linear'))) {
      throw 'missed non-linear flow (second outgoing edge)';
    }
    // 15. derive + confirm: no flows key -> one inferred draft flow per shell,
    //     chained in declaration order; confirm flips provenance on disk
    final derived = emitFlows(goodAnswers());
    if (derived.length != 1 ||
        derived[0]['id'] != 'flow-projects' ||
        derived[0]['provenance'] != 'inferred' ||
        (derived[0]['edges'] as List).length != 1) {
      throw 'derived draft flow wrong: $derived';
    }
    final tmp = Directory.systemTemp.createTempSync('appbox_intake_selftest');
    try {
      appboxHomeOverride = '${tmp.path}/.appbox';
      final res = const IntakeEngine().emit(goodAnswers(), project: 'selftest');
      if (!res.ok || res.flowsPath == null) throw 'project emit failed: ${res.errors}';
      for (final f in ['answers.json', 'brief.md', 'registry.json', 'flows.json']) {
        if (!File('${shellDir('selftest', 'intake')}/$f').existsSync()) {
          throw 'project emit missing $f';
        }
      }
      if (const IntakeEngine().confirmFlow('selftest', 'flow-projects', 'ghost') == null) {
        throw 'confirmFlow accepted a bad --as value';
      }
      if (const IntakeEngine().confirmFlow('selftest', 'flow-projects', 'founder') != null) {
        throw 'confirmFlow failed';
      }
      final confirmed = jsonDecode(
          File('${shellDir('selftest', 'intake')}/flows.json').readAsStringSync());
      if (confirmed[0]['provenance'] != 'founder') {
        throw 'confirmFlow did not flip provenance: $confirmed';
      }
    } finally {
      appboxHomeOverride = null;
      tmp.deleteSync(recursive: true);
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
        // No declared states AND no shape signal ("credits" is neither a
        // collection nor a form) — carries the additive-only invariant.
        {
          'id': 'projects.credits',
          'label': 'Credits',
          'shell': 'projects',
          'provenance': 'client',
        },
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
