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
  _expansionLine(
    report,
    title: '1. golden expansion (showcase = Q8 gate, bidirectional)',
    strayTitle: '1.',
    subject: 'showcase',
    lib: showcaseLib,
    types: types,
  );

  // The spike's own golden tree, through the SAME function. A second
  // implementation here would make a green spike line prove nothing about the
  // showcase bar, so there isn't one.
  final golden = _goldenTree(root);
  if (golden == null) {
    report.check(
      '1b. golden expansion (spike tree)',
      false,
      'BLOCKED: no emitted tree at tool/spike-q11-shells/golden — the emitter '
      'did not run, so there is nothing to gate.',
    );
    return;
  }
  _expansionLine(
    report,
    title: '1b. golden expansion (spike tree = same Q8 gate, bidirectional)',
    strayTitle: '1b.',
    subject: 'spike',
    lib: Directory('${golden.path}/lib'),
    types: types,
  );
}

/// The Q8 bidirectional expansion rule applied to one `lib/` directory.
///
/// Forward: every file on disk is explained by a template expansion.
/// Backward: every declared shell/surface directory carries its cardinality-one
/// view + viewmodel. Shared by showcase (the gate) and the spike (the candidate).
void _expansionLine(
  ProbeReport report, {
  required String title,
  required String strayTitle,
  required String subject,
  required Directory lib,
  required List<Map<String, dynamic>> types,
}) {
  // Non-Dart artifacts the manifest types by literal filename (no `<slot>` to
  // substitute), keyed by the directory level their pathTemplate names. A file
  // matching one here is explained by the manifest, not a stray.
  Set<String> literalsAt(String pathTemplate) => types
      .where((t) =>
          t['pathTemplate'] == pathTemplate &&
          t['nameTemplate'] is String &&
          (t['nameTemplate'] as String).isNotEmpty &&
          !(t['nameTemplate'] as String).contains('<') &&
          !(t['nameTemplate'] as String).endsWith('.dart'))
      .map((t) => t['nameTemplate'] as String)
      .toSet();
  final shellLevel = literalsAt('lib/ui/views/<app>_<feature>_shell/');
  final surfaceLevel =
      literalsAt('lib/ui/views/<app>_<feature>_shell/<app>_<surface>/');
  if (!lib.existsSync()) {
    report.check(title, false, '$subject lib missing at ${lib.path}');
    return;
  }

  final viewsDir = Directory('${lib.path}/ui/views');
  if (!viewsDir.existsSync()) {
    report.check(title, false, 'no lib/ui/views in $subject');
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
          if (!n.endsWith('.dart')) {
            if (!surfaceLevel.contains(n)) strays.add('$shellName/$surfaceName/$n');
            continue;
          }
          if (!_matchesViewTemplates(n, surfaceName)) {
            unexplained.add('$shellName/$surfaceName/$n');
          }
        }
      } else if (entity is File) {
        // forward: every file in a shell dir matches a shell template.
        final n = entity.path.split('/').last;
        if (!n.endsWith('.dart')) {
          if (!shellLevel.contains(n)) strays.add('$shellName/$n');
          continue;
        }
        if (!_matchesViewTemplates(n, shellName)) {
          unexplained.add('$shellName/$n');
        }
      }
    }
  }

  final ok = unexplained.isEmpty && missing.isEmpty;
  final detail = StringBuffer(
    '$subject: $shells shells, $surfaces surfaces; '
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
  report.check(title, ok, detail.toString());
  if (strays.isNotEmpty) {
    // Non-Dart files inside a shell dir are no longer categorically unexpressible:
    // ratification (c) gives them typed manifest entries keyed by literal filename
    // (today only `design-system.md`; `.shell-structure.json` is typed one level
    // up at `lib/ui/views/` and never reaches this walk). What remains here is the
    // genuinely untyped residue — a file the manifest still cannot round-trip.
    report.warn('$strayTitle non-Dart files inside shell dirs with no matching typed '
        'manifest entry (${strays.length}): ${strays.take(4).join(", ")} '
        '— each needs a typed artifact entry or deletion.');
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
  final opts = File('${golden.path}/analysis_options.yaml');
  if (!opts.existsSync()) {
    report.check('2. dart analyze clean', false,
        'no analysis_options.yaml in the emitted tree — flutter_lints as a dev '
        'dependency alone runs no lints, so a green here would test less than it appears to');
    return;
  }
  // The two files are NOT byte-identical and should not be: showcase excludes
  // its stacked_generator router, which the spike does not emit. The `include:`
  // line is what pins the lint set, so that is what gets compared.
  String includeLine(File f) => f
      .readAsLinesSync()
      .firstWhere((l) => l.trim().startsWith('include:'), orElse: () => '');
  final wantInclude =
      includeLine(File('${root.path}/kit/showcase_app/analysis_options.yaml'));
  final gotInclude = includeLine(opts);
  if (wantInclude.isEmpty || gotInclude != wantInclude) {
    report.check('2. dart analyze clean', false,
        'analysis_options.yaml does not pin the showcase lint set — '
        'expected `$wantInclude`, got `$gotInclude`');
    return;
  }

  // Resolution is machine-local and gitignored: a clean `git status` is not a
  // resolved package_config.json. Without this, a fresh clone analyzed nothing
  // and still exited 0 — the same false-green class as the empty-dir bug below.
  var resolution = 'pre-resolved';
  if (!File('${golden.path}/.dart_tool/package_config.json').existsSync()) {
    final pub = Process.runSync('dart', <String>['pub', 'get'],
        workingDirectory: golden.path);
    if (pub.exitCode != 0) {
      report.check('2. dart analyze clean', false,
          'dart pub get failed in the emitted tree (analyze cannot be trusted '
          'without resolution): ${(pub.stderr as String).trim().split('\n').take(3).join(' / ')}');
      return;
    }
    resolution = 'resolved by probe (dart pub get)';
  }
  // No --no-fatal-warnings: the ruling was "the showcase's bar, not a weaker
  // default". Warnings fail here exactly as they would in showcase.
  final res = Process.runSync('dart', <String>['analyze'],
      workingDirectory: golden.path);
  report.check(
      '2. dart analyze clean (warnings fatal — showcase bar)',
      res.exitCode == 0,
      res.exitCode == 0
          ? 'exit 0; lint set pinned by the same `$wantInclude` as showcase; $resolution'
          : (res.stdout as String).split('\n').take(6).join('\n      '));
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
  final golden = _goldenTree(root);
  if (golden == null) {
    report.check('3. second run byte-identical', false,
        'BLOCKED: emitter exists but no committed golden tree to compare against.');
    return;
  }

  // Emit twice into throwaway dirs from the FROZEN input/design.json. The
  // designer (creative) stage is exempt per the Q2<->Q11 audit resolution, so
  // what is under test is the transliterator alone. Excluded from the compare:
  // pubspec.lock and .dart_tool (pub artifacts, not emitter output).
  final tmp = Directory.systemTemp.createTempSync('q11-byte-identity-');
  try {
    final runs = <String, Map<String, String>>{};
    for (final n in <String>['a', 'b']) {
      final out = Directory('${tmp.path}/$n');
      final res = Process.runSync(
        'dart',
        <String>['run', '${root.path}/tool/spike-q11-shells/bin/emit_spike_app.dart', out.path],
        workingDirectory: root.path,
      );
      if (res.exitCode != 0) {
        report.check('3. second run byte-identical', false,
            'emitter run "$n" failed (exit ${res.exitCode}): '
            '${(res.stderr as String).split('\n').take(4).join(' / ')}');
        return;
      }
      runs[n] = _hashTree(out);
    }
    final committed = _hashTree(golden);

    final diffs = <String>[];
    void compare(String label, Map<String, String> lhs, Map<String, String> rhs) {
      final keys = <String>{...lhs.keys, ...rhs.keys}.toList()..sort();
      for (final k in keys) {
        if (lhs[k] != rhs[k]) {
          diffs.add('$label: $k (${lhs[k] == null ? "absent" : rhs[k] == null ? "extra" : "differs"})');
        }
      }
    }

    compare('run-a vs run-b', runs['a']!, runs['b']!);
    compare('run-a vs committed', runs['a']!, committed);

    final ok = diffs.isEmpty;
    final detail = StringBuffer(
      'emitted twice from frozen input/design.json; '
      '${runs['a']!.length} files per run, byte-compared against the committed '
      'tree (pubspec.lock + .dart_tool excluded)',
    );
    if (!ok) {
      for (final d in diffs.take(8)) {
        detail.write('\n      $d');
      }
    }
    report.check('3. second run byte-identical', ok, detail.toString());
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

/// Repo-relative path -> exact bytes (base64) for every file under [dir] except
/// pub artifacts, which are not emitter output. Byte-exact by construction —
/// no digest, so "identical" here means identical, not merely non-colliding.
Map<String, String> _hashTree(Directory dir) {
  final out = <String, String>{};
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(dir.path.length).replaceAll(RegExp(r'^/'), '');
    if (rel == 'pubspec.lock' || rel.startsWith('.dart_tool/')) continue;
    out[rel] = base64Encode(f.readAsBytesSync());
  }
  return out;
}

// =============================================================== verdict 4 ===
void _verdictInspectAttrs(ProbeReport report, Directory root, Directory showcaseLib) {
  // Both open decisions that made this verdict circular are now CLOSED, so the
  // probe verifies against ratified sources instead of asserting a shape of its
  // own invention:
  //   (a) the Dart shape is `AppBoxKitInspectAttrs` in kit core;
  //   (b) the anatomy-node vocabulary is a CLOSED set at
  //       skills/appbox-scaffolder/kind-resolution.registry.json (v1.2.0).
  // Showcase was back-stamped at the same ratification, so it is NORMATIVE here
  // and no longer exempt — the corroboration is now a real gate on both trees.
  final vocab = _anatomyVocabulary(root);
  if (vocab.isEmpty) {
    report.check(
      '4. inspectAttrs (vocabulary)',
      false,
      'BLOCKED: no closed anatomy-node vocabulary at '
      'skills/appbox-scaffolder/kind-resolution.registry.json#/anatomyNodes/vocabulary. '
      'Without the ratified set there is nothing to check membership against.',
    );
    return;
  }

  // Showcase screenIds must be verbatim intake/registry.json entry ids. This is
  // the join that class-name convention cannot reproduce (app-architecture.md:169).
  _inspectAttrsLine(
    report,
    title: '4. inspectAttrs triple on every showcase surface (normative, back-stamped)',
    subject: 'showcase',
    lib: showcaseLib,
    vocab: vocab,
    allowedScreenIds: _showcaseRegistryIds(root),
    screenIdSource: 'kit/showcase_app/intake/registry.json entry ids',
  );

  final golden = _goldenTree(root);
  if (golden == null) {
    report.check(
      '4b. inspectAttrs triple on every emitted surface',
      false,
      'BLOCKED: no emitted tree at tool/spike-q11-shells/golden — the emitter did '
      'not run, so there is nothing to gate.',
    );
    return;
  }
  // The emitted tree is held to the same ratified sources. Its screenIds must be
  // values carried by the FROZEN design input, not strings the emitter invented.
  _inspectAttrsLine(
    report,
    title: '4b. inspectAttrs triple on every emitted surface (same ratified gate)',
    subject: 'spike',
    lib: Directory('${golden.path}/lib/ui/views'),
    vocab: vocab,
    allowedScreenIds: _designScreenIds(root),
    screenIdSource: 'screenId values declared in tool/spike-q11-shells/input/design.json',
  );
}

/// The ratified closed anatomy-node vocabulary. Empty set = not ratified.
Set<String> _anatomyVocabulary(Directory root) {
  final f = File('${root.path}/skills/appbox-scaffolder/kind-resolution.registry.json');
  if (!f.existsSync()) return <String>{};
  final nodes = (jsonDecode(f.readAsStringSync()) as Map)['anatomyNodes'];
  if (nodes is! Map) return <String>{};
  final vocab = nodes['vocabulary'];
  if (vocab is Map) return vocab.keys.cast<String>().toSet();
  if (vocab is List) return vocab.cast<String>().toSet();
  return <String>{};
}

/// Verbatim entry ids from the showcase intake registry.
Set<String> _showcaseRegistryIds(Directory root) {
  final f = File('${root.path}/kit/showcase_app/intake/registry.json');
  if (!f.existsSync()) return <String>{};
  final decoded = jsonDecode(f.readAsStringSync());
  final entries = decoded is List ? decoded : (decoded as Map)['entries'] as List;
  return entries.map((e) => (e as Map)['id'] as String).toSet();
}

/// The `screenId` values DECLARED by the frozen spike design input — not any
/// string that happens to appear in it. "Any string" would let the app name or a
/// label satisfy the join, which is not a join at all.
Set<String> _designScreenIds(Directory root) {
  final f = File('${root.path}/tool/spike-q11-shells/input/design.json');
  if (!f.existsSync()) return <String>{};
  final out = <String>{};
  void walk(dynamic n) {
    if (n is List) n.forEach(walk);
    if (n is Map) {
      final v = n['screenId'];
      if (v is String) out.add(v);
      n.values.forEach(walk);
    }
  }
  walk(jsonDecode(f.readAsStringSync()));
  return out;
}

/// One inspectAttrs gate over a `lib/ui/views` tree: the triple is present on
/// every view, its anatomyNodeId is inside the closed vocabulary, and its
/// screenId comes from the declared source rather than from a name convention.
void _inspectAttrsLine(
  ProbeReport report, {
  required String title,
  required String subject,
  required Directory lib,
  required Set<String> vocab,
  required Set<String> allowedScreenIds,
  required String screenIdSource,
}) {
  String? cap(String src, String key) =>
      RegExp("$key:\\s*'([^']+)'").firstMatch(src)?.group(1);

  if (allowedScreenIds.isEmpty) {
    report.check(
      title,
      false,
      'BLOCKED: $screenIdSource yielded no ids, so the screenId join cannot be '
      'checked. Reporting red rather than degrading to a presence-only pass.',
    );
    return;
  }

  final surfaces = <String>[];
  final failures = <String>[];
  for (final f in lib.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('_view.dart')) continue;
    final rel = f.path.substring(lib.path.length + 1);
    surfaces.add(rel);
    final src = f.readAsStringSync();
    final screenId = cap(src, 'screenId');
    final surfaceId = cap(src, 'surfaceId');
    final anatomyNodeId = cap(src, 'anatomyNodeId');
    final absent = <String>[
      if (screenId == null) 'screenId',
      if (surfaceId == null) 'surfaceId',
      if (anatomyNodeId == null) 'anatomyNodeId',
    ];
    if (absent.isNotEmpty) {
      failures.add('$rel — missing ${absent.join(", ")}');
      continue;
    }
    if (!vocab.contains(anatomyNodeId)) {
      failures.add("$rel — anatomyNodeId '$anatomyNodeId' outside the closed vocabulary");
    }
    if (!allowedScreenIds.contains(screenId)) {
      failures.add("$rel — screenId '$screenId' is not in $screenIdSource");
    }
  }

  final ok = surfaces.isNotEmpty && failures.isEmpty;
  final detail = StringBuffer(
    '$subject: ${surfaces.length} view files, each carrying the inspectAttrs triple; '
    'every anatomyNodeId inside the closed vocabulary (${vocab.length} member'
    '${vocab.length == 1 ? '' : 's'}, kind-resolution.registry.json); every screenId '
    'drawn from $screenIdSource.',
  );
  for (final m in failures.take(8)) {
    detail.write('\n      $m');
  }
  if (surfaces.isEmpty) detail.write('\n      no _view.dart files found under ${lib.path}');
  report.check(title, ok, detail.toString());
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
  _frontmatterLine(
    report,
    root: root,
    lib: showcaseLib,
    subject: 'showcase',
    title: '5. frontmatter conventions (Q5, enforced against showcase)',
  );

  // Same rule, same function, applied to the spike's emitted tree.
  final golden = _goldenTree(root);
  if (golden == null) {
    report.check('5b. frontmatter conventions (spike tree)', false,
        'BLOCKED: no emitted tree at tool/spike-q11-shells/golden.');
    return;
  }
  _frontmatterLine(
    report,
    root: root,
    lib: Directory('${golden.path}/lib'),
    subject: 'spike',
    title: '5b. frontmatter conventions (Q5, enforced against the emitted tree)',
  );
}

/// Q5 frontmatter, applied to one `lib/` directory.
void _frontmatterLine(
  ProbeReport report, {
  required Directory root,
  required Directory lib,
  required String subject,
  required String title,
}) {
  final viewsDir = Directory('${lib.path}/ui/views');
  if (!viewsDir.existsSync()) {
    report.check(title, false, 'no $subject views at ${viewsDir.path}');
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
  final detail = StringBuffer('$subject: $checked view/viewmodel files checked, '
      '${failures.length} non-conforming');
  if (!ok) {
    for (final x in failures.take(10)) {
      detail.write('\n      $x');
    }
    if (failures.length > 10) detail.write('\n      … ${failures.length - 10} more');
  }
  report.check(title, ok, detail.toString());
}
