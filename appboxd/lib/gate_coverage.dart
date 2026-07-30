// Coverage gate — port of gates/coverage/coverage.sh to pure Dart.
//
// The SCAFFOLD COVERAGE gate (plan 06). The seam nothing else crossed: freeze
// guarantees the design's shell/surface map; scaffold validates shell shape;
// neither compares the two. This gate does — every frozen surface of an
// ADOPTED shell must carry EXACTLY the target-derived form-factor set, and
// every active target's platform ceremonies must fire.
//
// Targets drive coverage (6.2/6.3): read from pipeline state (the ambient set);
// the form-factor set + ceremony set both DERIVE from them via
// pipeline/state/targets.derivation.json — adding a target is a data edit, not
// a gate edit.
//
// Checks:
//   §6  fresh    — design tree matches the frozen designHash (hash-bound approval)
//   4.4 input    — structure.json present and parses (missing input never passes)
//   C1  coverage — every frozen surface of an adopted shell is mapped and its dir
//                  carries the derived form-factor set (6.5/6.6)
//   C2  orphans  — a real surface dir not mapped is a view the design never froze
//   C3  declared — a shell with real surface dirs must be in selfContained
//   C4  progress — unadopted shells REPORTED with counts, never silent
//   C5  ceremonies — every active target's platform files/keys present (6.8)
//
// Two producer shapes (dogfood P14): app.routes.js at the design root => htmx
// producer — coverage derives + reports the form-factor set and DEFERS the
// scaffold/ceremony checks (no Flutter layer for an htmx design yet). The
// stacked_kit producer runs the full C1–C5 set over lib/ui/views.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gates.dart';

/// Directories under a shell that are NOT surfaces (matches freeze check 4's
/// hard-coded index.html exclusion: a name-anything-you-like escape turns the
/// orphan check off).
const _notSurface = {'bottom_sheets', 'dialogs', 'widgets', 'shared', 'common', 'overlays'};

GateResult coverageGate(GateContext ctx) {
  final repoRoot = ctx.repoRoot;
  final appRoot = ctx.appRoot ?? repoRoot;
  final designRel = Platform.environment['KIT_DESIGN_DIR'] ?? 'design';
  final designDir = '$appRoot/$designRel';
  final derivationPath = '$repoRoot/pipeline/state/targets.derivation.json';
  final configPath = ctx.configFile;
  final viewsPath = '$appRoot/lib/ui/views';
  final manifestPath = '$viewsPath/.shell-structure.json';
  final structurePath = '$designDir/structure.json';

  final details = <String>[];
  var fails = 0;

  void ok(String m) => details.add('  ✓ coverage: $m');
  void info(String m) => details.add('  coverage: $m');
  void fail(String m) {
    details.add('FAIL: coverage: $m');
    ctx.sarif.result('coverage', 'error', appRoot, 'FAIL: coverage: $m');
    fails++;
  }

  // ---- targets: ambient pipeline state (6.2). --targets (6.3) is the bash ----
  // flag; not wired through GateContext, so the explicit-override path is the
  // caller's responsibility — same as gate_deploy reading ctx.state.targets.
  final targets = ctx.state.targets;
  if (targets.isEmpty) {
    const m = 'no --targets given and no targets in pipeline state — pass '
        '--targets explicitly (6.3); a reproducibility run that reads ambient '
        'state is the stale-green defect';
    details.add('FAIL: $m');
    ctx.sarif.result('coverage', 'error', appRoot, 'FAIL: $m');
    return GateResult.fail('coverage: FAIL — $m', details);
  }

  // ---- §6: design freshness, against THIS app's design dir (not ctx.designRoot,
  // which points at the repo's own designs/appbox). Fail-open only on an empty
  // hash (legacy); a written hash that no longer matches means the design moved.
  final stored = ctx.state.get('designHash') as String?;
  if (stored == null || stored.isEmpty) {
    details.add('  · designHash: empty in pipeline state — legacy/unbound design, '
        'freshness not enforced (§6 binds only a written hash)');
  } else if (!Directory(designDir).existsSync()) {
    details.add('  · designHash: design dir absent at $designDir — freshness N/A '
        'here; the gate\'s own input checks (4.4) apply');
  } else {
    final current = designHash(designDir);
    if (current == stored) {
      details.add('  ✓ designHash: design matches the frozen hash '
          '(${_short12(stored)}…) (§6)');
    } else {
      details.add('FAIL: designHash: the design moved after freeze — state has '
          '${_short12(stored)}…, the tree hashes to ${_short12(current)}… '
          '(§6 hash-bound approval). Re-freeze the design, or restore it.');
      ctx.sarif.result('coverage', 'error', appRoot,
          'design moved after freeze (designHash mismatch, §6)');
      return GateResult.fail(
          'coverage: FAIL — design moved after freeze (designHash, §6)', details);
    }
  }

  // ---- load the derivation table + config viewports (the form-factor source) ----
  final Map<String, dynamic> tbl;
  try {
    final doc =
        jsonDecode(File(derivationPath).readAsStringSync()) as Map<String, dynamic>;
    final t = doc['targets'];
    if (t is! Map) {
      throw FormatException('targets.derivation.json has no "targets" object');
    }
    tbl = t.cast<String, dynamic>();
  } catch (e) {
    fail('cannot read targets derivation at $derivationPath — $e');
    return GateResult.fail('coverage: FAIL ($fails check(s))', details);
  }
  final List<String> cfgVps;
  try {
    final cfg =
        jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
    final vps = cfg['viewports'];
    cfgVps = vps is Map ? vps.keys.cast<String>().toList() : <String>[];
  } catch (e) {
    fail('cannot read config viewports at $configPath — $e');
    return GateResult.fail('coverage: FAIL ($fails check(s))', details);
  }

  // ---- unknown targets fail loudly ----
  final unknown = targets.where((t) => !tbl.containsKey(t)).toList();
  if (unknown.isNotEmpty) {
    fail('unknown target(s): ${unknown.join(', ')} — add an entry to '
        'pipeline/state/targets.derivation.json');
    return GateResult.fail('coverage: FAIL ($fails check(s))', details);
  }

  // ---- derive the form-factor set + ceremonies (inherits-aware, 6.1/6.5/6.8) ----
  final resolved = _resolveAll(targets, tbl);
  // config order; unknown names dropped (widths live ONLY in config, R3).
  final factors = [for (final v in cfgVps) if (resolved.viewports.contains(v)) v];
  final ceremonyList = resolved.ceremonies;

  // ---- 4.4: structure.json present + parses (missing input never passes) ----
  final structureFile = File(structurePath);
  if (!structureFile.existsSync()) {
    fail('$designRel/structure.json not found — coverage gate input is missing; '
        'a gate that cannot find its input never passes quietly (4.4). Freeze '
        'the design, or point KIT_DESIGN_DIR at the producer folder.');
    return GateResult.fail('coverage: FAIL ($fails check(s))', details);
  }
  Map<String, dynamic> structure;
  try {
    structure =
        jsonDecode(structureFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    fail('$designRel/structure.json does not parse — $e');
    return GateResult.fail('coverage: FAIL ($fails check(s))', details);
  }

  // ---- frozen surfaces, grouped by shellDir (insertion-ordered) ----
  final frozen = <String, Set<String>>{};
  for (final s in (structure['screens'] as List?) ?? const []) {
    if (s is! Map) continue;
    final surface = s['surface'];
    final shellDir = s['shellDir'];
    if (_truthy(surface) && _truthy(shellDir)) {
      frozen.putIfAbsent(shellDir.toString(), () => <String>{}).add(surface.toString());
    }
  }
  if (frozen.isEmpty) {
    fail('$designRel/structure.json declares no surfaces — nothing to cover');
    return GateResult.fail('coverage: FAIL ($fails check(s))', details);
  }

  // ---- producer shape: app.routes.js at the design root => htmx ----
  final producer =
      File('$designDir/app.routes.js').existsSync() ? 'htmx' : 'stacked_kit';

  if (producer == 'htmx') {
    final n = frozen.values.fold(0, (a, v) => a + v.length);
    final filesPer = 1 + factors.length + 1;
    ok('htmx producer — $n frozen surface(s) across ${frozen.length} shell(s)');
    info('targets [${targets.join(',')}] -> form factors '
        '[${factors.isEmpty ? 'none' : factors.join(', ')}] -> $filesPer '
        'file(s)/surface when the Flutter scaffold is emitted');
    info('no Flutter scaffold layer for this htmx producer yet — scaffold/'
        'ceremony checks deferred (C4 incremental); $designRel/structure.json '
        'verified');
    return GateResult.ok('coverage: PASS — htmx producer; scaffold checks deferred.',
        details);
  }

  // ---- stacked_kit producer: full C1–C5 over lib/ui/views ----
  Map<String, dynamic> mf = {};
  final manifestFile = File(manifestPath);
  if (manifestFile.existsSync()) {
    try {
      final parsed = jsonDecode(manifestFile.readAsStringSync());
      if (parsed is Map) {
        mf = parsed.cast<String, dynamic>();
      } else {
        fail('lib/ui/views/.shell-structure.json does not parse — top level is not an object');
        return GateResult.fail('coverage: FAIL ($fails check(s))', details);
      }
    } catch (e) {
      fail('lib/ui/views/.shell-structure.json does not parse — $e');
      return GateResult.fail('coverage: FAIL ($fails check(s))', details);
    }
  }
  final sc = mf['selfContained'];
  final adopted = sc is List ? sc.cast<String>() : <String>[];
  final Object smapVal =
      _truthy(mf['surfaces']) ? mf['surfaces'] : const <String, dynamic>{};
  if (smapVal is! Map) {
    fail('.shell-structure.json "surfaces" must be an object of {shell: {surfaceId: dir}}');
    return GateResult.fail('coverage: FAIL ($fails check(s))', details);
  }
  final smap = smapVal.cast<String, dynamic>();

  // ---- C3: a shell you have started building must be declared ----
  final viewsDir = Directory(viewsPath);
  final viewsListing = <String>[];
  if (viewsDir.existsSync()) {
    viewsListing.addAll(
      viewsDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split('/').last)
          .where((n) => !n.startsWith('.')),
    );
    viewsListing.sort();
  }
  for (final shell in viewsListing) {
    if (adopted.contains(shell)) continue;
    final got = _realDirs(viewsPath, shell);
    if (got.isNotEmpty) {
      final sortedGot = got.toList()..sort();
      fail("shell '$shell' has ${got.length} surface dir(s) "
          "(${sortedGot.join(', ')}) but is not in .shell-structure.json "
          'selfContained — a shell you have started building must be declared, '
          'or coverage silently stops applying to it');
    }
  }

  // ---- C1 + C2: adopted shells are covered completely ----------------------
  for (final shell in (adopted.toList()..sort())) {
    final want = frozen[shell];
    if (want == null) {
      fail("shell '$shell' is adopted but $designRel/structure.json freezes no "
          'surface for it');
      continue;
    }
    final mVal = smap[shell];
    if (mVal != null && mVal is! Map) {
      fail('surfaces["$shell"] must be an object of {surfaceId: dir}');
      continue;
    }
    final m = (mVal is Map) ? mVal.cast<String, dynamic>() : <String, dynamic>{};
    final mappedKeys = m.keys.toSet();
    final f0 = fails;

    // C1a: frozen surfaces that are not mapped
    for (final s in want.difference(mappedKeys).toList()..sort()) {
      fail("shell '$shell': frozen surface '$s' is not mapped in "
          '.shell-structure.json surfaces["$shell"] — adopting a shell means '
          'covering all of it');
    }
    // C1b: mapped surfaces the design never froze
    for (final s in mappedKeys.difference(want).toList()..sort()) {
      fail("shell '$shell': surfaces[\"$shell\"] maps '$s', which "
          '$designRel/structure.json does not freeze for this shell');
    }
    // duplicate dirs (two surfaces claim the same directory)
    final dirs = m.values.map((v) => v.toString()).toList();
    final dirCounts = <String, int>{};
    for (final d in dirs) {
      dirCounts[d] = (dirCounts[d] ?? 0) + 1;
    }
    for (final d
        in dirCounts.entries.where((e) => e.value > 1).map((e) => e.key).toList()..sort()) {
      fail("shell '$shell': directory '$d' is claimed by ${dirCounts[d]} surfaces");
    }
    // C1c: the derived form-factor set (6.5/6.6)
    for (final s in mappedKeys.intersection(want).toList()..sort()) {
      final d = m[s].toString();
      final base = '$viewsPath/$shell/$d';
      if (!Directory(base).existsSync()) {
        fail("shell '$shell': surface '$s' maps to '$d/' which does not exist "
            'under lib/ui/views/$shell/');
        continue;
      }
      final need = <String>[
        '${d}_view.dart',
        for (final f in factors) '${d}_view.$f.dart',
        '${d}_viewmodel.dart',
      ];
      final gone = need.where((n) => !File('$base/$n').existsSync()).toList();
      if (gone.isNotEmpty) {
        final factorsDesc = factors.isEmpty ? '(none)' : factors.join(' ');
        fail("shell '$shell': lib/ui/views/$shell/$d/ is missing ${gone.join(', ')} "
            "— targets [${targets.join(',')}] derive form-factor(s) "
            '[$factorsDesc]; the gate requires _view.dart + each derived '
            '_view.<factor>.dart + _viewmodel.dart');
      }
    }
    // C2: orphan dirs — a real surface dir the design never froze
    final claimedDirs = m.values.map((v) => v.toString()).toSet();
    for (final d in _realDirs(viewsPath, shell).difference(claimedDirs).toList()..sort()) {
      fail("shell '$shell': lib/ui/views/$shell/$d/ is a view the design never "
          'froze (not a value in surfaces["$shell"])');
    }

    final built = want.length - (fails - f0);
    if (fails == f0) {
      ok('$shell: ${want.length}/${want.length} frozen surfaces scaffolded');
    } else {
      details.add('  ✗ coverage: $shell: ${built < 0 ? 0 : built}/${want.length} '
          'frozen surfaces scaffolded');
    }
  }

  // ---- C4: progress, always visible (non-fatal) ----
  final todo = frozen.keys.where((k) => !adopted.contains(k)).toList()..sort();
  var covered = 0;
  for (final s in adopted) {
    if (frozen.containsKey(s)) covered += frozen[s]!.length;
  }
  final total = frozen.values.fold(0, (a, v) => a + v.length);
  info('$covered/$total frozen surface(s) in ${adopted.length} adopted shell(s) '
      'of ${frozen.length}; targets [${targets.join(',')}] -> form factors '
      '[${factors.isEmpty ? 'none' : factors.join(', ')}]');
  if (todo.isNotEmpty) {
    final todoSurfaces = todo.fold(0, (a, s) => a + frozen[s]!.length);
    details.add('  not yet adopted ($todoSurfaces surface(s)):');
    for (final s in todo) {
      details.add('      ${s.padRight(18)} ${frozen[s]!.length}');
    }
  }

  // ---- C5: platform ceremonies fire from targets (6.8) ----
  for (final ce in ceremonyList) {
    final cid = (ce['id'] as String?) ?? '?';
    final cdesc = (ce['desc'] as String?) ?? '';
    for (final chk
        in ((ce['checks'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final p = chk['path'] as String?;
      final key = chk['key'] as String?;
      if (p == null) continue;
      final full = '$appRoot/$p';
      if (!File(full).existsSync()) {
        fail("ceremony '$cid' ($cdesc): $p missing — targets [${targets.join(',')}] "
            'require it');
      } else if (key != null && key.isNotEmpty) {
        String body;
        try {
          body = File(full).readAsStringSync();
        } catch (_) {
          body = '';
        }
        if (!body.contains(key)) {
          fail("ceremony '$cid' ($cdesc): $p present but lacks key '$key'");
        }
      }
    }
  }

  if (fails > 0) {
    return GateResult.fail('coverage: FAIL ($fails check(s))', details);
  }
  return GateResult.ok(
    'coverage: PASS — $covered/$total frozen surface(s) covered across '
    '${adopted.length} adopted shell(s); targets [${targets.join(',')}] -> '
    'form factors [${factors.isEmpty ? 'none' : factors.join(', ')}].',
    details,
  );
}

// ── helpers ──────────────────────────────────────────────────────────────────

/// Resolve a single target's viewports + ceremonies, parent (inherits) first.
/// Cycle-safe via [seen]; [seen] is per top-level target (matches the Python,
/// which gives each top-level resolve a fresh seen set).
({List<String> viewports, List<Map<String, dynamic>> ceremonies}) _resolve(
    String t, Map<String, dynamic> tbl, Set<String> seen) {
  if (seen.contains(t) || tbl[t] is! Map) {
    return (viewports: const [], ceremonies: const []);
  }
  seen.add(t);
  final e = tbl[t] as Map<String, dynamic>;
  final ownVps = ((e['viewports'] as List?) ?? const []).cast<String>();
  final ownCers =
      ((e['ceremonies'] as List?) ?? const []).cast<Map<String, dynamic>>();
  var vps = [...ownVps];
  var cers = [...ownCers];
  final inherits = e['inherits'] as String?;
  if (inherits != null && inherits.isNotEmpty) {
    final parent = _resolve(inherits, tbl, seen);
    vps = [...parent.viewports, ...vps];
    cers = [...parent.ceremonies, ...cers];
  }
  return (viewports: vps, ceremonies: cers);
}

/// Union every target's resolved viewports + ceremonies (dedup, first-wins).
({List<String> viewports, List<Map<String, dynamic>> ceremonies}) _resolveAll(
    List<String> targets, Map<String, dynamic> tbl) {
  final vps = <String>[];
  final cers = <Map<String, dynamic>>[];
  for (final t in targets) {
    final r = _resolve(t, tbl, <String>{});
    for (final v in r.viewports) {
      if (!vps.contains(v)) vps.add(v);
    }
    for (final ce in r.ceremonies) {
      // ceremonies carry a stable id; dedup on it (== Python's value-equality
      // outcome for well-formed, unique-id input).
      final id = ce['id'];
      if (!cers.any((c) => c['id'] == id)) cers.add(ce);
    }
  }
  return (viewports: vps, ceremonies: cers);
}

/// Real surface dirs under `<views>/<shell>`: directories that are not dotfiles
/// and not in the NOT_SURFACE escape list.
Set<String> _realDirs(String viewsPath, String shell) {
  final d = Directory('$viewsPath/$shell');
  if (!d.existsSync()) return <String>{};
  final out = <String>{};
  for (final entry in d.listSync()) {
    if (entry is! Directory) continue;
    final name = entry.path.split('/').last;
    if (name.startsWith('.') || _notSurface.contains(name)) continue;
    out.add(name);
  }
  return out;
}

/// First 12 chars of a hex hash (Bash ${h:0:12}); safe against short strings.
String _short12(String s) => s.length >= 12 ? s.substring(0, 12) : s;

/// Python-style truthiness for JSON-derived values (matches `s.get(x) and ...`).
bool _truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is String) return v.isNotEmpty;
  if (v is List) return v.isNotEmpty;
  if (v is Map) return v.isNotEmpty;
  if (v is num) return v != 0;
  return true;
}
