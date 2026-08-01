// scaffold — Dart port of skills/appbox-scaffolder/scaffold.py (860 lines).
//
// THE CONTRACT
//   The structure gate (gates/structure) asserts the authored layer
//   (registry.json + ui/views/**) matches structure.json. This engine is the
//   INVERSE: it reads a FROZEN structure.json + the target set and PRODUCES the
//   per-surface Dart tree the coverage gate (gates/coverage) then asserts.
//
//   Form factors FOLLOW TARGETS (architecture §16). --targets macos derives
//   [desktop] -> three files/surface (_view.dart + _view.desktop.dart +
//   _viewmodel.dart). --targets ios,android derives [mobile, tablet] -> four
//   files/surface. The set is read from the derivation table + config viewports
//   (P06), NEVER a per-surface literal. An empty .mobile/.tablet is never emitted
//   to satisfy a counter — a file that exists, passes the check, and is never
//   rendered is the stale-green pattern §16 exists to kill.
//
//   The engine emits STRUCTURE. The widget bodies are the builder's job (plan 08):
//   every file is a minimal valid Dart skeleton carrying the class name the
//   builder implements, marked as a stub. It does not compile Dart; it produces
//   the file set + the .shell-structure.json manifest the coverage gate reads.
//
//   Directory naming is a scaffolder DECISION, recorded in the manifest (the
//   coverage gate refuses to guess it). The decision here: dir = <shell>_<short>
//   from the registry id — the stable key §18 says must never be reused — which is
//   single-segment by construction and matches the existing app convention
//   (projects_home/, settings_kits/) and the coverage gate's dir==file-prefix rule.
//
//   The OPTIONAL l10n layer: when the design carries l10n/*.arb catalogs, they are
//   copied verbatim into lib/l10n/ and a fixed-contract l10n.yaml (gen-l10n) is
//   dropped at the app root; the manifest records the locale set so gates can read
//   it. A design with no l10n/ dir gets NO l10n artifacts (backward compat).
//
// Pure stdlib (dart:io + dart:convert). Exit: 0 emitted / in-sync ·
// 1 missing input, drift, wrong count.

import 'dart:convert';
import 'dart:io';

import 'mem_b.dart';

/// The gen-l10n config is a FIXED contract — gates assert it verbatim, so it is
/// a constant, never templated. (synthetic-package deliberately absent: the SDK
/// deprecated it — output always lands in the package now.)
const l10nYaml = '''arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
nullable-getter: false
''';

final _arbRe = RegExp(r'app_([A-Za-z0-9_]+)\.arb$');

// ----------------------------------------------------------- derivation

/// The P06 rule: union each target's viewports (resolving `inherits`), ordered
/// by the config viewports table. Widths live ONLY in config (R3) — names here
/// reference config viewports; this returns names, never widths.
///
/// Mirrors gates/coverage's resolve()+FACTORS exactly so the producer and the
/// gate agree on what "derived form-factor set" means. Throws [FormatException]
/// naming any unknown target (an operator may only pass a target the table
/// declares).
List<String> deriveFactors(
    List<String> targets, String derivationPath, String configPath) {
  final tbl = (jsonDecode(File(derivationPath).readAsStringSync())
      as Map<String, dynamic>)['targets'] as Map<String, dynamic>;
  final cfgVps = (jsonDecode(File(configPath).readAsStringSync())
      as Map<String, dynamic>)['viewports'] as Map<String, dynamic>;

  final unknown = targets.where((t) => !tbl.containsKey(t)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException(
        'unknown target(s): ${unknown.join(', ')} — add an entry to '
        'pipeline/state/targets.derivation.json (P06: targets are data, '
        'never inferred)');
  }

  List<String> vpsOf(String t, Set<String> seen) {
    if (seen.contains(t)) return []; // cycle guard
    seen.add(t);
    final e = tbl[t] as Map<String, dynamic>;
    final out = <String>[...(e['viewports'] as List).cast<String>()];
    final inherits = e['inherits'] as String?;
    if (inherits != null) {
      out.insertAll(0, vpsOf(inherits, seen));
    }
    return out;
  }

  final union = <String>[];
  for (final t in targets) {
    for (final v in vpsOf(t, <String>{})) {
      if (!union.contains(v)) union.add(v);
    }
  }
  // config order; names the table forgot to put in config are dropped (R3).
  return cfgVps.keys.where((v) => union.contains(v)).toList();
}

// ----------------------------------------------------------- naming

/// dir = `<shell>_<short>` from the screen id (the registry's stable key, §18).
/// Single segment by construction; matches the existing app convention
/// (projects_home/, settings_kits/) and the coverage gate's d==file-prefix
/// contract. Throws [FormatException] on a non-2-part id.
String surfaceDir(Map<String, dynamic> screen) {
  final sid = screen['id'] as String;
  final parts = sid.split('.');
  if (parts.length != 2) {
    throw FormatException(
        "screen id '$sid' is not <shell>.<short> — cannot derive a directory");
  }
  return '${parts[0]}_${parts[1]}';
}

/// desktop -> Desktop (no lowercasing of the tail).
String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// stage_shell -> StageShell (the shell's class-name convention).
String _pascal(String snake) =>
    snake.split('_').map(_cap).join();

// ----------------------------------------------------------- dart stubs

/// The base _view.dart — the router's entry point. Declares `<comp>View` over its
/// viewmodel. Does NOT wire the form-factor switch: that is the builder's job
/// (plan 08), so the derived factors are recorded in the header, not faked with
/// imports the stub does not yet use.
String _stubView(
    Map<String, dynamic> screen, List<String> factors, List<String> targets) {
  final comp = screen['comp'] as String;
  final d = surfaceDir(screen);
  final fl = factors.isNotEmpty ? factors.join(', ') : '(none)';
  final deps = (screen['deps'] as List?)?.cast<String>() ?? <String>[];
  final depsLine = deps.isNotEmpty
      ? '//   deps (builder wires): ${deps.join(', ')}\n'
      : '';
  final kits = (screen['kits'] as List?)?.cast<String>() ?? <String>[];
  final kitsLine = kits.isNotEmpty
      ? '//   kits (builder wires): ${kits.join(', ')}\n'
      : '';
  final surface = screen['surface'] as String;
  final sid = screen['id'] as String;
  final shellDir = screen['shellDir'] as String;
  return '// appbox-scaffolder: surface skeleton. STRUCTURE ONLY — the builder fills this.\n'
      '//   surface:       $surface\n'
      '//   comp:          ${comp}View\n'
      '//   id:            $sid\n'
      '//   shell:         $shellDir\n'
      '//   targets:       [${targets.join(',')}] -> derived form factors [$fl]\n'
      '$depsLine'
      '$kitsLine'
      '// The widget tree and the form-factor switch are the builder\'s job (plan 08).\n'
      "import 'package:flutter/material.dart';\n"
      "import 'package:stacked/stacked.dart';\n"
      '\n'
      "import '${d}_viewmodel.dart';\n"
      '\n'
      'class ${comp}View extends StackedView<${comp}ViewModel> {\n'
      '  const ${comp}View({super.key});\n'
      '\n'
      '  @override\n'
      '  Widget builder(context, viewModel, child) => const Scaffold(\n'
      "        body: Center(child: Text('$sid')),\n"
      '      );\n'
      '\n'
      '  @override\n'
      '  ${comp}ViewModel viewModelBuilder(context) => ${comp}ViewModel();\n'
      '}\n';
}

/// One _view.`<factor>`.dart per DERIVED factor. macos derives desktop only, so
/// no .mobile/.tablet is ever produced for a macos target (§16).
String _stubFactor(
    Map<String, dynamic> screen, String factor, List<String> targets) {
  final comp = screen['comp'] as String;
  final d = surfaceDir(screen);
  final fc = _cap(factor);
  final surface = screen['surface'] as String;
  final sid = screen['id'] as String;
  return '// appbox-scaffolder: $factor layout skeleton. STRUCTURE ONLY — builder fills this.\n'
      '//   surface:       $surface\n'
      '//   comp:          ${comp}View$fc\n'
      '//   factor:        $factor   (derived from targets=[${targets.join(',')}])\n'
      "import 'package:flutter/material.dart';\n"
      "import 'package:stacked/stacked.dart';\n"
      '\n'
      "import '${d}_viewmodel.dart';\n"
      '\n'
      'class ${comp}View$fc extends ViewModelWidget<${comp}ViewModel> {\n'
      '  const ${comp}View$fc({super.key});\n'
      '\n'
      '  @override\n'
      '  Widget build(context, viewModel) => const Scaffold(\n'
      "        body: Center(child: Text('$sid · $factor')),\n"
      '      );\n'
      '}\n';
}

/// The `<comp>ViewModel` skeleton over BaseViewModel (stacked 3.x). The builder
/// wires the services the structure recorded in `deps`.
String _stubViewmodel(Map<String, dynamic> screen) {
  final comp = screen['comp'] as String;
  final deps = (screen['deps'] as List?)?.cast<String>() ?? <String>[];
  final depsLine = deps.isNotEmpty
      ? '//   deps (builder wires): ${deps.join(', ')}\n'
      : '';
  final kits = (screen['kits'] as List?)?.cast<String>() ?? <String>[];
  final kitsLine = kits.isNotEmpty
      ? '//   kits (builder wires): ${kits.join(', ')}\n'
      : '';
  final surface = screen['surface'] as String;
  return '// appbox-scaffolder: view model skeleton. STRUCTURE ONLY — builder fills this.\n'
      '//   surface:       $surface\n'
      '//   comp:          ${comp}ViewModel\n'
      '$depsLine'
      '$kitsLine'
      '// TODO(appbox-builder): wire services from the deps above.\n'
      "import 'package:stacked/stacked.dart';\n"
      '\n'
      'class ${comp}ViewModel extends BaseViewModel {}\n';
}

/// The design-system.md every surface dir must carry (the review gate's
/// design_system_doc check). STRUCTURE ONLY — the builder fills the real intent.
String _designSystemDoc(Map<String, dynamic> screen, List<String> factors) {
  final surface = screen['surface'] as String;
  final sid = screen['id'] as String;
  final shellDir = screen['shellDir'] as String;
  final fl = factors.isNotEmpty ? factors.join(', ') : '(none)';
  return '# design-system — $surface\n'
      '\n'
      '> appbox-scaffolder: STRUCTURE ONLY. The builder (plan 08) fills the real intent.\n'
      '\n'
      '- **surface:** `$surface`  ($sid)\n'
      '- **shell:**  $shellDir\n'
      '- **derived form factors:** $fl\n'
      '\n'
      '## Palette\n'
      '<!-- builder: KitColors.* tokens this surface uses -->\n'
      '\n'
      '## Type\n'
      '<!-- builder: KitTypography.* roles -->\n'
      '\n'
      '## Spacing\n'
      '<!-- builder: spacing tokens (no ad-hoc SizedBox gaps) -->\n'
      '\n'
      '## Motion\n'
      '<!-- builder: KitMotion.* curves/durations -->\n'
      '\n'
      '## Forbidden\n'
      '- `Icons.*` (use `KitGlyphs.*`)\n'
      '- ad-hoc `Color(0x…)` (use `KitColors.*`)\n'
      '- stock `ElevatedButton`/`FilledButton`/`TextButton` CTAs (use `KitNativeButton`)\n';
}

/// The shell-level design-system.md the scaffold gate (S4) requires at
/// views/`<shell>`/design-system.md. STRUCTURE ONLY.
String _shellDesignSystemDoc(String shell) {
  return '# design-system — $shell (shell)\n'
      '\n'
      '> appbox-scaffolder: STRUCTURE ONLY. The builder (plan 08) fills the real intent.\n'
      '\n'
      '## Palette\n'
      "- `KitColors` — the shell's palette source (builder: name the kc* tokens)\n"
      '\n'
      '## Type\n'
      '<!-- builder: KitTypography.* roles -->\n'
      '\n'
      '## Spacing\n'
      '<!-- builder: spacing tokens (no ad-hoc SizedBox gaps) -->\n'
      '\n'
      '## Motion\n'
      '<!-- builder: KitMotion.* curves/durations -->\n'
      '\n'
      '## Forbidden\n'
      '- `Icons.*` (use `KitGlyphs.*`)\n'
      '- ad-hoc `Color(0x…)` (use `KitColors.*`)\n'
      '- stock CTA buttons (use `KitNativeButton`)\n';
}

/// The *_chrome.dart every self-contained shell owns (scaffold gate S6).
/// STRUCTURE ONLY.
String _shellChrome(String shell) {
  final comp = _pascal(shell);
  return '// appbox-scaffolder: shell chrome skeleton. STRUCTURE ONLY — builder fills this.\n'
      '//   shell:  $shell\n'
      '//   The chrome is the shell\'s persistent frame (nav rail / tabs / gate badge).\n'
      '//   S6 (scaffold gate) requires every self-contained shell to own a chrome or a\n'
      "//   widgets/ home; this stub satisfies ownership. The builder wires the layout.\n"
      "import 'package:flutter/material.dart';\n"
      '\n'
      'class ${comp}Chrome {\n'
      '  const ${comp}Chrome();\n'
      '}\n';
}

// ----------------------------------------------------------- l10n

/// The optional l10n layer: a frozen design may carry l10n/*.arb catalogs
/// (app_`<locale>`.arb). Returns the sorted catalog filenames, or null when the
/// design has no l10n/ dir — backward compat: no l10n artifacts are emitted.
/// Throws [FormatException] on a malformed catalog name or a missing app_en.arb.
List<String>? designL10n(String designRoot) {
  final d = Directory('$designRoot/l10n');
  if (!d.existsSync()) return null;
  final files = d
      .listSync()
      .whereType<File>()
      .map((f) => f.path.split('/').last)
      .where((fn) => fn.endsWith('.arb'))
      .toList()
    ..sort();
  if (files.isEmpty) return null; // kimitail: an empty l10n/ dir = absent
  for (final fn in files) {
    if (!_arbRe.hasMatch(fn)) {
      throw FormatException(
          'l10n/$fn is not app_<locale>.arb — locales are derived from the '
          'catalog filenames, so this name is unparseable');
    }
  }
  if (!files.contains('app_en.arb')) {
    throw FormatException(
        'l10n/ has no app_en.arb — the l10n.yaml contract fixes '
        'template-arb-file: app_en.arb, so the English catalog is required');
  }
  return files;
}

/// app_`<locale>`.arb -> locale, for the manifest the gates read.
List<String> l10nLocales(List<String> files) =>
    files.map((fn) => _arbRe.firstMatch(fn)!.group(1)!).toList();

/// Copy the design's ARB catalogs verbatim into lib/l10n/ and drop the fixed
/// l10n.yaml at the app root.
void _emitL10n(String designRoot, String appRoot, List<String> files) {
  final dst = '$appRoot/lib/l10n';
  Directory(dst).createSync(recursive: true);
  for (final fn in files) {
    final data = File('$designRoot/l10n/$fn').readAsBytesSync();
    File('$dst/$fn').writeAsBytesSync(data);
  }
  File('$appRoot/l10n.yaml').writeAsStringSync(l10nYaml);
}

// ----------------------------------------------------------- manifest

/// The .shell-structure.json the coverage gate reads: selfContained shells +
/// the {shell: {surfaceId: dir}} map. The dir is the scaffolder's recorded
/// decision.
Map<String, dynamic> buildManifest(
    List<Map<String, dynamic>> frozen, List<String> factors, List<String> targets,
    [List<String>? l10n]) {
  final shells = <String>{};
  for (final s in frozen) {
    shells.add(s['shellDir'] as String);
  }
  final sortedShells = shells.toList()..sort();
  final byShell = <String, Map<String, String>>{
    for (final sh in sortedShells) sh: <String, String>{},
  };
  for (final s in frozen) {
    byShell[s['shellDir'] as String]![s['surface'] as String] = surfaceDir(s);
  }
  final fl = factors.isNotEmpty ? factors.join(', ') : 'none';
  final m = <String, dynamic>{
    'selfContained': sortedShells,
    'surfaces': byShell,
    // the DERIVED form-factor set (§16): macos -> [desktop], never the full
    // mobile+tablet+desktop. The review gate (form_factor_files) reads this.
    'factors': factors,
    'targets': targets,
    'notes': 'scaffolded by appbox-scaffolder from a frozen structure.json; '
        'targets=[${targets.join(',')}] -> form factors [$fl]; '
        'dir=<shell>_<short> from the registry id (the stable key, §18). '
        "Widget bodies are the builder's job (plan 08).",
  };
  if (l10n != null) {
    m['l10n'] = {'arbDir': 'lib/l10n', 'locales': l10nLocales(l10n)};
  }
  // Per-surface kit declarations (kit dir names only), recorded for the
  // builder. Omitted entirely when no surface declares kits, so existing
  // apps' manifests don't drift.
  final kitsBySurface = <String, List<String>>{
    for (final s in frozen)
      if ((s['kits'] as List?)?.isNotEmpty ?? false)
        s['surface'] as String: (s['kits'] as List).cast<String>(),
  };
  if (kitsBySurface.isNotEmpty) m['kits'] = kitsBySurface;
  return m;
}

// ----------------------------------------------------------- io

void _fail(String msg) => stderr.writeln('FAIL: $msg');

/// Read + sanity-check the frozen structure.json. Returns (data, null) on
/// success or (null, error) on failure.
({Map<String, dynamic>? data, String? error}) loadStructure(String designRoot) {
  final path = '$designRoot/structure.json';
  final f = File(path);
  if (!f.existsSync()) {
    return (
      data: null,
      error: 'structure.json not found under $designRoot — scaffold needs a '
          'FROZEN structure.json. Run emit_structure first, or point '
          'KIT_DESIGN_DIR at the producer folder.',
    );
  }
  Map<String, dynamic> data;
  try {
    data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    return (data: null, error: 'structure.json does not parse as JSON — $e');
  }
  final screens = data['screens'];
  if (screens is! List) {
    return (
      data: null,
      error: "structure.json 'screens' is not a list — not a structure.json",
    );
  }
  return (data: data, error: null);
}

/// Every frozen surface must carry the keys the scaffold emits from. Also
/// enforces the 2-part id (`<shell>.<short>`) so [surfaceDir] never throws
/// downstream — a clean exit 1, not a crash. Returns true on success.
bool _validateFrozen(List<Map<String, dynamic>> frozen) {
  for (final s in frozen) {
    for (final req in ['id', 'comp', 'shellDir', 'surface', 'viewmodel']) {
      final v = s[req];
      if (v == null || (v is String && v.isEmpty)) {
        final who = (s['id'] ?? s['surface'] ?? '?') as String;
        _fail("screen '$who' declares a surface '${s['surface']}' but has no "
            "'$req' — structure.json is malformed (a frozen surface without a "
            'viewmodel is exactly what emit_structure refuses to produce; this '
            'one slipped through)');
        return false;
      }
    }
    // 2-part id enforcement: <shell>.<short>.
    final sid = s['id'] as String;
    if (sid.split('.').length != 2) {
      _fail("screen id '$sid' is not <shell>.<short> — cannot derive a directory");
      return false;
    }
    // Optional kits declaration: shape only (the emitter already validated the
    // names against the kit registry; scaffold consumes frozen output).
    if (s.containsKey('kits')) {
      final k = s['kits'];
      if (k is! List || k.any((i) => i is! String)) {
        _fail("screen '$sid' carries a malformed 'kits' — must be a list of "
            'kit name strings');
        return false;
      }
    }
  }
  return true;
}

/// The exact file set one surface must carry: base _view.dart + one
/// _view.`<factor>`.dart per DERIVED factor + _viewmodel.dart.
List<String> expectedFiles(Map<String, dynamic> s, List<String> factors) {
  final d = surfaceDir(s);
  return [
    '${d}_view.dart',
    for (final f in factors) '${d}_view.$f.dart',
    '${d}_viewmodel.dart',
  ];
}

/// Two surfaces deriving the same dir would be silently merged — the
/// stale-green pattern. Returns true on collision (FAIL printed).
bool _dirCollisions(List<Map<String, dynamic>> frozen) {
  final seen = <String, String>{};
  for (final s in frozen) {
    final d = surfaceDir(s);
    if (seen.containsKey(d)) {
      _fail("surfaces '${seen[d]}' and '${s['surface']}' both derive dir '$d' "
          '(id collision) — the registry must give them distinct <shell>.<short> ids');
      return true;
    }
    seen[d] = s['surface'] as String;
  }
  return false;
}

// ----------------------------------------------------------- entry

/// Emit (or drift-check) the per-surface Dart tree from a frozen structure.json
/// + the target set. Mirrors scaffold.py `scaffold(...)`. Returns 0 on
/// success / in-sync, 1 on any failure (FAIL: line on stderr).
int scaffold(
  String designRoot,
  String appRoot,
  List<String> targets,
  String derivationPath,
  String configPath, {
  bool check = false,
}) {
  final loaded = loadStructure(designRoot);
  if (loaded.error != null) {
    _fail(loaded.error!);
    return 1;
  }

  List<String> factors;
  try {
    factors = deriveFactors(targets, derivationPath, configPath);
  } on FormatException catch (e) {
    _fail(e.message);
    return 1;
  }

  List<String>? l10n;
  try {
    l10n = designL10n(designRoot);
  } on FormatException catch (e) {
    _fail(e.message);
    return 1;
  }

  final frozen = (loaded.data!['screens'] as List)
      .whereType<Map<String, dynamic>>()
      .where((s) => (s['surface'] ?? '').isNotEmpty)
      .toList();
  if (frozen.isEmpty) {
    _fail('structure.json declares no surfaces (surface:null everywhere) — '
        'nothing to scaffold; the design has nothing for the coverage gate');
    return 1;
  }
  if (!_validateFrozen(frozen)) return 1;

  final views = '$appRoot/lib/ui/views';

  if (check) {
    return _check(views, frozen, factors, targets, appRoot, l10n);
  }

  final per = 2 + factors.length; // base + viewmodel + one per derived factor
  if (_dirCollisions(frozen)) return 1;

  var written = 0;
  for (final s in frozen) {
    final d = surfaceDir(s);
    final base = '$views/${s['shellDir']}/$d';
    Directory(base).createSync(recursive: true);
    File('$base/${d}_view.dart').writeAsStringSync(_stubView(s, factors, targets));
    for (final f in factors) {
      File('$base/${d}_view.$f.dart').writeAsStringSync(_stubFactor(s, f, targets));
    }
    File('$base/${d}_viewmodel.dart').writeAsStringSync(_stubViewmodel(s));
    File('$base/design-system.md').writeAsStringSync(_designSystemDoc(s, factors));
    written++;
  }

  // shell-level structure: each self-contained shell owns a design-system.md
  // (scaffold gate S4) + a *_chrome.dart (S6), at views/<shell>/.
  final shells = <String>{};
  for (final s in frozen) {
    shells.add(s['shellDir'] as String);
  }
  for (final sh in shells.toList()..sort()) {
    final shDir = '$views/$sh';
    Directory(shDir).createSync(recursive: true);
    File('$shDir/design-system.md').writeAsStringSync(_shellDesignSystemDoc(sh));
    File('$shDir/${sh}_chrome.dart').writeAsStringSync(_shellChrome(sh));
  }

  final manifest = buildManifest(frozen, factors, targets, l10n);
  Directory(views).createSync(recursive: true);
  final mfPath = '$views/.shell-structure.json';
  File(mfPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n');

  if (l10n != null) {
    _emitL10n(designRoot, appRoot, l10n);
  }

  // MEM-B (architecture §4): the memory file that travels with the delivered
  // app, write-on-diff like the rest of the emit. Best-effort — a memory
  // read failure warns, never fails the scaffold.
  try {
    if (writeMemB(
        appRoot,
        assembleMemB(findRepoRoot(appRoot),
            appName: appRoot.split('/').where((s) => s.isNotEmpty).last,
            surfaces: [for (final s in frozen) s['surface'] as String],
            targets: targets,
            factors: factors))) {
      print('  MEM-B.md refreshed');
    }
  } catch (e) {
    stderr.writeln('scaffold: WARN MEM-B write failed: $e');
  }

  final fl = factors.isNotEmpty ? factors.join(', ') : 'none';
  final sortedShells = shells.toList()..sort();
  print('scaffold: $written surface(s) x $per file(s) = ${written * per} files');
  print('  targets [${targets.join(',')}] -> form factors [$fl]');
  print('  shells: ${sortedShells.join(', ')}');
  if (l10n != null) {
    print('  l10n: ${l10n.length} catalog(s) -> lib/l10n/ + l10n.yaml '
        '(locales: ${l10nLocales(l10n).join(', ')})');
  }
  print('  manifest -> ${_relPath(mfPath, appRoot)}');
  return 0;
}

/// Compare the on-disk tree against what structure.json + targets imply.
/// Returns 0 if in sync, 1 naming every drift.
int _check(
  String views,
  List<Map<String, dynamic>> frozen,
  List<String> factors,
  List<String> targets,
  String appRoot,
  List<String>? l10n,
) {
  final problems = <String>[];
  for (final s in frozen) {
    final d = surfaceDir(s);
    final base = '$views/${s['shellDir']}/$d';
    for (final fn in expectedFiles(s, factors)) {
      if (!File('$base/$fn').existsSync()) {
        final flStr = factors.isNotEmpty ? factors.join(', ') : 'none';
        problems.add(
            'lib/ui/views/${s['shellDir']}/$d/$fn missing — targets [${targets.join(',')}] '
            'derive form factors [$flStr]');
      }
    }
  }
  final mf = File('$views/.shell-structure.json');
  final want = buildManifest(frozen, factors, targets, l10n);
  if (!mf.existsSync()) {
    problems.add('lib/ui/views/.shell-structure.json missing — the manifest the '
        'coverage gate reads');
  } else {
    try {
      final onDisk =
          jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
      if (!_jsonEqual(onDisk['surfaces'], want['surfaces'])) {
        problems.add('.shell-structure.json surfaces drifted from structure.json '
            '— re-run scaffold');
      }
      final diskSelf = (onDisk['selfContained'] as List?)?.cast<String>() ?? <String>[];
      if (!_jsonEqual(diskSelf..sort(), (want['selfContained'] as List).cast<String>()..sort())) {
        problems.add('.shell-structure.json selfContained drifted from '
            'structure.json — re-run scaffold');
      }
      if (!_jsonEqual(onDisk['l10n'], want['l10n'])) {
        problems.add('.shell-structure.json l10n drifted from the design\'s l10n/ '
            'catalogs — re-run scaffold');
      }
      if (!_jsonEqual(onDisk['kits'], want['kits'])) {
        problems.add('.shell-structure.json kits drifted from structure.json '
            '— re-run scaffold');
      }
    } catch (e) {
      problems.add('.shell-structure.json does not parse — $e');
    }
  }
  if (l10n != null) {
    final dst = Directory('$appRoot/lib/l10n');
    final onDisk = <String>[];
    if (dst.existsSync()) {
      onDisk.addAll(dst.listSync().whereType<File>().map((f) {
        final segs = f.path.split('/');
        return segs.last;
      }).where((fn) => fn.endsWith('.arb')));
      onDisk.sort();
    }
    for (final fn in l10n) {
      if (!onDisk.contains(fn)) {
        problems.add('lib/l10n/$fn missing — the design\'s l10n/ catalog was not '
            'scaffolded (re-run scaffold)');
      }
    }
    for (final fn in onDisk) {
      if (!l10n.contains(fn)) {
        problems.add('lib/l10n/$fn has no source in the design\'s l10n/ — drift '
            '(re-run scaffold)');
      }
    }
    final yf = File('$appRoot/l10n.yaml');
    if (!yf.existsSync()) {
      problems.add('l10n.yaml missing — the gen-l10n config for the design\'s l10n/ '
          'catalogs (re-run scaffold)');
    } else if (!yf.readAsStringSync().contains('template-arb-file: app_en.arb')) {
      problems.add('l10n.yaml template-arb-file drifted (contract: app_en.arb) — '
          're-run scaffold');
    }
  }
  if (problems.isNotEmpty) {
    for (final p in problems) {
      _fail(p);
    }
    return 1;
  }
  final fl = factors.isNotEmpty ? factors.join(', ') : 'none';
  print('in-sync: ${frozen.length} surface(s), targets [${targets.join(',')}] -> '
      'form factors [$fl]');
  return 0;
}

/// Deep structural equality for JSON-decoded values (Dart Map== is identity).
bool _jsonEqual(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_jsonEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

String _relPath(String path, String from) {
  if (path.startsWith('$from/')) return path.substring(from.length + 1);
  return path;
}

// ----------------------------------------------------------- emitter facade

/// OO facade over [scaffold] for callers that prefer a configured emitter.
/// Derivation + config paths default to repo-root discovery (walk up from
/// [appRoot] for config/appbox.config.json); inject them for hermetic tests.
class ScaffoldEmitter {
  ScaffoldEmitter({
    required this.appRoot,
    required this.designDir,
    required this.targets,
    this.derivationPath,
    this.configPath,
  });

  final String appRoot;
  final String designDir;
  final List<String> targets;
  final String? derivationPath;
  final String? configPath;

  String get _designRoot => _abs('$appRoot/$designDir');
  String get _absAppRoot => _abs(appRoot);

  String get _derivationPath =>
      derivationPath ?? '${findRepoRoot(appRoot)}/pipeline/state/targets.derivation.json';
  String get _configPath =>
      configPath ?? '${findRepoRoot(appRoot)}/config/appbox.config.json';

  /// Emit the per-surface tree. Returns 0 on success, 1 on failure.
  int emit() => scaffold(_designRoot, _absAppRoot, targets, _derivationPath, _configPath);

  /// Drift-check the on-disk tree. Returns 0 if in sync, 1 on drift.
  int check() => scaffold(_designRoot, _absAppRoot, targets, _derivationPath,
      _configPath, check: true);
}

String _abs(String path) => File(path).absolute.path;

/// Discover the repo root by walking up from [start] for config/appbox.config.json.
String findRepoRoot(String start) {
  var dir = Directory(start).absolute;
  while (true) {
    if (File('${dir.path}/config/appbox.config.json').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.absolute.path;
}

// ----------------------------------------------------------- self-test

/// The negative-case self-test (R5: a check that has never failed is not a
/// check). Plants each defect and asserts the engine catches it, plus the §16
/// invariant. Returns 0 if all pass, 1 otherwise.
int runSelfTest() {
  var pass = 0;
  var fail = 0;
  void chk(bool cond, String what) {
    if (cond) {
      pass++;
    } else {
      fail++;
      stderr.writeln('  FAIL: $what');
    }
  }

  final tmp = Directory.systemTemp.createTempSync('scaffold-selftest-');
  try {
    final derivationPath = '${tmp.path}/targets.derivation.json';
    File(derivationPath).writeAsStringSync('{"targets":{'
        '"ios":{"viewports":["mobile","tablet"],"ceremonies":[]},'
        '"android":{"viewports":["mobile","tablet"],"ceremonies":[]},'
        '"web":{"viewports":["mobile","tablet","desktop"],"ceremonies":[]},'
        '"pwa":{"inherits":"web","viewports":[],"ceremonies":[]},'
        '"macos":{"viewports":["desktop"],"ceremonies":[]},'
        '"linux":{"viewports":["desktop"],"ceremonies":[]},'
        '"windows":{"viewports":["desktop"],"ceremonies":[]}}}');
    final configPath = '${tmp.path}/appbox.config.json';
    File(configPath).writeAsStringSync('{"viewports":{'
        '"mobile":{"width":390,"height":844},'
        '"tablet":{"width":744,"height":1133},'
        '"desktop":{"width":1280,"height":800}}}');

    final struct = {
      'screens': [
        {
          'id': 'stage.shell',
          'shell': 'stage',
          'comp': 'StageShell',
          'shellDir': 'stage_shell',
          'surface': 'stage_shell_view',
          'viewmodel': 'ui/views/stage_shell/stage_shell_viewmodel.js',
          'deps': ['services/facades/shell_facade.js'],
        },
        {
          'id': 'projects.home',
          'shell': 'projects',
          'comp': 'ProjectsHome',
          'shellDir': 'stage_shell',
          'surface': 'stage_shell_projects_home_view',
          'viewmodel': 'ui/views/stage_shell/projects/home/home_viewmodel.js',
          'deps': ['services/facades/project_facade.js'],
        },
      ],
    };

    String plant(String name) {
      final des = '${tmp.path}/$name/design';
      Directory(des).createSync(recursive: true);
      File('$des/structure.json').writeAsStringSync(jsonEncode(struct));
      return des;
    }

    // macos -> [desktop] -> 3 files/surface.
    final des = plant('d');
    final app1 = '${tmp.path}/app1';
    chk(scaffold(des, app1, ['macos'], derivationPath, configPath) == 0,
        'macos scaffold emits (exit 0)');
    chk(deriveFactors(['macos'], derivationPath, configPath).toString() ==
        '[desktop]', 'macos derives [desktop] only');
    final base = '$app1/lib/ui/views/stage_shell/projects_home';
    chk(File('$base/projects_home_view.dart').existsSync(), 'base _view.dart exists');
    chk(File('$base/projects_home_view.desktop.dart').existsSync(),
        'desktop factor exists');
    chk(!File('$base/projects_home_view.mobile.dart').existsSync(),
        'no empty .mobile.dart (§16)');
    chk(!File('$base/projects_home_view.tablet.dart').existsSync(),
        'no empty .tablet.dart (§16)');

    final mf = jsonDecode(File('$app1/lib/ui/views/.shell-structure.json')
            .readAsStringSync()) as Map<String, dynamic>;
    chk(mf['selfContained'].toString() == '[stage_shell]',
        'manifest selfContained lists the shell');

    // ios,android -> [mobile, tablet] -> 4 files/surface.
    final app2 = '${tmp.path}/app2';
    chk(scaffold(des, app2, ['ios', 'android'], derivationPath, configPath) == 0,
        'ios,android scaffold emits (exit 0)');
    chk(deriveFactors(['ios', 'android'], derivationPath, configPath).toString() ==
        '[mobile, tablet]', 'ios,android derives [mobile, tablet]');

    // web -> all three.
    chk(deriveFactors(['web'], derivationPath, configPath).toString() ==
        '[mobile, tablet, desktop]', 'web derives all three');
    chk(deriveFactors(['pwa'], derivationPath, configPath).toString() ==
        '[mobile, tablet, desktop]', 'pwa inherits web -> all three');

    // NEGATIVE: missing structure.json.
    final empty = '${tmp.path}/empty';
    Directory(empty).createSync(recursive: true);
    chk(scaffold(empty, '${tmp.path}/appE', ['macos'], derivationPath, configPath) == 1,
        'missing structure.json -> exit 1');

    // NEGATIVE: surface without viewmodel.
    final bad = jsonDecode(jsonEncode(struct)) as Map<String, dynamic>;
    (bad['screens'] as List)[1]['viewmodel'] = null;
    final bdes = '${tmp.path}/bd/design';
    Directory(bdes).createSync(recursive: true);
    File('$bdes/structure.json').writeAsStringSync(jsonEncode(bad));
    chk(scaffold(bdes, '${tmp.path}/appB', ['macos'],
            derivationPath, configPath) ==
        1, 'surface with no viewmodel -> exit 1');

    // NEGATIVE: unknown target.
    chk(scaffold(des, '${tmp.path}/appU', ['zxspectrum'], derivationPath, configPath) == 1,
        'unknown target -> exit 1');

    // NEGATIVE: wrong file count -> --check exit 1, restore -> green.
    final missing = '$base/projects_home_view.desktop.dart';
    File(missing).deleteSync();
    chk(scaffold(des, app1, ['macos'], derivationPath, configPath, check: true) == 1,
        'wrong file count -> --check exit 1');
    File(missing).writeAsStringSync('// restored');
    chk(scaffold(des, app1, ['macos'], derivationPath, configPath, check: true) == 0,
        '--check green after restoring');

    // NEGATIVE: dir collision.
    final coll = jsonDecode(jsonEncode(struct)) as Map<String, dynamic>;
    (coll['screens'] as List).add({
      'id': 'projects.home',
      'shell': 'projects',
      'comp': 'ProjectsHome2',
      'shellDir': 'stage_shell',
      'surface': 'stage_shell_projects_home_2_view',
      'viewmodel': 'ui/views/x.js',
      'deps': <String>[],
    });
    final cdes = '${tmp.path}/cd/design';
    Directory(cdes).createSync(recursive: true);
    File('$cdes/structure.json').writeAsStringSync(jsonEncode(coll));
    chk(scaffold(cdes, '${tmp.path}/appC', ['macos'],
            derivationPath, configPath) ==
        1, 'dir collision -> exit 1');

    // class-name contents.
    final view = File('$base/projects_home_view.dart').readAsStringSync();
    chk(view.contains('class ProjectsHomeView extends StackedView<ProjectsHomeViewModel>'),
        'base view declares <comp>View over its viewmodel');

    // BACKWARD COMPAT: no l10n -> no artifacts.
    chk(!Directory('$app1/lib/l10n').existsSync(), 'no l10n/ -> no lib/l10n');
    chk(!File('$app1/l10n.yaml').existsSync(), 'no l10n/ -> no l10n.yaml');

    // l10n layer.
    final ldes = '${tmp.path}/ld/design';
    Directory('$ldes/l10n').createSync(recursive: true);
    File('$ldes/structure.json').writeAsStringSync(jsonEncode(struct));
    File('$ldes/l10n/app_en.arb').writeAsStringSync('{"appTitle": "Demo"}');
    File('$ldes/l10n/app_pl.arb').writeAsStringSync('{"appTitle": "Demo pl"}');
    final appL = '${tmp.path}/appL';
    chk(scaffold(ldes, appL, ['macos'], derivationPath,
            configPath) ==
        0, 'l10n design scaffold emits (exit 0)');
    chk(File('$appL/lib/l10n/app_en.arb').readAsStringSync() == '{"appTitle": "Demo"}',
        'app_en.arb copied verbatim');
    chk(File('$appL/l10n.yaml').readAsStringSync() == l10nYaml,
        'l10n.yaml matches the fixed contract');
    final mfL = jsonDecode(File('$appL/lib/ui/views/.shell-structure.json')
            .readAsStringSync()) as Map<String, dynamic>;
    chk(mfL['l10n'].toString() == '{arbDir: lib/l10n, locales: [en, pl]}',
        'manifest records l10n arbDir + locales');
    chk(scaffold(ldes, appL, ['macos'], derivationPath,
            configPath, check: true) ==
        0, 'l10n design --check green');
    File('$appL/lib/l10n/app_pl.arb').deleteSync();
    chk(scaffold(ldes, appL, ['macos'], derivationPath,
            configPath, check: true) ==
        1, 'deleted catalog -> --check exit 1');

    // NEGATIVE: l10n/ without app_en.arb.
    final bdes2 = '${tmp.path}/bdl/design';
    Directory('$bdes2/l10n').createSync(recursive: true);
    File('$bdes2/structure.json').writeAsStringSync(jsonEncode(struct));
    File('$bdes2/l10n/app_pl.arb').writeAsStringSync('{}');
    chk(scaffold(bdes2, '${tmp.path}/appBL', ['macos'],
            derivationPath, configPath) ==
        1, 'l10n/ without app_en.arb -> exit 1');
  } finally {
    tmp.deleteSync(recursive: true);
  }

  stderr.writeln('\nscaffold self-test: passed=$pass failed=$fail');
  if (fail != 0) return 1;
  stderr.writeln('ALL GREEN');
  return 0;
}
