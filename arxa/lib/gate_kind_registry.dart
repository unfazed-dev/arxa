// kind_registry gate — Dart port of
// skills/arxa-scaffolder/scripts/validate-registry.py (Q7 + Q12).
//
// The registry under skills/arxa-scaffolder/kind-resolution.registry.json
// maps designer widget kinds to kit targets. It is checked against three
// ground truths:
//   1. VOCABULARY — skills/arxa-designer/starter-partials/widgets/_<kind>.tsx
//      IS the kind vocabulary; the registry must cover it exactly.
//   2. TARGETS — every widget/variants/companions/composedFrom/presentation
//      reference must be a real class declared under kit/ui_library/lib.
//   3. INSPECT IDENTITY (Q12) — the Dart shape named by
//      designVocabulary.inspectAttrs must exist, declare the triple
//      (screenId, surfaceId, anatomyNodeId) and be exported from the
//      kit-core barrel; and no anatomy id stamped anywhere under kit/ may
//      sit outside the closed anatomyNodes.vocabulary set.
//
// Duplicate JSON keys are detected mechanically because the registry was
// twice given one ("modal", "tabs") and decode silently keeps the last
// entry — a carefully authored entry vanished with no error and no diff
// conflict. Prose review did not catch it either time.
//
// Exit code convention: 0 pass / 1 FAIL / 2 not-applicable (no registry).
import 'dart:convert';
import 'dart:io';

import 'package:arxa/gates.dart';
import 'package:path/path.dart' as p;

/// What the validator found, independent of GateContext so tests can drive
/// it over fixture trees directly.
class KindRegistryReport {
  final List<String> violations;
  final String registryVersion;
  final int kindCount;
  final int vocabCount;
  final int anatomyCount;

  const KindRegistryReport({
    this.violations = const [],
    this.registryVersion = '?',
    this.kindCount = 0,
    this.vocabCount = 0,
    this.anatomyCount = 0,
  });

  bool get clean => violations.isEmpty;
}

const _shapes = ['widget', 'variants', 'composedFrom', 'presentation'];

final _anatomyIdRe = RegExp(
    r'^anatomy:[a-z][a-zA-Z0-9]*(?:\.[a-z][a-zA-Z0-9]*)*$');
// Any 'anatomy:...' string literal stamped in Dart under kit/. Deliberately
// broad: it catches ids invented at the call site, which is exactly how a
// closed set rots.
final _anatomyUseRe = RegExp(r'''['"](anatomy:[^'"]*)['"]''');

final _classDeclRe = RegExp(
    r'^\s*(?:abstract\s+|final\s+|base\s+|sealed\s+)*class\s+(\w+)',
    multiLine: true);

/// Core validator — a pure function over the four paths the Python original
/// derived from its own location.
KindRegistryReport validateKindRegistry({
  required String registryPath,
  required String partialsDir,
  required String kitLibDir,
  required String kitRoot,
}) {
  final bad = <String>[];

  final registryFile = File(registryPath);
  if (!registryFile.existsSync()) {
    return const KindRegistryReport(
        violations: ['kind-resolution.registry.json not found'],
        registryVersion: '?');
  }
  final raw = registryFile.readAsStringSync();

  // ---- duplicate keys (the founding failure this gate exists for) --------
  final dups = _scanDuplicateKeys(raw);
  for (final d in dups) {
    bad.add(
        "DUPLICATE KEY '$d' — JSON keeps only the last; an entry is being silently discarded");
  }

  Map<String, dynamic> reg;
  try {
    reg = jsonDecode(raw) as Map<String, dynamic>;
  } on FormatException catch (e) {
    return KindRegistryReport(
        violations: ['registry does not parse as JSON: ${e.message}']);
  }

  final kinds = (reg['kinds'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final order = ((reg['resolution'] as Map<String, dynamic>?)?['order']
          as List?)
      ?.map((e) => e.toString())
      .toList() ??
      const <String>[];

  // ---- ground truth 1: vocabulary ----------------------------------------
  var vocab = <String>{};
  final partialsDirectory = Directory(partialsDir);
  if (partialsDirectory.existsSync()) {
    vocab = partialsDirectory.listSync().whereType<File>().map((f) {
      final name = p.basename(f.path);
      return name.startsWith('_') && name.endsWith('.tsx')
          ? name.substring(1, name.length - 4)
          : null;
    }).whereType<String>().toSet();
  } else {
    bad.add('vocabulary source missing: $partialsDir');
  }

  for (final k in vocab.difference(kinds.keys.toSet())) {
    bad.add(
        "UNCOVERED KIND '$k' — _$k.tsx is authored but has no registry entry");
  }
  for (final k in kinds.keys.toSet().difference(vocab)) {
    bad.add("ORPHAN ENTRY '$k' — registry maps a kind with no authored partial");
  }

  // ---- ground truth 2: targets -------------------------------------------
  final classes = <String>{};
  final kitLibDirectory = Directory(kitLibDir);
  if (kitLibDirectory.existsSync()) {
    for (final f in kitLibDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      classes.addAll(
          _classDeclRe.allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
    }
  }
  if (classes.isEmpty) {
    bad.add('no Dart classes found under $kitLibDir — cannot verify targets');
  }

  for (final shape in _shapes) {
    if (!order.any((o) => o.contains(shape))) {
      bad.add(
          "'$shape' NOT IN resolution.order — entries using it fall through to FAIL");
    }
  }

  for (final kind in kinds.keys.toList()..sort()) {
    final v = kinds[kind];
    if (v is! Map<String, dynamic>) {
      bad.add('$kind: entry is not an object');
      continue;
    }
    if (!_shapes.any((s) => v[s] != null && v[s] != false && v[s] != '')) {
      bad.add('$kind: UNRESOLVABLE — none of $_shapes present');
    }
    final refs = <String>[
      if (v['widget'] is String) v['widget'] as String,
      if (v['composedFrom'] is List)
        ...(v['composedFrom'] as List).whereType<String>(),
      if (v['companions'] is List)
        ...(v['companions'] as List).whereType<String>(),
      ...(((v['presentation'] as Map<String, dynamic>?) ?? {})
          .values
          .whereType<String>()
          .where((x) => x.startsWith('ArxaKit'))),
      ...(((v['variants'] as Map<String, dynamic>?) ?? {})
          .values
          .whereType<String>()),
    ];
    for (final r in refs) {
      if (classes.isNotEmpty && !classes.contains(r)) {
        bad.add(
            "$kind: '$r' is not a class in kit/ui_library/lib — invented placeholder?");
      }
    }
    final esc = v['escape'];
    if (esc is Map<String, dynamic> &&
        !['reason', 'owner', 'expires'].every((k) =>
            esc[k] is String && (esc[k] as String).isNotEmpty)) {
      bad.add('$kind: escape entry must carry reason, owner and expires');
    }
  }

  // ---- ground truth 3 (Q12): inspect identity ----------------------------
  final anat = (reg['anatomyNodes'] as Map<String, dynamic>?) ?? {};
  final declared =
      (anat['vocabulary'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final shapePkg =
      (reg['designVocabulary'] as Map<String, dynamic>?)?['inspectAttrs']
          as String?;

  if (declared.isEmpty) {
    bad.add(
        "anatomyNodes.vocabulary is empty — the inspect triple's third slot has no closed set");
  }
  for (final nid in declared.keys.toList()..sort()) {
    if (!_anatomyIdRe.hasMatch(nid)) {
      bad.add(
          "MALFORMED anatomy id '$nid' — expected anatomy:<dotted.lowerCamel> segments");
    }
    final desc = declared[nid];
    if (desc is! String || desc.trim().isEmpty) {
      bad.add(
          "anatomy id '$nid' has no description — an id nobody can place is an id nobody can check");
    }
  }

  if (shapePkg == null || shapePkg.isEmpty) {
    bad.add(
        'designVocabulary.inspectAttrs missing — the inspect shape has no declared single home');
  } else {
    // package:arxa_kit_core/common/x.dart -> kit/core/lib/common/x.dart
    final rel = shapePkg.contains('/')
        ? shapePkg.split('/').skip(1).join('/')
        : '';
    final shapePath = p.join(kitRoot, 'core', 'lib', rel);
    final shapeFile = File(shapePath);
    if (!shapeFile.existsSync()) {
      bad.add(
          'inspectAttrs shape $shapePkg does not exist on disk ($shapePath)');
    } else {
      final src = shapeFile.readAsStringSync();
      if (!src.contains('class ArxaKitInspectAttrs')) {
        bad.add('$shapePkg does not declare class ArxaKitInspectAttrs');
      }
      for (final slot in ['screenId', 'surfaceId', 'anatomyNodeId']) {
        if (!RegExp(r'\b' + slot + r'\b').hasMatch(src)) {
          bad.add("$shapePkg does not carry triple slot '$slot'");
        }
      }
      final barrel =
          File(p.join(kitRoot, 'core', 'lib', 'arxa_kit_core.dart'));
      if (barrel.existsSync() &&
          !barrel.readAsStringSync().contains(p.basename(rel))) {
        bad.add(
            'inspectAttrs shape is not exported from arxa_kit_core.dart — importers cannot reach the single home');
      }
    }
  }

  // The anti-drift half: every anatomy id stamped under kit/ must be
  // registered. An unused declared id is harmless; an unregistered stamped
  // id is drift.
  if (declared.isNotEmpty) {
    final seen = <String, List<String>>{};
    final kitDirectory = Directory(kitRoot);
    if (kitDirectory.existsSync()) {
      for (final f in kitDirectory
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final normalized = p.normalize(f.absolute.path);
        if (normalized.contains('${p.separator}.dart_tool${p.separator}') ||
            normalized.contains('${p.separator}build${p.separator}')) {
          continue;
        }
        for (final m in _anatomyUseRe.allMatches(f.readAsStringSync())) {
          final id = m.group(1)!;
          if (!declared.containsKey(id)) {
            seen
                .putIfAbsent(id, () => [])
                .add(p.relative(f.path, from: kitRoot));
          }
        }
      }
    }
    for (final nid in seen.keys.toList()..sort()) {
      final where = (seen[nid]!.toSet().toList()..sort()).take(3).join(', ');
      bad.add(
          "UNREGISTERED anatomy id '$nid' stamped at $where — not in anatomyNodes.vocabulary");
    }
  }

  return KindRegistryReport(
    violations: bad,
    registryVersion: reg['registryVersion']?.toString() ?? '?',
    kindCount: kinds.length,
    vocabCount: vocab.length,
    anatomyCount: declared.length,
  );
}

/// Scans raw JSON text for keys that appear more than once within the same
/// object — the check Dart's decoder cannot do (it silently keeps the last,
/// exactly like Python's). Tracks string tokens, object nesting, and whether
/// a string is followed by ':' (a key). Backslash is compared by code unit
/// (92) because no Dart string literal can end a raw string with one.
Set<String> _scanDuplicateKeys(String src) {
  final dups = <String>{};
  final stack = <Map<String, int>>[];

  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '{') {
      stack.add(<String, int>{});
      i++;
    } else if (c == '}') {
      if (stack.isNotEmpty) stack.removeLast();
      i++;
    } else if (c == '"') {
      final start = ++i;
      while (i < src.length && src[i] != '"') {
        if (src.codeUnitAt(i) == 92) i++; // skip escaped char
        i++;
      }
      final token = src.substring(start, i);
      i++; // closing quote
      // Key iff the next non-whitespace char is ':'.
      var j = i;
      while (j < src.length && src.codeUnitAt(j) <= 0x20) {
        j++;
      }
      if (j < src.length && src[j] == ':' && stack.isNotEmpty) {
        final counts = stack.last;
        counts[token] = (counts[token] ?? 0) + 1;
        if (counts[token]! > 1) dups.add(token);
      }
    } else {
      i++;
    }
  }
  return dups;
}

/// Gate wrapper — resolves the real repo paths and renders the report.
GateResult kindRegistryGate(GateContext ctx) {
  if (ctx.selfTest) return _selfTest();

  final root = ctx.repoRoot;
  final report = validateKindRegistry(
    registryPath: p.join(
        root, 'skills', 'arxa-scaffolder', 'kind-resolution.registry.json'),
    partialsDir: p.join(
        root, 'skills', 'arxa-designer', 'starter-partials', 'widgets'),
    kitLibDir: p.join(root, 'kit', 'ui_library', 'lib'),
    kitRoot: p.join(root, 'kit'),
  );

  if (report.violations.contains('kind-resolution.registry.json not found')) {
    return GateResult(
      passed: false,
      exitCode: envExit,
      summary:
          'kind_registry: no kind-resolution.registry.json under skills/arxa-scaffolder — not applicable',
    );
  }

  if (report.clean) {
    return GateResult(
      passed: true,
      exitCode: passExit,
      summary:
          'registry OK — v${report.registryVersion}, ${report.kindCount} kinds, '
          'vocabulary matches ${report.vocabCount} partials, all targets real, '
          '${report.anatomyCount} anatomy node id(s) closed and unviolated',
      details: const [
        '  ✓ kind-resolution.registry.json passes all three ground truths'
      ],
    );
  }

  for (final v in report.violations) {
    ctx.sarif.result(
        'kind_registry', 'error', 'kind-resolution.registry.json', v);
  }
  return GateResult(
    passed: false,
    exitCode: failExit,
    summary: 'REGISTRY INVALID — ${report.violations.length} violation(s)',
    details: report.violations.map((v) => '  ✗ $v').toList(),
  );
}

/// --self-test (R5): proves the negatives fire — a registry that should fail
/// does fail for the right reason, and the scanner catches planted dups.
GateResult _selfTest() {
  final tmp = Directory.systemTemp.createTempSync('kind_registry_selftest');
  final problems = <String>[];

  final registry = p.join(tmp.path, 'r.json');
  File(registry).writeAsStringSync('''
{
  "registryVersion": "0.0.0-test",
  "kinds": {
    "ghost": { "widget": "ArxaKitNope" }
  },
  "resolution": { "order": ["widget"] },
  "anatomyNodes": { "vocabulary": { "anatomy:ok": "fine" } }
}
''');
  final report = validateKindRegistry(
    registryPath: registry,
    partialsDir: p.join(tmp.path, 'no-partials'),
    kitLibDir: p.join(tmp.path, 'no-kit'),
    kitRoot: p.join(tmp.path, 'no-kit'),
  );
  const expectedFragments = [
    'ORPHAN ENTRY',
    'no Dart classes found under',
    'NOT IN resolution.order',
    'designVocabulary.inspectAttrs missing',
  ];
  for (final frag in expectedFragments) {
    if (!report.violations.any((v) => v.contains(frag))) {
      problems.add('self-test: expected a violation containing "$frag"');
    }
  }

  final dupFile = p.join(tmp.path, 'dup.json');
  File(dupFile).writeAsStringSync('{"a": 1, "a": 2}');
  if (!_scanDuplicateKeys(File(dupFile).readAsStringSync()).contains('a')) {
    problems.add('self-test: duplicate-key scanner missed the planted dup');
  }

  final result = GateResult(
    passed: problems.isEmpty,
    exitCode: problems.isEmpty ? passExit : failExit,
    summary: problems.isEmpty
        ? 'kind_registry self-test OK — ${expectedFragments.length} planted defects all detected'
        : 'kind_registry self-test FAILED',
    details: problems.map((v) => '  ✗ $v').toList(),
  );
  tmp.deleteSync(recursive: true);
  return result;
}

