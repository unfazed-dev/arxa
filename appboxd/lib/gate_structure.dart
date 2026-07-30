// Structure gate — port of gates/structure/structure.sh to pure Dart.
//
// Owns the shell/surface MAP. Checks (cheapest first, all must pass):
//   §6  fresh   — design tree matches the frozen designHash (hash-bound approval)
//   S0  input   — structure.json present and parses
//   S1a sync    — structure.json in sync with the authored layer: the same
//                 screen IDs + surfaces as registry.json, and the same
//                 shellRoots as app.routes.js. The in-Dart equivalent of
//                 emit_structure --check (regenerate-to-memory compare).
//   S1b tracked — structure.json committed (porcelain clean for it; git diff
//                 --exit-code cannot see a new file)
//   S2  resolve — every shell root lands on a screen WITH a surface

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gates.dart';

GateResult structureGate(GateContext ctx) {
  const designRel = 'designs/appbox';
  final designRoot = ctx.designRoot;
  final structurePath = '$designRoot/structure.json';
  final details = <String>[];
  var groupFails = 0;

  void ok(String msg) => details.add('  ✓ $msg');

  // fail() counts one failed check GROUP (matching the bash "$F check group(s)").
  void fail(String msg) {
    details.add('  ✗ $msg');
    ctx.sarif.result('structure', 'error', '$designRel/structure.json', msg);
    groupFails++;
  }

  // ---- §6: design freshness (hash-bound approval), before any assertion ----
  final fresh = assertDesignFresh(ctx);
  if (fresh != null) {
    details.add(fresh);
    ctx.sarif.result('structure', 'error', designRel,
        'design moved after freeze (designHash mismatch, §6)');
    return GateResult.fail(
        'structure: FAIL — design moved after freeze (designHash, §6)', details);
  }

  // ---- S0: input present + parses (missing input never passes quietly) ----
  final structureFile = File(structurePath);
  if (!structureFile.existsSync()) {
    fail('structure: no $designRel/structure.json — the structure gate\'s input '
        'is missing (run emit_structure.py)');
    return GateResult.fail('structure: FAIL ($groupFails check group(s))', details);
  }
  Map<String, dynamic> structure;
  try {
    structure =
        jsonDecode(structureFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    fail('structure: $designRel/structure.json does not parse — $e');
    return GateResult.fail('structure: FAIL ($groupFails check group(s))', details);
  }

  // ---- S1a: in sync with the authored registry (ids + surfaces + shellRoots) ----
  if (_authoredInSync(designRoot, structure)) {
    ok('structure: structure.json is in sync with the authored registry');
  } else {
    fail('structure: $designRel/structure.json drifted from the authored '
        'registry — re-run emit_structure.py');
  }

  // ---- S1b: tracked + committed (porcelain, NEVER git diff --exit-code) ----
  final rel = _relativeUnder(structurePath, ctx.repoRoot);
  if (rel == null) {
    details.add(
        '  · structure: structure.json sits outside this repo — porcelain tracking skipped');
  } else {
    final dirty = assertTreeClean(ctx.repoRoot);
    final code = dirty == null ? null : _porcelainCode(dirty, rel);
    if (code == null) {
      ok('structure: structure.json is tracked and committed');
    } else {
      final label = code == '??' ? 'untracked' : 'modified';
      fail('structure: $designRel/structure.json is $label — regenerate then '
          'commit it (porcelain, not git-diff)');
    }
  }

  // ---- S2: resolve + reconcile (every shell root lands on a surfaced screen) ----
  final s2 = _resolveCheck(structure, designRel);
  for (final err in s2.errors) {
    details.add('  ✗ $err');
    ctx.sarif.result('structure', 'error', '$designRel/structure.json', err);
  }
  if (s2.errors.isEmpty) {
    if (s2.reconcile != null) details.add('  ✓ ${s2.reconcile}');
    if (s2.exclusions != null) details.add('    ${s2.exclusions}');
  } else {
    groupFails++;
  }

  if (groupFails > 0) {
    return GateResult.fail('structure: FAIL ($groupFails check group(s))', details);
  }
  return GateResult.ok(
      'structure: PASS — $designRel/structure.json resolves and is in sync.',
      details);
}

// ── S1a: registry.json + app.routes.js drift compare ──────────────────────

/// True iff structure.json's screen IDs + surfaces match registry.json, and its
/// shellRoots match app.routes.js (when that file is present and parseable).
/// Any missing/unparseable input is a drift.
bool _authoredInSync(String designRoot, Map<String, dynamic> structure) {
  final registryFile =
      File('$designRoot/models/screens_model/registry.json');
  if (!registryFile.existsSync()) return false;

  final regSurface = <String, dynamic>{};
  try {
    final reg = jsonDecode(registryFile.readAsStringSync());
    if (reg is! List) return false;
    for (final e in reg) {
      if (e is Map && e['id'] is String) {
        regSurface[e['id'] as String] = e['surface'];
      }
    }
  } catch (_) {
    return false;
  }

  final screens = structure['screens'];
  if (screens is! List) return false;
  final stSurface = <String, dynamic>{};
  for (final s in screens) {
    if (s is Map && s['id'] is String) stSurface[s['id'] as String] = s['surface'];
  }

  if (regSurface.length != stSurface.length) return false;
  for (final id in regSurface.keys) {
    if (stSurface[id] != regSurface[id]) return false;
  }

  // shellRoots originate in app.routes.js; cross-check when available.
  final routesFile = File('$designRoot/app.routes.js');
  if (routesFile.existsSync()) {
    final routeRoots = _shellRootsFromRoutes(routesFile.readAsStringSync());
    if (routeRoots != null && !_shellRootsEqual(routeRoots, structure['shellRoots'])) {
      return false;
    }
  }
  return true;
}

/// Lifts the exported `shellRoots` object out of app.routes.js as a Dart map.
/// Returns null when the export is absent or unparsable (caller skips).
Map<String, String>? _shellRootsFromRoutes(String src) {
  final block = RegExp(
          r'export\s+const\s+shellRoots\s*=\s*\{([^}]*)\}',
          dotAll: true)
      .firstMatch(src);
  if (block == null) return null;
  final out = <String, String>{};
  // Non-raw string: the regex matches key: 'value' or key: "value" (the value
  // holds any char that is not a quote). ['"] == the python ['\"] class.
  final pairRe = RegExp("([A-Za-z_][\\w-]*)\\s*:\\s*['\"]([^'\"]+)['\"]");
  for (final m in pairRe.allMatches(block.group(1)!)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out.isEmpty ? null : out;
}

bool _shellRootsEqual(Map<String, String> a, dynamic b) {
  if (b is! Map || b.length != a.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

// ── S1b: porcelain helpers ────────────────────────────────────────────────

/// Path of [path] relative to [root], or null if [path] is not under [root].
String? _relativeUnder(String path, String root) {
  final prefix = root.endsWith('/') ? root : '$root/';
  if (path.startsWith(prefix)) return path.substring(prefix.length);
  return null;
}

/// The 2-char git status code for [rel] within [dirty] porcelain lines, or null
/// if [rel] is clean. Lines are `XY <space> PATH`; structure.json is never a rename.
String? _porcelainCode(List<String> dirty, String rel) {
  for (final line in dirty) {
    if (line.length >= 3 && line.substring(3) == rel) return line.substring(0, 2);
  }
  return null;
}

// ── S2: resolve + reconcile ───────────────────────────────────────────────

/// Validates that every shell root lands on a surfaced screen, and reports the
/// reconcile tally. reconcile/exclusions are populated only when there are no
/// errors (the python prints the ok line only on the success path).
({List<String> errors, String? reconcile, String? exclusions}) _resolveCheck(
    Map<String, dynamic> structure, String designRel) {
  final errors = <String>[];
  final screens = structure['screens'];
  final roots = structure['shellRoots'];

  if (screens is! List || screens.isEmpty) {
    errors.add('structure: $designRel/structure.json needs a non-empty "screens" list');
    return (errors: errors, reconcile: null, exclusions: null);
  }
  if (roots is! Map || roots.isEmpty) {
    errors.add('structure: $designRel/structure.json needs a non-empty "shellRoots" object');
    return (errors: errors, reconcile: null, exclusions: null);
  }

  // shellRoots carry routes, not screen ids — the structural question is: does
  // every shell group have at least one frozen (non-excluded) screen?
  final groupsWithSurface = <String>{};
  for (final s in screens) {
    if (s is Map && s['surface'] != null && s['shell'] is String) {
      groupsWithSurface.add(s['shell'] as String);
    }
  }
  final keys = roots.keys.cast<String>().toList()..sort();
  for (final group in keys) {
    if (!groupsWithSurface.contains(group)) {
      errors.add("structure: shell '$group' has no screen with a surface — its "
          'landing screen was excluded or never designed');
    }
  }
  if (errors.isNotEmpty) {
    return (errors: errors, reconcile: null, exclusions: null);
  }

  final n = screens.length;
  final excl = <String>[];
  for (final s in screens) {
    if (s is Map && s['surface'] == null) excl.add(s['id'] as String);
  }
  final reconcile = 'structure: $n screens / ${n - excl.length} frozen / '
      '${excl.length} excluded, ${roots.length} shell roots land on a surface';
  return (
    errors: errors,
    reconcile: reconcile,
    exclusions: excl.isNotEmpty ? 'exclusions (surface:null): ${excl.join(', ')}' : null,
  );
}
