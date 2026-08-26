// Freeze gate — Dart port of gates/freeze/freeze.sh (531 lines, bash + embedded
// python + render_htmx.mjs) to a pure-Dart gate module.
//
// The FREEZE / PROTOTYPE gate. Asserts the frozen design inputs are present,
// the design-approval stamp is valid, and every surface renders clean at every
// DERIVED viewport — the width set implied by --targets via
// pipeline/state/targets.derivation.json (6.4). Widths come ONLY from
// config/arxa.config.json (R3); there are no viewport literals here.
//
// Checks (cheapest first, all must pass):
//   1. shape      — every required input present (per producer: htmx vs arxa_kit)
//   1b. approval  — design/approval.lock targets + inputsHash still match (6.7)
//   2. vocab      — [arxa_kit] tokens.json parses as DTCG and carries kit paths
//   3. exclusions — [arxa_kit] harness chrome in surfaces covered by exclusions.json
//   3b. l10n      — locale ARB key + placeholder parity when <design>/l10n/ exists
//   4. render     — headless Chromium (CDP) renders every surface clean at every
//                   config viewport; falls back to the proven Python/Node tools
//                   (strangler) when the Dart CDP path is not ready.
//
// Hash-bound approval (§6): on PASS the gate records a sha256 of the whole design
// tree into state.designHash (live state only — the tracked seed is read-only).
// `--approve` mints design/approval.lock against the current targets + inputs hash.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arxa/cdp.dart';
import 'package:arxa/crypto_aead.dart' as crypto;
import 'package:arxa/gates.dart';
import 'package:arxa/design_server.dart';
import 'package:path/path.dart' as p;

/// A derived viewport: a config name plus its width/height from config.
class _Vp {
  final String name;
  final int width;
  final int height;
  _Vp(this.name, this.width, this.height);
}

/// Run the freeze gate.
///
/// [targets] overrides the pipeline-state target set (6.3 — explicit for a
/// deterministic snapshot). [approve] mints/refreshes design/approval.lock.
Future<GateResult> freezeGate(
  GateContext ctx, {
  List<String>? targets,
  bool approve = false,
}) async {
  var designRel = GateContext.studioDesignDir;
  var designRoot = ctx.designRoot;
  // v2 is canonical, but a tree planting only v1 (fixtures, the retained
  // reference) freezes against what exists.
  if (!Directory(designRoot).existsSync()) {
    final legacy = p.join(p.dirname(designRoot), 'arxa-studio');
    if (Directory(legacy).existsSync()) {
      designRoot = legacy;
      designRel = 'designs/arxa-studio';
    }
  }
  final details = <String>[];
  var groupFails = 0;

  void ok(String msg) => details.add('  ✓ $msg');
  void fail(String msg) {
    details.add('  ✗ $msg');
    ctx.sarif.result('freeze', 'error', designRel, msg);
    groupFails++;
  }

  // ---- targets (6.2 / 6.3): explicit flag, else ambient pipeline state ----
  final requested = targets?.where((t) => t.isNotEmpty).toList() ?? ctx.targets;
  if (requested.isEmpty) {
    final msg = 'no --targets given and no targets in pipeline state — pass '
        '--targets explicitly (6.3); a reproducibility run that reads ambient '
        'state is the stale-green defect';
    fail(msg);
    return GateResult.fail('freeze: FAIL ($groupFails check group(s))', details);
  }

  // ---- derive the ordered viewport set for these targets (6.4, R3) ----
  final derivation = _deriveViewports(requested, ctx.repoRoot);
  if (derivation.error != null) {
    fail(derivation.error!);
    return GateResult.fail('freeze: FAIL ($groupFails check group(s))', details);
  }
  final viewports = derivation.viewports!;

  // ---- 0. the design dir itself (anchor) ----
  if (!Directory(designRoot).existsSync()) {
    fail('no design dir at $designRoot — the design SSOT must live at '
        '<project-root>/$designRel; point the design session\'s output there, '
        'then re-run');
    return GateResult.fail('freeze: FAIL ($groupFails check group(s))', details);
  }

  // ---- 0b. producer shape (producer-shape seam, dogfood P14 #1) ----
  final producer = File('$designRoot/app.routes.js').existsSync()
      ? 'htmx'
      : 'kit';
  if (producer == 'htmx') {
    ok('shape: htmx producer (app.routes.js present) — render via the designer Node server');
  }

  // ---- 1. shape (per producer) ----
  final shapeOk = _checkShape(ctx, designRoot, designRel, producer, ok, fail);
  if (!shapeOk) {
    return GateResult.fail('freeze: FAIL ($groupFails check group(s))', details);
  }

  // ---- 1b. design-approval invalidation (6.7) — VALIDATE the existing stamp ----
  final inputsHash = _inputsHash(designRoot, producer, requested);
  _validateApproval(designRoot, designRel, requested, inputsHash, ok, fail);

  // ---- 2/3. vocab + exclusions (arxa_kit only) ----
  if (producer == 'kit') {
    _checkVocab(designRoot, designRel, ok, fail);
    _checkExclusions(designRoot, designRel, ok, fail);
  } else {
    ok('vocab/exclusions: N/A for the htmx producer (no tokens.json/exclusions.json; '
        'the render check in step 4 is the htmx analog)');
  }
  if (groupFails > 0) {
    return GateResult.fail('freeze: FAIL ($groupFails check group(s))', details);
  }

  // ---- 3b. l10n parity (only when the design carries an l10n/ catalog) ----
  if (Directory('$designRoot/l10n').existsSync()) {
    _checkL10n(designRoot, designRel, ok, fail);
    if (groupFails > 0) {
      return GateResult.fail('freeze: FAIL ($groupFails check group(s))', details);
    }
  }

  // ---- 4. render (headless Chromium; skip via FREEZE_RENDER=skip / EMIT_RENDER=skip) ----
  final skipRender = Platform.environment['FREEZE_RENDER'] == 'skip' ||
      Platform.environment['EMIT_RENDER'] == 'skip';
  if (skipRender) {
    details.add('  (render pass SKIPPED — FREEZE_RENDER=skip; hermetic/non-browser runs only)');
    final names = viewports.map((v) => v.name).join(' ');
    details.add('  (derived widths for targets [${requested.join(',')}]: $names)');
  } else {
    final root = ctx.appRoot ?? ctx.repoRoot;
    final evidence = '$root/.kit/state/prototype/evidence';
    await Directory(evidence).create(recursive: true);
    final renderOutcome = await _runRender(
      designRoot: designRoot,
      evidence: evidence,
      producer: producer,
      viewports: viewports,
      repoRoot: ctx.repoRoot,
      ok: ok,
      fail: fail,
      details: details,
    );
    if (renderOutcome == _RenderStatus.env) {
      // No render backend at all — env/not-applicable (bash exit 2).
      return GateResult.env(
          'freeze: ERROR (exit 2) — no render backend (install Chrome for the '
          'CDP path, or FREEZE_RENDER=skip for a hermetic run)');
    }
    if (groupFails > 0) {
      return GateResult.fail('freeze: FAIL ($groupFails check group(s))', details);
    }
  }

  // ---- §6 hash-bound approval: record the design hash on pass ----
  final hash = designHash(designRoot);
  if (ctx.state.set('designHash', hash)) {
    ok('designHash: recorded ${hash.substring(0, 12)}… in pipeline state '
        '(§6 — downstream gates fail if the design moves)');
  } else {
    details.add('  (designHash: no live pipeline state — hash not recorded; set '
        'ARXA_STATE or create pipeline/state/run.state.json)');
  }

  // ---- mint the approval stamp only after every check passed (6.7) ----
  if (approve) {
    _mintApproval(designRoot, requested, inputsHash);
    ok('approval: stamped $designRel/approval.lock (targets=${requested.join(',')}, '
        'inputsHash=${inputsHash.substring(0, 12)}…)');
    details.add('freeze: APPROVED — $designRel stamped (all checks passed).');
    return GateResult.ok('freeze: APPROVED — $designRel stamped (all checks passed).', details);
  }

  details.add('freeze: PASS — $designRel is frozen SSOT material.');
  return GateResult.ok('freeze: PASS — $designRel is frozen SSOT material.', details);
}

// ── target / viewport derivation (port of the embedded python, 6.4 + R3) ────

class _Derivation {
  final List<_Vp>? viewports;
  final String? error;
  _Derivation.ok(this.viewports) : error = null;
  _Derivation.fail(this.error) : viewports = null;
}

_Derivation _deriveViewports(List<String> targets, String repoRoot) {
  final derivationPath = '$repoRoot/pipeline/state/targets.derivation.json';
  final configPath = '$repoRoot/config/arxa.config.json';

  Map<String, dynamic> tbl;
  Map<String, dynamic> cfgVps;
  try {
    final d = jsonDecode(File(derivationPath).readAsStringSync())
        as Map<String, dynamic>;
    tbl = d['targets'] as Map<String, dynamic>;
    final cfg =
        jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
    cfgVps = cfg['viewports'] as Map<String, dynamic>;
  } catch (e) {
    return _Derivation.fail(
        'could not read derivation/config ($derivationPath / $configPath) — $e');
  }

  final unknown =
      targets.where((t) => !tbl.containsKey(t)).toList();
  if (unknown.isNotEmpty) {
    return _Derivation.fail(
        'unknown target(s): ${unknown.join(', ')} — add an entry to '
        'pipeline/state/targets.derivation.json');
  }

  // Resolve each target's viewports, following `inherits` (cycle-safe).
  List<String> vpsOf(String t, Set<String> seen) {
    if (seen.contains(t)) return [];
    seen.add(t);
    final entry = tbl[t] as Map<String, dynamic>;
    final out =
        (entry['viewports'] as List).cast<String>().toList();
    final inherits = entry['inherits'];
    if (inherits is String) {
      return [...vpsOf(inherits, {...seen}), ...out];
    }
    return out;
  }

  // Union in first-seen order, then re-order by config declaration order.
  final union = <String>[];
  for (final t in targets) {
    for (final v in vpsOf(t, {})) {
      if (!union.contains(v)) union.add(v);
    }
  }
  final ordered =
      cfgVps.keys.where((n) => union.contains(n)).toList();
  if (ordered.isEmpty) {
    return _Derivation.fail(
        'could not derive viewports from targets (${targets.join(',')})');
  }

  final vps = <_Vp>[];
  for (final name in ordered) {
    final v = cfgVps[name] as Map<String, dynamic>;
    vps.add(_Vp(name, v['width'] as int, v['height'] as int));
  }
  return _Derivation.ok(vps);
}

// ── 1. shape (per producer) ──────────────────────────────────────────────────

bool _checkShape(
  GateContext ctx,
  String designRoot,
  String designRel,
  String producer,
  void Function(String) ok,
  void Function(String) fail,
) {
  if (producer == 'htmx') {
    for (final f in ['app.routes.js', 'structure.json']) {
      if (File('$designRoot/$f').existsSync()) {
        ok('shape: $f');
      } else {
        fail('shape: $designRel/$f missing (htmx producer)');
      }
    }
    // registry path is recorded in structure.json; fall back to the designer default
    final regRel = _registryRel(designRoot);
    if (File('$designRoot/$regRel').existsSync()) {
      ok('shape: $regRel');
    } else {
      fail('shape: $designRel/$regRel missing (registry SSOT for the screen model)');
    }
    final views = _viewTemplates(designRoot);
    if (views.isNotEmpty) {
      ok('shape: ${views.length} view template(s) under $designRel/ui/views/');
    } else {
      fail('shape: no view templates — $designRel/ui/views/**/*_view.{html,tsx} missing');
    }
  } else {
    for (final f in [
      'tokens.json',
      'design-system.md',
      'exclusions.json',
      'direction-approved.md',
      'brand-spec.md',
      'structure.json',
    ]) {
      if (File('$designRoot/$f').existsSync()) {
        ok('shape: $f');
      } else {
        fail('shape: $designRel/$f missing (see the prototype freeze contract)');
      }
    }
    final surfaces = _surfaceHtml(designRoot);
    if (surfaces.isNotEmpty) {
      ok('shape: ${surfaces.length} surface(s) under $designRel/surfaces/');
    } else {
      fail('shape: no surfaces — $designRel/surfaces/*.html missing');
    }
  }
  // caller inspects ctx.sarif/groupFails via the fail() closure it passed
  return true;
}

/// The registry path recorded in structure.json (designer default if absent).
String _registryRel(String designRoot) {
  try {
    final s =
        jsonDecode(File('$designRoot/structure.json').readAsStringSync())
            as Map<String, dynamic>;
    final r = s['registry'];
    if (r is String && r.isNotEmpty) return r;
  } catch (_) {}
  return 'models/screens_model/registry.json';
}

// ── 1b. approval stamp (validate existing / mint on --approve) ──────────────

/// sha256 of sorted-targets + each producer's frozen-input set.
/// Mirrors the embedded python in freeze.sh (LOCK_HASH).
String _inputsHash(String designRoot, String producer, List<String> targets) {
  final buf = <int>[];
  final sortedTargets = targets.where((t) => t.isNotEmpty).toList()..sort();
  buf.addAll(utf8.encode(sortedTargets.join(',')));

  if (producer == 'htmx') {
    final reg = _registryRel(designRoot);
    for (final f in ['app.routes.js', 'structure.json', reg]) {
      buf.addAll(utf8.encode(f));
      final file = File('$designRoot/$f');
      if (file.existsSync()) buf.addAll(file.readAsBytesSync());
    }
    for (final v in _viewTemplates(designRoot)) {
      buf.addAll(v.readAsBytesSync());
    }
  } else {
    for (final f in [
      'tokens.json',
      'design-system.md',
      'exclusions.json',
      'direction-approved.md',
      'brand-spec.md',
      'structure.json',
    ]) {
      buf.addAll(utf8.encode(f));
      final file = File('$designRoot/$f');
      if (file.existsSync()) buf.addAll(file.readAsBytesSync());
    }
    for (final s in _surfaceHtml(designRoot)) {
      buf.addAll(s.readAsBytesSync());
    }
  }

  final digest = crypto.sha256(Uint8List.fromList(buf));
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void _validateApproval(
  String designRoot,
  String designRel,
  List<String> targets,
  String inputsHash,
  void Function(String) ok,
  void Function(String) fail,
) {
  final lockFile = File('$designRoot/approval.lock');
  if (!lockFile.existsSync()) {
    // bash only prints an advisory line here (not a failure).
    return;
  }
  Map<String, dynamic> lock;
  try {
    lock = jsonDecode(lockFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    fail('approval STALE — approval.lock does not parse — $e; the frozen design '
        'no longer covers the deliverable. Re-approve: freeze.sh --targets '
        '${targets.join(',')} --approve');
    return;
  }

  final approved = (lock['targets'] as List?)
          ?.whereType<String>()
          .where((t) => t.isNotEmpty)
          .toList() ??
      const [];
  final current = targets.where((t) => t.isNotEmpty).toList()..sort();
  final approvedSorted = [...approved]..sort();

  String? stale;
  if (!_listEq(approvedSorted, current)) {
    stale = 'targets changed since approval (approved $approved; now $current)';
  } else if (lock['inputsHash'] != inputsHash) {
    stale = 'frozen inputs changed since approval (re-mint with --approve)';
  }

  if (stale != null) {
    fail('approval STALE — $stale; the frozen design no longer covers the '
        'deliverable. Re-approve: freeze.sh --targets ${targets.join(',')} --approve');
  } else {
    ok('approval: $designRel/approval.lock valid (targets=${targets.join(',')})');
  }
}

void _mintApproval(String designRoot, List<String> targets, String inputsHash) {
  final doc = {
    'targets': targets.where((t) => t.isNotEmpty).toList()..sort(),
    'inputsHash': inputsHash,
    'approvedAt': DateTime.now().toUtc().toIso8601String(),
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(doc);
  File('$designRoot/approval.lock').writeAsStringSync('$encoded\n');
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── 2. vocab (tokens.json carries the kit token paths, DTCG) ────────────────

const _requiredTokens = [
  'color.brand.0', 'color.bg.surface', 'color.bg.surface-2', 'color.bg.paper',
  'color.fg.ink', 'color.fg.muted', 'color.fg.faint', 'color.border.rule',
  'color.status.good', 'color.status.warn', 'color.status.danger',
  'typography.sans', 'typography.mono',
];

void _checkVocab(
  String designRoot,
  String designRel,
  void Function(String) ok,
  void Function(String) fail,
) {
  final path = '$designRoot/tokens.json';
  Map<String, dynamic> d;
  try {
    d = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    fail('vocab: tokens.json does not parse — $e');
    return;
  }

  var bad = false;
  for (final p in _requiredTokens) {
    dynamic node = d;
    for (final part in p.split('.')) {
      node = (node is Map<String, dynamic>) ? node[part] : null;
      if (node == null) break;
    }
    if (node == null) {
      fail('vocab: missing token path $p');
      bad = true;
    } else if (node is! Map<String, dynamic> ||
        !node.containsKey('\$type') ||
        !node.containsKey('\$value')) {
      fail('vocab: $p lacks DTCG \$type/\$value');
      bad = true;
    }
  }
  if (!bad) {
    ok('vocab: ${_requiredTokens.length} kit token paths present (DTCG)');
  }
}

// ── 3. exclusions (harness chrome must be named, never scaffolded) ──────────

final _chromeSigs = <RegExp>[
  RegExp(r'tweak', caseSensitive: false),
  RegExp(r'device[-_ ]?frame', caseSensitive: false),
  RegExp(r'phone[-_ ]?frame', caseSensitive: false),
  RegExp(r'(?:iphone|android)[-_ ]?frame', caseSensitive: false),
  RegExp(r'device[-_ ]?bezel', caseSensitive: false),
  RegExp(r'9:41', caseSensitive: false),
  RegExp(r'status[-_ ]?bar', caseSensitive: false),
  RegExp(r'browser[-_ ]?chrome', caseSensitive: false),
  RegExp(r'mockup[-_ ]?chrome', caseSensitive: false),
];

void _checkExclusions(
  String designRoot,
  String designRel,
  void Function(String) ok,
  void Function(String) fail,
) {
  Map<String, dynamic> ex;
  try {
    ex = jsonDecode(File('$designRoot/exclusions.json').readAsStringSync())
        as Map<String, dynamic>;
  } catch (e) {
    fail('exclusions: exclusions.json does not parse — $e');
    return;
  }
  final globs = ex['globs'];
  final selectors = ex['selectors'];
  if (globs is! List || selectors is! List) {
    fail('exclusions: exclusions.json needs {"globs": [...], "selectors": [...]}');
    return;
  }
  final globList = globs.cast<String>();
  final selCores = selectors.cast<String>().map(_core).where((c) => c.isNotEmpty).toList();

  final surfaces = _surfaceHtml(designRoot);
  final uncovered = <String>[];
  var covered = 0;
  for (final file in surfaces) {
    final rel = '$designRel/surfaces/${_baseName(file)}';
    final basename = _baseName(file);
    final text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    final lines = const LineSplitter().convert(text);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      for (final sig in _chromeSigs) {
        if (!sig.hasMatch(line)) continue;
        final inGlob = globList.any(
            (g) => _fnmatch(rel, g) || _fnmatch(basename, g));
        final inSel = selCores.any(_core(line).contains);
        if (inGlob || inSel) {
          covered++;
        } else {
          uncovered.add('$rel:${i + 1} /${sig.pattern}/');
        }
      }
    }
  }
  if (uncovered.isEmpty) {
    ok('exclusions: $covered chrome reference(s) covered by exclusions.json');
  } else {
    for (final u in uncovered) {
      fail('exclusions: harness chrome present but not excluded — $u '
          '(add to exclusions.json)');
    }
  }
}

/// Python fnmatch (POSIX, case-sensitive): * / ? / [seq].
bool _fnmatch(String name, String pattern) {
  final sb = StringBuffer('^');
  var i = 0;
  while (i < pattern.length) {
    final c = pattern[i];
    if (c == '*') {
      sb.write('.*');
    } else if (c == '?') {
      sb.write('.');
    } else if (c == '[') {
      sb.write('[');
      i++;
      if (i < pattern.length && pattern[i] == '!') {
        sb.write('^');
        i++;
      }
      while (i < pattern.length && pattern[i] != ']') {
        sb.write(pattern[i]);
        i++;
      }
      sb.write(']');
    } else {
      sb.write(RegExp.escape(c));
    }
    i++;
  }
  sb.write(r'$');
  return RegExp(sb.toString(), dotAll: true).hasMatch(name);
}

/// re.sub(r"[^a-z0-9]","",s.lower())
String _core(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

// ── 3b. l10n parity (only when <design>/l10n/ exists) ───────────────────────

void _checkL10n(
  String designRoot,
  String designRel,
  void Function(String) ok,
  void Function(String) fail,
) {
  final l10n = Directory('$designRoot/l10n');
  final tmplPath = '${l10n.path}/app_en.arb';
  if (!File(tmplPath).existsSync()) {
    fail('l10n: app_en.arb (the template catalog) missing under l10n/');
    return;
  }
  Map<String, dynamic> tmpl;
  try {
    tmpl = jsonDecode(File(tmplPath).readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    fail('l10n: app_en.arb does not parse — $e');
    return;
  }

  Set<String> keys(Map<String, dynamic> d) =>
      d.keys.where((k) => !k.startsWith('@')).toSet();
  Set<String> tokens(dynamic v) => v is String
      ? RegExp(r'\{(\w+)\}').allMatches(v).map((m) => m.group(1)!).toSet()
      : const {};

  final tkeys = keys(tmpl);
  var bad = false;
  final locales = l10n
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in locales) {
    final name = _baseName(file);
    if (name == 'app_en.arb') continue;
    Map<String, dynamic> loc;
    try {
      loc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      fail('l10n: $name does not parse — $e');
      bad = true;
      continue;
    }
    final lkeys = keys(loc);
    final missing = tkeys.difference(lkeys);
    final extra = lkeys.difference(tkeys);
    if (missing.isNotEmpty) {
      fail('l10n: $name missing key(s): ${missing.toList()..sort}');
    }
    if (extra.isNotEmpty) {
      fail('l10n: $name has extra key(s) not in the template: ${extra.toList()..sort}');
    }
    for (final k in tkeys.intersection(lkeys).toList()..sort) {
      final tt = tokens(tmpl[k]);
      final lt = tokens(loc[k]);
      if (!_setEq(tt, lt)) {
        fail("l10n: $name key '$k' placeholder drift — template ${tt.toList()..sort} "
            'vs locale ${lt.toList()..sort}');
        bad = true;
      }
    }
  }
  if (!bad) {
    final n = locales.length - 1; // exclude the template
    ok('l10n: $n locale catalog(s) at key + placeholder parity with app_en.arb '
        '(${tkeys.length} keys)');
  }
}

bool _setEq(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

// ── 4. render (CDP primary, Python/Node fallback via Process.run) ───────────

enum _RenderStatus { ok, failed, env }

Future<_RenderStatus> _runRender({
  required String designRoot,
  required String evidence,
  required String producer,
  required List<_Vp> viewports,
  required String repoRoot,
  required void Function(String) ok,
  required void Function(String) fail,
  required List<String> details,
}) async {
  // Primary: Dart CDP path (the proven CdpClient). Falls back to the existing
  // Python/Node tools (strangler) when Chrome cannot launch.
  try {
    final errors = producer == 'htmx'
        ? await _renderHtmxCdp(designRoot, evidence, viewports, repoRoot, details)
        : await _renderStackedCdp(designRoot, evidence, viewports, details);
    _reportRender(errors, producer, viewports, designRoot, ok, fail, details);
    return errors.isEmpty ? _RenderStatus.ok : _RenderStatus.failed;
  } catch (e) {
    details.add('  (render: CDP path unavailable ($e) — falling back to Python/Node)');
  }

  // Fallback: shell out to the proven tools (strangler pattern).
  final fallbackErrors = await _renderFallback(
    designRoot: designRoot,
    evidence: evidence,
    producer: producer,
    viewports: viewports,
    repoRoot: repoRoot,
    details: details,
  );
  if (fallbackErrors == null) return _RenderStatus.env;
  _reportRender(fallbackErrors, producer, viewports, designRoot, ok, fail, details);
  return fallbackErrors.isEmpty ? _RenderStatus.ok : _RenderStatus.failed;
}

void _reportRender(
  List<String> errors,
  String producer,
  List<_Vp> viewports,
  String designRoot,
  void Function(String) ok,
  void Function(String) fail,
  List<String> details,
) {
  for (final e in errors) {
    fail('render: console/page error — $e');
  }
  if (errors.isEmpty) {
    if (producer == 'htmx') {
      final routes = _getRoutes(designRoot);
      final locales = _designLocales(designRoot);
      final langs = locales.isEmpty ? 1 : locales.length;
      final localeNote = locales.isEmpty
          ? ''
          : ' × ${locales.length} locale(s) [${locales.join(',')}]';
      details.add('  render: ${routes.length * viewports.length * langs} '
          'route/viewport render(s) across ${viewports.length} derived '
          'width(s)$localeNote, ${errors.length} error(s)');
    } else {
      final n = _surfaceHtml(designRoot).length;
      details.add('  render: ${n * viewports.length} surface/viewport render(s) '
          'across ${viewports.length} derived width(s), ${errors.length} error(s)');
    }
  }
}

// ── CDP render: arxa_kit (dart:io HttpServer + CdpClient) ────────────────

Future<List<String>> _renderStackedCdp(
  String designRoot,
  String evidence,
  List<_Vp> viewports,
  List<String> details,
) async {
  final server = await _bindStaticServer(designRoot);
  final surfaces = _surfaceHtml(designRoot);
  final errors = <String>[];
  CdpClient? client;
  try {
    client = await CdpClient.launch();
    for (final vp in viewports) {
      for (final file in surfaces) {
        final name = _surfaceName(file);
        final session = await client.newTab();
        await session.enable();
        session.clearErrors();
        await session.setViewport(vp.width, vp.height);
        final url = 'http://127.0.0.1:${server.port}/surfaces/$name.html';
        // fullPage: the stability loop must poll the SAME surface the capture
        // below takes, or it certifies a viewport that the golden doesn't use.
        final settle =
            await session.navigateAndSettleForCapture(url, fullPage: true);
        // Same channel as console errors: the freeze gate stamps a design as
        // frozen SSOT material, and a surface that never stops moving is not
        // freezable. Passing it would stamp a reference nothing can reproduce.
        if (!settle.converged) {
          errors.add('$name@${vp.name}: settle did not converge in '
              '${settle.elapsedMs}ms — surface is not reproducible');
        }
        for (final e in [...session.consoleErrors, ...session.pageErrors]) {
          errors.add('$name@${vp.name}: $e');
        }
        final png = await session.screenshot(fullPage: true);
        await File('$evidence/${name}_${vp.name}.png').writeAsBytes(png);
        details.add('  ✓ render: $name.html @ ${vp.name} (${vp.width}x${vp.height}) '
            'loaded, screenshot -> $evidence/${name}_${vp.name}.png');
      }
    }
  } finally {
    await client?.close();
    await server.close(force: true);
  }
  return errors;
}

/// Loopback static server over a directory (the dart:io analog of python's
/// SimpleHTTPRequestHandler used by the arxa_kit render).
Future<HttpServer> _bindStaticServer(String root) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final raw = Uri.decodeComponent(request.uri.path);
    // Reject path traversal — only files under [root] are served.
    if (raw.contains('..')) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    var fsPath = raw.endsWith('/') ? '$root$raw/index.html' : '$root$raw';
    final f = File(fsPath);
    if (await f.exists()) {
      final bytes = await f.readAsBytes();
      request.response
        ..headers.contentType = _mime(raw)
        ..contentLength = bytes.length
        ..add(bytes);
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  });
  return server;
}

ContentType _mime(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html')) return ContentType.html;
  if (lower.endsWith('.css')) return ContentType('text', 'css');
  if (lower.endsWith('.js')) return ContentType('application', 'javascript');
  if (lower.endsWith('.json')) return ContentType('application', 'json');
  if (lower.endsWith('.png')) return ContentType('image', 'png');
  if (lower.endsWith('.svg')) return ContentType('image', 'svg+xml');
  return ContentType('application', 'octet-stream');
}

// ── CDP render: htmx (designer Node server serves Jinja views; CdpClient renders) ─

Future<List<String>> _renderHtmxCdp(
  String designRoot,
  String evidence,
  List<_Vp> viewports,
  String repoRoot,
  List<String> details,
) async {
  final runtimeDir = '$repoRoot/skills/arxa-designer/runtime';
  final served = await _startDesignerServer(runtimeDir, designRoot);
  if (served.base == null) {
    served.dispose();
    throw StateError('designer server did not start '
        '(${served.error ?? "unknown error"})');
  }
  final base = served.base!.replaceAll(RegExp(r'/+$'), '');
  final routes = _getRoutes(designRoot);
  final locales = _designLocales(designRoot);
  final langs = locales.isEmpty ? <String?>[null] : locales.cast<String?>();
  final errors = <String>[];
  CdpClient? client;
  try {
    client = await CdpClient.launch();
    for (final vp in viewports) {
      for (final route in routes) {
        for (final lang in langs) {
          final session = await client.newTab();
          await session.enable();
          session.clearErrors();
          await session.setViewport(vp.width, vp.height);
          final sep = route.contains('?') ? '&' : '?';
          final url = lang == null ? '$base$route' : '$base$route${sep}lang=$lang';
          final settle =
              await session.navigateAndSettleForCapture(url, fullPage: true);
          final tag = lang == null ? '' : ' ($lang)';
          if (!settle.converged) {
            errors.add('$route@${vp.name}$tag: settle did not converge in '
                '${settle.elapsedMs}ms — surface is not reproducible');
          }
          for (final e in [...session.consoleErrors, ...session.pageErrors]) {
            errors.add('$route@${vp.name}$tag: $e');
          }
          final slug = route == '/'
              ? 'root'
              : route.replaceFirst('/', '').replaceAll('/', '__');
          final shot = lang == null
              ? '${slug}_${vp.name}.png'
              : '${slug}_${vp.name}_$lang.png';
          final png = await session.screenshot(fullPage: true);
          await File('$evidence/$shot').writeAsBytes(png);
          details.add('  ✓ render: $route @ ${vp.name} (${vp.width}x${vp.height})'
              '${lang == null ? '' : ' [$lang]'} loaded');
        }
      }
    }
  } finally {
    await client?.close();
    served.dispose();
  }
  return errors;
}

/// Boot the designer's Dart [DesignServer] in-process and return its bound base
/// URL. The server is stopped via [dispose]. The Dart server is the same live
/// serve path used by `arxa design serve` — the freeze gate shares one server
/// substrate with the command (formerly serve.mjs over Node, now in-process
/// Dart), so both the CDP render path and the htmx fallback render against it.
Future<_FutureServer> _startDesignerServer(String runtimeDir, String designRoot) async {
  try {
    final server = await DesignServer.start(
      artifactDir: designRoot,
      port: 0,
      host: '127.0.0.1',
      noWatch: true,
      runtimeVendorDir: '$runtimeDir/vendor',
    ).timeout(const Duration(seconds: 12));
    return _FutureServer(
      base: server.url,
      dispose: () => server.stop(),
    );
  } catch (e) {
    return _FutureServer(
      base: null,
      dispose: () {},
      error: e is TimeoutException
          ? 'designer server did not start within 12s'
          : 'designer server failed to start ($e)',
    );
  }
}

class _FutureServer {
  final String? base;
  final void Function() dispose;
  final String? error;
  _FutureServer({required this.base, required this.dispose, this.error});
}

/// GET routes from app.routes.js, matched by text regex (the server executes
/// producer code; we never do). Mirrors render_htmx.mjs.
List<String> _getRoutes(String designRoot) {
  final src = File('$designRoot/app.routes.js').readAsStringSync();
  // Matches `['GET', 'path'` by text (producer code is never executed — the
  // server does that). Non-raw string because the class holds both ' and ".
  final re = RegExp("\\[\\s*['\"]GET['\"]\\s*,\\s*['\"]([^'\"]+)['\"]");
  return re.allMatches(src).map((m) => m.group(1)!).toList();
}

/// Locales derived from app_*.arb names, qps-* excluded (pseudolocale is
/// tester-side layout stress, not a freeze render).
List<String> _designLocales(String designRoot) {
  final d = Directory('$designRoot/l10n');
  if (!d.existsSync()) return const [];
  final re = RegExp(r'^app_(.+)\.arb$');
  final out = <String>[];
  for (final f in d.listSync().whereType<File>()) {
    final m = re.firstMatch(_baseName(f));
    if (m != null && !m.group(1)!.startsWith('qps')) out.add(m.group(1)!);
  }
  return out;
}

// ── Fallback: shell out to the proven Python/Node tools (strangler) ─────────

/// Returns the list of error lines, or null if NO render backend is available
/// (bash exit 2 — env/not-applicable).
Future<List<String>?> _renderFallback({
  required String designRoot,
  required String evidence,
  required String producer,
  required List<_Vp> viewports,
  required String repoRoot,
  required List<String> details,
}) async {
  if (producer == 'htmx') {
    return _renderFallbackHtmx(designRoot, evidence, viewports, repoRoot, details);
  }
  return _renderFallbackStacked(designRoot, evidence, viewports, repoRoot, details);
}

/// arxa_kit fallback: `uv run --with playwright python -` with the same
/// render script freeze.sh embeds. If uv is absent, there is no backend.
Future<List<String>?> _renderFallbackStacked(
  String designRoot,
  String evidence,
  List<_Vp> viewports,
  String repoRoot,
  List<String> details,
) async {
  final uv = await _which('uv');
  if (uv == null) return null;

  final configPath = '$repoRoot/config/arxa.config.json';
  final derived = viewports.map((v) => v.name).join(' ');
  final py = _stackedRenderScript;
  final res = await Process.start(
    uv,
    ['run', '--with', 'playwright', 'python', '-',
      designRoot, evidence, configPath, derived],
  );
  res.stdin.write(py);
  await res.stdin.close();
  final out = <String>[];
  final errLines = <String>[];
  final subOut = res.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) {
    out.add(l);
    details.add('  $l');
  });
  final subErr = res.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(errLines.add);
  await res.exitCode;
  await subOut.cancel();
  await subErr.cancel();
  if (errLines.isNotEmpty) {
    details.addAll(errLines.map((l) =>  '  $l'));
  }
  return out.where((l) => l.startsWith('FAIL: render:')).toList();
}

/// htmx fallback: start the Dart designer server, then run render_htmx.mjs.
/// Mirrors freeze.sh's Node orchestration.
Future<List<String>?> _renderFallbackHtmx(
  String designRoot,
  String evidence,
  List<_Vp> viewports,
  String repoRoot,
  List<String> details,
) async {
  final node = await _which('node');
  if (node == null) return null;

  final runtimeDir = '$repoRoot/skills/arxa-designer/runtime';
  final served = await _startDesignerServer(runtimeDir, designRoot);
  if (served.base == null) {
    details.add('  FAIL: render: designer server did not start '
        '(${served.error ?? ""})');
    served.dispose();
    return ['render: designer server did not start'];
  }
  final base = served.base!.replaceAll(RegExp(r'/+$'), '');
  final renderDriver = '$repoRoot/gates/freeze/render_htmx.mjs';
  final vpsJson = jsonEncode(viewports
      .map((v) => {'name': v.name, 'width': v.width, 'height': v.height})
      .toList());
  final locales = _designLocales(designRoot).join(',');

  try {
    final res = await Process.run(node, [
      renderDriver,
      designRoot,
      base,
      evidence,
      vpsJson,
      runtimeDir,
      locales,
    ]);
    final out = (res.stdout as String).split('\n');
    details.addAll(out.where((l) => l.trim().isNotEmpty).map((l) => '  $l'));
    if ((res.stderr as String).trim().isNotEmpty) {
      details.add('  ${(res.stderr as String).trim()}');
    }
    return out.where((l) => l.startsWith('FAIL: render:')).toList();
  } finally {
    served.dispose();
  }
}

/// The exact arxa_kit render script freeze.sh embeds (uv + playwright),
/// trimmed of comments. Behaviour identical to the bash heredoc.
const _stackedRenderScript = r'''
import sys,threading,functools,http.server,socketserver,os,glob,json
design,evidence,config,derived=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
all_vps=json.load(open(config))["viewports"]
want=set(derived.split())
viewports=[(n,all_vps[n]["width"],all_vps[n]["height"]) for n in all_vps if n in want]
if not viewports:
    print(f"FAIL: render: derived viewports [{derived}] matched no config viewport"); sys.exit(1)
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
srv=socketserver.ThreadingTCPServer(("127.0.0.1",0),functools.partial(Q,directory=design))
port=srv.server_address[1]
threading.Thread(target=srv.serve_forever,daemon=True).start()
from playwright.sync_api import sync_playwright
errors=[]
surfaces=sorted(glob.glob(os.path.join(design,"surfaces","*.html")))
with sync_playwright() as pw:
    b=pw.chromium.launch()
    for vname,vw,vh in viewports:
        for html in surfaces:
            name=os.path.splitext(os.path.basename(html))[0]
            pg=b.new_page(viewport={"width":int(vw),"height":int(vh)})
            msgs=[]
            pg.on("console",lambda m,msgs=msgs: msgs.append(m.text) if m.type=="error" else None)
            pg.on("pageerror",lambda e,msgs=msgs: msgs.append(str(e)))
            pg.goto(f"http://127.0.0.1:{port}/surfaces/{name}.html")
            pg.wait_for_timeout(1200)
            pg.screenshot(path=os.path.join(evidence,f"{name}_{vname}.png"),full_page=True)
            for m in msgs: errors.append(f"{name}@{vname}: {m}")
            pg.close()
            print(f"  \u2713 render: {name}.html @ {vname} ({vw}x{vh}) loaded, screenshot -> {evidence}/{name}_{vname}.png")
    b.close()
srv.shutdown()
for e in errors: print(f"FAIL: render: console/page error \u2014 {e}")
print(f"  render: {len(surfaces)*len(viewports)} surface/viewport render(s) across {len(viewports)} derived width(s), {len(errors)} error(s)")
sys.exit(1 if errors else 0)
''';

Future<String?> _which(String cmd) async {
  try {
    final r = await Process.run('command', ['-v', cmd], runInShell: true);
    if (r.exitCode == 0) return (r.stdout as String).trim();
  } catch (_) {}
  // PATH lookup fallback (command -v can differ under non-login shells).
  final path = Platform.environment['PATH'] ?? '';
  for (final dir in path.split(':')) {
    if (dir.isEmpty) continue;
    final candidate = '$dir/$cmd';
    if (await File(candidate).exists()) return candidate;
  }
  return null;
}

// ── shared file helpers ─────────────────────────────────────────────────────

String _baseName(FileSystemEntity f) => f.uri.pathSegments.last;

String _surfaceName(File file) {
  final base = _baseName(file);
  return base.endsWith('.html') ? base.substring(0, base.length - 5) : base;
}

List<File> _surfaceHtml(String designRoot) {
  final d = Directory('$designRoot/surfaces');
  if (!d.existsSync()) return const [];
  return d.listSync().whereType<File>().where((f) => f.path.endsWith('.html')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

List<File> _viewTemplates(String designRoot) {
  final d = Directory('$designRoot/ui/views');
  if (!d.existsSync()) return const [];
  final out = <File>[];
  void walk(Directory dir) {
    for (final e in dir.listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (e is Directory) {
        walk(e);
      } else if (e is File &&
          (e.path.endsWith('_view.html') || e.path.endsWith('_view.tsx'))) {
        out.add(e);
      }
    }
  }
  walk(d);
  return out;
}
