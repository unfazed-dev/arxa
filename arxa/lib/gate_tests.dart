// Tests gate — behavior-TDD enforcement on a target app/package.
//
// The TEST gate: a scaffolded surface is not done when its files exist — it is
// done when its behavior is pinned by tests. Three rules, cheapest first:
//
//   T1 traceability + no empty stubs — every *_test.dart under <app>/test
//      carries at least one test( / testWidgets( / blocTest( invocation (a
//      stub file with only TODOs is a promise, not coverage), no group() is
//      left empty-bodied, and — when a story map exists — every story with
//      priority must/should has its id string appear in at least one file
//      under <app>/test. Discovery order: <app>/intake/map.json, then
//      <app>/docs/intake/story-map.json; `--project <name>` reads
//      ~/.arxa/projects/<name>/intake/map.json instead. No map → WARN + pass
//      (portalo-era projects predate the story-mapper; the gate never
//      false-fails them).
//   T2 anti-pattern scan — the banned mechanical tests from the canon
//      (skills/arxa-tester/behavior-tdd-rules.md §Banned anti-patterns):
//      getter/constructor/toString tests, verify()-only tests (mock
//      verification theater), and stub-then-assert-the-stub round-trips.
//      Each tests the test, not the behavior; each is detected by shape.
//   T3 tests pass — `flutter test` in the app root, or `dart test` for
//      pure-Dart packages (detected via pubspec.yaml: a `sdk: flutter`
//      dependency). Skipped in --check mode (drift checks never execute).
//
// Warnings are `WARN:` detail lines with GateResult.ok — there is no warn exit
// code. Failures also emit SARIF via ctx.sarif, like gate_scaffold.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/gates.dart';
import 'package:arxa/project.dart';

/// A test invocation, per T1: test(, testWidgets(, blocTest(, or a shared
/// contract-runner call (`run…Contract(` — e.g. runArxaKitRepositoryContract,
/// which parameterizes a whole named suite behind a backend factory). The word
/// boundary keeps `latest(`-style coincidences out; alternation order matters
/// not — backtracking tries the longer spellings.
final _invocationRe =
    RegExp(r'\b(?:test|testWidgets|blocTest|run\w*Contract)\s*\(');

/// Priorities that MUST be covered by a named test (MoSCoW).
const _coveredPriorities = {'must', 'should'};

// ── T2 vocabulary: the canon's banned mechanical tests, by shape ──────────

/// A test block opener — same alternation as [_invocationRe]; T2 walks the
/// blocks these delimit (one opener to the next, or EOF).
final _testOpenRe = RegExp(r'\b(?:test|testWidgets|blocTest)\s*\(');

/// A test name whose stated subject is construction or string form — the
/// canon's ban 1: such a test asserts nothing a user can observe.
final _getterishNameRe =
    RegExp(r'\b(?:constructor|to.?string|getters?)\b', caseSensitive: false);

/// The first quoted literal in a block: the test's name.
final _nameLiteralRe = RegExp(r'''['"]([^'"]+)['"]''');

/// mocktail verification (`verify(`, `verifyNever(`, …) and the assertions
/// that make a test behavioral rather than theatrical.
final _verifyRe = RegExp(r'\b(verify\w*)\s*\(');
final _expectRe = RegExp(r'\bexpect(?:Later)?\s*\(');

/// `when(() => receiver.member(` — captures the stubbed receiver/member so
/// the round-trip check can look for an expect on the SAME stub.
final _whenStubRe = RegExp(r'\bwhen\(\s*\(\)\s*=>\s*(\w+)\.(\w+)\s*\(');

/// An empty-bodied group() — the scaffolded placeholder the canon's ban 7
/// names; enforced under T1 beside empty file stubs.
final _emptyGroupRe =
    RegExp(r'''\bgroup\s*\(\s*['"][^'"]*['"]\s*,\s*\(\s*\)\s*\{\s*\}\s*\)\s*;''');

/// One T2 finding: the offending file, the shape it matched, and the test
/// name it belongs to (for a message a reader can act on).
typedef AntiPatternHit = ({String file, String shape, String testName});

/// Scan [testTexts] (path → source) for the canon's banned mechanical tests:
///
///   - getter/constructor/toString tests — the test NAME states construction
///     or string form as the subject (ban 1);
///   - verify() theater — every POSITIVE verify in the block carries only
///     `any()` matchers and the block asserts nothing else (ban 2's "proves a
///     call happened, not that the behavior is right"). A verify with PINNED
///     arguments is the canon's blessed trust-boundary pattern — the pinned
///     arguments ARE the observable behavior — and `verifyNever(…any())` is a
///     legitimate negative boundary, so neither is flagged;
///   - stub-then-assert-the-stub round-trips — a when() stub of
///     `receiver.member` answered by `expect(receiver.member(…))` on the same
///     stub (ban 3): that asserts mocktail, not the subject under test.
///
/// Blocks run opener-to-opener (or EOF) — coarse on purpose: every finding
/// names file + test for human review, and the shapes are coarse to begin
/// with. Bans 4–6 (dead arrange, copied logic, coverage-chasing) are judgment
/// calls the scan cannot make; the canon leaves them to review.
List<AntiPatternHit> antiPatternScan(Map<String, String> testTexts) {
  final hits = <AntiPatternHit>[];
  for (final entry in testTexts.entries) {
    final src = entry.value;
    final opens = _testOpenRe.allMatches(src).toList();
    for (var i = 0; i < opens.length; i++) {
      final block = src.substring(
          opens[i].start, i + 1 < opens.length ? opens[i + 1].start : src.length);
      final testName =
          _nameLiteralRe.firstMatch(block)?.group(1) ?? '(unnamed)';
      // Ban 1 — the name states the subject as construction/string form.
      if (_getterishNameRe.hasMatch(testName)) {
        hits.add((
          file: entry.key,
          shape: 'getter/constructor/toString test',
          testName: testName,
        ));
      }
      // Ban 2 — verification theater: every POSITIVE verify in the block
      // carries only any() matchers (no pinned argument, no literal) and the
      // block asserts nothing else. That proves calls happened, not that the
      // behavior is right — in any quantity. A verify with PINNED arguments
      // is the canon's blessed trust-boundary pattern (the arguments ARE the
      // assertion), and verifyNever(…any()) is a legitimate negative
      // boundary; two-phase tests (verifyNever + pinned verify) pass. The
      // canon's "verify at most once" count rule needs phase awareness a
      // line scanner lacks, so it stays review-only.
      final verifies = _verifyRe.allMatches(block).toList();
      final positive = verifies.where((v) => v.group(1) == 'verify').toList();
      if (positive.isNotEmpty && !_expectRe.hasMatch(block)) {
        bool bareAny(RegExpMatch v) {
          final close = block.indexOf(');', v.end);
          final args = block.substring(v.end, close < 0 ? block.length : close);
          return args.contains('any(') &&
              !args.contains("'") &&
              !args.contains('"') &&
              !RegExp(r'\d').hasMatch(args);
        }

        if (positive.every(bareAny)) {
          hits.add((
            file: entry.key,
            shape: 'verify()-only test',
            testName: testName,
          ));
        }
      }
      // Ban 3 — the stub answers itself: when(receiver.member) …
      // expect(receiver.member(…)). Receiver equality keeps a VM method that
      // merely shares the member name out of the blast radius.
      for (final stub in _whenStubRe.allMatches(block)) {
        final recv = stub.group(1)!, member = stub.group(2)!;
        final assertsOnStub = RegExp(
                '\\bexpect(?:Later)?\\s*\\(\\s*$recv\\.$member\\s*\\(')
            .hasMatch(block);
        if (assertsOnStub) {
          hits.add((
            file: entry.key,
            shape: 'stub-then-assert round-trip',
            testName: testName,
          ));
          break; // one hit per block is enough to name the fix
        }
      }
    }
  }
  return hits;
}

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

  // ---- T1: traceability + no empty stubs ----
  if (testFiles.isEmpty) {
    warn('no *_test.dart under $app/test — nothing to check (T1 vacuous)');
  } else {
    var t1Bad = 0;
    for (final f in testFiles) {
      if (!_invocationRe.hasMatch(testTexts[f.path]!)) {
        fail('empty test stub (T1): ${_rel(f.path, app)} — no test( / '
            'testWidgets( / blocTest( / run…Contract( invocation; a stub '
            'file is a promise, not coverage');
        t1Bad++;
      }
      if (_emptyGroupRe.hasMatch(testTexts[f.path]!)) {
        fail('empty group() stub (T1): ${_rel(f.path, app)} — a group with '
            'no tests is a scaffolded placeholder, not coverage; write the '
            'tests or delete the group');
        t1Bad++;
      }
    }
    if (t1Bad == 0) {
      ok('${testFiles.length} test file(s), every one carries a test '
          'invocation and no empty group() stubs (T1)');
    }
  }

  // ---- T1 (cont.): story coverage ----
  // Same name guard as the intake gate: project ids are directory names, and
  // a path-traversal name must not escape ~/.arxa/projects.
  if (project != null && !validProjectName(project)) {
    return GateResult.env('tests: bad project name "$project" — '
        'lowercase alnum + dash, like a surface id');
  }
  final mapPath = _discoverStoryMap(app, project);
  if (mapPath == null) {
    warn('no story map found — story coverage not enforced (T1); '
        'portalo-era projects lack maps (looked: '
        '${project != null ? '${shellDir(project, 'intake')}/map.json' : '$app/intake/map.json, $app/docs/intake/story-map.json'})');
  } else {
    final List<({String id, String priority})> required;
    try {
      final decoded = jsonDecode(File(mapPath).readAsStringSync());
      if (decoded is! Map) {
        throw const FormatException('top level is not an object');
      }
      required = _requiredStories(decoded);
    } catch (e) {
      fail('story map $mapPath does not parse — $e (T1)');
      return failResult();
    }
    final uncovered = <String>[];
    for (final s in required) {
      final covered =
          testTexts.values.any((text) => text.contains(s.id));
      if (!covered) uncovered.add(s.id);
    }
    for (final id in uncovered) {
      fail('uncovered story (T1): $id — a $mapPath story with priority '
          'must/should must have its id named in at least one file under '
          '$app/test');
    }
    if (uncovered.isEmpty) {
      ok('${required.length} must/should stor${required.length == 1 ? 'y' : 'ies'} '
          'from ${_rel(mapPath, app)}, every id named under test/ (T1)');
    }
  }

  // ---- T2: anti-pattern scan (banned mechanical tests) ----
  if (testFiles.isEmpty) {
    warn('no *_test.dart under $app/test — anti-pattern scan vacuous (T2)');
  } else {
    final hits = antiPatternScan(testTexts);
    for (final h in hits) {
      fail('${h.shape} (T2): ${_rel(h.file, app)} — test “${h.testName}” '
          'tests the test, not the behavior '
          '(skills/arxa-tester/behavior-tdd-rules.md §Banned anti-patterns)');
    }
    if (hits.isEmpty) {
      ok('${testFiles.length} test file(s) scanned, no banned anti-patterns '
          '(T2)');
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

/// T1 map discovery (story coverage): `--project` reads the project's intake
/// shell; otherwise the app's own intake map first, then the design-doc story
/// map. Null when no map exists anywhere.
String? _discoverStoryMap(String app, String? project) {
  if (project != null) {
    final p = '${shellDir(project, 'intake')}/map.json';
    return File(p).existsSync() ? p : null;
  }
  for (final candidate in [
    '$app/intake/map.json',
    '$app/docs/intake/story-map.json',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// Every must/should story id in a story map (shape: epics → features →
/// stories; see skills/arxa-story-mapper/story-map.schema.json). Unknown
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

// ── self-test (`arxa gate tests --self-test`) ─────────────────────────────

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

    // negative 2: plant a banned mechanical test — the scan must fail and
    // name both the file and the shape.
    File('${tmp.path}/test/empty_stub_test.dart').deleteSync();
    write('test/theater_test.dart', """
void main() {
  test('constructor sets name', () => expect(Folder('x').name, 'x'));
}
""");
    final r3 = run();
    if (r3.passed) {
      details.add('  FAIL  negative: the constructor test should have failed T2');
      return GateResult.fail(
          'tests self-test: FAIL (anti-pattern negative did not fail)', details);
    }
    final namesShape = r3.details.any((d) =>
        d.startsWith('FAIL') &&
        d.contains('theater_test.dart') &&
        d.contains('getter/constructor/toString'));
    if (!namesShape) {
      details.addAll(r3.details);
      details.add('  FAIL  negative: failed, but did not name the T2 shape');
      return GateResult.fail(
          'tests self-test: FAIL (anti-pattern negative did not name the shape)',
          details);
    }
    details.add('  # NEGATIVE: banned anti-pattern correctly failed T2 '
        '(theater_test.dart + shape named)');
    details.add('tests self-test: PASS (coverage + stub + anti-pattern '
        'negatives)');
    return GateResult.ok('tests self-test: PASS', details);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
