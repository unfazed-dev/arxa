// Native-dependency packaging gate — port of gates/native_deps/native_deps.sh
// to Dart.
//
// Asserts every plugin dependency is packaged the way the toolchain a target
// needs: today, Apple platforms migrating from CocoaPods to Swift Package
// Manager. Flutter 3.44 enables SwiftPM by default and warns that plugins
// without a Package.swift "will become an error in a future version of
// Flutter" — a warning that scrolls past unread, invisible to a generated app.
//
// Two detection strategies, both run and compared:
//   S1 (authoritative) Flutter's generated manifest at
//      <plat>/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/
//      Package.swift — the toolchain's own verdict, readable without rerunning
//      the toolchain.
//   S2 (cross-check) scan .dart_tool/package_config.json for plugins shipping
//      <plat>/*.podspec with no Package.swift anywhere under <plat>/.
//
// Severity (red must mean broken):
//   WARN (pass)  plugins lack SwiftPM but a CocoaPods fallback still builds.
//   FAIL         plugins lack SwiftPM AND no CocoaPods fallback: build broken.
//   FAIL         an unknown target was named.
//   N/A (env)    no Apple target, or no dependency metadata to read.
//
// Non-Apple targets are REPORTED as out of scope, never silently passed.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/gates.dart';
import 'package:path/path.dart' as p;

const _appleTargets = {'ios', 'macos'};
const _knownTargets = {'ios', 'macos', 'android', 'linux', 'windows', 'web'};
// Generated/build dirs pruned from the SwiftPM on-disk scan: a Package.swift
// under these says nothing about whether THIS plugin migrated.
const _pruneDirs = {'ephemeral', '.symlinks', 'Pods', 'build'};

GateResult nativeDepsGate(GateContext ctx) {
  final app = ctx.appRoot ?? ctx.repoRoot;
  final lines = <String>[];
  var fail = false;
  var warned = false;

  // Per-target on-disk/SwiftPM check — mutates fail/warned, appends lines.
  void checkTarget(String plat) {
    lines..add('')..add('--- $plat');
    final inv = _pluginsFor(app, plat);
    if (inv.isEmpty) {
      lines.add('  N/A   no dependency metadata for $plat '
          '(.dart_tool/package_config.json absent or no native plugins)');
      return;
    }
    final declared = inv.map((pl) => pl.name).toSet();
    final nDeclared = declared.length;
    final s2Missing = inv
        .where((pl) => pl.hasPod && !pl.hasSpm)
        .map((pl) => pl.name)
        .toSet();

    final s1 = _spmResolved(app, plat);
    Set<String> missing;
    if (s1 != null) {
      final s1Missing = declared.difference(s1);
      lines.add("  S1 Flutter's manifest names ${s1.length} Swift packages; "
          '$nDeclared native plugin(s) declared for $plat');
      // Where the two strategies disagree, surface both — do not guess.
      final only1 = s1Missing.difference(s2Missing);
      final only2 = s2Missing.difference(s1Missing);
      if (only1.isNotEmpty || only2.isNotEmpty) {
        warned = true;
        lines.add('  WARN  detection strategies disagree '
            '(flutter/flutter has an open defect here for git:+path: deps):');
        if (only1.isNotEmpty) {
          lines.add('          Flutter did not resolve, but a Package.swift '
              'is on disk: ${only1.join(' ')}');
        }
        if (only2.isNotEmpty) {
          lines.add('          Flutter resolved, but no Package.swift found '
              'on disk:   ${only2.join(' ')}');
        }
        ctx.sarif.result(
            'native_deps',
            'warning',
            '$app/$plat',
            'SwiftPM detection disagreement on $plat: '
            'only-S1=[${only1.join(' ')}] only-S2=[${only2.join(' ')}]');
      }
      missing = s1Missing;
    } else {
      lines.add('  S1 unavailable (no generated Swift package manifest — '
          'never built for $plat, or SwiftPM off)');
      lines.add('     falling back to the on-disk scan alone');
      missing = s2Missing;
    }

    missing = missing.where((s) => s.isNotEmpty).toSet();
    if (missing.isEmpty) {
      lines.add(
          '  ok    all $nDeclared native plugins support Swift Package Manager');
      return;
    }
    final sortedMissing = missing.toList()..sort();
    final podfile = File('$app/$plat/Podfile');
    if (podfile.existsSync()) {
      warned = true;
      lines.add('  WARN  ${sortedMissing.length} plugin(s) without '
          'Swift Package Manager support:');
      for (final m in sortedMissing) {
        lines.add('          - $m');
      }
      lines.add('        CocoaPods integration is present, so $plat still '
          'builds today.');
      lines.add('        Flutter warns this becomes an error in a future '
          'release. Remedy:');
      lines.add('        vendor the plugin and add a Package.swift — '
          'gates/native_deps/README.md.');
      for (final m in sortedMissing) {
        ctx.sarif.result('native_deps', 'warning', podfile.path,
            '$m has no Swift Package Manager support for $plat; '
            'building via the CocoaPods fallback');
      }
      return;
    }
    fail = true;
    lines.add('  FAIL  ${sortedMissing.length} plugin(s) without '
        'Swift Package Manager support');
    lines.add('        and NO CocoaPods integration at ${podfile.path} '
        'to fall back to:');
    for (final m in sortedMissing) {
      lines.add('          - $m');
    }
    for (final m in sortedMissing) {
      ctx.sarif.result('native_deps', 'error', '$app/$plat',
          '$m has no Swift Package Manager support for $plat and no '
          'CocoaPods fallback: $plat cannot build');
    }
  }

  // ---- targets ----
  final targets = ctx.targets.where((t) => t.isNotEmpty).toList();
  if (targets.isEmpty) {
    return GateResult(
      passed: false,
      exitCode: envExit,
      summary: 'native_deps: N/A — no targets declared',
      details: const ['native_deps: N/A — no targets declared'],
    );
  }

  lines.add('native_deps: over $app');
  lines.add('  targets: ${targets.join(' ')}');

  // ---- unknown targets are a state error, never skipped quietly ----
  final bad = targets.where((t) => !_knownTargets.contains(t)).toList();
  if (bad.isNotEmpty) {
    final badStr = bad.map((t) => ' $t').join();
    lines.add(
        '  FAIL  unknown target(s):$badStr (known: ${_knownTargets.join(' ')})');
    ctx.sarif.result('native_deps', 'error', app, 'unknown target(s):$badStr');
    return GateResult.fail('native_deps: FAIL', lines);
  }

  // ---- SwiftPM switched off? say so, never fake a clean bill of health ----
  final pubspec = File('$app/pubspec.yaml');
  if (pubspec.existsSync() &&
      RegExp(r'^\s*enable-swift-package-manager:\s*false', multiLine: true)
          .hasMatch(pubspec.readAsStringSync())) {
    warned = true;
    lines.add('  WARN  SwiftPM is disabled in pubspec.yaml (flutter: config: '
        'enable-swift-package-manager: false).');
    lines.add('        Apple targets are being built through CocoaPods by '
        'choice; this gate cannot vouch for them.');
    ctx.sarif.result('native_deps', 'warning', '$app/pubspec.yaml',
        'SwiftPM explicitly disabled; Apple native packaging is unverified '
        'by this gate');
  }

  // ---- per-target checks ----
  var appleSeen = false;
  final nonApple = <String>[];
  for (final t in targets) {
    if (_appleTargets.contains(t)) {
      appleSeen = true;
      checkTarget(t);
    } else {
      nonApple.add(t);
    }
  }

  // Report — never silently pass — the targets this gate has no assertion for.
  if (nonApple.isNotEmpty) {
    lines.add('');
    lines.add('  note  out of scope for this gate:'
        '${nonApple.map((t) => ' $t').join()}');
    lines.add('        Swift Package Manager is Apple-only; Gradle (android) '
        'and CMake');
    lines.add('        (linux/windows) own native packaging there, and '
        'neither has a');
    lines.add('        live migration in this repo. Not checked, and not '
        'claimed.');
  }

  if (!appleSeen) {
    lines.add('');
    final sum = 'native_deps: N/A — no Apple target among:'
        '${targets.map((t) => ' $t').join()}';
    lines.add(sum);
    return GateResult(
      passed: false,
      exitCode: envExit,
      summary: sum,
      details: lines,
    );
  }

  lines.add('');
  if (fail) {
    lines.add('native_deps: FAIL');
    return GateResult.fail('native_deps: FAIL', lines);
  }
  if (warned) {
    lines.add('native_deps: pass (with warnings)');
    return GateResult.ok('native_deps: pass (with warnings)', lines);
  }
  lines.add('native_deps: pass');
  return GateResult.ok('native_deps: pass', lines);
}

// ── S2 input: plugin inventory ─────────────────────────────────────

class _PluginInv {
  final String name;
  final bool hasPod;
  final bool hasSpm;
  const _PluginInv(this.name, this.hasPod, this.hasSpm);
}

/// Every dependency carrying native sources for [plat] (or the federated
/// `darwin/` directory). Reads `<app>/.dart_tool/package_config.json`; the host
/// app is excluded (its `<plat>/` holds the Runner and Flutter's generated
/// package, so without this it would count itself as a plugin).
List<_PluginInv> _pluginsFor(String app, String plat) {
  final cfgPath = '$app/.dart_tool/package_config.json';
  final cfg = File(cfgPath);
  if (!cfg.existsSync()) return const [];
  final base = p.dirname(p.absolute(cfgPath));
  final appReal = _realpath(app);

  Map<String, dynamic> doc;
  try {
    doc = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return const [];
  }
  final packages = doc['packages'];
  if (packages is! List) return const [];

  final out = <_PluginInv>[];
  for (final pkg in packages) {
    if (pkg is! Map) continue;
    final name = (pkg['name'] ?? '?').toString();
    final rootUri = (pkg['rootUri'] ?? '').toString();
    final root = rootUri.startsWith('file://')
        ? rootUri.substring(7)
        : p.normalize(p.join(base, rootUri));
    if (_realpath(root) == appReal) continue; // host app is not its own dep

    // Only stop once a directory actually yields native sources. A plugin can
    // ship an EMPTY <plat>/ alongside a populated federated darwin/ — breaking
    // on mere directory existence would hide it from the missing-SwiftPM set.
    for (final d in [plat, 'darwin']) {
      final pdir = p.join(root, d);
      if (!Directory(pdir).existsSync()) continue;
      final hasPod = _hasPodspec(pdir);
      final hasSpm = _hasPackageSwift(pdir);
      if (hasPod || hasSpm) {
        out.add(_PluginInv(name, hasPod, hasSpm));
        break;
      }
    }
  }
  return out;
}

/// `.podspec` directly in [dir] (os.listdir, not recursive).
bool _hasPodspec(String dir) {
  try {
    for (final entry in Directory(dir).listSync()) {
      if (entry.uri.pathSegments.last.endsWith('.podspec')) return true;
    }
  } catch (_) {}
  return false;
}

/// `Package.swift` anywhere under [dir], pruning generated/build dirs
/// (ephemeral, .symlinks, Pods, build) — a Package.swift under those is
/// Flutter's generated output, not a sign THIS package migrated.
bool _hasPackageSwift(String dir) {
  bool walk(String d) {
    try {
      for (final entry in Directory(d).listSync()) {
        if (entry is File) {
          if (entry.uri.pathSegments.last == 'Package.swift') return true;
        } else if (entry is Directory) {
          if (_pruneDirs.contains(entry.uri.pathSegments.last)) continue;
          if (walk(entry.path)) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  return walk(dir);
}

// ── S1: Flutter's persisted verdict ────────────────────────────────

/// Names Flutter resolved as Swift packages, or null when no generated
/// manifest exists (never built for [plat], or SwiftPM off). FlutterFramework
/// is Flutter's own SPM product, not a dependency to migrate — excluded.
Set<String>? _spmResolved(String app, String plat) {
  final gen = File('$app/$plat/Flutter/ephemeral/Packages/'
      'FlutterGeneratedPluginSwiftPackage/Package.swift');
  if (!gen.existsSync()) return null;
  final names = <String>{};
  final re = RegExp(r'\.package\(name:\s*"([^"]*)"');
  for (final line in gen.readAsLinesSync()) {
    final m = re.firstMatch(line);
    if (m != null) names.add(m.group(1)!);
  }
  names.remove('FlutterFramework');
  return names;
}

/// os.path.realpath equivalent: resolve symlinks, fall back to lexical
/// normalization when the path does not exist (realpath never throws).
String _realpath(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } catch (_) {
    return p.normalize(p.absolute(path));
  }
}
