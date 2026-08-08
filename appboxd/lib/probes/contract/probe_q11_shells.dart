// Q11 spike probe — one probe, five verdicts, over the Q8 feature-recipe manifest.
//
// `needsBrowser: false` and `mutates: false`: this probe reads the filesystem and
// nothing else. The runner therefore launches no Chrome (probe_cli.dart) and never
// contacts the server (the checkDisposableProject guard fires only for mutators).
//
// Suite: kSuiteContract. A contract probe "asserts the appbox opinion against ANY
// served design"; this one asserts the appbox opinion — the Q8 manifest — against a
// TREE rather than a served design. It names no route, so it is not miscategorised
// by the rule in probe_base.dart. It is, however, a third kind of probe (structural,
// offline) and that is worth a decision rather than an assumption.
//
// Two targets, deliberately:
//   * kit/showcase_app  — the manifest's own _comment makes showcase passing
//     golden-expansion the Q8 gate. This runs today, with no emitted tree.
//   * the spike golden tree — only if it exists; otherwise the emitted-output
//     verdicts report blocked-with-cause rather than vacuously passing.

import 'dart:io';
import 'dart:convert';

import 'package:appboxd/probes/probe_base.dart';

const Probe probeQ11Shells = Probe(
  name: 'q11-shells',
  summary: 'Q11 spike: manifest expansion, analyze, byte-identity, inspectAttrs, frontmatter',
  mutates: false,
  needsBrowser: false,
  suite: kSuiteContract,
  body: _run,
);

/// Repo root, found by walking up from the CWD until the manifest is visible.
/// The runner may be invoked from `appboxd/` or from the repo root.
Directory? _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final probe = File(
      '${dir.path}/kit/showcase_app/feature-recipe.manifest.json',
    );
    if (probe.existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

const List<String> _kFactors = <String>['mobile', 'tablet', 'desktop'];

/// The emitted tree, but only when it is REAL — a directory that exists but holds
/// no Dart is not a tree, and treating it as one manufactures false greens:
/// `dart analyze` in an empty directory exits 0, which would report verdict 2
/// green having compiled nothing. An empty golden must read as blocked, never pass.
Directory? _goldenTree(Directory root) {
  final dir = Directory('${root.path}/tool/spike-q11-shells/golden');
  if (!dir.existsSync()) return null;
  final hasDart = dir
      .listSync(recursive: true)
      .whereType<File>()
      .any((f) => f.path.endsWith('.dart'));
  if (!hasDart) return null;
  if (!File('${dir.path}/pubspec.yaml').existsSync()) return null;
  return dir;
}

Future<void> _run(ProbeContext ctx) async {
  final report = ctx.report;

  final root = _repoRoot();
  if (root == null) {
    report.check('q11 preconditions', false, 'repo root not found from ${Directory.current.path}');
    return;
  }

  final manifestFile = File('${root.path}/kit/showcase_app/feature-recipe.manifest.json');
  final Map<String, dynamic> manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final types = (manifest['artifactTypes'] as List).cast<Map<String, dynamic>>();

  final showcaseLib = Directory('${root.path}/kit/showcase_app/lib');

  report.section(
    'Q11 spike — manifest v${manifest['manifestVersion']} '
    '(${types.length} artifact types)',
  );

  // ---------------------------------------------------------------- verdict 1
  _verdictGoldenExpansion(report, root, showcaseLib, types);

  // ---------------------------------------------------------------- verdict 2
  _verdictAnalyze(report, root);

  // ---------------------------------------------------------------- verdict 3
  _verdictByteIdentity(report, root);

  // ---------------------------------------------------------------- verdict 4
  _verdictInspectAttrs(report, root, showcaseLib);

  // ---------------------------------------------------------------- verdict 5
  _verdictFrontmatter(report, root, showcaseLib, types);
}

// =============================================================== verdict 1 ===
// Golden expansion, BIDIRECTIONAL. One direction is not a match:
//   forward  — every view file on disk is explained by some template expansion
//              (no unexplained files);
//   backward — every discovered shell/surface directory carries the artifacts
//              the manifest declares as cardinality-one (nothing missing).
void _verdictGoldenExpansion(
  ProbeReport report,
  Directory root,
  Directory showcaseLib,
  List<Map<String, dynamic>> types,
) {
  if (!showcaseLib.existsSync()) {
    report.check('1. golden expansion', false, 'showcase lib missing at ${showcaseLib.path}');
    return;
  }

  final viewsDir = Directory('${showcaseLib.path}/ui/views');
  if (!viewsDir.existsSync()) {
    report.check('1. golden expansion', false, 'no lib/ui/views in showcase');
    return;
  }

  final unexplained = <String>[];
  final strays = <String>[];
  final missing = <String>[];
  var shells = 0;
  var surfaces = 0;

  for (final shellDir in viewsDir.listSync().whereType<Directory>()) {
    final shellName = shellDir.path.split('/').last;
    if (!shellName.endsWith('_shell')) {
      unexplained.add('$shellName/ (not <app>_<feature>_shell)');
      continue;
    }
    shells++;

    // backward: shell-view + shell-viewmodel are cardinality-one per feature.
    for (final suffix in <String>['_view.dart', '_viewmodel.dart']) {
      final f = File('${shellDir.path}/$shellName$suffix');
      if (!f.existsSync()) missing.add('$shellName/$shellName$suffix');
    }

    for (final entity in shellDir.listSync()) {
      if (entity is Directory) {
        final surfaceName = entity.path.split('/').last;
        surfaces++;
        // backward: surface-view + surface-viewmodel, cardinality-one per surface.
        for (final suffix in <String>['_view.dart', '_viewmodel.dart']) {
          final f = File('${entity.path}/$surfaceName$suffix');
          if (!f.existsSync()) missing.add('$shellName/$surfaceName/$surfaceName$suffix');
        }
        // forward: every file in a surface dir matches a surface template.
        for (final sf in entity.listSync().whereType<File>()) {
          final n = sf.path.split('/').last;
          if (!n.endsWith('.dart')) { strays.add('$shellName/$surfaceName/$n'); continue; }
          if (!_matchesViewTemplates(n, surfaceName)) {
            unexplained.add('$shellName/$surfaceName/$n');
          }
        }
      } else if (entity is File) {
        // forward: every file in a shell dir matches a shell template.
        final n = entity.path.split('/').last;
        if (!n.endsWith('.dart')) { strays.add('$shellName/$n'); continue; }
        if (!_matchesViewTemplates(n, shellName)) {
          unexplained.add('$shellName/$n');
        }
      }
    }
  }

  final ok = unexplained.isEmpty && missing.isEmpty;
  final detail = StringBuffer(
    'showcase: $shells shells, $surfaces surfaces; '
    'unexplained=${unexplained.length} missing=${missing.length}',
  );
  if (!ok) {
    for (final u in unexplained.take(8)) {
      detail.write('\n      unexplained: $u');
    }
    for (final m in missing.take(8)) {
      detail.write('\n      missing: $m');
    }
  }
  report.check('1. golden expansion (showcase = Q8 gate, bidirectional)', ok, detail.toString());
  if (strays.isNotEmpty) {
    // Not a failure: the manifest's artifact types describe .dart artifacts. But a
    // non-Dart file living inside a shell directory cannot be produced by any Q8
    // expansion, so the manifest cannot round-trip the showcase tree it was derived
    // from. Whether such files get an artifact type is a decision, not a probe call.
    report.warn('1. non-Dart files inside shell dirs, unexpressible in the Q8 '
        'manifest (${strays.length}): ${strays.take(4).join(", ")}');
  }

  // The spike's own golden tree, when it exists.
  final golden = _goldenTree(root);
  if (golden == null) {
    report.skip('1b. golden expansion (spike tree) — no emitted tree yet; emitter not '
        'built. Output location is settled: tool/spike-q11-shells/ (alongside probe '
        'tooling, repo-tracked, not tmp/), per the spike brief.');
  }
}

/// True when [name] is a legal expansion of a view/viewmodel template for the
/// directory stem [stem] — `<stem>_view.dart`, `<stem>_view.<factor>.dart`,
/// `<stem>_viewmodel.dart`. Factor must be in the derived set.
bool _matchesViewTemplates(String name, String stem) {
  if (name == '${stem}_view.dart') return true;
  if (name == '${stem}_viewmodel.dart') return true;
  for (final f in _kFactors) {
    if (name == '${stem}_view.$f.dart') return true;
  }
  return false;
}

// =============================================================== verdict 2 ===
void _verdictAnalyze(ProbeReport report, Directory root) {
  final golden = _goldenTree(root);
  if (golden == null) {
    report.check(
      '2. dart analyze clean',
      false,
      'BLOCKED: no emitted tree — the emitter is not built. This is unfinished spike '
      'work, NOT a decision owed by team-lead: output location is settled at '
      'tool/spike-q11-shells/ per the brief. '
      'Note also that the emitted tree MUST carry an analysis_options.yaml mirroring '
      'showcase — flutter_lints as a dev dependency alone runs no lints, so a green '
      'here without it would test less than it appears to.',
    );
    return;
  }
  if (!File('${golden.path}/analysis_options.yaml').existsSync()) {
    report.check('2. dart analyze clean', false,
        'no analysis_options.yaml in the emitted tree — flutter_lints as a dev '
        'dependency alone runs no lints, so a green here would test less than it appears to');
    return;
  }
  final res = Process.runSync('dart', <String>['analyze', '--no-fatal-warnings'],
      workingDirectory: golden.path);
  report.check('2. dart analyze clean', res.exitCode == 0,
      res.exitCode == 0 ? 'exit 0' : (res.stdout as String).split('\n').take(6).join('\n      '));
}

// =============================================================== verdict 3 ===
void _verdictByteIdentity(ProbeReport report, Directory root) {
  final emitter = File('${root.path}/tool/spike-q11-shells/bin/emit_spike_app.dart');
  if (!emitter.existsSync()) {
    report.check(
      '3. second run byte-identical',
      false,
      'BLOCKED: no transliterator yet. Design is fixed and recorded: the creative '
      '(designer) stage is exempt per the Q2<->Q11 audit resolution, so the spike '
      'freezes design.json and re-runs ONLY the transliterator. Consequence already '
      'locked in the design record: no timestamps/dates/run-ids in Q5 frontmatter — '
      'provenance is manifestVersion + registry version — or this verdict is '
      'unpassable by construction.',
    );
    return;
  }
  report.skip('3. second run byte-identical — emitter present but not yet wired here');
}

// =============================================================== verdict 4 ===
void _verdictInspectAttrs(ProbeReport report, Directory root, Directory showcaseLib) {
  // Showcase is EXEMPT and that exemption is not the probe's invention:
  // skills/appbox-scaffolder/SKILL.md:270 states showcase carries no inspectAttrs
  // today and that the corroboration must either exempt showcase or back-stamp it.
  report.warn(
    '4. inspectAttrs — showcase exempt by skills/appbox-scaffolder/SKILL.md:270 '
    '("kit/showcase_app carries no inspectAttrs today"). Exempt-vs-back-stamp is an '
    'open decision for team-lead, not a probe choice.',
  );

  final golden = _goldenTree(root);
  if (golden == null) {
    report.check(
      '4. inspectAttrs coverage (UNRATIFIED — see detail)',
      false,
      'BLOCKED, and blocked on more than the emitter. This verdict is currently '
      'CIRCULAR: (a) no Dart shape for inspectAttrs exists anywhere in kit/ — '
      'app-architecture.md:169 defines only the JS form; (b) the anatomy-node-id '
      'vocabulary does not exist — the repo contains exactly one illustrative value, '
      "'anatomy:view.body' at app-architecture.md:172, with no closed set and no home. "
      'Emitting a shape and a vocabulary of my own invention and then checking output '
      'against that invention would make a green here meaningless. Both need a '
      'ratified decision and a home (showcase-anatomy.md §3 or the registry) before '
      'this verdict can mean "Q12 satisfied".',
    );
    return;
  }
  report.skip('4. inspectAttrs — golden tree present; vocabulary still unratified');
}

// =============================================================== verdict 5 ===
// Q5 frontmatter is normative IN SHOWCASE, so it is enforceable against showcase
// today. The `History:` line is mechanically derivable, so it is mechanically gated:
// it must name the file's own repo-relative path.
void _verdictFrontmatter(
  ProbeReport report,
  Directory root,
  Directory showcaseLib,
  List<Map<String, dynamic>> types,
) {
  final viewsDir = Directory('${showcaseLib.path}/ui/views');
  if (!viewsDir.existsSync()) {
    report.check('5. frontmatter conventions', false, 'no showcase views');
    return;
  }

  final failures = <String>[];
  var checked = 0;

  for (final f in viewsDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final name = f.path.split('/').last;
    // `full` frontmatter applies to views, factors and viewmodels alike.
    if (!(name.endsWith('_view.dart') ||
        name.endsWith('_viewmodel.dart') ||
        _kFactors.any((x) => name.endsWith('_view.$x.dart')))) {
      continue;
    }
    checked++;
    final rel = f.path.substring(root.path.length + 1);
    final src = f.readAsStringSync();
    final head = src.split('library;').first;

    final missing = <String>[];
    if (!src.contains('library;')) missing.add('terminator `library;`');
    if (!head.trimLeft().startsWith('///')) missing.add('layer-intro');
    if (!head.contains('Requirements:')) missing.add('requirements');
    if (!head.contains('Relationships:')) missing.add('relationships');
    if (!head.contains('History: git log --follow -- ')) {
      missing.add('history');
    } else if (!head.contains('History: git log --follow -- $rel')) {
      missing.add('history names the WRONG path (must be $rel)');
    }
    if (missing.isNotEmpty) failures.add('$rel — ${missing.join(', ')}');
  }

  final ok = failures.isEmpty;
  final detail = StringBuffer('showcase: $checked view/viewmodel files checked, '
      '${failures.length} non-conforming');
  if (!ok) {
    for (final x in failures.take(10)) {
      detail.write('\n      $x');
    }
    if (failures.length > 10) detail.write('\n      … ${failures.length - 10} more');
  }
  report.check('5. frontmatter conventions (Q5, enforced against showcase)', ok, detail.toString());
}
