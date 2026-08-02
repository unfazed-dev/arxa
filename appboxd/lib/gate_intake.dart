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
// When the source is intake answers AND a brief exists on disk, the gate ALSO
// checks the brief carries the chain's sections (`## Surface inventory`, plus
// `## Layout template` when the answers declare one) — a stale standalone
// brief fails and must be re-emitted via the chain. Hand-written briefs
// without answers (10.7) skip this section check entirely.
//
// The registry path comes from structure.json's "registry" field (default
// models/screens_model/registry.json), relative to the design root — the
// engine's seed path, never the legacy docs/design/ path. If no source AND no
// registry exist, the gate passes vacuously (greenfield). A registry with
// entries but no traceable source is a FAIL: every entry is untraced.
//
// `--project <name>` points the gate at a project's own intake shell
// (~/.appbox/projects/<name>/intake) instead of the studio: answers.json,
// brief.md, registry.json, flows.json — the flat layout IntakeEngine.emit
// writes. The shell layout is fixed, so structure.json plays no part in
// project mode. Without the flag nothing changes: the gate reads the studio's
// design root and the repo's pipeline state exactly as before.
//
// Project mode also runs the FLOWS check: answers.json is the SSOT for flows
// and flows.json is its projection, so `flows.json ≡ emitFlows(answers)` must
// hold. Studio edits dual-write both files; this check is what stops the two
// from drifting apart silently. It is project-only by construction — the
// studio's own models/screens_model/flows.json is a hand-authored triad lens,
// not a projection of any answers document.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gates.dart';
import 'package:appboxd/intake.dart' show emitFlows;
import 'package:appboxd/project.dart';

GateResult intakeGate(GateContext ctx, {String? project}) {
  final repoRoot = ctx.repoRoot;
  final designRoot = ctx.designRoot;

  // ---- resolve inputs (answers → registry → brief) ---------------------------
  // sourceHome is only for messages — it names *which* tree we traced, so a
  // project's vacuous PASS can't be misread as the studio's.
  final String? answersPath;
  final String registryPath;
  final String? briefPath;
  final String? flowsPath;
  final String sourceHome;

  if (project != null) {
    // Same guard order as IntakeEngine.emit: name first (it also keeps a
    // path-traversal name from escaping ~/.appbox/projects), then existence.
    if (!validProjectName(project)) {
      return GateResult.env('intake: bad project name "$project" — '
          'lowercase alnum + dash, like a surface id');
    }
    if (!Directory(projectDir(project)).existsSync()) {
      return GateResult.env('intake: no such project "$project" — nothing at '
          '${projectDir(project)} (run appbox project init $project)');
    }
    final intakeDir = shellDir(project, 'intake');
    answersPath = _emitted('$intakeDir/answers.json');
    registryPath = '$intakeDir/registry.json';
    briefPath = _emitted('$intakeDir/brief.md');
    flowsPath = _emitted('$intakeDir/flows.json');
    sourceHome = intakeDir;
  } else {
    answersPath = _resolveAnswers(repoRoot);
    registryPath = _resolveRegistry(designRoot);
    briefPath = _resolveBrief(designRoot, repoRoot);
    flowsPath = null; // studio flows.json is authored, not projected — see header
    sourceHome = designRoot;
  }

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
  Map<dynamic, dynamic>? answersDoc;

  if (answersPath != null) {
    try {
      final data = jsonDecode(File(answersPath).readAsStringSync());
      // The state slot wraps answers under "answers"; a raw answers document is
      // also accepted (the engine's format).
      final answers =
          (data is Map && data.containsKey('answers')) ? data['answers'] : data;
      if (answers is Map) {
        answersDoc = answers;
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

  // ---- brief-section check (chain briefs only) -------------------------------
  // When the source is intake answers and a brief exists, the brief must be
  // the UNIFIED chain brief: `## Surface inventory` always, `## Layout
  // template` when the answers declare a layoutTemplate. Hand-written briefs
  // without answers (10.7) skip this entirely.
  if (sourceLabel == 'intake answers' && briefPath != null) {
    const chainHint = 're-emit via the chain: appbox emit story-map '
        '--brief-out <brief.md> --answers <answers.json>';
    final md = File(briefPath).readAsStringSync();
    bool hasHeading(String prefix) =>
        md.split('\n').any((l) => l.trimLeft().startsWith(prefix));
    if (!hasHeading('## Surface inventory')) {
      fail("brief $briefPath has no '## Surface inventory' heading — $chainHint");
    }
    if (answersDoc!.containsKey('layoutTemplate') &&
        !hasHeading('## Layout template')) {
      fail('answers declare a layoutTemplate but brief $briefPath has no '
          "'## Layout template' heading — $chainHint");
    }
  }

  // ---- flows ≡ emitFlows(answers) -------------------------------------------
  // answers.json is the SSOT; flows.json is its projection. Studio edits
  // dual-write both, so the two must AGREE — this is the check that catches a
  // write that landed in one file and not the other.
  if (answersDoc != null && flowsPath != null) {
    Object? flowsDoc;
    var parsed = false;
    try {
      flowsDoc = jsonDecode(File(flowsPath).readAsStringSync());
      parsed = true;
    } catch (e) {
      fail('flows file $flowsPath does not parse — $e');
    }
    if (parsed && flowsDoc is! List) {
      fail('flows $flowsPath must be a list of flows, got '
          '${_jsonTypeName(flowsDoc)}');
    } else if (parsed) {
      List<Map<String, dynamic>>? projected;
      try {
        projected = emitFlows(answersDoc.cast<String, dynamic>());
      } catch (e) {
        fail('answers $answersPath do not project to flows — $e');
      }
      if (projected != null) {
        final diffs = diffFlows(flowsDoc as List, projected);
        if (diffs.isEmpty) {
          ok('flows.json agrees with emitFlows(answers) — '
              '${flowsDoc.length} flow(s), no divergence');
        } else {
          // Name the repair command outright. Whoever trips this in six
          // months should not have to reconstruct it — and must be told which
          // way the projection runs, because `intake emit` REWRITES flows.json
          // from the answers: an edit living only in flows.json is destroyed
          // by the very command that fixes the divergence.
          final flag = project == null ? '' : ' --project $project';
          fail('$flowsPath disagrees with emitFlows(answers) in '
              '${diffs.length} place(s) — answers.json is the SSOT. Port each '
              'difference below into the ANSWERS, then re-project with: '
              '`appbox intake emit --answers $answersPath$flag`. That command '
              'OVERWRITES flows.json from the answers, so an edit that only '
              'ever reached flows.json will be lost unless you carry it over '
              'first. Re-check with: `appbox gate intake$flag`');
          for (final d in diffs) {
            fail(d);
          }
        }
      }
    }
  }

  // ---- collect REGISTRY surface ids -----------------------------------------
  if (!File(registryPath).existsSync()) {
    if (sourceIds.isEmpty) {
      // In project mode say where we looked — an unemitted project shell and
      // a greenfield studio produce the same PASS otherwise.
      final where = project == null ? '' : ' under $sourceHome';
      ok('no intake answers and no registry$where — nothing to trace (greenfield)');
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

/// Project-shell artifacts are at fixed flat paths (IntakeEngine.emit writes
/// them) — no search order, so "resolve" is just "has it been emitted yet?".
String? _emitted(String path) => File(path).existsSync() ? path : null;

// ── flows ≡ emitFlows(answers) ───────────────────────────────────────────────

/// Structural diff of [onDisk] (parsed flows.json) against [projected]
/// (`emitFlows(answers)`). Empty means they agree.
///
/// STRUCTURAL, never a byte or JSON-string compare — that would flap. Two
/// correct writers legitimately disagree on presentation: the studio's `excise`
/// path emits an edge as `{from, to, trigger, action, element}` while its
/// `appendTo` path emits `{from, to, trigger, action}`, so both key ORDER and
/// which optional keys are carried vary between honest writers. Hence:
///   - map keys are compared as a SET, order-insensitive;
///   - lists are compared IN ORDER — a flow is a chain, so edge order is
///     meaning, and two edges swapped is a real divergence;
///   - a key absent on BOTH sides is not a difference (it never enters the
///     key union), so an optional key nobody uses yet costs nothing.
///
/// Each message names the flow, the edge index, the key and both values —
/// enough to repair the data from the gate output alone.
List<String> diffFlows(List<Object?> onDisk, List<Object?> projected) {
  final out = <String>[];
  if (onDisk.length != projected.length) {
    out.add('flows.json has ${onDisk.length} flow(s), the answers project '
        '${projected.length}');
  }
  final flows = onDisk.length < projected.length ? onDisk.length : projected.length;
  for (var i = 0; i < flows; i++) {
    final disk = onDisk[i], want = projected[i];
    final id = (disk is Map ? disk['id'] : null) ??
        (want is Map ? want['id'] : null) ??
        i;
    final at = "flow '$id'";
    if (disk is! Map || want is! Map) {
      _diff(at, disk, want, out);
      continue;
    }
    for (final k in _keyUnion(disk, want)) {
      if (k == 'edges') continue;
      _diff("$at key '$k'", _keyed(disk, k), _keyed(want, k), out);
    }
    final diskEdges = disk['edges'], wantEdges = want['edges'];
    if (diskEdges is! List || wantEdges is! List) {
      _diff("$at key 'edges'", diskEdges, wantEdges, out);
      continue;
    }
    if (diskEdges.length != wantEdges.length) {
      out.add('$at has ${diskEdges.length} edge(s) in flows.json, '
          '${wantEdges.length} from the answers');
    }
    final edges = diskEdges.length < wantEdges.length
        ? diskEdges.length
        : wantEdges.length;
    for (var j = 0; j < edges; j++) {
      final d = diskEdges[j], w = wantEdges[j];
      if (d is! Map || w is! Map) {
        _diff('$at edge $j', d, w, out);
        continue;
      }
      for (final k in _keyUnion(d, w)) {
        _diff("$at edge $j key '$k'", _keyed(d, k), _keyed(w, k), out);
      }
    }
  }
  return out;
}

/// "not present on this side" — distinct from a JSON `null`, which is a value.
class _Absent {
  const _Absent();
}

const _absent = _Absent();

Object? _keyed(Map m, Object? k) => m.containsKey(k) ? m[k] : _absent;

List<Object?> _keyUnion(Map a, Map b) =>
    <Object?>{...a.keys, ...b.keys}.toList()
      ..sort((x, y) => '$x'.compareTo('$y'));

void _diff(String at, Object? disk, Object? want, List<String> out) {
  if (disk is Map && want is Map) {
    for (final k in _keyUnion(disk, want)) {
      _diff('$at.$k', _keyed(disk, k), _keyed(want, k), out);
    }
    return;
  }
  if (disk is List && want is List) {
    if (disk.length != want.length) {
      out.add('$at: flows.json has ${disk.length} item(s), the answers give '
          '${want.length}');
    }
    final n = disk.length < want.length ? disk.length : want.length;
    for (var i = 0; i < n; i++) {
      _diff('$at[$i]', disk[i], want[i], out);
    }
    return;
  }
  if (disk != want) {
    out.add('$at: flows.json has ${_show(disk)}, the answers give ${_show(want)}');
  }
}

String _show(Object? v) {
  if (v is _Absent) return '(absent)';
  try {
    return jsonEncode(v);
  } catch (_) {
    return '$v';
  }
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
