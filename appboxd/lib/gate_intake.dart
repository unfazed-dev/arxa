// Intake gate — port of gates/intake/intake.sh to pure Dart.
//
// The TRACEABILITY gate (plan 10.6; architecture §22): every registry surface
// traces to an intake answer/brief, and every intake answer/brief traces to a
// registry surface. No orphans either way. Duplicate registry ids are a bug —
// ids are permanent.
//
// Sources (first non-empty wins):
//   1. intake answers — pipeline/state/run.intake.json, then default.intake.json
//   2. hand-written brief (10.7) — the design's brief.md, then docs/design/brief.md
//
// The registry path comes from structure.json's "registry" field (default
// models/screens_model/registry.json), relative to the design root — the
// engine's seed path, never the legacy docs/design/ path. If no source AND no
// registry exist, the gate passes vacuously (greenfield). A registry with
// entries but no traceable source is a FAIL: every entry is untraced.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gates.dart';

GateResult intakeGate(GateContext ctx) {
  final repoRoot = ctx.repoRoot;
  final designRoot = ctx.designRoot;

  // ---- resolve inputs (answers → registry → brief) ---------------------------
  final answersPath = _resolveAnswers(repoRoot);
  final registryPath = _resolveRegistry(designRoot);
  final briefPath = _resolveBrief(designRoot, repoRoot);

  final details = <String>[];
  var fails = 0;

  void ok(String msg) => details.add('  ✓ intake: $msg');
  void fail(String msg) {
    details.add('  ✗ intake: $msg');
    ctx.sarif.result('intake', 'error', registryPath, msg);
    fails++;
  }

  // ---- collect SOURCE surface ids -------------------------------------------
  final sourceIds = <String>[];
  String? sourceLabel;

  if (answersPath != null) {
    try {
      final data = jsonDecode(File(answersPath).readAsStringSync());
      // The state slot wraps answers under "answers"; a raw answers document is
      // also accepted (the engine's format).
      final answers =
          (data is Map && data.containsKey('answers')) ? data['answers'] : data;
      if (answers is Map) {
        final surfaces = answers['surfaces'];
        if (surfaces is List) {
          for (final s in surfaces) {
            if (s is Map && s['id'] is String) {
              sourceIds.add(s['id'] as String);
            }
          }
        }
        sourceLabel = 'intake answers';
      }
    } catch (e) {
      fail('answers file $answersPath does not parse — $e');
      return GateResult.fail('intake: FAIL ($fails check(s))', details);
    }
  }

  // hand-written brief (10.7): parse the surface table for <shell>.<short> ids,
  // the same pattern the engine's seed_from_brief uses.
  if (sourceIds.isEmpty && briefPath != null) {
    _collectBriefIds(briefPath, sourceIds);
    if (sourceIds.isNotEmpty) sourceLabel = 'brief surface table';
  }

  // ---- collect REGISTRY surface ids -----------------------------------------
  if (!File(registryPath).existsSync()) {
    if (sourceIds.isEmpty) {
      ok('no intake answers and no registry — nothing to trace (greenfield)');
      return GateResult.ok('intake: PASS — nothing to trace (greenfield).', details);
    }
    fail('$sourceLabel has ${sourceIds.length} surface(s) but registry not found '
        'at $registryPath — run appbox intake emit to seed it');
    return GateResult.fail('intake: FAIL ($fails check(s))', details);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(File(registryPath).readAsStringSync());
  } catch (e) {
    fail('registry $registryPath does not parse — $e');
    return GateResult.fail('intake: FAIL ($fails check(s))', details);
  }
  if (decoded is! List) {
    fail('registry must be a list of entries, got ${_jsonTypeName(decoded)}');
    return GateResult.fail('intake: FAIL ($fails check(s))', details);
  }
  final registry = decoded;

  final registryIds = <String>[];
  for (var i = 0; i < registry.length; i++) {
    final e = registry[i];
    if (e is! Map || !e.containsKey('id')) {
      fail("registry[$i] is missing 'id'");
      return GateResult.fail('intake: FAIL ($fails check(s))', details);
    }
    registryIds.add(e['id'].toString());
  }

  // ---- registry exists, no source → every entry untraced --------------------
  if (sourceIds.isEmpty) {
    fail('${registryIds.length} registry surface(s) but no intake answers or brief '
        'found — every entry is untraced (provide --answers or a brief)');
    for (final sid in registryIds) {
      fail("surface '$sid' is in the registry but has no intake answer or brief");
    }
    return GateResult.fail('intake: FAIL ($fails check(s))', details);
  }

  // ---- orphans either way + duplicate ids -----------------------------------
  final sourceSet = sourceIds.toSet();
  final registrySet = registryIds.toSet();

  final orphanAnswers = sourceSet.difference(registrySet).toList()..sort();
  final unanswered = registrySet.difference(sourceSet).toList()..sort();
  final dupCounts = <String, int>{};
  for (final id in registryIds) {
    dupCounts[id] = (dupCounts[id] ?? 0) + 1;
  }
  final dups = dupCounts.entries
      .where((e) => e.value > 1)
      .map((e) => e.key)
      .toList()
    ..sort();

  for (final sid in orphanAnswers) {
    fail("surface '$sid' is in $sourceLabel but NOT in the registry — "
        'an intake answer with no registry entry (orphan answer)');
  }
  for (final sid in unanswered) {
    fail("surface '$sid' is in the registry but NOT in $sourceLabel — "
        'a registry entry with no intake answer (unanswered surface)');
  }
  for (final sid in dups) {
    fail("surface '$sid' appears more than once in the registry — ids are permanent");
  }

  if (fails == 0) {
    ok('${registryIds.length} registry surface(s) trace to $sourceLabel '
        '(no orphans either way)');
    return GateResult.ok(
      'intake: PASS — ${registryIds.length} registry surface(s) trace to '
      '$sourceLabel (no orphans either way).',
      details,
    );
  }
  return GateResult.fail('intake: FAIL ($fails check(s))', details);
}

// ── path resolvers ───────────────────────────────────────────────────────────

String? _resolveAnswers(String repoRoot) {
  final run = File('$repoRoot/pipeline/state/run.intake.json');
  if (run.existsSync()) return run.path;
  final def = File('$repoRoot/pipeline/state/default.intake.json');
  if (def.existsSync()) return def.path;
  return null;
}

/// structure.json's "registry" field (default models/screens_model/registry.json),
/// relative to the design root — the engine's seed path.
String _resolveRegistry(String designRoot) {
  var rel = 'models/screens_model/registry.json';
  final struct = File('$designRoot/structure.json');
  if (struct.existsSync()) {
    try {
      final data = jsonDecode(struct.readAsStringSync());
      if (data is Map &&
          data['registry'] is String &&
          (data['registry'] as String).isNotEmpty) {
        rel = data['registry'] as String;
      }
    } catch (_) {
      // keep default on parse error
    }
  }
  return '$designRoot/$rel';
}

String? _resolveBrief(String designRoot, String repoRoot) {
  final local = File('$designRoot/brief.md');
  if (local.existsSync()) return local.path;
  final docs = File('$repoRoot/docs/design/brief.md');
  if (docs.existsSync()) return docs.path;
  return null;
}

// ── brief surface-table parsing (10.7) ───────────────────────────────────────

final _idRe = RegExp(r'^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$');
final _sepChars = {'-', ':', ' '};

/// Parse a hand-written brief's surface table for `<shell>.<short>` ids, the same
/// pattern the engine's seed_from_brief uses. Dedup preserving order.
void _collectBriefIds(String briefPath, List<String> out) {
  final md = File(briefPath).readAsStringSync();
  for (final line in md.split('\n')) {
    final s = line.trim();
    if (!s.startsWith('|') || !s.endsWith('|')) continue;
    final cells = _stripChar(s, '|')
        .split('|')
        .map((c) => _stripChar(c.trim(), '`'))
        .toList();
    if (cells.every(_isSeparatorCell)) continue; // table separator row
    for (final c in cells) {
      final t = c.trim();
      if (_idRe.hasMatch(t)) {
        if (!out.contains(t)) out.add(t);
        break;
      }
    }
  }
}

/// Strip all leading/trailing occurrences of [ch] from [s] (Python str.strip).
String _stripChar(String s, String ch) {
  final unit = ch.codeUnitAt(0);
  var start = 0, end = s.length;
  while (start < end && s.codeUnitAt(start) == unit) {
    start++;
  }
  while (end > start && s.codeUnitAt(end - 1) == unit) {
    end--;
  }
  return s.substring(start, end);
}

bool _isSeparatorCell(String c) {
  if (c.isEmpty) return false;
  for (final ch in c.split('')) {
    if (!_sepChars.contains(ch)) return false;
  }
  return true;
}

/// Python type names for JSON values, so "got dict" matches the bash gate.
String _jsonTypeName(Object? v) {
  if (v is Map) return 'dict';
  if (v is List) return 'list';
  if (v is String) return 'str';
  return v.runtimeType.toString();
}
