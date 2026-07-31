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
// `(?:<[^{]*>)?` tolerates a generic superclass (e.g. FutureViewModel<List<X>>)
// — without it the class line doesn't match and a busy-capable VM looks base-less.
final _classRe = RegExp(
  r'class\s+(\w+)\s*(?:extends\s+(\w+)(?:<[^{]*>)?)?(?:\s+implements\s+([^{]+?))?\s*\{',
);
final _asyncRe = RegExp(r'\b(async\b|await\b|Future\b|Stream\b)');
final _abstractClassRe = RegExp(r'\babstract\s+class\b');

const _baseVms = <String>{
  'BaseViewModel',
  'FutureViewModel',
  'MultipleFutureViewModel',
  'StreamViewModel',
  'IndexTrackingViewModel',
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
