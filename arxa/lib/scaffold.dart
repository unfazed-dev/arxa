// scaffold — Dart port of skills/arxa-scaffolder/scaffold.py (860 lines).
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
//   It also emits the RED-FIRST test seeds (behavior-TDD canon, enforced by
//   `arxa gate tests`): per surface, test/viewmodels/<dir>_viewmodel_test.dart
//   with one SKIPPED test per story the story map attaches to that surface —
//   T1-passing (test( present), T2-passing (story id cited verbatim), T3-green
//   (skipped) until the builder implements the behavior and removes the skip.
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
//   The OPTIONAL kit-manifest sidecar (D8): the studio's scaffold picker persists
//   its confirmed kit selection as kit-manifest.json BESIDE the frozen
//   structure.json. When present, `resolved` is consumed verbatim (plan/apply
//   semantics) and written into .shell-structure.json's `kits` map as the final
//   set that reaches the build. Absent: kits derive from structure.json exactly
//   as before. Malformed: FAIL — never silently fall back to an unconfirmed set.
//
// Pure stdlib (dart:io + dart:convert). Exit: 0 emitted / in-sync ·
// 1 missing input, drift, wrong count.

import 'dart:convert';
import 'dart:io';

import 'mem_b.dart';
import 'story_map.dart';

/// The gen-l10n config is a FIXED contract — gates assert it verbatim, so it is
/// a constant, never templated. (synthetic-package deliberately absent: the SDK
/// deprecated it — output always lands in the package now.)
const l10nYaml = '''arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
nullable-getter: false
''';

final _arbRe = RegExp(r'app_([A-Za-z0-9_]+)\.arb$');

/// BCP-47 pseudolocale catalogs (qps-ploc, qps-plocm, ...) emitted by the
/// design-server pseudolocalize tool into the same l10n/ dir.
final _pseudoArbRe = RegExp(r'^app_qps-[A-Za-z0-9-]+\.arb$');

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
/// Test seams — see [tplViewForTest] in blueprint.dart for why generator
/// templates need them (the output is a string; analyze cannot look inside it).
String stubViewForTest(
        Map<String, dynamic> screen, List<String> factors, List<String> targets) =>
    _stubView(screen, factors, targets);
String stubViewModelForTest(Map<String, dynamic> screen) =>
    _stubViewmodel(screen);

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
  return '// arxa-scaffolder: surface skeleton. STRUCTURE ONLY — the builder fills this.\n'
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
      // TYPED, and it matters now. The signature used to be
      // `builder(context, viewModel, child)` — untyped, which was harmless
      // while the body touched no ViewModel members. The states below call
      // three of them, and on a dynamic parameter a typo in `isBusy`,
      // `hasError` or `refresh` is a RUNTIME failure in the generated app
      // rather than a compile error. Nothing in this repo runs `dart analyze`
      // over materialized scaffold output (checked), and the parse gate only
      // parses — so the type annotation is the only thing standing between a
      // renamed ViewModel member and a crash in someone else's app.
      '  Widget builder(\n'
      '      BuildContext context, ${comp}ViewModel viewModel, Widget? child) {\n'
      '    // ADR-0003: no async without a busy/error surface. Emitted here so the\n'
      '    // mandate has an emission point rather than only a comment (task #43).\n'
      '    // No empty state: this skeleton binds no collection, and a generated\n'
      "    // `isEmpty` over nothing is a check that can only ever pass.\n"
      '    if (viewModel.isBusy) {\n'
      '      return const Scaffold(\n'
      '          body: Center(child: CircularProgressIndicator()));\n'
      '    }\n'
      '    if (viewModel.hasError) {\n'
      '      // A sentence, never viewModel.modelError — the raw object leaks\n'
      '      // internals and reads as a crash. Log it; show this.\n'
      '      return Scaffold(\n'
      '        body: Center(\n'
      '          child: Column(\n'
      '            mainAxisSize: MainAxisSize.min,\n'
      '            children: [\n'
      "              const Text('Something went wrong loading this screen.'),\n"
      '              const SizedBox(height: 12),\n'
      '              FilledButton(\n'
      '                onPressed: viewModel.refresh,\n'
      "                child: const Text('Try again'),\n"
      '              ),\n'
      '            ],\n'
      '          ),\n'
      '        ),\n'
      '      );\n'
      '    }\n'
      '    return const Scaffold(\n'
      "      body: Center(child: Text('$sid')),\n"
      '    );\n'
      '  }\n'
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
  return '// arxa-scaffolder: $factor layout skeleton. STRUCTURE ONLY — builder fills this.\n'
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
  return '// arxa-scaffolder: view model skeleton. STRUCTURE ONLY — builder fills this.\n'
      '//   surface:       $surface\n'
      '//   comp:          ${comp}ViewModel\n'
      '$depsLine'
      '$kitsLine'
      '// TODO(arxa-builder): wire services from the deps above.\n'
      "import 'package:stacked/stacked.dart';\n"
      '\n'
      'class ${comp}ViewModel extends BaseViewModel {\n'
      "  /// What the view's error retry calls. Emitted by the same generator as\n"
      '  /// that view, so the button can never point at a missing method.\n'
      '  /// Wrap the real load in setBusy/setError so the branches light up.\n'
      '  Future<void> refresh() async {}\n'
      '}\n';
}

// ------------------------------------------------ red-first test seeds

/// The behavior-TDD seed for `<comp>ViewModel` (canon: skills/arxa-tester/
/// behavior-tdd-rules.md), one SKIPPED test per story the story map attaches
/// to this surface. The stub VM has no behavior yet, so a "real" test is
/// impossible — the skip is the honest red-first state: it satisfies gate T1's
/// test( presence, cites the story id verbatim for T2, and cannot fail T3.
/// The builder implements the VM, writes the given/when/then body, and removes
/// the skip.
///
/// [stories] is null when no story map was found (or it did not parse) — the
/// seed then carries a single placeholder skipped test citing no id (still
/// T1-passing) with a run-intake-first comment. Empty means the map exists but
/// no stories roll up to this surface.
String _stubViewmodelTest(
    Map<String, dynamic> screen, List<Map<String, dynamic>>? stories) {
  final comp = screen['comp'] as String;
  final surface = screen['surface'] as String;
  final b = StringBuffer()
    ..write('// arxa-scaffolder: red-first behavior-test seed. Canon:\n')
    ..write('// skills/arxa-tester/behavior-tdd-rules.md — each skipped test cites its\n')
    ..write('// story id verbatim (gate T2) and stays green (T3) until the builder\n')
    ..write('// implements the behavior and removes the skip.\n')
    ..write('//   surface:       $surface\n')
    ..write('//   comp:          ${comp}ViewModel\n')
    ..write("import 'package:flutter_test/flutter_test.dart';\n")
    ..write('\n')
    ..write('void main() {\n')
    ..write("  group('${comp}ViewModel', () {\n")
    ..write('    setUp(() {\n')
    ..write('      // builder: register kit fakes / port mocks here once the VM wires services.\n')
    ..write('    });\n')
    ..write('\n')
    ..write('    tearDown(() {\n')
    ..write('      // builder: reset locator/static state here if the VM touches it.\n')
    ..write('    });\n');
  if (stories == null || stories.isEmpty) {
    b.write('\n');
    if (stories == null) {
      b.write('    // No story map found (intake/map.json, docs/intake/story-map.json) —\n');
      b.write('    // run `arxa intake` first, then re-scaffold to seed one test per story.\n');
    } else {
      b.write('    // The story map attaches no stories to this surface yet — extend\n');
      b.write('    // the map (arxa intake), then re-scaffold.\n');
    }
    b.write("    test('placeholder — seed me from the story map', () async {\n");
    b.write('      // red-first: implement with ${comp}ViewModel, then remove the skip.\n');
    b.write("    }, skip: 'red-first seed — implement with ${comp}ViewModel');\n");
  } else {
    for (final s in stories) {
      final id = s['id'] as String;
      final name = _sentenceCase((s['name'] as String?) ?? id);
      b.write('\n');
      b.write("    test('${_dartSingleQuoted('$id — $name')}', () async {\n");
      b.write('      // red-first: implement with ${comp}ViewModel, then remove the skip.\n');
      b.write("    }, skip: 'red-first seed — implement with ${comp}ViewModel');\n");
    }
  }
  b.write('  });\n');
  b.write('}\n');
  return b.toString();
}

/// "create folder" -> "Create folder": first letter up, the rest untouched —
/// never lowercases an intentional capital ("Use OAuth2" stays "Use OAuth2").
String _sentenceCase(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Escape [s] for a single-quoted Dart string literal.
String _dartSingleQuoted(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$')
    .replaceAll('\n', r'\n');

/// Story-map discovery for the test seeds — the same lookup the tests gate
/// enforces (gate_tests T2): `<app>/intake/map.json`, then
/// `<app>/docs/intake/story-map.json`. Returns surface-id -> stories (surfaces
/// derive from features exactly as story_map.dart's deriveSurfaces rolls them
/// up, so the ids match the structure.json screen ids), or null when no map
/// exists / the map does not parse — never a scaffold failure.
Map<String, List<Map<String, dynamic>>>? _storiesBySurface(String appRoot) {
  String? mapPath;
  for (final candidate in [
    '$appRoot/intake/map.json',
    '$appRoot/docs/intake/story-map.json',
  ]) {
    if (File(candidate).existsSync()) {
      mapPath = candidate;
      break;
    }
  }
  if (mapPath == null) return null;
  try {
    final data = jsonDecode(File(mapPath).readAsStringSync());
    if (data is! Map<String, dynamic>) return null;
    return {
      for (final s in deriveSurfaces(data).surfaces)
        s.id: [
          for (final st in s.stories)
            if (st['id'] is String) st,
        ],
    };
  } catch (_) {
    stderr.writeln('scaffold: WARN story map $mapPath does not parse — '
        'emitting placeholder test seeds (run intake first)');
    return null;
  }
}

/// The design-system.md every surface dir must carry (the review gate's
/// design_system_doc check). STRUCTURE ONLY — the builder fills the real intent.
String _designSystemDoc(
  Map<String, dynamic> screen,
  List<String> factors, {
  Map<String, dynamic>? theme,
  Map<String, dynamic>? fonts,
}) {
  final surface = screen['surface'] as String;
  final sid = screen['id'] as String;
  final shellDir = screen['shellDir'] as String;
  final fl = factors.isNotEmpty ? factors.join(', ') : '(none)';
  return '# design-system — $surface\n'
      '\n'
      '> arxa-scaffolder: STRUCTURE ONLY. The builder (plan 08) fills the real intent.\n'
      '\n'
      '- **surface:** `$surface`  ($sid)\n'
      '- **shell:**  $shellDir\n'
      '- **derived form factors:** $fl\n'
      '\n'
      '${_paletteSection(theme)}'
      '\n'
      '${_typeSection(fonts)}'
      '\n'
      '## Spacing\n'
      '<!-- builder: spacing tokens (no ad-hoc SizedBox gaps) -->\n'
      '\n'
      '## Motion\n'
      '<!-- builder: ArxaKitMotionSpec.* presets/curves/durations -->\n'
      '\n'
      '## Forbidden\n'
      '- `Icons.*` (use `ArxaKitGlyphs.*`)\n'
      '- ad-hoc `Color(0x…)` (use `ArxaKitColors.*`)\n'
      '- stock `ElevatedButton`/`FilledButton`/`TextButton` CTAs (use `ArxaKitNativeButton`)\n';
}

/// Token-exact Palette guidance from structure@2's `theme` block.
///
/// The scaffolder names the ACCENT API and the authored swatches; it does not
/// guess which role this surface uses — that stays the builder's call. When
/// structure.json carries no `theme` (a structure@1 design), the placeholder is
/// emitted unchanged rather than inventing tokens.
String _paletteSection(Map<String, dynamic>? theme) {
  if (theme == null) {
    return '## Palette\n'
        '<!-- builder: ArxaKitColors.* tokens this surface uses -->\n';
  }
  final swatches = (theme['swatches'] as List?) ?? const [];
  final names = swatches
      .whereType<Map>()
      .map((s) => s['name'])
      .whereType<String>()
      .toList();
  final def = theme['default'] as String?;
  final b = StringBuffer('## Palette\n');
  b.write('\n');
  b.write('The ramp is `ArxaKitColors` (light) / `ArxaKitDarkColors` (dark). The brand\n'
      'accent is NOT a constant — it is a user setting, so read it through the\n'
      'swatch API and never hard-code one of the hexes below.\n');
  b.write('\n');
  if (names.isNotEmpty) {
    b.write('- **authored swatches:** ${names.map((n) => '`$n`').join(', ')}\n');
  }
  if (def != null) {
    b.write('- **default:** `$def` — `arxaKitAccentByName(\'$def\')`, '
        'or `arxaKitDefaultAccent` for the same value\n');
  }
  b.write('- **read a swatch:** `arxaKitAccentByName(name)'
      '.forBrightness(Theme.of(context).brightness)` — the 5 roles are\n'
      '  `.accent` `.soft` `.surface` `.text` `.muted`\n');
  b.write('- **theme:** `arxaKitLightTheme(accent: …)` / `arxaKitDarkTheme(accent: …)` —\n'
      '  `accent` is a `Color`, not a swatch: pass a role off the swatch\n'
      '  (e.g. `arxaKitAccentByName(n).forBrightness(b).accent`)\n');
  b.write('\n');
  b.write('<!-- builder: which of the 5 roles this surface uses, and where -->\n');
  return b.toString();
}

/// Token-exact Type guidance from structure@2's `fonts` block.
///
/// Absent until the design side authors `models/fonts.json`; the placeholder is
/// emitted unchanged rather than naming faces the design has not declared.
String _typeSection(Map<String, dynamic>? fonts) {
  if (fonts == null) {
    return '## Type\n'
        '<!-- builder: TextTheme roles -->\n';
  }
  final families = (fonts['families'] as List?) ?? const [];
  final ids = families
      .whereType<Map>()
      .map((f) => f['id'])
      .whereType<String>()
      .toList();
  final def = fonts['default'] as String?;
  final b = StringBuffer('## Type\n');
  b.write('\n');
  b.write('Sizes come from the abx-scale (the theme\'s `TextTheme` roles) — the font\n'
      'block chooses the FACE only, never the size.\n');
  b.write('\n');
  if (ids.isNotEmpty) {
    b.write('- **declared families:** ${ids.map((i) => '`$i`').join(', ')}\n');
  }
  if (def != null) {
    b.write('- **default:** `$def` — `arxaKitFontById(\'$def\').cssName`\n');
  }
  b.write('- **apply:** pass that css name to '
      '`arxaKitLightTheme(fontFamily: …)` / `arxaKitDarkTheme(fontFamily: …)`\n');
  b.write('- **NOTE:** a family name whose binary is not bundled falls back to\n'
      '  the platform default SILENTLY — check `arxaKitFontIsBundled` before\n'
      '  trusting a face, and call `registerArxaKitFontLicenses()` once bundled\n');
  b.write('\n');
  b.write('<!-- builder: TextTheme roles this surface uses -->\n');
  return b.toString();
}

/// The shell-level design-system.md the scaffold gate (S4) requires at
/// views/`<shell>`/design-system.md. STRUCTURE ONLY.
String _shellDesignSystemDoc(
  String shell, {
  Map<String, dynamic>? theme,
  Map<String, dynamic>? fonts,
}) {
  return '# design-system — $shell (shell)\n'
      '\n'
      '> arxa-scaffolder: STRUCTURE ONLY. The builder (plan 08) fills the real intent.\n'
      '\n'
      '${_paletteSection(theme)}'
      '\n'
      '${_typeSection(fonts)}'
      '\n'
      '## Spacing\n'
      '<!-- builder: spacing tokens (no ad-hoc SizedBox gaps) -->\n'
      '\n'
      '## Motion\n'
      '<!-- builder: ArxaKitMotionSpec.* presets/curves/durations -->\n'
      '\n'
      '## Forbidden\n'
      '- `Icons.*` (use `ArxaKitGlyphs.*`)\n'
      '- ad-hoc `Color(0x…)` (use `ArxaKitColors.*`)\n'
      '- stock CTA buttons (use `ArxaKitNativeButton`)\n';
}

/// The *_chrome.dart every self-contained shell owns (scaffold gate S6).
/// STRUCTURE ONLY.
//
// ponytail: the three-tier widget law (lib/ui/widgets/ cross-shell,
// <shell>/shared/widgets/ intra-shell, <view>/widgets/ per-surface) is enforced
// by gate_scaffold S6/S6c but NOT emitted here, because structure.json carries
// no widget map: its screen records are id/comp/shellDir/surface/viewmodel/kits
// and nothing says which widget serves which surfaces. Emitting a widgets tier
// today would mean inventing that signal in the scaffolder, and an empty tier
// created speculatively is itself a placement-law violation. Ceiling: emission
// lands when the design-side widget map reaches structure.json (emit_structure),
// at which point a widget with consumers in 2+ shells emits into lib/ui/widgets/
// and the rest into the narrowest shell/surface tier.
String _shellChrome(String shell) {
  final comp = _pascal(shell);
  return '// arxa-scaffolder: shell chrome skeleton. STRUCTURE ONLY — builder fills this.\n'
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
      // Pseudolocale catalogs (app_qps-*.arb, written by the design server's
      // pseudolocalize tool) are design-time QA artifacts, not shippable app
      // locales: Flutter gen-l10n cannot parse a hyphenated filename suffix,
      // so they are skipped here rather than copied into the app or rejected.
      .where((fn) => !_pseudoArbRe.hasMatch(fn))
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
///
/// D8: when the picker's kit-manifest.json sidecar supplied [resolved], the
/// `kits` section carries that picker-confirmed set VERBATIM under `resolved`
/// (the final set that reaches the build — D1: scaffold is the single
/// authoritative merge point), with the per-surface declarations kept under
/// `surfaces` so the builder can still see which screen asked for what (a
/// declared kit missing from `resolved` is a D2 removal — the builder wires
/// the forced fallback). Without a sidecar the section stays the flat
/// per-surface map it has always been: no picker selection, no new shape.
Map<String, dynamic> buildManifest(
    List<Map<String, dynamic>> frozen, List<String> factors, List<String> targets,
    [List<String>? l10n, List<dynamic>? resolved]) {
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
    'notes': 'scaffolded by arxa-scaffolder from a frozen structure.json; '
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
  if (resolved != null) {
    m['kits'] = {
      'resolved': resolved,
      if (kitsBySurface.isNotEmpty) 'surfaces': kitsBySurface,
    };
  } else if (kitsBySurface.isNotEmpty) {
    m['kits'] = kitsBySurface;
  }
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

/// D8: the optional kit-manifest.json sidecar the studio's scaffold picker
/// persists BESIDE the frozen structure.json. Three states, deliberately
/// distinct:
///   absent           -> (resolved: null, error: null): no picker selection,
///                       behavior unchanged (kits derive from structure.json)
///   present, valid   -> `resolved` consumed VERBATIM (plan/apply semantics)
///   present, broken  -> FAIL: a sidecar that does not parse or whose
///                       `resolved` is the wrong shape must never silently
///                       fall back to a kit set the picker did not confirm
/// A sidecar with no `resolved` section yet (intake wrote a wishlist, the
/// picker never ran) is the absent case — nothing confirmed, nothing applied.
({List<dynamic>? resolved, String? error}) loadKitManifest(String path) {
  final f = File(path);
  if (!f.existsSync()) return (resolved: null, error: null);
  Map<String, dynamic> data;
  try {
    data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    return (
      resolved: null,
      error: 'kit-manifest.json does not parse as a JSON object — $e',
    );
  }
  final resolved = data['resolved'];
  if (resolved == null) return (resolved: null, error: null);
  if (resolved is! List ||
      resolved.any((k) => k is! Map || k['id'] is! String)) {
    return (
      resolved: null,
      error: "kit-manifest.json 'resolved' must be a list of kit entries "
          '({id, package, provenance, auto}) — the picker writes this file; '
          'fix it through the studio, not by hand',
    );
  }
  return (resolved: resolved, error: null);
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
///
/// D8: [kitManifestPath] is an extra input like [derivationPath] — the picker
/// sidecar. Defaults to kit-manifest.json beside structure.json; pass it
/// explicitly to point elsewhere. Absent sidecar: behavior unchanged.
int scaffold(
  String designRoot,
  String appRoot,
  List<String> targets,
  String derivationPath,
  String configPath, {
  bool check = false,
  String? kitManifestPath,
}) {
  final loaded = loadStructure(designRoot);
  if (loaded.error != null) {
    _fail(loaded.error!);
    return 1;
  }

  final sidecarPath = kitManifestPath ?? '$designRoot/kit-manifest.json';
  final sidecar = loadKitManifest(sidecarPath);
  if (sidecar.error != null) {
    _fail(sidecar.error!);
    return 1;
  }
  final resolved = sidecar.resolved;

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
    return _check(views, frozen, factors, targets, appRoot, l10n, resolved);
  }

  final per = 2 + factors.length; // base + viewmodel + one per derived factor
  if (_dirCollisions(frozen)) return 1;

  // structure@2 design blocks — optional; a structure@1 design has neither and
  // the emitted docs keep their placeholders rather than inventing tokens.
  final themeBlock = loaded.data!['theme'] as Map<String, dynamic>?;
  final fontsBlock = loaded.data!['fonts'] as Map<String, dynamic>?;

  // Red-first behavior-test seeds (behavior-TDD canon): one per surface, from
  // the same story map the tests gate reads. Null = no map -> placeholders.
  final storiesBySurface = _storiesBySurface(appRoot);
  final testDir = '$appRoot/test/viewmodels';

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
    File('$base/design-system.md').writeAsStringSync(_designSystemDoc(s, factors, theme: themeBlock, fonts: fontsBlock));
    Directory(testDir).createSync(recursive: true);
    File('$testDir/${d}_viewmodel_test.dart').writeAsStringSync(_stubViewmodelTest(
        s,
        storiesBySurface == null
            ? null
            : storiesBySurface[s['id']] ?? const []));
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
    File('$shDir/design-system.md').writeAsStringSync(_shellDesignSystemDoc(sh, theme: themeBlock, fonts: fontsBlock));
    File('$shDir/${sh}_chrome.dart').writeAsStringSync(_shellChrome(sh));
  }

  final manifest = buildManifest(frozen, factors, targets, l10n, resolved);
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
  print('  red-first test seeds: $written file(s) -> test/viewmodels/ '
      '(${storiesBySurface == null ? 'no story map — placeholders' : 'seeded from the story map'})');
  print('  shells: ${sortedShells.join(', ')}');
  if (l10n != null) {
    print('  l10n: ${l10n.length} catalog(s) -> lib/l10n/ + l10n.yaml '
        '(locales: ${l10nLocales(l10n).join(', ')})');
  }
  if (resolved != null) {
    print('  kit-manifest: ${resolved.length} resolved kit(s) from '
        '${_relPath(sidecarPath, appRoot)} (D8 picker-confirmed set)');
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
  List<dynamic>? resolved,
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
  final want = buildManifest(frozen, factors, targets, l10n, resolved);
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
        problems.add('.shell-structure.json kits drifted from structure.json'
            '${resolved != null ? ' + kit-manifest.json' : ''} '
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
/// [appRoot] for config/arxa.config.json); inject them for hermetic tests.
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
      configPath ?? '${findRepoRoot(appRoot)}/config/arxa.config.json';

  /// Emit the per-surface tree. Returns 0 on success, 1 on failure.
  int emit() => scaffold(_designRoot, _absAppRoot, targets, _derivationPath, _configPath);

  /// Drift-check the on-disk tree. Returns 0 if in sync, 1 on drift.
  int check() => scaffold(_designRoot, _absAppRoot, targets, _derivationPath,
      _configPath, check: true);
}

String _abs(String path) => File(path).absolute.path;

/// Discover the repo root by walking up from [start] for config/arxa.config.json.
String findRepoRoot(String start) {
  var dir = Directory(start).absolute;
  while (true) {
    if (File('${dir.path}/config/arxa.config.json').existsSync()) {
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
    final configPath = '${tmp.path}/arxa.config.json';
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
