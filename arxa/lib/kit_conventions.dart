// kit_conventions.dart — enforce the arxa_kit structural contract
// (Dart port of arxa_kit/tools/conventions.sh).
//
// This is the KIT contract — barrel files, publish_to, SDK pin, dependency
// topology — and is distinct from lint_conventions.dart, which carries the
// repo-wide R2/R3 checks (stripped names, absolute paths). The two ports
// cover disjoint rules from the original conventions.sh family.
//
// Fatal (fails the gate; populates [ArxaKitConventionResult.errors]):
//   - barrel lib/<pkg>.dart missing for a library kit (apps exempt)
//   - publish_to: 'none' missing from a pubspec
//   - SDK pin differing across kits
//   - a cross-kit dependency not allowed by the hub-and-spoke topology
// Warning (non-fatal):
//   - missing lib/testing.dart

import 'dart:io';

import 'package:path/path.dart' as p;

class ArxaKitConventionResult {
  final List<String> errors;
  final List<String> warnings;
  const ArxaKitConventionResult(this.errors, this.warnings);
  bool get ok => errors.isEmpty;
}

// Demo apps exempt from barrel + testing.dart checks (they are not libraries).
const _apps = <String>{'showcase_app'};

// Allowed arxa_kit_* deps per kit directory, encoding the hub-and-spoke
// topology: core is the hub; data + ui_library may reach core (ui_library also
// reaches motion, ADR 0011 — ArxaKitDrawer's ArxaKitMotionScope driver seam);
// showcase_app aggregates all. The '*' sentinel means "any kit". A directory
// absent from this map is standalone — no cross-kit deps at all.
const _allowedDeps = <String, Set<String>>{
  'data': {'arxa_kit_core'},
  'ui_library': {'arxa_kit_core', 'arxa_kit_motion'},
  'showcase_app': {'*'},
};

final _nameLine = RegExp(r'^name:\s*(\S+)');
// Indented (2-space) arxa_kit_* dependency entries only — excludes the
// kit's own column-0 `name:` line.
final _kitDep = RegExp(r'^  (arxa_kit_[a-z_]+)', multiLine: true);
final _publishNone = RegExp("publish_to:\\s*['\"]none['\"]");
final _sdkLine = RegExp(r'^\s*sdk:\s*.+$');

/// Checks the structural contract of every kit under [kitRoot].
ArxaKitConventionResult checkArxaKitConventions(String kitRoot) {
  final errors = <String>[];
  final warnings = <String>[];
  final sdkPins = <String>{};

  final rootDir = Directory(kitRoot);
  final entries =
      rootDir.existsSync() ? rootDir.listSync() : const <FileSystemEntity>[];
  for (final entry in entries) {
    if (entry is! Directory) continue;
    final dir = p.basename(entry.path);
    final pubspec = File(p.join(entry.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) continue;
    final spec = pubspec.readAsStringSync();
    final name = (_nameLine.firstMatch(spec)?.group(1)) ?? 'unknown';
    final isApp = _apps.contains(dir);

    // Barrel + testing.dart (apps exempt).
    if (!isApp) {
      if (!File(p.join(entry.path, 'lib', '$name.dart')).existsSync()) {
        errors.add('$dir missing barrel lib/$name.dart');
      }
      if (!File(p.join(entry.path, 'lib', 'testing.dart')).existsSync()) {
        warnings.add('$dir missing lib/testing.dart');
      }
    }

    // publish_to: none.
    if (!_publishNone.hasMatch(spec)) {
      errors.add("$dir missing publish_to: 'none'");
    }

    // Dependency topology — indented arxa_kit_* deps only. '*' allows all;
    // an empty set (standalone, or a directory not listed) allows none.
    final allow = _allowedDeps[dir] ?? const <String>{};
    if (!allow.contains('*')) {
      for (final m in _kitDep.allMatches(spec)) {
        final dep = m.group(1)!;
        if (!allow.contains(dep)) {
          errors.add('$dir -> $dep (allowed only: ${allow.join(' ')})');
        }
      }
    }

    // SDK pin — collected across kits, mismatch is fatal after the loop.
    final sdk = _extractSdk(spec);
    if (sdk != null) sdkPins.add(sdk);
  }

  if (sdkPins.length > 1) {
    errors.add('SDK pins differ across kits: ${sdkPins.join(', ')}');
  }

  return ArxaKitConventionResult(errors, warnings);
}

/// Extracts the `sdk:` constraint under `environment:` (mirrors the awk
/// `/environment:/{f=1} f&&/sdk:/{print;exit}`): the first `sdk:` line at or
/// after the `environment:` key. Returns it trimmed, or null if absent.
String? _extractSdk(String spec) {
  var inEnv = false;
  for (final line in spec.split('\n')) {
    if (line.trim() == 'environment:') {
      inEnv = true;
      continue;
    }
    if (inEnv && _sdkLine.hasMatch(line)) return line.trim();
  }
  return null;
}
