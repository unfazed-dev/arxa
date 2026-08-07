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
//       AppBoxKitNotificationService's confirm/prompt/alert/notice verbs.
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
// `appBoxKitLocator`).
final _uiSheetServiceRe = RegExp(r'[Ll]ocator<(Dialog|BottomSheet)Service>\(\)');

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
  'AppBoxKitViewModel',
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
          'DialogService/BottomSheetService used from UI — confirm-then-act flows are viewmodel actions via AppBoxKitNotificationService (builder playbook: View/ViewModel boundaries)'));
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
