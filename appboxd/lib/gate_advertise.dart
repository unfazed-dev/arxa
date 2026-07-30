// Advertise gate — port of gates/advertise/advertise.py to pure Dart.
//
// The one gate that stops a surface offering a provider above its recorded
// verification tier (plan 13.2/13.3). Two assertions, forever:
//
//   1. EVIDENCE — every registry provider whose verification tier != 'stub'
//      must carry a matching, suite-backed record in the evidence ledger
//      (tier, suite path, content digest, run timestamp). The ledger is
//      written ONLY by a tier suite; the gate never writes it. Hand-editing
//      a tier in the registry therefore fails: the bumped tier has no
//      evidence to back it.
//
//   2. OFFER — no surface may offer a provider above its recorded tier.
//      Offering a 'stub'-tier provider at any level fails outright (a stub
//      can never be offered); offering a provider above its recorded tier
//      fails.
//
// Inputs (defaults relative to repoRoot):
//   tools/vendor/kit_registry/kit-registry.json  — recorded tier per provider
//   tools/verification/evidence.json             — ledger of suites that ran
//   gates/advertise/offers.json                  — what each surface offers

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/crypto_aead.dart' as crypto;
import 'package:appboxd/gates.dart';

const _tiers = ['stub', 'port-tested', 'sim-verified', 'device-verified'];

/// tier -> rank, mirroring Python's RANK (enumerate(TIERS)).
final _rank = {
  for (var i = 0; i < _tiers.length; i++) _tiers[i]: i,
};

/// Python's repr(TIERS) — `['stub', 'port-tested', ...]` with quotes. Dart's
/// List.toString() omits quotes, so we format it to match the Python message.
final _tiersRepr = "[${_tiers.map((t) => "'$t'").join(', ')}]";

/// A single finding: the user-facing message and the manifest file it concerns
/// (fed to SARIF as the artifact location).
class _Finding {
  final String message;
  final String file;
  _Finding(this.message, this.file);
}

/// {(kit_dir/provider_name): verification} across all kits, in registry order.
/// The slash-joined key is exactly the ledger key (`"$kit/$name"`), so an
/// evidence lookup needs no re-derivation.
Map<String, String> _providerIndex(Map<String, dynamic> reg) {
  final idx = <String, String>{};
  for (final k in (reg['kits'] as List).cast<Map<String, dynamic>>()) {
    final dir = k['dir'] as String;
    final providers = k['providers'];
    if (providers is! List) continue;
    for (final p in providers.cast<Map<String, dynamic>>()) {
      idx['$dir/${p['name']}'] = p['verification'] as String;
    }
  }
  return idx;
}

/// `"sha256:" + hex` of a file's raw bytes. Python streams 64KB chunks; the
/// digest is over the concatenation so a single read is identical.
String _fileDigest(String path) {
  final digest = crypto.sha256(File(path).readAsBytesSync());
  return 'sha256:${digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

/// Parse a JSON file as a Map, or null on any read/parse failure.
Map<String, dynamic>? _load(String path) {
  try {
    final parsed = jsonDecode(File(path).readAsStringSync());
    if (parsed is Map<String, dynamic>) return parsed;
    if (parsed is Map) return parsed.cast<String, dynamic>();
    return null;
  } catch (_) {
    return null;
  }
}

/// `os.path.relpath(p, root)`, enough for the "no ledger at `<rel>`" message.
String _relpath(String p, String root) {
  if (!p.startsWith(root)) return p;
  var r = p.substring(root.length);
  while (r.startsWith('/')) {
    r = r.substring(1);
  }
  return r.isEmpty ? '.' : r;
}

/// Every registry provider whose tier != 'stub' must have a matching,
/// suite-backed evidence record.
List<_Finding> _checkEvidence(
    Map<String, String> idx, String evidencePath, String root,
    String registryPath) {
  final errs = <_Finding>[];
  final evFile = File(evidencePath);
  if (!evFile.existsSync()) {
    final rel = _relpath(evidencePath, root);
    for (final entry in idx.entries) {
      if (entry.value != 'stub') {
        errs.add(_Finding(
          "${entry.key}: tier '${entry.value}' but no evidence ledger at "
          "$rel — a tier is set only by a suite that ran (13.3); hand-edit "
          "rejected",
          registryPath,
        ));
      }
    }
    return errs;
  }

  final ledgerRaw = _load(evidencePath)?['ledger'];
  final ledger = ledgerRaw is Map
      ? ledgerRaw.cast<String, Map<String, dynamic>>()
      : <String, Map<String, dynamic>>{};

  for (final entry in idx.entries) {
    final key = entry.key;
    final tier = entry.value;
    if (tier == 'stub') continue;
    final rec = ledger[key];
    if (rec == null) {
      errs.add(_Finding(
        "$key: tier '$tier' but no evidence record — a tier is set only by "
        "a suite that ran (13.3); hand-edit rejected",
        registryPath,
      ));
      continue;
    }
    if (rec['tier'] != tier) {
      errs.add(_Finding(
        "$key: registry tier '$tier' != evidence tier '${rec['tier']}' — "
        "registry was hand-edited away from what the suite recorded",
        registryPath,
      ));
      continue;
    }
    final suite = rec['suite'] as String?;
    final suiteAbs =
        (suite != null && suite.startsWith('/')) ? suite : '$root/$suite';
    if (suite == null || !File(suiteAbs).existsSync()) {
      errs.add(_Finding(
        "$key: evidence points at suite '$suite' which does not exist — "
        "evidence is stale or forged",
        evidencePath,
      ));
      continue;
    }
    final actual = _fileDigest(suiteAbs);
    if (rec['digest'] != actual) {
      errs.add(_Finding(
        "$key: suite '$suite' changed since the tier was set "
        "(digest ${rec['digest']} -> $actual) — re-run the suite to re-record "
        "evidence at the new suite content",
        evidencePath,
      ));
    }
  }
  return errs;
}

/// No surface offers a provider above its recorded tier; a stub is never
/// offered. A missing offers manifest means nothing is advertised — vacuously
/// honest.
List<_Finding> _checkOffers(Map<String, String> idx, String offersPath) {
  final errs = <_Finding>[];
  if (!File(offersPath).existsSync()) return errs;
  final offers = _load(offersPath);
  if (offers == null) return errs;

  for (final surf
      in ((offers['surfaces'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
    final sname = (surf['name'] as String?) ?? '?';
    final offerList = surf['offers'];
    if (offerList is! List) continue;
    for (final off in offerList.cast<Map<String, dynamic>>()) {
      final kit = off['kit'] as String?;
      final prov = off['provider'] as String?;
      final otier = (off['tier'] as String?) ?? 'stub';
      final key = '$kit/$prov';
      if (!idx.containsKey(key)) {
        errs.add(_Finding(
          "surface '$sname' offers $key which is not in the registry — "
          "cannot advertise an unknown provider",
          offersPath,
        ));
        continue;
      }
      final rtier = idx[key]!;
      if (rtier == 'stub') {
        errs.add(_Finding(
          "surface '$sname' offers $key but its recorded tier is 'stub' — "
          "a stub may never be offered (13.2)",
          offersPath,
        ));
        continue;
      }
      // rtier is vocabulary-validated before this runs; otier defaults to
      // 'stub'. Guard the comparison so an out-of-vocab offer tier can't crash
      // (Python's dict[k] would KeyError) — it just isn't ranked above.
      final oRank = _rank[otier];
      final rRank = _rank[rtier];
      if (oRank != null && rRank != null && oRank > rRank) {
        errs.add(_Finding(
          "surface '$sname' offers $key at '$otier' above its recorded tier "
          "'$rtier' (13.2)",
          offersPath,
        ));
      }
    }
  }
  return errs;
}

/// Port of gates/advertise/advertise.py main().
GateResult advertiseGate(GateContext ctx) {
  final root = ctx.repoRoot;
  final registryPath = '$root/tools/vendor/kit_registry/kit-registry.json';
  final evidencePath = '$root/tools/verification/evidence.json';
  final offersPath = '$root/gates/advertise/offers.json';

  // Registry is the essential input — its absence is a hard fail, not vacuous.
  final Map<String, dynamic> reg;
  try {
    reg = jsonDecode(File(registryPath).readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    return GateResult.fail('cannot read registry $registryPath — $e');
  }
  final idx = _providerIndex(reg);

  final findings = <_Finding>[];

  // Validate the tier vocabulary itself (typo guard).
  for (final entry in idx.entries) {
    if (!_rank.containsKey(entry.value)) {
      findings.add(_Finding(
        "${entry.key}: unknown verification tier '${entry.value}' "
        "(must be one of $_tiersRepr)",
        registryPath,
      ));
    }
  }

  findings.addAll(_checkEvidence(idx, evidencePath, root, registryPath));
  findings.addAll(_checkOffers(idx, offersPath));

  if (findings.isNotEmpty) {
    final details = <String>[];
    for (final f in findings) {
      details.add('  ✗ ${f.message}');
      ctx.sarif.result('advertise', 'error', f.file, f.message);
    }
    return GateResult.fail('advertise gate FAILED', details);
  }

  final nprov = idx.length;
  final nstub = idx.values.where((t) => t == 'stub').length;
  return GateResult.ok(
    'advertise gate OK — $nprov provider(s), $nstub stub (not offered), '
    '${nprov - nstub} evidence-backed',
  );
}
