// kb_check.dart — validate kb/sources.json schema, per-kit source coverage
// (>=3), and References-block presence in each kit playbook.
// (Dart port of arxa_kit/tools/kb_check.sh.)
//
// Fatal (populates [KbCheckResult.errors], sets ok=false):
//   - sources.json missing / not valid JSON / not an object
//   - a source missing a required key, with a bad kind, a bad url, a non-list
//     kits field, or a duplicate id
//   - a kit (derived from memory/facts/*.json) with fewer than three backing
//     sources (registry sources whose `kits` names it or is `*`, plus mined
//     backingPackages from the kit's fact file)
//   - a kit playbook missing or lacking the kb:begin/kb:end References block
//
// Non-fatal (warnings):
//   - a `community` source whose lastVerified is older than 12 months, or has
//     an unparseable date.
//
// Network link-liveness (--verify-links) is intentionally NOT ported; passing
// verifyLinks=true records a TODO warning instead of doing HTTP HEAD checks.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class KbCheckResult {
  final List<String> errors;
  final List<String> warnings;
  const KbCheckResult(this.errors, this.warnings);
  bool get ok => errors.isEmpty;
}

const _requiredKeys = <String>{'id', 'title', 'url', 'kind', 'kits'};
const _validKinds = <String>{
  'official',
  'api',
  'package',
  'community',
  'mcp',
};

/// Validates the knowledge-base state under [repoRoot].
///
/// Reads `kb/sources.json` and `memory/facts/*.json`, and looks for each
/// kit's playbook at `<repoRoot>/<kit>/<kit>_playbook.mdx`.
KbCheckResult kbCheck(String repoRoot, {bool verifyLinks = false}) {
  final errors = <String>[];
  final warnings = <String>[];

  if (verifyLinks) {
    warnings.add('TODO: --verify-links network liveness check not yet ported');
  }

  // --- sources.json load + schema -----------------------------------------
  final sourcesPath = p.join(repoRoot, 'kb', 'sources.json');
  final List<dynamic> sources;
  try {
    final raw = jsonDecode(File(sourcesPath).readAsStringSync());
    if (raw is! Map<String, dynamic>) {
      errors.add('sources.json: top-level value must be an object');
      return KbCheckResult(errors, warnings);
    }
    sources = (raw['sources'] ?? const []) as List<dynamic>;
  } catch (e) {
    errors.add('sources.json is not valid JSON: $e');
    return KbCheckResult(errors, warnings);
  }

  final ids = <String>{};
  for (final raw in sources) {
    if (raw is! Map) {
      errors.add('source entry is not an object');
      continue;
    }
    final s = raw.cast<String, dynamic>();
    final id = (s['id'] ?? '?').toString();
    final missing = _requiredKeys.difference(s.keys.toSet());
    if (missing.isNotEmpty) errors.add('$id: missing $missing');
    if (s.containsKey('id')) {
      final idStr = s['id'].toString();
      if (ids.contains(idStr)) errors.add('duplicate id: $idStr');
      ids.add(idStr);
    }
    if (!_validKinds.contains(s['kind'])) {
      errors.add('$id: bad kind ${s['kind']}');
    }
    if (!s['url'].toString().startsWith(RegExp(r'^https?://'))) {
      errors.add('$id: bad url');
    }
    if (s['kits'] is! List) errors.add('$id: kits must be a list');
  }

  // --- kits known from memory/facts/*.json --------------------------------
  final factsDir = p.join(repoRoot, 'memory', 'facts');
  final kits = <String>[];
  final factsDirEnt = Directory(factsDir);
  if (factsDirEnt.existsSync()) {
    for (final entry in factsDirEnt.listSync()) {
      final name = p.basename(entry.path);
      if (entry is File && name.endsWith('.json')) {
        kits.add(name.substring(0, name.length - 5));
      }
    }
  }
  kits.sort();
  final known = kits.toSet();

  // --- coverage: registry sources + mined backingPackages -----------------
  final cov = <String, Set<String>>{for (final k in kits) k: <String>{}};
  for (final raw in sources) {
    if (raw is! Map) continue;
    final s = raw.cast<String, dynamic>();
    final id = (s['id'] ?? '?').toString();
    final kitsField = s['kits'];
    if (kitsField is! List) continue;
    final coversAll = kitsField.any((k) => k == '*');
    final covered = coversAll
        ? known.toSet()
        : {for (final k in kitsField) if (known.contains(k)) k.toString()};
    for (final k in covered) {
      cov[k]?.add(id);
    }
  }
  for (final k in kits) {
    final fact = _readFact(factsDir, k);
    for (final pkg in (fact?['backingPackages'] ?? const []) as List) {
      cov[k]?.add('pkg-$k-$pkg');
    }
  }
  for (final k in kits) {
    final n = cov[k]?.length ?? 0;
    if (n < 3) errors.add('$k: only $n source(s) — need >= 3');
  }

  // --- playbook References block ------------------------------------------
  for (final k in kits) {
    final playbook = File(p.join(repoRoot, k, '${k}_playbook.mdx'));
    if (!playbook.existsSync()) {
      errors.add('$k: missing ${k}_playbook.mdx');
      continue;
    }
    final txt = playbook.readAsStringSync();
    if (!txt.contains('<!-- kb:begin -->') || !txt.contains('<!-- kb:end -->')) {
      errors.add('$k: playbook missing kb:begin/kb:end References block');
    }
  }

  // --- community staleness (warning) --------------------------------------
  final today = DateTime.now();
  for (final raw in sources) {
    if (raw is! Map) continue;
    final s = raw.cast<String, dynamic>();
    if (s['kind'] != 'community') continue;
    final lv = s['lastVerified']?.toString();
    if (lv == null || lv.isEmpty) continue;
    final d = DateTime.tryParse(lv);
    if (d == null) {
      warnings.add('${s['id']}: bad lastVerified date $lv');
    } else if (today.difference(d).inDays > 365) {
      warnings.add(
          '${s['id']}: community source not verified in >12 months ($lv)');
    }
  }

  return KbCheckResult(errors, warnings);
}

Map<String, dynamic>? _readFact(String factsDir, String kit) {
  final f = File(p.join(factsDir, '$kit.json'));
  if (!f.existsSync()) return null;
  try {
    final parsed = jsonDecode(f.readAsStringSync());
    return parsed is Map<String, dynamic> ? parsed : null;
  } catch (_) {
    return null;
  }
}
