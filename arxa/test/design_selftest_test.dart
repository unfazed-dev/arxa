// Task 21: the designer selftest, tested in-process.
//
// Three layers (plan §21.1):
//   1. baseline — a known-good fixture copy → passed N, failed 0, exit 0.
//   2. planted violation — apply one mutation, run the full suite, assert
//      exactly its labeled check flips (the 6-row compact subset).
//   3. --negative — a falsifiability pass over a provable subset →
//      proven N, unproven 0, exit 0.
//
// The render section (every GET route → 200) needs Chrome; these tests run
// with skipRender: true to stay fast and Chrome-independent, matching how the
// bash .sh skips render when node_modules is absent. The render path itself is
// covered by design_server_test.dart's Chrome-backed group.
//
// Skill-degradation note: the repo skill USED TO carry legacy verify-*.mjs
// (hardcoded ladder widths) and serve.mjs (upstream tokens) that made the bash
// selftest report `passed 22, failed 2`. Task 23 archived those runtimes, so
// the hardcoded-ladder-width check now passes against the repo skill. The
// upstream-leak check still flips: the kept vendored runtime/vendor/drag.js
// carries a `// kimitail:` comment whose `kimi` substring matches the
// upstream-token filter. To test the green path in isolation, the tests build a
// minimal clean skill (just the two ladder files the checks read). A separate
// test proves the tool catches the real (upstream-leak) degradation against the
// repo skill.

library;

import 'dart:io';

import 'package:arxa/design_selftest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _fixture =
    p.absolute('../skills/arxa-designer/examples/hello-hda');

/// A minimal clean skill — just the two ladder files the skill checks read.
/// No .mjs files (so no hardcoded widths), no upstream tokens. This is the
/// green baseline the repo skill will be once Tasks 22+ disposition the
/// legacy runtime.
late String _cleanSkill;

Future<String> _copyFixture(String prefix) async {
  final tmp = await Directory.systemTemp.createTemp(prefix);
  for (final e in Directory(_fixture).listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: _fixture);
    final out = File(p.join(tmp.path, rel))..createSync(recursive: true);
    out.writeAsBytesSync(e.readAsBytesSync());
  }
  return tmp.path;
}

void main() {
  setUpAll(() async {
    final skillSrc = _skillDir();
    final tmp = await Directory.systemTemp.createTemp('selftest-clean-skill-');
    _cleanSkill = tmp.path;
    // kit-catalog.md rides along: the kit-mirror check reads it out of the
    // skill under test, so a clean skill without it cannot be a green baseline.
    for (final rel in [
      p.join('references', 'viewport-ladder.md'),
      p.join('runtime', 'ladder.json'),
      p.join('references', 'kit-catalog.md'),
    ]) {
      final src = File(p.join(skillSrc, rel));
      final out = File(p.join(tmp.path, rel))..createSync(recursive: true);
      out.writeAsBytesSync(src.readAsBytesSync());
    }
  });

  tearDownAll(() async {
    await Directory(_cleanSkill).delete(recursive: true);
  });

  // ── 1. baseline ────────────────────────────────────────────────────────
  group('baseline', () {
    test('clean fixture + clean skill → passed N, failed 0, exit 0', () async {
      final tmp = await _copyFixture('selftest-baseline-');
      try {
        final r = await runSelftest(
            artifactDir: tmp, skillDir: _cleanSkill, skipRender: true);
        expect(r.exitCode, 0, reason: r.stderrText);
        expect(r.failedCount, 0);
        expect(r.passedCount, greaterThan(18),
            reason: 'expected ~20+ structural checks to pass');
        expect(r.stdoutText, contains('failed 0'));
      } finally {
        await Directory(tmp).delete(recursive: true);
      }
    });

    test('prints the artifact path + section headers', () async {
      final tmp = await _copyFixture('selftest-format-');
      try {
        final r = await runSelftest(
            artifactDir: tmp, skillDir: _cleanSkill, skipRender: true);
        expect(r.stdoutText, contains('artifact:'));
        expect(r.stdoutText, contains('== structure =='));
      } finally {
        await Directory(tmp).delete(recursive: true);
      }
    });

    test('real repo skill is clean (no upstream token leak)', () async {
      // runtime/vendor/drag.js once carried a `// kimitail:` comment whose
      // `kimi` substring tripped the upstream-token filter — that real leak
      // is fixed, so the baseline against the real skill must pass. A new
      // leak regresses here; the planted upstream-leak mutation row proves
      // the check still catches one.
      final tmp = await _copyFixture('selftest-degraded-');
      try {
        final r = await runSelftest(
            artifactDir: tmp, skillDir: _skillDir(), skipRender: true);
        expect(r.exitCode, 0, reason: r.stderrText);
        expect(r.failLabels,
            isNot(contains('no upstream references outside LICENSE')));
      } finally {
        await Directory(tmp).delete(recursive: true);
      }
    });

    test('non-existent dir → exit 64', () async {
      expect(await designSelftestMain(['/no/such/dir/zzz']), 64);
    });

    test('unknown flag → exit 64', () async {
      expect(await designSelftestMain([_fixture, '--bogus']), 64);
    });
  });

  // ── 2. planted violations (6-row compact subset) ───────────────────────
  // Each mutation must flip EXACTLY its labeled check — proving the check can
  // catch the break it claims to catch. Clean skill isolates the one violation.
  group('planted violations', () {
    const cases = {
      'registry-key': 'registry parses with required keys',
      'surface-id': 'every viewmodel declares surfaceId',
      'orphan-post': 'every mutation route is reachable from markup',
      'dead-url': 'every static URL in markup resolves to a route',
      'emoji-icon': 'icons come from the icon() global, never emoji stand-ins',
      'client-js': 'zero-custom-client-JS lint',
      // Pinned by label, not just by exit code: the mutation deletes the widget
      // layer, which reddens neighbouring checks too, and an exit-code-only
      // assertion would still pass if THIS check had quietly stopped biting.
      'widget-partials':
          'widgets live in the two-tier homes and surfaces compose them',
    };
    for (final entry in cases.entries) {
      test('${entry.key} flips "${entry.value}"', () async {
        final tmp = await _copyFixture('selftest-${entry.key}-');
        try {
          applyMutation(entry.key, tmp, _cleanSkill);
          final r = await runSelftest(
              artifactDir: tmp, skillDir: _cleanSkill, skipRender: true);
          expect(r.exitCode, isNot(0), reason: 'mutation should cause failure');
          expect(r.failLabels, contains(entry.value),
              reason:
                  'expected "${entry.value}" to fail, got: ${r.failLabels}');
          // Some mutations break more than one check (e.g. surface-id also
          // uncovers the registry entry); what matters is the targeted check
          // flips, not that it is the only failure.
        } finally {
          await Directory(tmp).delete(recursive: true);
        }
      });
    }
  });

  // ── 2b. the half-migrated tree ─────────────────────────────────────────
  // The fixture is now FULLY on the two-tier homes (the hello-hda migration
  // landed), so every mixed state — the `ui/widgets/` root occupied while a
  // widget sits in a homeless group, or a straggler remains in the retired
  // tiers — has no fixture of its own. Those are the states that actually
  // occur during a migration, so they are planted explicitly.
  group('two-tier widget law', () {
    test('homeless new-root widgets and retired-tier stragglers fail, named',
        () async {
      final tmp = await _copyFixture('selftest-mixed-tier-');
      try {
        // Homeless: under ui/widgets/ but in an unnamed group.
        File(p.join(tmp, 'ui', 'widgets', 'components', '_stale.html'))
          ..createSync(recursive: true)
          ..writeAsStringSync('<nav class="stale">left behind</nav>\n');
        // Straggler: a widgets/ dir back inside the shell tree (retired tier).
        File(p.join(tmp, 'ui', 'views', 'main_shell', 'home', 'widgets',
                '_straggler.html'))
          ..createSync(recursive: true)
          ..writeAsStringSync('<nav class="stale">left behind</nav>\n');
        final r = await runSelftest(
            artifactDir: tmp, skillDir: _cleanSkill, skipRender: true);
        expect(
            r.failLabels,
            contains(
                'widgets live in the two-tier homes and surfaces compose them'),
            reason: 'mixed tier should fail, got: ${r.failLabels}');
      } finally {
        await Directory(tmp).delete(recursive: true);
      }
    });

    test('the fixture itself passes as a lawful two-tier artifact',
        () async {
      // Guards the planted mixed state above from going vacuous: the fixture
      // must sit wholly in LEGAL two-tier homes (every top-level group under
      // ui/widgets/ is common/ or <app>_<feature>_widgets/), otherwise the
      // mixed-state plant would be probing a state the fixture already has.
      final root = Directory(p.join(_fixture, 'ui', 'widgets'));
      expect(root.existsSync(), isTrue,
          reason: 'fixture is expected to sit on the two-tier homes');
      for (final e in root.listSync()) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        expect(name == 'common' || name.endsWith('_widgets'), isTrue,
            reason: 'illegal widget group under ui/widgets/: $name');
      }
      final r = await runSelftest(
          artifactDir: _fixture, skillDir: _cleanSkill, skipRender: true);
      expect(
          r.failLabels,
          isNot(contains(
              'widgets live in the two-tier homes and surfaces compose them')));
    });
  });

  // ── 3. negative mode (falsifiability over a provable subset) ───────────
  group('negative mode', () {
    test('proven N, unproven 0 over a provable subset', () async {
      // Artifact-only mutations (no skill, no render) — all provable against
      // the hello-hda fixture with a clean skill and render skipped. Run against
      // a hermetic temp copy with a freshly-initialized git index: Task 23
      // replaced the fixture's serve.mjs/generate.mjs with a README.md note, so
      // the live working tree carries an untracked file between write and
      // commit. A temp copy + `git init && git add .` gives a clean git baseline
      // (all files tracked) independent of the working tree's flux — which is
      // exactly what the 'untracked-file' mutation needs to stay provable.
      final subset = [
        'registry-key',
        'exclusions-file',
        'surface-id',
        'orphan-id',
        'uncovered-entry',
        'empty-shellroots',
        'repo-import',
        'fixture-provenance',
        'arb-parity',
        'full-reload',
        'fragment-typo',
        'orphan-post',
        'dead-url',
        'dangling-target',
        'emoji-icon',
        'widget-partials',
        'untracked-file',
        'client-js',
        'commented-js',
        'kit-catalog-row',
      ];
      final tmp = await Directory.systemTemp.createTemp('selftest-neg-repo-');
      // The artifact must be a SUBDIR of the git repo (not the repo root): the
      // _lGit check walks the artifact dir for files, and a .git/ inside it
      // would surface as untracked internals. src==art==<repo>/hello-hda keeps
      // git's path-base aligned with the artifact's, while rev-parse still
      // resolves to the parent repo.
      final artDir = Directory(p.join(tmp.path, 'hello-hda'))
        ..createSync(recursive: true);
      for (final e in Directory(_fixture).listSync(recursive: true)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: _fixture);
        final out = File(p.join(artDir.path, rel))..createSync(recursive: true);
        out.writeAsBytesSync(e.readAsBytesSync());
      }
      Process.runSync('git', ['-C', tmp.path, 'init', '-q']);
      Process.runSync('git', ['-C', tmp.path, 'add', 'hello-hda']);
      try {
        final r = await runSelftest(
          artifactDir: artDir.path,
          skillDir: _cleanSkill,
          srcDir: artDir.path,
          negative: true,
          skipRender: true,
          mutations: subset,
        );
        expect(r.exitCode, 0, reason: r.stderrText);
        expect(r.unprovenCount, 0);
        expect(r.provenCount, subset.length);
        expect(r.stdoutText, contains('unproven 0'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('baseline-red aborts with exit 65', () async {
      // Plant a violation that breaks the baseline, then attempt negative mode.
      final tmp = await _copyFixture('selftest-neg-red-');
      applyMutation('registry-key', tmp, _cleanSkill);
      try {
        final r = await runSelftest(
          artifactDir: tmp,
          skillDir: _cleanSkill,
          negative: true,
          skipRender: true,
          mutations: ['surface-id'],
        );
        expect(r.exitCode, 65);
      } finally {
        await Directory(tmp).delete(recursive: true);
      }
    });
  });
}

/// Resolve the repo skill dir (the ladder/upstream checks target it).
String _skillDir() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/config/arxa.config.json').existsSync()) {
      return p.join(dir.path, 'skills', 'arxa-designer');
    }
    if (dir.parent.path == dir.path) {
      return p.join(Directory.current.path, 'skills', 'arxa-designer');
    }
    dir = dir.parent;
  }
}
