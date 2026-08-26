// arch_guard.dart — deterministic architecture validator. Port of arch_guard.py.
//
// Pure code, no analyzer. Enforces the fixed contract (ADR-0003): Stacked MVVM +
// DDD 4-layer + repository Ports + Supabase confinement + busy/error. Static,
// regex-based parse of `<target>/lib` Dart. Fail → re-emit (the deterministic
// gate before any build).
//
// Rules:
//   G0  no lib/ directory → not a Flutter target.
//   G1  layering: domain is pure (no Flutter, no Supabase, no UI/infra imports);
//       application has no Flutter widget UI, no Supabase; infrastructure holds
//       Supabase (and only it imports supabase); presentation is unconstrained.
//   G2  every `*_viewmodel.dart` extends a Stacked busy-capable base
//       (BaseViewModel / FutureViewModel / MultipleFutureViewModel /
//       StreamViewModel / *BaseViewModel / *ViewModelBase).
//   G3  no async-without-busy: a ViewModel using async/await/Future must extend a
//       busy-capable base.
//   G4  infrastructure repository files implement a domain Port (warn-level).
//   G5  Supabase confined to infrastructure: any non-infra file importing
//       package:supabase* → violation.
//   G6  one viewmodel per view: a `*_view[.<factor>].dart` may import only its
//       own `*_viewmodel.dart` — foreign viewmodel imports are violations
//       (navigation intent travels via route params, shared state via facade
//       streams — builder playbook: View/ViewModel boundaries).
//   G7  no mutable static fields on a viewmodel (`static` fields must be
//       const/final) — statics are cross-screen coupling by the back door.
//   G8  DialogService/BottomSheetService used from a view or widget file —
//       confirm-then-act flows are viewmodel actions via
//       ArxaKitNotificationService's confirm/prompt/alert/notice verbs.
//   G9  service-layer direction is one-way: repository < adapter < facade <
//       viewmodel. A viewmodel's only service door is the facade — it never
//       imports a repository, adapter, or view; a facade never imports a
//       viewmodel/view; adapters and repositories import none of the higher
//       tiers. Multi-service transactions are facade work — never viewmodel
//       work (builder playbook: What lives where).
//   G10 no repeated URIs within a file's imports, or within its exports.
//       (Import + export of the same URI is not a *duplicate* — but in a
//       viewmodel the export side is banned outright, see G11.)
//   G11 viewmodels never re-export: no `export` directives in a
//       `*_viewmodel.dart`. Views/widgets import model barrels and kit types
//       directly — types are vocabulary; only behavior flows through the VM.
//   G12 enums and sealed discriminator types live in lib/enums/<shell>_enums/ —
//       a top-level `enum` or `sealed class`/`sealed mixin` anywhere else is a
//       violation. Generated files (app.router.dart, *.g.dart, *.gr.dart,
//       *.gen.dart, *.freezed.dart) are exempt — their types aren't authored.
//   G13 semantic frontmatter: covered files (views, viewmodels, facades,
//       adapters, repositories, widgets, models) carry a `library;` directive
//       preceded by a `///` doc comment with the fixed spine — a role paragraph
//       (`This is the … for`), numbered requirements (`N. [Name]` — full spine
//       only, not models), and `History: git log`. Mechanical checks: structural
//       presence, spine ordering (role → requirements → relationships → history),
//       and body-section separators in the locked order per file kind. Diagram
//       geometry and requirement quality stay review rules. Barrel files,
//       lib/enums/, lib/app/, and generated files are exempt.
//   G13-language plain-language canon on prose doc comments in covered files:
//       frontmatter paragraphs (the `///` block above `library;`) are capped at
//       6 lines, member docs at 2 lines, a frontmatter file's class declarations
//       carry no multi-line doc (the frontmatter IS the class doc), and banned
//       jargon tokens are rejected case-insensitively outside backticked spans.
//       Requirement lines (`N. [Name]`), the Relationships diagram, the
//       inventory columns, and the History line are exempt zones.
//   G14 naming: the ratified abxAction vocabulary (`abx*` lowerCamel
//       constants/identifiers, `ArxaKit*` PascalCase types) is the one
//       family — no rename, no rival. Three mechanical checks:
//       - no `k`-prefixed const/final declaration reintroducing Flutter's
//         `k`-style for the action/hub vocabulary (`kFooAction`, `kBarHub`,
//         …) — `abxAction`/`ArxaKitActionHub` already own it. Declarations
//         only, so unrelated Flutter constants (`kDebugMode`, `kToolbarHeight`)
//         used (not declared) in app code are untouched.
//       - no lowercase-k casing typo (`Arxa` immediately followed by lowercase `kit`)
//         anywhere an identifier is declared or referenced — canonical
//         casing is `ArxaKit` (capital K).
//       - no rival `Abx*` PascalCase type (`class`/`mixin`) — the sanctioned
//         type family is `ArxaKit*`; `abx*` stays lowerCamel constants only.

import 'dart:io';

import 'package:path/path.dart' as p;

/// A single G-rule finding (violation or warning).
class ArchGuardFinding {
  final String rule;
  final String file;
  final String msg;

  ArchGuardFinding(this.rule, this.file, this.msg);

  @override
  String toString() => '$rule $file: $msg';
}

/// Result of running [archGuard] on a target. Mirrors the Python dict shape:
/// `{passed, violations, warnings, files}`.
class ArchGuardResult {
  final bool passed;
  final List<ArchGuardFinding> violations;
  final List<ArchGuardFinding> warnings;
  final int files;

  ArchGuardResult({
    required this.passed,
    required this.violations,
    required this.warnings,
    required this.files,
  });
}

// ── patterns (identical to arch_guard.py) ────────────────────────────────────

final _importRe = RegExp(r"""^\s*import\s+(['"])([^'"]+)\1""", multiLine: true);
final _exportRe = RegExp(r"""^\s*export\s+(['"])([^'"]+)\1""", multiLine: true);
// `(?:<[^{]*>)?` tolerates a generic superclass (e.g. FutureViewModel<List<X>>)
// — without it the class line doesn't match and a busy-capable VM looks base-less.
final _classRe = RegExp(
  r'class\s+(\w+)\s*(?:extends\s+(\w+)(?:<[^{]*>)?)?(?:\s+implements\s+([^{]+?))?\s*\{',
);
final _asyncRe = RegExp(r'\b(async\b|await\b|Future\b|Stream\b)');
final _abstractClassRe = RegExp(r'\babstract\s+class\b');

// G6: view filenames — `_view.dart` plus one file per derived form factor.
final _viewFileRe = RegExp(r'_view(\.(mobile|tablet|desktop|web))?\.dart$');
// G8: locator-resolved dialog/bottom-sheet services (`locator` or
// `arxaKitLocator`).
final _uiSheetServiceRe = RegExp(r'[Ll]ocator<(Dialog|BottomSheet)Service>\(\)');

// G12: top-level declarations only — `^` anchored (enums and sealed types
// can't be nested in Dart, so an anchored match is a declaration site).
final _enumRe = RegExp(r'^enum\s+(\w+)', multiLine: true);
final _sealedRe =
    RegExp(r'^(?:abstract\s+)?sealed\s+(?:class|mixin)\s+(\w+)', multiLine: true);

/// G12: generated files declare their own types (stacked router, build_runner
/// output) — never authored, so exempt from placement conventions.
bool _isGeneratedFile(String rel) {
  final base = p.basename(rel);
  return base == 'app.router.dart' ||
      base.endsWith('.g.dart') ||
      base.endsWith('.gr.dart') ||
      base.endsWith('.gen.dart') ||
      base.endsWith('.freezed.dart');
}

// G14: a k-prefixed const/final declaration reintroducing Flutter's k-style
// for the action/hub vocabulary the abx family already owns. Declaration
// syntax only (optional `static`, `const`/`final`, optional `late`, optional
// type token) — never a bare reference, so imported Flutter constants used
// (not declared) in app code (`kDebugMode`, `kFloatingActionButtonMargin`)
// never match.
final _g14KPrefixActionRe = RegExp(
    r'\b(?:static\s+)?(?:const|final)\s+(?:late\s+)?(?:[\w<>.?]+\s+)??(k[A-Z]\w*(?:Action|Hub)\w*)\s*=');

// G14: the lowercase-k casing typo — canonical casing is `ArxaKit`
// (capital K). Lookahead keeps the pattern source from spelling the typo
// contiguously (this file is itself scanned, so a literal contiguous match
// would self-flag); it matches identically to a plain substring search,
// including mid-identifier (the `dispose…Actions` form).
final _g14KitCasingRe = RegExp(r'Arxa(?=kit)');

// G14: a rival PascalCase `Abx*` type declaration — the sanctioned type
// family is `ArxaKit*`; `abx*` stays lowerCamel constants/identifiers only.
final _g14RivalAbxTypeRe =
    RegExp(r'^(?:abstract\s+)?(?:class|mixin)\s+(Abx\w*)', multiLine: true);

// G13: the bare `library;` directive (own line, multiline-anchored).
final _libraryRe = RegExp(r'^library;', multiLine: true);

// G13: role-paragraph opener — fixed per file kind.
final _g13RoleRe = RegExp(
    r'This is the (user interface|business logic|front door|bridge to the device|store|data shape) for');

// G13: numbered-requirement line (`N. [Name]`).
final _g13RequirementsRe = RegExp(r'\d+\.\s+\[.*?\]');

// G13: history footer.
final _g13HistoryRe = RegExp(r'History:\s+git log');

/// G13: locked body-section order per file kind. Views and widgets follow the
/// file's natural build order — no locked sections.
const _g13LockedSections = <String, List<String>>{
  'viewmodel': [
    'Setup',
    'Initial state',
    'Streams',
    'Commands',
    'Actions',
    'Side effects',
    'Cleanup',
  ],
  'facade': ['Setup', 'Initial state', 'Streams', 'Writes', 'Reads', 'Cleanup'],
  'adapter': ['Setup', 'Initial state', 'Streams', 'Actions', 'Cleanup'],
  'repository': ['Setup', 'Reads', 'Writes', 'Cleanup'],
};

/// G13: section separator marker — `// ── Name ──…` (─ is U+2500, not ASCII `-`).
final _g13SectionSepRe = RegExp(r'// ──\s*(\w[\w ]*?)\s*──');

// G13-language: banned jargon tokens (checked lowercase, word-bounded).
const _g13LangBanned = <String>[
  'paradigm',
  'leverage',
  'utilize',
  'facilitates',
  'facilitate',
  'abstraction',
  'boilerplate',
  'wrapper',
  'self-contained',
  'preferredsizewidget',
  'nestedrouter',
  'indexedstack',
  'statelesswidget',
  'statefulwidget',
  'buildcontext',
  'scaffold',
];
final _g13LangBannedRe = RegExp(
    '\\b(${_g13LangBanned.map(RegExp.escape).join('|')})\\b',
    caseSensitive: false);

// G13-language: backticked spans hold code, not prose — stripped before the
// token check.
final _g13LangBacktickRe = RegExp(r'`[^`]*`');

// G13-language: a requirement line (`N. [Name]`) — an exempt zone.
final _g13LangReqLineRe = RegExp(r'^\s*///\s*\d+\.\s*\[');

// G13-language: a member-doc requirement reference (`[N. Name] …`) — the tag
// line carries the trace link, not prose; it doesn't count against the cap.
final _g13LangReqRefRe = RegExp(r'^\s*///\s*\[\d+\.');

/// G13: classify a covered file by its frontmatter kind, or null if not
/// covered. Full-spine kinds (view, viewmodel, facade, adapter, repository,
/// widget) need the complete spine; models need the light variant only.
String? _g13CoveredKind(String rel) {
  if (rel.endsWith('_viewmodel.dart')) return 'viewmodel';
  if (_viewFileRe.hasMatch(rel)) return 'view';
  if (rel.endsWith('_facade_service.dart')) return 'facade';
  if (rel.endsWith('_adapter_service.dart')) return 'adapter';
  if (rel.endsWith('_repository_service.dart')) return 'repository';
  if (rel.endsWith('_widget.dart')) return 'widget';
  if (rel.endsWith('_model.dart')) return 'model';
  return null;
}

/// G13: barrel files (export-only, no declarations) are exempt.
bool _isBarrelFile(String src) {
  if (!_exportRe.hasMatch(src)) return false;
  return !RegExp(r'\b(class|enum|mixin|void|Future)\b').hasMatch(src);
}

/// G13: extract the contiguous `///` block immediately preceding [pos] in
/// [src], or null if there isn't one. Skips trailing blank lines so the
/// comment can sit a line or two above `library;`.
List<String>? _docCommentBefore(String src, int pos) {
  final lines = src.substring(0, pos).split('\n');
  var i = lines.length - 1;
  while (i >= 0 && lines[i].trim().isEmpty) {
    i--;
  }
  final doc = <String>[];
  while (i >= 0 && lines[i].trimLeft().startsWith('///')) {
    doc.insert(0, lines[i]);
    i--;
  }
  return doc.isEmpty ? null : doc;
}

/// G13: extract diagram tier centers from the doc comment. Returns one center
/// per tier (lines containing ┌), or null when there are fewer than 2 tiers
/// (single-box diagrams have nothing to align). For multi-box tiers the
/// center is the midpoint of the leftmost ┌ and rightmost ┐.
List<double>? _g13DiagramCenters(List<String> doc) {
  final centers = <double>[];
  for (final raw in doc) {
    if (!raw.contains('┌')) continue;
    final content = raw.startsWith('/// ')
        ? raw.substring(4)
        : raw.startsWith('///')
            ? raw.substring(3)
            : raw;
    final padded = content.padRight(200);
    final lefts = <int>[];
    final rights = <int>[];
    for (int c = 0; c < padded.length; c++) {
      if (padded[c] == '┌') lefts.add(c);
      if (padded[c] == '┐') rights.add(c);
    }
    if (lefts.isNotEmpty && rights.isNotEmpty) {
      centers.add((lefts.first + rights.last) / 2);
    }
  }
  return centers.length >= 2 ? centers : null;
}

/// G13-language: per-line exempt-zone flags for one `///` block. Exempt:
/// requirement lines, the diagram (from `Relationships:` or a ```text fence
/// to the closing fence), the inventory columns (same zone), and the History
/// line itself. Zone state carries across lines but resets per block.
List<bool> _g13LangExemptLines(List<String> block) {
  final flags = <bool>[];
  var zone = false;
  for (final line in block) {
    if (_g13LangReqLineRe.hasMatch(line) || _g13LangReqRefRe.hasMatch(line)) {
      flags.add(true);
    } else if (line.contains('Relationships:') || line.contains('```text')) {
      zone = true;
      flags.add(true);
    } else if (line.contains('```')) {
      zone = false;
      flags.add(true);
    } else if (line.contains('History:')) {
      zone = false;
      flags.add(true);
    } else {
      flags.add(zone);
    }
  }
  return flags;
}

/// G13-language: run the plain-language canon over every `///` block in
/// [src]. The block above `library;` (when present) is the frontmatter —
/// paragraphs capped at 6 lines, no multi-line class docs below it; every
/// other block is a member doc capped at 2 lines. Banned tokens are checked
/// outside backticked spans and outside the exempt zones.
void _g13LanguageCheck(
    String src, String rel, List<ArchGuardFinding> violations) {
  final lines = src.split('\n');

  // Locate the frontmatter block (the contiguous `///` run above `library;`).
  int? fmStart;
  final libMatch = _libraryRe.firstMatch(src);
  if (libMatch != null) {
    final libLine = '\n'.allMatches(src.substring(0, libMatch.start)).length;
    var i = libLine - 1;
    while (i >= 0 && lines[i].trim().isEmpty) {
      i--;
    }
    if (i >= 0 && lines[i].trimLeft().startsWith('///')) {
      var s = i;
      while (s > 0 && lines[s - 1].trimLeft().startsWith('///')) {
        s--;
      }
      fmStart = s;
    }
  }

  var i = 0;
  while (i < lines.length) {
    if (!lines[i].trimLeft().startsWith('///')) {
      i++;
      continue;
    }
    final start = i;
    while (i < lines.length && lines[i].trimLeft().startsWith('///')) {
      i++;
    }
    final block = lines.sublist(start, i);
    final exempt = _g13LangExemptLines(block);
    final isFrontmatter = fmStart != null && start == fmStart;

    // Banned tokens (exempt zones and backticked spans skipped).
    for (var j = 0; j < block.length; j++) {
      if (exempt[j]) continue;
      final prose = block[j].replaceAll(_g13LangBacktickRe, '');
      final m = _g13LangBannedRe.firstMatch(prose);
      if (m != null) {
        violations.add(ArchGuardFinding('G13-language', '$rel:${start + j + 1}',
            "banned token '${m.group(1)}' — doc comments use plain language; code/type names go in backticks"));
      }
    }

    if (isFrontmatter) {
      // Paragraph cap: runs of consecutive non-empty, non-exempt lines.
      var run = 0;
      var runStart = start;
      for (var j = 0; j <= block.length; j++) {
        final content = j < block.length
            ? block[j].trimLeft().replaceFirst(RegExp(r'^///\s?'), '').trim()
            : '';
        if (j < block.length && content.isNotEmpty && !exempt[j]) {
          if (run == 0) runStart = start + j;
          run++;
        } else {
          if (run > 6) {
            violations.add(ArchGuardFinding('G13-language', '$rel:${runStart + 1}',
                'frontmatter paragraph capped at 6 lines (found $run) — plain language says it shorter'));
          }
          run = 0;
        }
      }
    } else {
      // Member doc cap: exempt lines (requirement references, zones) don't
      // count — the cap is on prose lines.
      final counted =
          [for (var j = 0; j < block.length; j++) if (!exempt[j]) j].length;
      if (counted > 2) {
        violations.add(ArchGuardFinding('G13-language', '$rel:${start + 1}',
            'member doc comment capped at 2 lines (found $counted) — plain language says it shorter'));
      }
      // In a frontmatter file the `///` block above `library;` IS the class
      // doc — a multi-line doc above a class duplicates it (one line passes).
      if (fmStart != null && block.length >= 2) {
        var k = i;
        while (k < lines.length && lines[k].trim().isEmpty) {
          k++;
        }
        if (k < lines.length &&
            RegExp(r'^\s*(?:abstract\s+)?class\s').hasMatch(lines[k])) {
          violations.add(ArchGuardFinding('G13-language', '$rel:${start + 1}',
              'class doc comment duplicating the frontmatter — the `///` block above `library;` is the class doc (a single sentence passes)'));
        }
      }
    }
  }
}

/// G9: classify a lib-relative path or import path into its service tier.
String? _serviceTier(String path) {
  final n = path.replaceAll('\\', '/');
  if (n.contains('/repositories/') || n.endsWith('_repository_service.dart')) {
    return 'repository';
  }
  if (n.contains('/facades/') || n.endsWith('_facade_service.dart')) {
    return 'facade';
  }
  if (n.contains('/adapters/') || n.endsWith('_adapter_service.dart')) {
    return 'adapter';
  }
  if (n.endsWith('_viewmodel.dart')) return 'viewmodel';
  if (_viewFileRe.hasMatch(n)) return 'view';
  return null;
}

/// G9: tiers each file tier must never import. Direction is one-way:
/// repository < adapter < facade < viewmodel — and a viewmodel's only
/// service door is the facade (never adapters/repositories directly).
/// Views talk to their viewmodel only (G6 covers the viewmodel import;
/// this covers services).
const _g9Banned = <String, Set<String>>{
  'repository': {'facade', 'adapter', 'viewmodel', 'view'},
  'adapter': {'facade', 'repository', 'viewmodel', 'view'},
  'facade': {'viewmodel', 'view'},
  'viewmodel': {'repository', 'adapter', 'view'},
  'view': {'repository', 'facade', 'adapter'},
};

const _baseVms = <String>{
  'BaseViewModel',
  'FutureViewModel',
  'MultipleFutureViewModel',
  'StreamViewModel',
  'IndexTrackingViewModel',
  // The kit's own busy-capable base (extends BaseViewModel, mixes in the
  // action-hub owner) — the regex guard can't see through package imports.
  'ArxaKitViewModel',
};

const _flutterUi = <String>{
  'package:flutter/material.dart',
  'package:flutter/widgets.dart',
  'package:flutter/cupertino.dart',
  'dart:ui',
};

const _importLayerKeywords = <(String, String)>[
  ('domain', 'domain'),
  ('application', 'application'),
  ('infrastructure', 'infrastructure'),
  ('presentation', 'presentation'),
  ('ui', 'presentation'),
  ('app', 'presentation'),
];

/// Map a `lib/...` relpath to its DDD layer. Mirrors Python `_layer`.
String _layer(String relpath) {
  final parts = relpath.replaceAll('\\', '/').split('/');
  if (parts.contains('domain')) return 'domain';
  if (parts.contains('application')) return 'application';
  if (parts.contains('infrastructure')) return 'infrastructure';
  // presentation, ui, app → presentation
  return 'presentation';
}

/// Map an import path to its logical layer. Mirrors Python `_import_layer`.
String _importLayer(String imp) {
  if (imp.startsWith('package:supabase')) return 'supabase';
  if (imp.startsWith('package:flutter/') || imp == 'dart:ui') return 'flutter';
  if (imp.startsWith('package:')) return 'external';
  // relative → sniff by path keyword
  for (final (kw, lyr) in _importLayerKeywords) {
    if (imp.contains(kw)) return lyr;
  }
  return 'unknown';
}

/// Walk `<libDir>/**/*.dart`, yielding (file, relpath-relative-to-libDir).
List<(File, String)> _dartFiles(Directory libDir) {
  final out = <(File, String)>[];
  for (final entry in libDir.listSync(recursive: true)) {
    if (entry is File && entry.path.endsWith('.dart')) {
      out.add((entry, p.relative(entry.path, from: libDir.path)));
    }
  }
  return out;
}

/// Main entry point: validate the architecture contract on `<targetDir>/lib`.
ArchGuardResult archGuard(String targetDir) {
  final libDir = Directory(p.join(targetDir, 'lib'));
  final violations = <ArchGuardFinding>[];
  final warnings = <ArchGuardFinding>[];

  if (!libDir.existsSync()) {
    return ArchGuardResult(
      passed: false,
      violations: [
        ArchGuardFinding('G0', 'lib/', 'no lib/ directory — not a Flutter target'),
      ],
      warnings: const [],
      files: 0,
    );
  }

  var nFiles = 0;
  for (final (file, rel) in _dartFiles(libDir)) {
    nFiles++;
    String src;
    try {
      src = file.readAsStringSync();
    } catch (_) {
      continue;
    }
    final layer = _layer(rel);
    final impPaths = _importRe.allMatches(src).map((m) => m.group(2)!).toList();
    final impLayers = <(String, String)>{
      for (final path in impPaths) (_importLayer(path), path),
    };

    final hasFlutterUi = impPaths.any((p) => _flutterUi.contains(p));
    final hasFlutterPkg = impPaths.any((p) => p.startsWith('package:flutter/'));
    final hasSupabase = impPaths.any((p) => p.startsWith('package:supabase'));

    // ── G1 layering ────────────────────────────────────────────────────────
    if (layer == 'domain') {
      if (hasFlutterPkg) {
        violations.add(ArchGuardFinding(
            'G1', rel, 'domain must not import Flutter (pure Dart)'));
      }
      if (hasSupabase) {
        violations.add(
            ArchGuardFinding('G1', rel, 'domain must not import Supabase'));
      }
      for (final (lyr, path) in impLayers) {
        if (lyr == 'infrastructure' || lyr == 'presentation') {
          violations.add(ArchGuardFinding(
              'G1', rel, 'domain must not import $lyr ($path)'));
        }
      }
    } else if (layer == 'application') {
      if (hasFlutterUi) {
        violations.add(ArchGuardFinding(
            'G1', rel, 'application must not import Flutter widget UI'));
      }
      if (hasSupabase) {
        violations.add(ArchGuardFinding(
            'G1', rel, 'application must not import Supabase (go through a Port)'));
      }
      for (final (lyr, path) in impLayers) {
        if (lyr == 'infrastructure') {
          violations.add(ArchGuardFinding('G1', rel,
              'application must not import infrastructure ($path) — use a domain Port'));
        }
      }
    }

    // ── G5 Supabase confinement (covers all non-infra layers) ──────────────
    if (hasSupabase && layer != 'infrastructure') {
      violations.add(ArchGuardFinding(
          'G5', rel, 'Supabase confined to infrastructure (found import in $layer)'));
    }

    // ── G2 + G3 ViewModels ─────────────────────────────────────────────────
    final isVm = rel.endsWith('_viewmodel.dart');
    if (isVm) {
      final classes = _classRe.allMatches(src).toList();
      final extendsAny = classes.any((c) => c.group(2) != null);
      // A generated state-machine base (`*ViewModelBase` in a sibling
      // `*_viewmodel.gen.dart`) itself extends a Stacked base — so a stub extending
      // it is busy-capable. Accept that convention alongside the exact Stacked bases.
      final extendsBase = classes.any((c) {
        final e = c.group(2);
        if (e == null) return false;
        return _baseVms.contains(e) ||
            e.endsWith('ViewModelBase') ||
            e.endsWith('BaseViewModel');
      });
      if (!extendsBase) {
        if (extendsAny) {
          violations.add(ArchGuardFinding('G2', rel,
              'ViewModel must extend a Stacked base (BaseViewModel/FutureViewModel/…)'));
        } else {
          violations.add(ArchGuardFinding(
              'G2', rel, 'ViewModel class missing — expected a class extending BaseViewModel'));
        }
      }
      if (_asyncRe.hasMatch(src) && !extendsBase) {
        violations.add(ArchGuardFinding(
            'G3', rel, 'async in ViewModel without a busy-capable base'));
      }

      // ── G11 viewmodels never re-export ──────────────────────────────────
      if (_exportRe.hasMatch(src)) {
        violations.add(ArchGuardFinding('G11', rel,
            'viewmodel re-exports — views/widgets import model barrels and kit types directly; only behavior flows through the viewmodel'));
      }

      // ── G7 no mutable static state on a viewmodel ──────────────────────
      for (final line in src.split('\n')) {
        final t = line.trimLeft();
        if (!t.startsWith('static ')) continue;
        if (t.startsWith('static const ') ||
            t.startsWith('static final ') ||
            t.startsWith('static late final ')) {
          continue;
        }
        // Methods/getters/setters are fine; only plain fields couple screens.
        if (t.contains('(') || t.contains(' get ') || t.contains(' set ')) {
          continue;
        }
        if (!t.trimRight().endsWith(';')) continue;
        violations.add(ArchGuardFinding('G7', rel,
            'mutable static field on a ViewModel — cross-screen intent belongs in route params or facade streams'));
        break;
      }
    }

    // ── G4 infra repos implement a Port (skip the abstract base adapter) ────
    if (layer == 'infrastructure' && rel.endsWith('_repository.dart')) {
      final isAbstractBase = _abstractClassRe.hasMatch(src);
      if (!isAbstractBase) {
        final classes = _classRe.allMatches(src).toList();
        if (!classes.any((c) {
          final impl = c.group(3);
          return impl != null && impl.contains('Repository');
        })) {
          warnings.add(ArchGuardFinding('G4', rel,
              'infrastructure repository does not declare `implements <Port>Repository`'));
        }
      }
    }

    // ── G6 one viewmodel per view ─────────────────────────────────────────
    if (_viewFileRe.hasMatch(rel)) {
      final ownVm =
          p.basename(rel).replaceFirst(_viewFileRe, '_viewmodel.dart');
      for (final imp in impPaths) {
        final base = p.basename(imp);
        if (base.endsWith('_viewmodel.dart') && base != ownVm) {
          violations.add(ArchGuardFinding('G6', rel,
              'view imports a foreign viewmodel ($imp) — navigation intent travels via route params, shared state via facade streams'));
        }
      }
    }

    // ── G8 dialogs/bottom sheets from UI are VM actions ───────────────────
    if ((_viewFileRe.hasMatch(rel) || rel.endsWith('_widget.dart')) &&
        _uiSheetServiceRe.hasMatch(src)) {
      violations.add(ArchGuardFinding('G8', rel,
          'DialogService/BottomSheetService used from UI — confirm-then-act flows are viewmodel actions via ArxaKitNotificationService (builder playbook: View/ViewModel boundaries)'));
    }

    // ── G9 service-layer dependency direction ────────────────────────────
    final tier = _serviceTier(rel);
    if (tier != null) {
      for (final imp in impPaths) {
        final impTier = _serviceTier(imp);
        if (impTier != null && _g9Banned[tier]!.contains(impTier)) {
          violations.add(ArchGuardFinding('G9', rel,
              '$tier must not import a $impTier ($imp) — direction is repository < adapter < facade < viewmodel'));
        }
      }
    }

    // ── G10 no repeated URIs within imports / within exports ─────────────
    final exportPaths =
        _exportRe.allMatches(src).map((m) => m.group(2)!).toList();
    for (final (kind, uris) in [('import', impPaths), ('export', exportPaths)]) {
      final seen = <String>{};
      for (final uri in uris) {
        if (!seen.add(uri)) {
          violations.add(ArchGuardFinding(
              'G10', rel, 'duplicate $kind of $uri — one directive per URI'));
        }
      }
    }

    // ── G14 naming: the ratified abxAction vocabulary is the one family ───
    final relPosix = rel.replaceAll('\\', '/');
    if (!_isGeneratedFile(relPosix)) {
      for (final m in _g14KPrefixActionRe.allMatches(src)) {
        violations.add(ArchGuardFinding('G14', rel,
            "k-prefixed action/hub constant '${m.group(1)}' — the abxAction vocabulary owns this family, no k-prefix reintroduction"));
      }
      if (_g14KitCasingRe.hasMatch(src)) {
        violations.add(ArchGuardFinding('G14', rel,
            "lowercase-k casing typo ('Arxa' immediately followed by 'kit') — canonical casing is 'ArxaKit' (capital K)"));
      }
      for (final m in _g14RivalAbxTypeRe.allMatches(src)) {
        violations.add(ArchGuardFinding('G14', rel,
            "rival type ${m.group(1)} — the sanctioned type family is ArxaKit*; abx* stays lowerCamel constants/identifiers only"));
      }
    }

    // ── G12 enums/sealed types live in lib/enums/ ────────────────────────
    if (!relPosix.startsWith('enums/') && !_isGeneratedFile(relPosix)) {
      for (final m in _enumRe.allMatches(src)) {
        violations.add(ArchGuardFinding('G12', rel,
            'enum ${m.group(1)} declared outside lib/enums/ — enums and sealed discriminator types live in lib/enums/<shell>_enums/'));
      }
      for (final m in _sealedRe.allMatches(src)) {
        violations.add(ArchGuardFinding('G12', rel,
            'sealed type ${m.group(1)} declared outside lib/enums/ — enums and sealed discriminator types live in lib/enums/<shell>_enums/'));
      }
    }

    // ── G13 semantic frontmatter ──────────────────────────────────────────
    final kind = _g13CoveredKind(relPosix);
    if (kind != null &&
        !relPosix.startsWith('enums/') &&
        !relPosix.startsWith('app/') &&
        !_isGeneratedFile(relPosix) &&
        !_isBarrelFile(src)) {
      final libMatch = _libraryRe.firstMatch(src);
      if (libMatch == null) {
        violations.add(ArchGuardFinding(
            'G13', rel, 'covered $kind file missing `library;` directive'));
      } else {
        final doc = _docCommentBefore(src, libMatch.start);
        if (doc == null || doc.length < 3) {
          violations.add(ArchGuardFinding('G13', rel,
              'covered $kind file missing doc comment (≥3 `///` lines) above `library;`'));
        } else {
          final docText = doc.join('\n');
          if (!_g13RoleRe.hasMatch(docText)) {
            violations.add(ArchGuardFinding('G13', rel,
                'doc comment missing role paragraph (`This is the … for`)'));
          }
          if (kind != 'model') {
            if (!_g13RequirementsRe.hasMatch(docText)) {
              violations.add(ArchGuardFinding('G13', rel,
                  'doc comment missing numbered requirements (`N. [Name]`)'));
            }
            if (!_g13HistoryRe.hasMatch(docText)) {
              violations.add(ArchGuardFinding(
                  'G13', rel, 'doc comment missing `History: git log …`'));
            }
            // G13: diagram tier center-alignment (mechanical check — ±1 of
            // the middle-tier anchor).
            final centers = _g13DiagramCenters(doc);
            if (centers != null) {
              final anchorCenter = centers[centers.length ~/ 2];
              for (int ti = 0; ti < centers.length; ti++) {
                if ((centers[ti] - anchorCenter).abs() > 1.0) {
                  violations.add(ArchGuardFinding('G13', rel,
                      'diagram tier centers not aligned (tier $ti center=${centers[ti]}, anchor center=$anchorCenter)'));
                  break;
                }
              }
            }

            // G13: spine parts in order (role → requirements → relationships
            // → history). Only when all four markers are present — missing
            // markers are already reported by the presence checks above.
            final roleM = _g13RoleRe.firstMatch(docText);
            final reqM = _g13RequirementsRe.firstMatch(docText);
            final histM = _g13HistoryRe.firstMatch(docText);
            int? relPos;
            for (final marker in ['┌', 'Relationships:']) {
              final p = docText.indexOf(marker);
              if (p >= 0 && (relPos == null || p < relPos)) relPos = p;
            }
            if (roleM != null &&
                reqM != null &&
                histM != null &&
                relPos != null) {
              if (!(roleM.start < reqM.start &&
                  reqM.start < relPos &&
                  relPos < histM.start)) {
                violations.add(ArchGuardFinding('G13', rel,
                    'spine parts out of order (expected: role → requirements → relationships → history)'));
              }
            }
          }
        }
      }

      // G13: body-section separators in the locked order for the file kind.
      // Operates on the code body (src), not the doc comment. Views and widgets
      // have no locked sections — natural build order.
      final locked = _g13LockedSections[kind];
      if (locked != null) {
        final found = _g13SectionSepRe
            .allMatches(src)
            .map((m) => m.group(1)!.trim())
            .toList();
        String? prevName;
        var prevLockedIdx = -1;
        for (final name in found) {
          final pos = locked.indexOf(name);
          if (pos < 0) {
            warnings.add(ArchGuardFinding('G13', rel,
                "unknown section separator '$name' — not in the locked order for $kind"));
            continue;
          }
          if (pos < prevLockedIdx) {
            violations.add(ArchGuardFinding('G13', rel,
                "section separator '$prevName' appears before '$name' — locked order is ${locked.join(' → ')}"));
            break;
          }
          prevLockedIdx = pos;
          prevName = name;
        }
      }

      // ── G13-language plain-language canon on doc comments ─────────────
      _g13LanguageCheck(src, rel, violations);
    }
  }

  violations.sort((a, b) {
    final byRule = a.rule.compareTo(b.rule);
    return byRule != 0 ? byRule : a.file.compareTo(b.file);
  });
  warnings.sort((a, b) {
    final byRule = a.rule.compareTo(b.rule);
    return byRule != 0 ? byRule : a.file.compareTo(b.file);
  });

  return ArchGuardResult(
    passed: violations.isEmpty,
    violations: violations,
    warnings: warnings,
    files: nFiles,
  );
}
