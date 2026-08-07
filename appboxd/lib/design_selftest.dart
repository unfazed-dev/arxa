// The designer selftest, ported from skills/appbox-designer/selftest.sh
// (Task 21). `appbox design selftest [artifact-dir] [--negative]`.
//
// A check that has never been observed failing is not a check, it is a line
// that runs. The baseline asserts the structural contract holds against a
// known-good artifact; `--negative` re-runs one targeted check per mutation
// and requires the named check to flip — proving every check can fail.
//
// The ~25 checks are ported in selftest.sh's order, keeping the labels and the
// `ok` / `FAIL <label>` / `passed N, failed M` output contract. The
// `--negative` summary is `proven N, unproven M`. Exit codes: 64 usage/unknown
// flag, 65 baseline-red/unclaimed, non-zero on any failure.
//
// The /tmp guard from the .sh (mutations refusing to run outside temp dirs) is
// structural here: the mutation runner only ever operates on its own temp copy.

library;

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/design_selftest_kit_catalog_mirror.dart';
import 'package:appboxd/design_server.dart';
import 'package:appboxd/design_tools.dart';
// The W-gate owns the placement vocabulary (homes, the include graph). Reusing
// it keeps ONE parser for `{% include %}`/`{% import %}` rather than a second
// that can drift from the gate the same artifacts are linted against.
import 'package:appboxd/gate_design_widgets.dart'
    show buildIncludeGraph, isRetiredFlatWidget, isWidget, widgetHomeOf;
import 'package:appboxd/project.dart';
import 'package:path/path.dart' as p;

// ══ result types ════════════════════════════════════════════════════════

/// One check's outcome. [summary] (check 1 only) prints as an indented echo
/// after the `ok` line, mirroring the bash selftest's registry summary.
class CheckOutcome {
  final bool ok;
  final bool skipped;
  final String detail;
  final String? summary;
  const CheckOutcome.ok([this.detail = ''])
      : ok = true,
        skipped = false,
        summary = null;
  const CheckOutcome.okWithSummary(this.summary)
      : ok = true,
        skipped = false,
        detail = '';
  const CheckOutcome.fail([this.detail = ''])
      : ok = false,
        skipped = false,
        summary = null;
  const CheckOutcome.skip([this.detail = ''])
      : ok = false,
        skipped = true,
        summary = null;
}

/// Full selftest outcome — exit code + every output line + parsed label sets.
class SelftestResult {
  final int exitCode;
  final List<String> stdoutLines;
  final List<String> stderrLines;
  final List<String> okLabels;
  final List<String> failLabels;
  final List<String> skipLabels;
  final int? provenCount;
  final int? unprovenCount;
  const SelftestResult({
    required this.exitCode,
    this.stdoutLines = const [],
    this.stderrLines = const [],
    this.okLabels = const [],
    this.failLabels = const [],
    this.skipLabels = const [],
    this.provenCount,
    this.unprovenCount,
  });
  int get passedCount => okLabels.length;
  int get failedCount => failLabels.length;
  String get stdoutText => stdoutLines.join('\n');
  String get stderrText => stderrLines.join('\n');
}

// ══ check labels (single source of truth — checks + mutations share them) ══

const _lRegistry = 'registry parses with required keys';
const _lExclusions = 'no exclusions.json — surface:null is the exclusion';
const _lSurfaceId = 'every viewmodel declares surfaceId';
const _lSurfaceJoin = 'every surfaceId joins a registry entry';
const _lCoverage = 'every buildable registry entry has a surface';
const _lShellRoots = 'app.routes.js exports a non-empty shellRoots';
const _lRepoImport = 'no viewmodel imports a repository directly';
const _lFixtures = 'fixtures record their seed provenance';
const _lArbParity = 'ARB catalogs have key parity across locales';
const _lLadderDoc = 'references/viewport-ladder.md exists';
const _lLadderConfig = 'runtime/ladder.json exists — the ladder is config, not code';
const _lLadderDrift = 'ladder.json and viewport-ladder.md agree; no rung on a boundary';
const _lLadderHardcode = 'no ladder width hardcoded in skill code';
const _lUpstreamLeak = 'no upstream references outside LICENSE';
const _lFullReload = 'no mutation answers with a full reload';
const _lFragments = 'every rendered fragment exists as a macro';
const _lMutationsPosted = 'every mutation route is reachable from markup';
const _lUrlsResolve = 'every static URL in markup resolves to a route';
const _lTargetsExist = 'every hx-target names an element that exists';
const _lWidgets = 'widgets live in the three-tier homes and surfaces compose them';
const _lIcons = 'icons come from the icon() global, never emoji stand-ins';
const _lGit = 'every artifact file is tracked by git';
const _lLint = 'zero-custom-client-JS lint';
const _lRender = 'every GET route answers 200';
const _lKitCatalogMirror = 'kit-catalog.md mirrors every kit in kit-registry.json';

// ══ internal types ══════════════════════════════════════════════════════

enum _Section { structure, render }

typedef _CheckFn = Future<CheckOutcome> Function(String art, String skill, String src);

class _Check {
  final String label;
  final _Section section;
  final _CheckFn run;
  const _Check(this.label, this.section, this.run);
}

class _Mutation {
  final String name;
  final String label;
  final bool wantOk;
  final void Function(String art, String skill) apply;
  const _Mutation(this.name, this.label, this.wantOk, this.apply);
  bool get targetsSkill =>
      name.startsWith('ladder-') ||
      name == 'upstream-leak' ||
      name == 'kit-catalog-row';
}

// ══ helpers ═════════════════════════════════════════════════════════════

List<File> _walkFiles(Directory d) =>
    d.listSync(recursive: true).whereType<File>().toList();

/// Artifact-root-relative POSIX path of [f] under [art].
String _relOf(String art, File f) =>
    p.split(p.relative(f.path, from: art)).join('/');

/// Widgets sitting in one of the three legal homes: `ui/common/widgets/`,
/// `ui/views/<shell>/shared/widgets/`, `<surface>/widgets/`.
///
/// [widgetHomeOf] returns null for every non-home, the retired flat tier
/// included, so this is exactly "is a widget AND has a home". The retired-tier
/// predicate is imported rather than restated: two spellings of the same list
/// drift, and W1 and this check must agree on what counts as migrated.
bool _isThreeTierWidget(String rel) =>
    isWidget(rel) && widgetHomeOf(rel) != null;

List<String> _threeTierWidgets(String art) =>
    (_htmlFiles(art).map((f) => _relOf(art, f)).where(_isThreeTierWidget).toList()
      ..sort());

List<String> _legacyFlatWidgets(String art) =>
    (_htmlFiles(art).map((f) => _relOf(art, f)).where(isRetiredFlatWidget).toList()
      ..sort());

List<File> _htmlFiles(String dir) => _walkFiles(Directory(dir))
    .where((f) => f.path.endsWith('.html') || f.path.endsWith('.tsx'))
    .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// One swept GET route + the route module that declared it.
class _Route {
  final String path;
  final String module;
  const _Route(this.path, this.module);

  /// Project-backed shells render from the overlaid `~/.appbox` project, so
  /// their routes only answer with a project mounted. Named by module, not by
  /// path prefix, so the set stays right when intake/build go project-aware.
  bool get projectBacked => _projectBackedModules.contains(module);
}

/// Route modules whose surfaces render from the live project overlay.
const _projectBackedModules = {'routes.design.js'};

final _getRouteRe = RegExp(r"""\[\s*['"]GET['"]\s*,\s*['"]([^'"]+)['"]""");
final _routeImportRe = RegExp(r"""from\s+['"](\.[^'"]+)['"]""");

/// Every GET route the artifact serves: the literals in `app.routes.js` plus
/// those in the route modules it imports. Regexing app.routes.js alone sees
/// only the routes spelled there — the shells that `import ... routes.*.js`
/// would go unswept, which is most of them.
List<_Route> _getRoutes(String art) {
  final entry = File(p.join(art, 'app.routes.js'));
  if (!entry.existsSync()) return const [];
  final entrySrc = entry.readAsStringSync();
  final out = <_Route>[
    for (final m in _getRouteRe.allMatches(entrySrc))
      _Route(m.group(1)!, 'app.routes.js'),
  ];
  // Follow the relative imports whose basename is `routes.*.js` — the naming
  // convention for a shell's route table.
  for (final m in _routeImportRe.allMatches(entrySrc)) {
    final rel = m.group(1)!;
    final base = p.basename(rel);
    if (!base.startsWith('routes.') || !base.endsWith('.js')) continue;
    final f = File(p.normalize(p.join(art, rel)));
    if (!f.existsSync()) continue;
    for (final r in _getRouteRe.allMatches(f.readAsStringSync())) {
      out.add(_Route(r.group(1)!, base));
    }
  }
  final seen = <String>{};
  return out.where((r) => seen.add(r.path)).toList();
}

List<File> _viewModels(String dir) => _walkFiles(Directory(p.join(dir, 'ui', 'views')))
    .where((f) => f.path.endsWith('_viewmodel.js'))
    .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

List<File> _allViewModels(String dir) => _walkFiles(Directory(p.join(dir, 'ui')))
    .where((f) => f.path.endsWith('_viewmodel.js'))
    .toList();

String? _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/config/appbox.config.json').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

String _defaultSkillDir() {
  final repo = _findRepoRoot() ?? Directory.current.path;
  return p.join(repo, 'skills', 'appbox-designer');
}

Future<Directory> _copyDirToTemp(String src, String prefix) async {
  final tmp = await Directory.systemTemp.createTemp(prefix);
  for (final f in _walkFiles(Directory(src))) {
    if (RegExp(r'[/\\]node_modules([/\\]|$)').hasMatch(f.path)) continue;
    final rel = p.relative(f.path, from: src);
    final out = File(p.join(tmp.path, rel))..createSync(recursive: true);
    out.writeAsBytesSync(f.readAsBytesSync());
  }
  return tmp;
}

// ══ the 25 checks ═══════════════════════════════════════════════════════

/// Build the check list. [skipRender] is captured by the render check so the
/// runner can avoid booting Chrome when the caller opts out.
List<_Check> _buildChecks({required bool skipRender}) {
  return [
    // --- 1. the registry parses and has the required keys -----------------
    _Check(_lRegistry, _Section.structure, (art, skill, src) async {
      final f = File(p.join(art, 'models', 'screens_model', 'registry.json'));
      try {
        final r = jsonDecode(f.readAsStringSync());
        if (r is! List || r.isEmpty) {
          return const CheckOutcome.fail('registry is not a non-empty array');
        }
        const need = ['id', 'label', 'surface', 'shell', 'comp'];
        final bad = <String>[];
        for (final e in r) {
          for (final k in need) {
            if (e is! Map || !e.containsKey(k)) bad.add('${e?['id'] ?? '?'}: $k');
          }
        }
        if (bad.isNotEmpty) return CheckOutcome.fail(bad.join('; '));
        final buildable = r.where((e) => (e as Map)['surface'] != null).length;
        final excluded = r.length - buildable;
        return CheckOutcome.okWithSummary(
            '{total: ${r.length}, buildable: $buildable, excluded: $excluded}');
      } catch (e) {
        return CheckOutcome.fail(e.toString());
      }
    }),

    // --- 2. no separate exclusions list ------------------------------------
    _Check(_lExclusions, _Section.structure, (art, skill, src) async {
      if (File(p.join(art, 'exclusions.json')).existsSync()) {
        return const CheckOutcome.fail('exclusions.json exists');
      }
      return const CheckOutcome.ok();
    }),

    // --- 3. every viewmodel declares a surfaceId ---------------------------
    _Check(_lSurfaceId, _Section.structure, (art, skill, src) async {
      final missing = _viewModels(art)
          .where((f) => !f.readAsStringSync().contains('export const surfaceId'))
          .map((f) => p.relative(f.path, from: art))
          .toList();
      if (missing.isNotEmpty) return CheckOutcome.fail('missing in: ${missing.join(", ")}');
      return const CheckOutcome.ok();
    }),

    // --- 4. every declared surfaceId resolves to a registry entry ----------
    _Check(_lSurfaceJoin, _Section.structure, (art, skill, src) async {
      final reg = jsonDecode(
          File(p.join(art, 'models', 'screens_model', 'registry.json')).readAsStringSync());
      final ids = (reg as List).map((e) => (e as Map)['id'] as String).toSet();
      final bad = <String>[];
      for (final f in _viewModels(art)) {
        final m = RegExp(r"""export const surfaceId\s*=\s*['"]([^'"]+)""")
            .firstMatch(f.readAsStringSync());
        if (m == null) continue;
        if (!ids.contains(m.group(1))) {
          bad.add('${p.basename(f.path)}: surfaceId "${m.group(1)}" matches no registry entry');
        }
      }
      if (bad.isNotEmpty) return CheckOutcome.fail(bad.join('; '));
      return const CheckOutcome.ok();
    }),

    // --- 5. coverage: buildable entries have a viewmodel -------------------
    _Check(_lCoverage, _Section.structure, (art, skill, src) async {
      final reg = jsonDecode(
          File(p.join(art, 'models', 'screens_model', 'registry.json')).readAsStringSync());
      final declared = <String>{};
      for (final f in _viewModels(art)) {
        final m = RegExp(r"""surfaceId\s*=\s*['"]([^'"]+)""")
            .firstMatch(f.readAsStringSync());
        if (m != null) declared.add(m.group(1)!);
      }
      final bad = <String>[];
      for (final e in reg as List) {
        final entry = e as Map;
        if (entry['surface'] != null && !declared.contains(entry['id'])) {
          bad.add('registry "${entry['id']}" is buildable but no viewmodel declares it');
        }
      }
      if (bad.isNotEmpty) return CheckOutcome.fail(bad.join('; '));
      return const CheckOutcome.ok();
    }),

    // --- 6. shellRoots exported and non-empty ------------------------------
    _Check(_lShellRoots, _Section.structure, (art, skill, src) async {
      final src2 = File(p.join(art, 'app.routes.js')).readAsStringSync();
      final m = RegExp(r'export\s+const\s+shellRoots\s*=\s*\{([^}]*)\}').firstMatch(src2);
      if (m == null) return const CheckOutcome.fail('shellRoots not exported');
      final body = m.group(1)!;
      final keys = RegExp(r'(\w+)\s*:').allMatches(body).map((m) => m.group(1)!).join(', ');
      if (keys.isEmpty) return const CheckOutcome.fail('shellRoots is empty');
      return CheckOutcome.okWithSummary(keys);
    }),

    // --- 7. viewmodels do not reach past facades ---------------------------
    _Check(_lRepoImport, _Section.structure, (art, skill, src) async {
      final leak = _walkFiles(Directory(p.join(art, 'ui')))
          .where((f) => f.path.endsWith('.js'))
          .where((f) => f.readAsStringSync().contains('repositories/'))
          .map((f) => p.relative(f.path, from: art))
          .toList();
      if (leak.isNotEmpty) return CheckOutcome.fail(leak.join(' '));
      return const CheckOutcome.ok();
    }),

    // --- 8. fixtures are generated, not authored ---------------------------
    // The designer-side kit mirror. Lives in its own file (authored while
    // another agent held appboxd/lib) — the registration is here because
    // _Check/_Section are library-private.
    _Check(_lKitCatalogMirror, _Section.structure, kitCatalogMirrorCheck),
    _Check(_lFixtures, _Section.structure, (art, skill, src) async {
      final ungen = _walkFiles(Directory(p.join(art, 'models')))
          .where((f) => RegExp(r'_fixtures.*\.json$').hasMatch(p.basename(f.path)))
          .where((f) => !f.readAsStringSync().contains('_generated_from'))
          .map((f) => p.relative(f.path, from: art))
          .toList();
      if (ungen.isNotEmpty) return CheckOutcome.fail(ungen.join(' '));
      return const CheckOutcome.ok();
    }),

    // --- 8b. ARB catalogs mirror the en catalog key-for-key ----------------
    _Check(_lArbParity, _Section.structure, (art, skill, src) async {
      final l10nDir = Directory(p.join(art, 'l10n'));
      if (!l10nDir.existsSync()) return const CheckOutcome.ok('no l10n/ — nothing to check');
      final keys = <String, List<String>>{};
      for (final f in l10nDir.listSync().whereType<File>()) {
        if (!RegExp(r'^app_.+\.arb$').hasMatch(p.basename(f.path))) continue;
        final entries = parseArb(f.path);
        keys[p.basename(f.path)] = entries.keys
            .where((k) => !k.startsWith('@'))
            .toList()
          ..sort();
      }
      final files = keys.keys.toList()..sort();
      if (files.length < 2) return const CheckOutcome.ok();
      final baseName = keys.containsKey('app_en.arb') ? 'app_en.arb' : files.first;
      final base = keys[baseName]!;
      final bad = <String>[];
      for (final f in files) {
        if (f == baseName) continue;
        final missing = base.where((k) => !keys[f]!.contains(k)).toList();
        final extra = keys[f]!.where((k) => !base.contains(k)).toList();
        if (missing.isNotEmpty || extra.isNotEmpty) {
          bad.add('$f: missing [${missing.join(",")}] extra [${extra.join(",")}] vs $baseName');
        }
      }
      if (bad.isNotEmpty) return CheckOutcome.fail(bad.join('; '));
      return const CheckOutcome.ok();
    }),

    // --- 9. the ladder is documented, configured, and unhardcoded ----------
    _Check(_lLadderDoc, _Section.structure, (art, skill, src) async {
      if (!File(p.join(skill, 'references', 'viewport-ladder.md')).existsSync()) {
        return const CheckOutcome.fail('references/viewport-ladder.md missing');
      }
      return const CheckOutcome.ok();
    }),

    _Check(_lLadderConfig, _Section.structure, (art, skill, src) async {
      if (!File(p.join(skill, 'runtime', 'ladder.json')).existsSync()) {
        return const CheckOutcome.fail('runtime/ladder.json missing');
      }
      return const CheckOutcome.ok();
    }),

    _Check(_lLadderDrift, _Section.structure, (art, skill, src) async {
      final cfgFile = File(p.join(skill, 'runtime', 'ladder.json'));
      final docFile = File(p.join(skill, 'references', 'viewport-ladder.md'));
      if (!cfgFile.existsSync() || !docFile.existsSync()) {
        return const CheckOutcome.fail('ladder config or doc missing');
      }
      final problems = checkLadderFromInputs(
          cfg: cfgFile.readAsStringSync(), docText: docFile.readAsStringSync());
      if (problems.isNotEmpty) return CheckOutcome.fail(problems.join('; '));
      return const CheckOutcome.ok();
    }),

    _Check(_lLadderHardcode, _Section.structure, (art, skill, src) async {
      // Non-recursive globs matching the bash: runtime/*.mjs, runtime/lib/*.mjs,
      // agents/*.mjs (NOT agents/tests/*.mjs — the bash glob is top-level only).
      final files = <File>[];
      for (final d in ['runtime', p.join('runtime', 'lib'), 'agents']) {
        final dp = Directory(p.join(skill, d));
        if (dp.existsSync()) {
          files.addAll(dp.listSync().whereType<File>()
              .where((f) => f.path.endsWith('.mjs')));
        }
      }
      final hardRe = RegExp(r'\b(390|744|1280)\b');
      final bad = <String>[];
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('ladder-exempt:')) continue;
          if (hardRe.hasMatch(lines[i])) {
            bad.add('${p.relative(f.path, from: skill)}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      if (bad.isNotEmpty) return CheckOutcome.fail(bad.join('\n'));
      return const CheckOutcome.ok();
    }),

    // --- 10. no upstream identity leaked -----------------------------------
    _Check(_lUpstreamLeak, _Section.structure, (art, skill, src) async {
      final tokens = ['kimi', 'baoyu', 'huashu', 'jimliu', 'flutter-crew'];
      final re = RegExp(tokens.map(RegExp.escape).join('|'), caseSensitive: false);
      final bad = <String>[];
      for (final f in _walkFiles(Directory(skill))) {
        final name = p.basename(f.path);
        if (name == 'LICENSE' || name == 'selftest.sh') continue;
        if (RegExp(r'[/\\]node_modules([/\\]|$)').hasMatch(f.path)) continue;
        try {
          if (re.hasMatch(f.readAsStringSync())) {
            bad.add(p.relative(f.path, from: skill));
          }
        } catch (_) {} // binary — skip
      }
      if (bad.isNotEmpty) return CheckOutcome.fail(bad.join(' '));
      return const CheckOutcome.ok();
    }),

    // --- 11. mutations answer with a swap, not a full page reload ----------
    _Check(_lFullReload, _Section.structure, (art, skill, src) async {
      final bad = <String>[];
      for (final f in _allViewModels(art)) {
        final lines = f.readAsLinesSync();
        var lastExempt = -99;
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('refresh-exempt:')) lastExempt = i;
          if (RegExp(r'h\.refresh\(').hasMatch(lines[i]) && i - lastExempt > 4) {
            bad.add('${p.relative(f.path, from: art)}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      if (bad.isNotEmpty) return CheckOutcome.fail(bad.take(3).join(' '));
      return const CheckOutcome.ok();
    }),

    // --- 12-15. wiring: the artifact must DO something ---------------------
    _Check(_lFragments, _Section.structure, (art, skill, src) async {
      final problems = checkWiringArtifact(art, 'fragments');
      if (problems.isNotEmpty) return CheckOutcome.fail(problems.join('; '));
      return const CheckOutcome.ok();
    }),

    _Check(_lMutationsPosted, _Section.structure, (art, skill, src) async {
      final problems = checkWiringArtifact(art, 'mutations-posted');
      if (problems.isNotEmpty) return CheckOutcome.fail(problems.join('; '));
      return const CheckOutcome.ok();
    }),

    _Check(_lUrlsResolve, _Section.structure, (art, skill, src) async {
      final problems = checkWiringArtifact(art, 'urls-resolve');
      if (problems.isNotEmpty) return CheckOutcome.fail(problems.join('; '));
      return const CheckOutcome.ok();
    }),

    _Check(_lTargetsExist, _Section.structure, (art, skill, src) async {
      final problems = checkWiringArtifact(art, 'targets-exist');
      if (problems.isNotEmpty) return CheckOutcome.fail(problems.join('; '));
      return const CheckOutcome.ok();
    }),

    // --- 16-17. component library + icons ----------------------------------
    _Check(_lWidgets, _Section.structure, (art, skill, src) async {
      final tiered = _threeTierWidgets(art);
      final legacy = _legacyFlatWidgets(art);

      if (tiered.isNotEmpty) {
        // Mixed is the dangerous state: half the tree has moved and half has
        // not, so neither the law nor the old shape describes it. Name the
        // stragglers — whoever is mid-migration should see they are theirs.
        if (legacy.isNotEmpty) {
          return CheckOutcome.fail(
              'widgets in the three-tier homes AND in the retired flat tier: '
              '${legacy.join(', ')} — move each to ui/common/widgets/, '
              'ui/views/<shell>/shared/widgets/ or <surface>/widgets/');
        }
        final graph = buildIncludeGraph(art);
        final composed =
            tiered.where((w) => (graph[w] ?? const <String>{}).isNotEmpty).length;
        if (composed == 0) {
          return CheckOutcome.fail(
              'widgets exist in the three-tier homes but nothing includes or '
              'imports any of them: ${tiered.join(', ')}');
        }
        return CheckOutcome.ok(
            '${tiered.length} widget(s) in three-tier homes, $composed composed');
      }

      if (legacy.isNotEmpty) {
        // Transition tolerance, deliberately not a failure: `design lint` W1
        // already fails each of these and names its three-tier destination, so
        // hard-failing here would only duplicate that with a worse message.
        return CheckOutcome.ok(
            '${legacy.length} widget(s) still in the retired flat tier — '
            '`design lint` W1 names the three-tier destination for each');
      }

      // No widgets anywhere: the artifact must at least carry a shared macro
      // library under ui/common (the pre-widget generation's shape).
      final commonDir = Directory(p.join(art, 'ui', 'common'));
      final found = commonDir.existsSync() &&
          _walkFiles(commonDir)
              .where((f) => f.path.endsWith('.html'))
              .any((f) => RegExp(r'\{%\s*macro').hasMatch(f.readAsStringSync()));
      if (!found) {
        return const CheckOutcome.fail(
            'no widgets in the three-tier homes (ui/common/widgets/, '
            'ui/views/<shell>/shared/widgets/, <surface>/widgets/) and no macro '
            'in ui/common');
      }
      return const CheckOutcome.ok();
    }),

    _Check(_lIcons, _Section.structure, (art, skill, src) async {
      final emojiRe = RegExp(
          r'[\u{2190}-\u{21FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{1F000}-\u{1FAFF}\u{FE0F}]',
          unicode: true);
      final bad = <String>[];
      for (final f in _htmlFiles(art)) {
        // Comments are prose, not chrome — an arrow in a comment is not an
        // icon stand-in (same rule as the wiring checks).
        for (final m in emojiRe.allMatches(stripComments(f.readAsStringSync()))) {
          bad.add('${p.relative(f.path, from: art)}: found ${m[0]}');
          if (bad.length >= 3) break;
        }
        if (bad.length >= 3) break;
      }
      if (bad.isNotEmpty) return CheckOutcome.fail(bad.join(' '));
      final hasIcon = _walkFiles(Directory(p.join(art, 'ui')))
          .where((f) => f.path.endsWith('.html') || f.path.endsWith('.tsx'))
          .any((f) {
        final src = f.readAsStringSync();
        // Legacy: {{ icon('name') }} in .html. TSX: <Icon name="..." /> component.
        return src.contains("icon('") || src.contains('<Icon');
      });
      if (!hasIcon) return const CheckOutcome.fail("no icon(' or <Icon> usage found in ui/");
      return const CheckOutcome.ok();
    }),

    // --- 18. the tree the gates read is the tree git has -------------------
    _Check(_lGit, _Section.structure, (art, skill, src) async {
      final toplevel = Process.runSync('git', ['-C', src, 'rev-parse', '--show-toplevel']);
      if (toplevel.exitCode != 0) {
        return const CheckOutcome.skip('not a git work tree; nothing to be inconsistent with');
      }
      final tracked = Process.runSync('git', ['-C', src, 'ls-files', '-z', '.']);
      final trackedSet = (tracked.stdout as String)
          .split('\x00')
          .where((s) => s.isNotEmpty)
          .toSet();
      final artFiles = _walkFiles(Directory(art))
          .map((f) => p.relative(f.path, from: art).split(p.separator).join('/'))
          .toSet();
      final untracked = artFiles.difference(trackedSet).toList()..sort();
      if (untracked.isNotEmpty) {
        // Deliberately git-ignored files are not artifact — a hook's scratch
        // (.claude-flow/) must not be able to fail this check. git itself is
        // the authority on what "ignored" means; an unignored stray still
        // fails, which the untracked-file mutation proves.
        // No -z: it is stdin-only for check-ignore (fatal otherwise), and a
        // 128 here must not silently exempt nothing — artifact paths are
        // plain enough for line splitting.
        final ig = Process.runSync(
            'git', ['-C', src, 'check-ignore', '--', ...untracked]);
        final ignored = (ig.stdout as String)
            .split('\n')
            .where((s) => s.isNotEmpty)
            .toSet();
        final strays = untracked.where((f) => !ignored.contains(f)).toList();
        if (strays.isNotEmpty) return CheckOutcome.fail(strays.join(' '));
      }
      return const CheckOutcome.ok();
    }),

    // --- 19. zero-custom-client-JS lint (pure Dart — always available) -----
    _Check(_lLint, _Section.render, (art, skill, src) async {
      final findings = lintArtifact(art);
      if (findings.isNotEmpty) return CheckOutcome.fail(findings.map((f) => '$f').join('; '));
      return const CheckOutcome.ok();
    }),

    // --- 20. render: every GET route answers 200 ---------------------------
    _Check(_lRender, _Section.render, (art, skill, src) async {
      if (skipRender) {
        return const CheckOutcome.skip('render section skipped (no Chrome)');
      }
      try {
        if (!File(CdpClient.defaultChromePath()).existsSync()) {
          return const CheckOutcome.skip('Chrome not found — render gate unverified');
        }
      } catch (e) {
        return CheckOutcome.skip('Chrome not found: $e');
      }
      DesignServer? srv;
      try {
        // The route-200 sweep serves the artifact WITH the current project
        // overlaid (the studio live-reads ~/.appbox) when one exists — the
        // smoke-test project is part of the artifact's render contract.
        final projDir = Directory(projectDir(currentProject())).existsSync()
            ? projectDir(currentProject())
            : null;
        srv = await DesignServer.start(
            artifactDir: art, port: 0, noWatch: true, projectDir: projDir);
        final routes = _getRoutes(art);
        // With no project mounted the project-backed shells have no model to
        // render and answer 500. Sweep the rest and name the gap in the summary
        // — a silently narrowed sweep is the failure this check exists to catch.
        final swept = projDir != null
            ? routes
            : routes.where((r) => !r.projectBacked).toList();
        final held = routes.length - swept.length;
        final client = HttpClient();
        final bad = <String>[];
        try {
          for (final r in swept) {
            final req = await client.getUrl(Uri.parse('${srv.url}${r.path.substring(1)}'));
            final res = await req.close();
            await utf8.decoder.bind(res).join();
            // Any 2xx: an empty tray legitimately answers 204, not 200.
            if (res.statusCode ~/ 100 != 2) {
              bad.add('GET ${r.path} -> ${res.statusCode}');
            }
          }
        } finally {
          client.close(force: true);
        }
        if (bad.isNotEmpty) return CheckOutcome.fail(bad.join('; '));
        return CheckOutcome.okWithSummary(held == 0
            ? '${swept.length} GET routes swept'
            : '${swept.length} GET routes swept; $held held back — no project '
                'mounted (${_projectBackedModules.join(", ")})');
      } catch (e) {
        // FAIL, not skip. A boot failure means the render half of the suite
        // never ran, and a skip is reported green: a duplicate `export const`
        // in a facade took the whole artifact down, made every route
        // unreachable, and the run still summarised `passed 23, failed 0`,
        // exit 0. The only signal was the check count quietly dropping by one.
        // `--skip-render` remains the way to opt out of this section on
        // purpose; a crash is not an opt-out.
        return CheckOutcome.fail('render boot failed: $e');
      } finally {
        await srv?.stop();
      }
    }),
  ];
}

// ══ the 25-row mutation table ═══════════════════════════════════════════

final List<_Mutation> _mutations = [
  _Mutation('registry-key', _lRegistry, false, _mutateRegistryKey),
  _Mutation('exclusions-file', _lExclusions, false, _mutateExclusionsFile),
  _Mutation('surface-id', _lSurfaceId, false, _mutateSurfaceId),
  _Mutation('orphan-id', _lSurfaceJoin, false, _mutateOrphanId),
  _Mutation('uncovered-entry', _lCoverage, false, _mutateUncoveredEntry),
  _Mutation('empty-shellroots', _lShellRoots, false, _mutateEmptyShellRoots),
  _Mutation('repo-import', _lRepoImport, false, _mutateRepoImport),
  _Mutation('fixture-provenance', _lFixtures, false, _mutateFixtureProvenance),
  _Mutation('arb-parity', _lArbParity, false, _mutateArbParity),
  _Mutation('ladder-doc', _lLadderDoc, false, _mutateLadderDoc),
  _Mutation('ladder-config', _lLadderConfig, false, _mutateLadderConfig),
  _Mutation('ladder-drift', _lLadderDrift, false, _mutateLadderDrift),
  _Mutation('ladder-hardcode', _lLadderHardcode, false, _mutateLadderHardcode),
  _Mutation('upstream-leak', _lUpstreamLeak, false, _mutateUpstreamLeak),
  _Mutation('full-reload', _lFullReload, false, _mutateFullReload),
  _Mutation('fragment-typo', _lFragments, false, _mutateFragmentTypo),
  _Mutation('orphan-post', _lMutationsPosted, false, _mutateOrphanPost),
  _Mutation('dead-url', _lUrlsResolve, false, _mutateDeadUrl),
  _Mutation('dangling-target', _lTargetsExist, false, _mutateDanglingTarget),
  _Mutation('emoji-icon', _lIcons, false, _mutateEmojiIcon),
  _Mutation('widget-partials', _lWidgets, false, _mutateWidgetPartials),
  _Mutation('untracked-file', _lGit, false, _mutateUntrackedFile),
  _Mutation('client-js', _lLint, false, _mutateClientJs),
  // The inverse row: a commented ban is NOT a violation — the lint must still pass.
  _Mutation('commented-js', _lLint, true, _mutateCommentedJs),
  _Mutation('kit-catalog-row', _lKitCatalogMirror, false, _mutateKitCatalogRow),
  _Mutation('broken-route', _lRender, false, _mutateBrokenRoute),
];

// ── mutation implementations (ported one-for-one from selftest.sh) ────────

void _mutateRegistryKey(String art, String skill) {
  final f = File(p.join(art, 'models', 'screens_model', 'registry.json'));
  final r = jsonDecode(f.readAsStringSync()) as List;
  (r[0] as Map).remove('label');
  f.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(r)}\n');
}

void _mutateExclusionsFile(String art, String skill) {
  File(p.join(art, 'exclusions.json')).writeAsStringSync('');
}

void _mutateSurfaceId(String art, String skill) {
  final vms = _viewModels(art);
  if (vms.isEmpty) return;
  final f = vms.first;
  final lines = f
      .readAsLinesSync()
      .where((l) => !l.contains('export const surfaceId'))
      .toList();
  f.writeAsStringSync('${lines.join('\n')}\n');
}

void _mutateOrphanId(String art, String skill) {
  final vms = _viewModels(art);
  if (vms.isEmpty) return;
  final f = vms.first;
  final src = f.readAsStringSync();
  f.writeAsStringSync(src.replaceFirstMapped(
      RegExp(r"""(surfaceId\s*=\s*["'])[^"']+"""), (m) => '${m[1]}zzz.nope'));
}

void _mutateUncoveredEntry(String art, String skill) {
  final f = File(p.join(art, 'models', 'screens_model', 'registry.json'));
  final r = jsonDecode(f.readAsStringSync()) as List;
  r.add({'id': 'zzz.ghost', 'label': 'Ghost', 'surface': 'ghost_view', 'shell': 'main', 'comp': 'Ghost'});
  f.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(r)}\n');
}

void _mutateEmptyShellRoots(String art, String skill) {
  final f = File(p.join(art, 'app.routes.js'));
  f.writeAsStringSync(f.readAsStringSync().replaceFirst(
      RegExp(r'export const shellRoots\s*=\s*\{[^}]*\}'), 'export const shellRoots = {}'));
}

void _mutateRepoImport(String art, String skill) {
  final vms = _viewModels(art);
  if (vms.isEmpty) return;
  final f = vms.first;
  f.writeAsStringSync('${f.readAsStringSync()}\n// reaches services/repositories/x.js directly\n');
}

void _mutateFixtureProvenance(String art, String skill) {
  final files = _walkFiles(Directory(p.join(art, 'models')))
      .where((f) => RegExp(r'_fixtures.*\.json$').hasMatch(p.basename(f.path)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) return;
  final f = files.first;
  final lines = f.readAsLinesSync().where((l) => !l.contains('_generated_from')).toList();
  f.writeAsStringSync('${lines.join('\n')}\n');
}

void _mutateArbParity(String art, String skill) {
  final l10nDir = Directory(p.join(art, 'l10n'));
  if (!l10nDir.existsSync()) return;
  File? target;
  for (final f in l10nDir.listSync().whereType<File>()) {
    if (RegExp(r'^app_(?!en[.])[^/]+\.arb$').hasMatch(p.basename(f.path))) {
      target = f;
      break;
    }
  }
  if (target == null) return;
  final j = parseArb(target.path);
  final keys = j.keys.where((k) => !k.startsWith('@')).toList();
  if (keys.isEmpty) return;
  j.remove(keys.first);
  target.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(j)}\n');
}

void _mutateLadderDoc(String art, String skill) {
  final f = File(p.join(skill, 'references', 'viewport-ladder.md'));
  if (f.existsSync()) f.deleteSync();
}

void _mutateLadderConfig(String art, String skill) {
  final f = File(p.join(skill, 'runtime', 'ladder.json'));
  if (f.existsSync()) f.deleteSync();
}

void _mutateLadderDrift(String art, String skill) {
  final f = File(p.join(skill, 'runtime', 'ladder.json'));
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final compact = (j['rungs'] as Map)['compact'] as Map;
  compact['width'] = (compact['width'] as num).toInt() + 1;
  f.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(j)}\n');
}

void _mutateLadderHardcode(String art, String skill) {
  // The scanned globs (runtime/*.mjs …) no longer exist in the ported skill
  // — write the probe file rather than appending to a dropped one.
  File(p.join(skill, 'runtime', 'console-check.mjs'))
      .writeAsStringSync('const _probe = 390;\n');
}

void _mutateUpstreamLeak(String art, String skill) {
  File(p.join(skill, 'LEAK.md')).writeAsStringSync('kimi\n');
}

void _mutateFullReload(String art, String skill) {
  final vms = _viewModels(art);
  if (vms.isEmpty) return;
  final f = vms.first;
  f.writeAsStringSync("${f.readAsStringSync()}\nexport const _probe = (c, h) => h.refresh(c);\n");
}

void _mutateFragmentTypo(String art, String skill) {
  // Rename a fragment a viewmodel actually renders — renaming an
  // unreferenced fragment (shared partials) would prove nothing.
  for (final vm in _viewModels(art)) {
    final src = vm.readAsStringSync();
    final frag = RegExp(r'\$\{VIEW\}#(\w+)').firstMatch(src);
    if (frag == null) continue;
    final named =
        RegExp(r"""const VIEW\s*=\s*['"]([^'"]+)['"]""").firstMatch(src);
    if (named == null) continue;
    // View refs keep .html paths for registry parity; post-migration the
    // actual file is .tsx (same resolution as the 'fragments' wiring check).
    var view = File(p.join(art, named.group(1)!));
    if (!view.existsSync()) {
      final tsx = File(view.path.replaceAll(RegExp(r'\.html$'), '.tsx'));
      if (tsx.existsSync()) view = tsx;
    }
    if (!view.existsSync()) continue;
    final tpl = view.readAsStringSync();
    if (view.path.endsWith('.tsx')) {
      // TSX: the fragment is an exported component, PascalCase of the ref
      // (#tick → Tick) — mirror the check's lookup.
      final n = frag.group(1)!;
      final comp = n[0].toUpperCase() + n.substring(1);
      final re = RegExp(r'(export\s+(?:default\s+)?(?:function|const)\s+)' +
          RegExp.escape(comp) +
          r'\b');
      if (!re.hasMatch(tpl)) continue;
      view.writeAsStringSync(tpl.replaceFirst(re, '\${1}${comp}zz'));
      return;
    }
    final re = RegExp(r'(\{%\s*macro\s+)' + RegExp.escape(frag.group(1)!) + r'\b');
    if (!re.hasMatch(tpl)) continue;
    view.writeAsStringSync(
        tpl.replaceFirst(re, '\${1}${frag.group(1)}zz'));
    return;
  }
}

void _mutateKitCatalogRow(String art, String skill) {
  // Drop one kit's table row from the mirror doc — prose mentions stay, so
  // only a row-scoped check can see it (the check's own header comment).
  final f = File(p.join(skill, 'references', 'kit-catalog.md'));
  if (!f.existsSync()) return;
  final lines = f.readAsLinesSync();
  final idx = lines.indexWhere(
      (l) => l.trimLeft().startsWith('|') && l.contains('`'));
  if (idx < 0) return;
  lines.removeAt(idx);
  f.writeAsStringSync('${lines.join('\n')}\n');
}

void _mutateOrphanPost(String art, String skill) {
  // A route no markup sends to must be caught. (Removing one hx-post no
  // longer orphans anything: senders multiply — boosted forms, templated
  // and annotated sends cover the same route.)
  final f = File(p.join(art, 'app.routes.js'));
  f.writeAsStringSync(
      "${f.readAsStringSync()}\n['POST', '/__orphan-post', null],\n");
}

void _mutateDeadUrl(String art, String skill) {
  for (final f in _htmlFiles(art)) {
    final src = f.readAsStringSync();
    final re = RegExp(r'href="/(?!assets/|_ds/)[^"{]*"');
    if (re.hasMatch(src)) {
      f.writeAsStringSync(src.replaceFirst(re, 'href="/zzz-nope"'));
      return;
    }
  }
}

void _mutateDanglingTarget(String art, String skill) {
  for (final f in _htmlFiles(art)) {
    final src = f.readAsStringSync();
    final re = RegExp(r'hx-target="#[^"]*"');
    if (re.hasMatch(src)) {
      f.writeAsStringSync(src.replaceFirst(re, 'hx-target="#zznope"'));
      return;
    }
  }
}

void _mutateEmojiIcon(String art, String skill) {
  final files = _htmlFiles(art);
  if (files.isEmpty) return;
  final f = files.first;
  f.writeAsStringSync('${f.readAsStringSync()}\n<p>\u2192</p>\n');
}

void _mutateWidgetPartials(String art, String skill) {
  // Remove the widget layer wherever it lives — the three-tier homes and the
  // retired flat tier both — so the mutation keeps biting through the
  // migration, not just while the artifact is still flat.
  //
  // FILES, not directories: deleting `ui/common/` would take `base.html` with
  // it and redden neighbouring checks, which masks whether THIS check flipped.
  var removed = 0;
  for (final f in _htmlFiles(art)) {
    final rel = _relOf(art, f);
    if (_isThreeTierWidget(rel) || isRetiredFlatWidget(rel)) {
      f.deleteSync();
      removed++;
    }
  }
  // An artifact with no widget layer at all falls through to the ui/common
  // macro-library branch; strip its macros so the mutation still lands.
  if (removed > 0) return;
  final common = Directory(p.join(art, 'ui', 'common'));
  if (!common.existsSync()) return;
  for (final f in _walkFiles(common).where((f) => f.path.endsWith('.html'))) {
    final src = f.readAsStringSync();
    if (RegExp(r'\{%\s*macro').hasMatch(src)) {
      f.writeAsStringSync(src.replaceAll(RegExp(r'\{%\s*macro'), '{# macro'));
    }
  }
}

void _mutateUntrackedFile(String art, String skill) {
  File(p.join(art, 'ui', 'stray.txt')).writeAsStringSync('stray\n');
}

void _mutateClientJs(String art, String skill) {
  final files = _htmlFiles(art);
  if (files.isEmpty) return;
  final f = files.first;
  f.writeAsStringSync('${f.readAsStringSync()}\n<div hx-on:click="alert(1)"></div>\n');
}

void _mutateCommentedJs(String art, String skill) {
  final files = _htmlFiles(art);
  if (files.isEmpty) return;
  final f = files.first;
  f.writeAsStringSync("${f.readAsStringSync()}\n{# hx-on:click is banned here — ADR-0002 #}\n");
}

void _mutateBrokenRoute(String art, String skill) {
  final f = File(p.join(art, 'app.routes.js'));
  final src = f.readAsStringSync();
  final re = RegExp(r"""\[\s*['"]GET['"]\s*,\s*(['"][^'"]+['"])\s*,\s*[^\]]+\]""");
  f.writeAsStringSync(src.replaceFirstMapped(
      re, (m) => "['GET', ${m[1]}, () => { throw new Error('mutation'); }]"));
}

// ══ the runner ══════════════════════════════════════════════════════════

/// Run the designer selftest.
///
/// [artifactDir] — the artifact to check.
/// [skillDir] — the designer skill (ladder/upstream checks target it);
///   defaults to the repo's `skills/appbox-designer`.
/// [srcDir] — original source for the git-tracking check; defaults to
///   [artifactDir]. In negative mode this is the unmutated original so the
///   git check compares mutated-copy files against real tracking.
/// [negative] — run falsifiability mode (one targeted check per mutation).
/// [skipRender] — skip the Chrome render section (lint still runs).
/// [mutations] — in negative mode, run only these mutation rows (null = all).
Future<SelftestResult> runSelftest({
  required String artifactDir,
  String? skillDir,
  String? srcDir,
  bool negative = false,
  bool skipRender = false,
  List<String>? mutations,
}) async {
  final skill = skillDir ?? _defaultSkillDir();
  final src = srcDir ?? artifactDir;
  final checks = _buildChecks(skipRender: skipRender);
  if (negative) {
    return _runNegative(
        art: artifactDir, skill: skill, src: src, checks: checks, mutationNames: mutations);
  }
  return _runPositive(art: artifactDir, skill: skill, src: src, checks: checks);
}

Future<SelftestResult> _runPositive({
  required String art,
  required String skill,
  required String src,
  required List<_Check> checks,
}) async {
  final out = <String>['artifact: $art', ''];
  final ok = <String>[], fail = <String>[], skip = <String>[];
  _Section? prev;
  for (final c in checks) {
    if (c.section != prev) {
      out.add('');
      out.add(c.section == _Section.structure ? '== structure ==' : '== render ==');
      prev = c.section;
    }
    final r = await c.run(art, skill, src);
    if (r.skipped) {
      out.add('  skip  ${c.label}${r.detail.isNotEmpty ? ' — ${r.detail}' : ''}');
      skip.add(c.label);
    } else if (r.ok) {
      out.add('  ok   ${c.label}');
      if (r.summary != null) out.add('       ${r.summary}');
      ok.add(c.label);
    } else {
      out.add('  FAIL ${c.label}${r.detail.isNotEmpty ? ' — ${r.detail}' : ''}');
      fail.add(c.label);
    }
  }
  out.add('');
  // The skipped count and the total ride on the summary line on purpose: a run
  // that quietly stopped executing a check used to print exactly what a full
  // green run prints. `passed 23, failed 0, skipped 1 of 24` cannot be mistaken
  // for `passed 24, failed 0, skipped 0 of 24` at a glance or in a log grep.
  out.add('passed ${ok.length}, failed ${fail.length}, '
      'skipped ${skip.length} of ${checks.length}');
  return SelftestResult(
    exitCode: fail.isEmpty ? 0 : 1,
    stdoutLines: out,
    okLabels: ok,
    failLabels: fail,
    skipLabels: skip,
  );
}

Future<SelftestResult> _runNegative({
  required String art,
  required String skill,
  required String src,
  required List<_Check> checks,
  List<String>? mutationNames,
}) async {
  final base = await _runPositive(art: art, skill: skill, src: src, checks: checks);

  // The baseline must be green — a check already failing gets "proven" by every
  // mutation, the free pass that is the exact shape of the defect this mode kills.
  if (base.failedCount > 0) {
    return SelftestResult(
      exitCode: 65,
      stderrLines: [
        'baseline is not green — mutations cannot prove anything against it:',
        ...base.failLabels.map((l) => '  FAIL $l'),
      ],
      okLabels: base.okLabels,
      failLabels: base.failLabels,
      skipLabels: base.skipLabels,
    );
  }

  final names = mutationNames ?? _mutations.map((m) => m.name).toList();

  // Every baseline label must be claimed by some mutation row — an unclaimed
  // check would be reported proven without ever being tested (full-set only).
  if (mutationNames == null) {
    final claimed = <String>{};
    for (final m in _mutations) {
      claimed.add(m.label);
    }
    final unmapped = <String>[];
    for (final l in [...base.okLabels, ...base.skipLabels]) {
      if (!claimed.any((c) => l.startsWith(c))) unmapped.add(l);
    }
    if (unmapped.isNotEmpty) {
      return SelftestResult(
        exitCode: 65,
        stderrLines: [
          'checks with no mutation — they would be reported proven without ever '
              'being tested: ${unmapped.join("; ")}',
        ],
        okLabels: base.okLabels,
        failLabels: base.failLabels,
        skipLabels: base.skipLabels,
      );
    }
  }

  final out = <String>[
    'artifact: $art',
    '',
    ...base.stdoutLines.sublist(2), // skip the repeated artifact header
    '',
    '== falsifiability: one check per mutation ==',
  ];
  var proven = 0, unproven = 0;

  for (final name in names) {
    final mut = _findMutation(name);
    if (mut == null) {
      out.add('  FAIL unknown mutation: $name');
      unproven++;
      continue;
    }
    // A check the baseline skipped cannot be proven here either.
    if (base.skipLabels.contains(mut.label)) {
      out.add('  skip  $name — "${mut.label}" does not apply to this artifact');
      continue;
    }
    // Fresh throwaway copies — the mutation runner never touches the original.
    final tmpArt = await _copyDirToTemp(art, 'selftest-neg-$name-');
    final skillTmpDir =
        mut.targetsSkill ? await _copyDirToTemp(skill, 'selftest-neg-skill-') : null;
    final tmpSkillPath = skillTmpDir?.path ?? skill;
    try {
      mut.apply(tmpArt.path, tmpSkillPath);
      final check = checks.where((c) => c.label == mut.label).first;
      final r = await check.run(tmpArt.path, tmpSkillPath, src);
      if (mut.wantOk) {
        if (r.ok && !r.skipped) {
          out.add('  ok   $name leaves "${mut.label}" passing');
          proven++;
        } else {
          out.add('  FAIL $name broke "${mut.label}" — a comment is not behaviour');
          unproven++;
        }
      } else {
        if (!r.ok && !r.skipped) {
          out.add('  ok   "${mut.label}" catches $name');
          proven++;
        } else {
          out.add('  FAIL "${mut.label}" did NOT fail under $name — the check cannot detect it');
          unproven++;
        }
      }
    } finally {
      await tmpArt.delete(recursive: true);
      await skillTmpDir?.delete(recursive: true);
    }
  }

  out.add('');
  out.add('proven $proven, unproven $unproven');
  return SelftestResult(
    exitCode: unproven == 0 ? 0 : 1,
    stdoutLines: out,
    okLabels: base.okLabels,
    failLabels: base.failLabels,
    skipLabels: base.skipLabels,
    provenCount: proven,
    unprovenCount: unproven,
  );
}

// ══ public mutation helpers (for tests) ═════════════════════════════════

_Mutation? _findMutation(String name) {
  for (final m in _mutations) {
    if (m.name == name) return m;
  }
  return null;
}

/// Apply a named mutation to the [artifactDir] / [skillDir] pair. Throws
/// [ArgumentError] for an unknown mutation name (exit 64 at the CLI).
void applyMutation(String name, String artifactDir, String skillDir) {
  final mut = _findMutation(name);
  if (mut == null) throw ArgumentError('unknown mutation: $name');
  mut.apply(artifactDir, skillDir);
}

/// The check label a mutation targets.
String mutationLabel(String name) {
  final mut = _findMutation(name);
  if (mut == null) throw ArgumentError('unknown mutation: $name');
  return mut.label;
}

// ══ CLI entry ═══════════════════════════════════════════════════════════

/// `appbox design selftest [artifact-dir] [--negative]` — returns the exit code.
Future<int> designSelftestMain(List<String> args) async {
  String? src;
  var negative = false;
  for (final a in args) {
    if (a == '--negative') {
      negative = true;
    } else if (a.startsWith('-')) {
      stderr.writeln('unknown flag: $a');
      return 64;
    } else {
      src = a;
    }
  }
  // Default to the skill's starter example. A path that does not exist is a
  // FAILURE, never a silent fallback.
  if (src != null) {
    if (!Directory(src).existsSync()) {
      stderr.writeln('no such artifact dir: $src');
      return 64;
    }
  } else {
    src = p.join(_defaultSkillDir(), 'examples', 'hello-hda');
  }
  final r = await runSelftest(artifactDir: src, negative: negative);
  for (final l in r.stdoutLines) {
    stdout.writeln(l);
  }
  for (final l in r.stderrLines) {
    stderr.writeln(l);
  }
  return r.exitCode;
}
