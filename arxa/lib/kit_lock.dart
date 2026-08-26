// kit_lock.dart — deterministic kit.lock generator (Dart port of
// arxa_kit/tools/gen_kit_lock.sh).
//
// kit.lock is a Terraform-lock-shaped JSON pin of the Input Tuple: kit
// version, per-skill SKILL.md content hashes, and substrate tool hashes.
// Deterministic by design — no timestamps, no absolute paths — so re-running
// on an unchanged tree reproduces kit.lock byte-for-byte and drift shows up
// as an ordinary git diff.
//
// Skills and tools are discovered (not hard-coded) and emitted in sorted
// name order, so the lock tracks whatever the tree currently ships without a
// list to keep in sync. SHA-256 reuses the pure-Dart primitive in
// crypto_aead.dart (no third-party crypto, per arxa's zero-dependency rule).

import 'dart:convert';
import 'dart:io';

import 'package:arxa/crypto_aead.dart';
import 'package:path/path.dart' as p;

/// Generates kit.lock content as a deterministic JSON string.
///
/// [repoRoot] is the arxa root — `skills/` and `tools/` live here.
/// [kitRoot] is the `kit/` directory; the kit version is read from
/// `core/pubspec.yaml` (core is the keystone kit).
String generateKitLock(String repoRoot, String kitRoot) {
  final skills = _discoverSkills(repoRoot);
  final tools = _discoverTools(repoRoot);

  final lock = <String, dynamic>{
    'lockfileVersion': 1,
    'kit': {
      'name': 'arxa_kit',
      'version': _kitVersion(kitRoot),
    },
    'model': {
      'identity': 'session-config',
      'note': 'Declared, not enforced: this harness pins model identity '
          'session-wide (config.toml), not per skill — the gates, not '
          'API parameters, carry equivalence enforcement (ADR 0009).',
    },
    'skills': {
      for (final name in skills)
        name: {
          'path': 'skills/$name/SKILL.md',
          'sha256': _sha256OfFile(
              p.join(repoRoot, 'skills', name, 'SKILL.md')),
        },
    },
    'tools': {
      for (final name in tools)
        name: {
          'path': 'tools/$name',
          'sha256': _sha256OfFile(p.join(repoRoot, 'tools', name)),
        },
    },
  };

  // 2-space indent + trailing newline matches the bash generator's layout.
  // JsonEncoder does not sort keys — it follows insertion order, which we
  // control (sorted skill/tool names), so output is byte-stable on re-run.
  return '${const JsonEncoder.withIndent('  ').convert(lock)}\n';
}

/// Reads the kit version from `core/pubspec.yaml` (mirrors the bash regex
/// `^version:\s*(\S+)`). Returns 'unknown' if core or the version is absent.
String _kitVersion(String kitRoot) {
  final pubspec = File(p.join(kitRoot, 'core', 'pubspec.yaml'));
  if (!pubspec.existsSync()) return 'unknown';
  final m = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(pubspec.readAsStringSync());
  return m?.group(1) ?? 'unknown';
}

/// Sorted basenames of `skills/<name>/` subdirectories that contain a
/// SKILL.md. Sorted for deterministic lock output.
List<String> _discoverSkills(String repoRoot) {
  final d = Directory(p.join(repoRoot, 'skills'));
  if (!d.existsSync()) return const [];
  final names = <String>[];
  for (final entry in d.listSync()) {
    if (entry is Directory &&
        File(p.join(entry.path, 'SKILL.md')).existsSync()) {
      names.add(p.basename(entry.path));
    }
  }
  names.sort();
  return names;
}

/// Sorted basenames of files directly under `tools/`. Sorted for deterministic
/// lock output.
List<String> _discoverTools(String repoRoot) {
  final d = Directory(p.join(repoRoot, 'tools'));
  if (!d.existsSync()) return const [];
  final names = <String>[];
  for (final entry in d.listSync()) {
    if (entry is File) names.add(p.basename(entry.path));
  }
  names.sort();
  return names;
}

String _sha256OfFile(String path) =>
    hexEncode(sha256(File(path).readAsBytesSync()));
