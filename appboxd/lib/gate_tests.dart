// Tests gate — behavior-TDD enforcement on a target app/package.
//
// The TEST gate: a scaffolded surface is not done when its files exist — it is
// done when its behavior is pinned by tests. Three rules, cheapest first:
//
//   T1 no empty stubs — every *_test.dart under <app>/test carries at least one
//      test( / testWidgets( / blocTest( invocation. A stub file with only
//      TODOs is a promise, not coverage, and it reads green in every listing.
//   T2 story coverage — when a story map exists, every story with priority
//      must/should has its id string appear in at least one file under
//      <app>/test. Discovery order: <app>/intake/map.json, then
//      <app>/docs/design/story-map.json; `--project <name>` reads
//      ~/.appbox/projects/<name>/intake/map.json instead. No map → WARN + pass
//      (portalo-era projects predate the story-mapper; the gate never
//      false-fails them).
//   T3 tests pass — `flutter test` in the app root, or `dart test` for
//      pure-Dart packages (detected via pubspec.yaml: a `sdk: flutter`
//      dependency). Skipped in --check mode (drift checks never execute).
//
// Warnings are `WARN:` detail lines with GateResult.ok — there is no warn exit
// code. Failures also emit SARIF via ctx.sarif, like gate_scaffold.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gates.dart';
import 'package:appboxd/project.dart';

/// A test invocation, per T1: test(, testWidgets(, or blocTest(. The word
/// boundary keeps `latest(`-style coincidences out; alternation order matters
/// not — backtracking tries the longer spellings.
final _invocationRe = RegExp(r'\b(?:test|testWidgets|blocTest)\s*\(');

/// Priorities that MUST be covered by a named test (MoSCoW).
const _coveredPriorities = {'must', 'should'};

GateResult testsGate(GateContext ctx, {String? project}) {
  // ---- R5 self-test (see gates/README.md:39-44) ----
  if (ctx.selfTest) return _testsSelfTest();

  final app = ctx.appRoot ?? ctx.repoRoot;
  final details = <String>[];
  var fails = 0;

  void ok(String m) => details.add('  ✓ tests: $m');
  void warn(String m) => details.add('WARN: tests: $m');
  void fail(String m) {
    details.add('FAIL: tests: $m');
    ctx.sarif.result('tests', 'error', app, m);
    fails++;
  }

  GateResult passResult() => GateResult.ok('tests: PASS ($app)', details);
  GateResult failResult() => GateResult.fail('tests: $fails failure(s)', details);

  final testDir = Directory('$app/test');
  final testFiles = <File>[
    if (testDir.existsSync())
      ...testDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('_test.dart')),
  ]..sort((a, b) => a.path.compareTo(b.path));
  final testTexts = <String, String>{
    for (final f in testFiles) f.path: f.readAsStringSync(),
  };

  // ---- T1: no empty stubs ----
  if (testFiles.isEmpty) {
    warn('no *_test.dart under $app/test — nothing to check (T1 vacuous)');
  } else {
    var t1Bad = 0;
    for (final f in testFiles) {
      if (!_invocationRe.hasMatch(testTexts[f.path]!)) {
        fail('empty test stub (T1): ${_rel(f.path, app)} — no test( / '
            'testWidgets( / blocTest( invocation; a stub file is a promise, '
            'not coverage');
        t1Bad++;
      }
    }
    if (t1Bad == 0) {
      ok('${testFiles.length} test file(s), every one carries a test '
          'invocation (T1)');
    }
  }

  // ---- T2: story coverage ----
  // Same name guard as the intake gate: project ids are directory names, and
  // a path-traversal name must not escape ~/.appbox/projects.
  if (project != null && !validProjectName(project)) {
    return GateResult.env('tests: bad project name "$project" — '
        'lowercase alnum + dash, like a surface id');
  }
  final mapPath = _discoverStoryMap(app, project);
  if (mapPath == null) {
    warn('no story map found — story coverage not enforced (T2); '
        'portalo-era projects lack maps (looked: '
        '${project != null ? '${shellDir(project, 'intake')}/map.json' : '$app/intake/map.json, $app/docs/design/story-map.json'})');
  } else {
    final List<({String id, String priority})> required;
    try {
      final decoded = jsonDecode(File(mapPath).readAsStringSync());
      if (decoded is! Map) {
        throw const FormatException('top level is not an object');
      }
      required = _requiredStories(decoded);
    } catch (e) {
      fail('story map $mapPath does not parse — $e (T2)');
      return failResult();
    }
    final uncovered = <String>[];
    for (final s in required) {
      final covered =
          testTexts.values.any((text) => text.contains(s.id));
      if (!covered) uncovered.add(s.id);
    }
    for (final id in uncovered) {
      fail('uncovered story (T2): $id — a $mapPath story with priority '
          'must/should must have its id named in at least one file under '
          '$app/test');
    }
    if (uncovered.isEmpty) {
      ok('${required.length} must/should stor${required.length == 1 ? 'y' : 'ies'} '
          'from ${_rel(mapPath, app)}, every id named under test/ (T2)');
    }
  }

  // ---- T3: tests pass (skipped in --check mode) ----
  if (ctx.check) {
    ok('check-only mode (--check): test run skipped (T3)');
  } else {
    final pubspec = File('$app/pubspec.yaml');
    if (!pubspec.existsSync()) {
      warn('no pubspec.yaml at $app — test run skipped (T3)');
    } else {
      final isFlutter = pubspec.readAsStringSync().contains('sdk: flutter');
      final tool = isFlutter ? 'flutter' : 'dart';
      final result = Process.runSync(tool, ['test'], workingDirectory: app);
      if (result.exitCode == 0) {
        ok('$tool test passed (T3)');
      } else {
        final out = '${result.stdout}\n${result.stderr}'.trim();
        final lines = out.isEmpty ? const <String>[] : out.split('\n');
        final tail = lines.length > 20
            ? '…\n${lines.sublist(lines.length - 20).join('\n')}'
            : out;
        fail('$tool test failed (exit ${result.exitCode}) (T3) — '
            'output tail:\n$tail');
      }
    }
  }

  if (fails > 0) return failResult();
  return passResult();
}

/// T2 map discovery: `--project` reads the project's intake shell; otherwise
/// the app's own intake map first, then the design-doc story map. Null when
/// no map exists anywhere.
String? _discoverStoryMap(String app, String? project) {
  if (project != null) {
    final p = '${shellDir(project, 'intake')}/map.json';
    return File(p).existsSync() ? p : null;
  }
  for (final candidate in [
    '$app/intake/map.json',
    '$app/docs/design/story-map.json',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// Every must/should story id in a story map (shape: epics → features →
/// stories; see skills/appbox-story-mapper/story-map.schema.json). Unknown
/// priorities are ignored — intake does not own the MoSCoW vocabulary, but
/// only must/should are load-bearing here.
List<({String id, String priority})> _requiredStories(Map<dynamic, dynamic> map) {
  final out = <({String id, String priority})>[];
  final epics = map['epics'];
  if (epics is! List) return out;
  for (final e in epics) {
    if (e is! Map) continue;
    final features = e['features'];
    if (features is! List) continue;
    for (final f in features) {
      if (f is! Map) continue;
      final stories = f['stories'];
      if (stories is! List) continue;
      for (final s in stories) {
        if (s is! Map) continue;
        final id = s['id'];
        final priority = s['priority'];
        if (id is String && priority is String && _coveredPriorities.contains(priority)) {
          out.add((id: id, priority: priority));
        }
      }
    }
  }
  return out;
}

/// Path of [path] relative to [root], for messages.
String _rel(String path, String root) =>
    path.startsWith('$root/') ? path.substring(root.length + 1) : path;

// ── self-test (`appbox gate tests --self-test`) ─────────────────────────────

/// Build a temp fixture app, prove a positive (covered story + real test) and
/// a NEGATIVE (an empty stub MUST fail and name the file) — the
/// gates-must-be-able-to-fail contract. Runs with check: true so T3 stays
/// hermetic (no `dart test` subprocess inside the self-test).
GateResult _testsSelfTest() {
  final tmp = Directory.systemTemp.createTempSync('gate-tests-selftest-');
  final details = <String>[];
  try {
    void write(String rel, String body) {
      final f = File('${tmp.path}/$rel');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(body);
    }

    GateResult run() => testsGate(
        GateContext(repoRoot: tmp.path, appRoot: tmp.path, check: true));

    // positive: a real test invocation + a covered must story.
    write('pubspec.yaml', 'name: demo\n');
    write('test/demo_test.dart',
        "// covers demo.things.do-thing\nvoid main() { test('works', () {}); }\n");
    write('intake/map.json', jsonEncode({
      'epics': [
        {
          'id': 'demo',
          'features': [
            {
              'id': 'demo.things',
              'stories': [
                {'id': 'demo.things.do-thing', 'priority': 'must'},
              ],
            },
          ],
        },
      ],
    }));
    final r1 = run();
    if (!r1.passed) {
      details.addAll(r1.details);
      details.add('  FAIL  positive: expected the covered fixture to pass');
      return GateResult.fail('tests self-test: FAIL (positive case)', details);
    }
    details.add('  PASS  positive: covered story + real test invocation pass');

    // negative: plant an empty stub — the gate must fail and name the file.
    write('test/empty_stub_test.dart', '// TODO: write these tests\n');
    final r2 = run();
    if (r2.passed) {
      details.add('  FAIL  negative: the empty stub should have failed T1');
      return GateResult.fail(
          'tests self-test: FAIL (negative case did not fail)', details);
    }
    final namesIt = r2.details.any(
        (d) => d.startsWith('FAIL') && d.contains('empty_stub_test.dart'));
    if (!namesIt) {
      details.addAll(r2.details);
      details.add('  FAIL  negative: failed, but did not name '
          'empty_stub_test.dart');
      return GateResult.fail(
          'tests self-test: FAIL (negative case did not name the file)',
          details);
    }
    details.add('  # NEGATIVE: empty stub correctly failed T1 '
        '(empty_stub_test.dart named)');
    details.add('tests self-test: PASS (positive coverage + negative stub)');
    return GateResult.ok('tests self-test: PASS', details);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
