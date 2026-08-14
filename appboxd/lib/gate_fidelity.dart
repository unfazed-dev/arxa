// Fidelity gate — enforces the app fidelity mode spec
// (docs/plans/fidelity-mode-config.md, QF-1..QF-4).
//
// Four checks, all collected (no short-circuit — a gate names every failure):
//   1. Map legality: `fidelity` values in config/appbox.config.json must be
//      flutter|mix|native, keyed by known derivation targets; `mix`/`native`
//      are illegal where no native tier exists (today: everything except
//      ios/android — flipping that is a data edit to [nativeTierTargets],
//      mirroring the spec's legality table).
//   2. iOS floor: `native` on ios forces the deployment floor to iOS 26
//      (Liquid Glass gate is `iosMajor >= 26`). If the ios project exists it
//      must carry IPHONEOS_DEPLOYMENT_TARGET >= 26 everywhere; project
//      *presence* stays the coverage gate's job.
//   3. Const-drift: the kit reads APPBOX_FIDELITY via String.fromEnvironment
//      with defaultValue `mix`. Every emitted `APPBOX_FIDELITY=<v>` under the
//      app root must name a declared mode, and a non-mix declaration with NO
//      emitted define anywhere is drift-by-omission (the const silently folds
//      to mix). Until the scaffolder emitter standardizes the launch surface,
//      occurrence→target binding is unknowable, so non-uniform maps check
//      membership in the declared mode set; uniform maps check equality.
//   4. preferFlutterTier lint: when any target declares `native`, a per-widget
//      `preferFlutterTier: true` in app Dart code contradicts the declared
//      mode and is an error (spec §2; QF-2).
//
// Sanctioned exception (QF-4): `flutter` mode lawfully ships WITHOUT native
// tier wiring — this gate must never demand warm-up/chrome-gate/slicer
// presence for a flutter target. It says so in its output rather than staying
// silent, so a later reviewer knows the absence was recognized, not missed.
// Refs: docs/liquid-glass-allowlist.md "Sanctioned exception — app fidelity
// mode"; docs/m3e-law.md rule 5; VOCABULARY.md "App fidelity mode".

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gates.dart';

const _modes = {'flutter', 'mix', 'native'};

/// Targets that have a native tier today (liquid-glass law: iOS Liquid Glass;
/// m3e-law: Android M3E). Desktop/web native tiers, if ever added, flip the
/// spec's §1 legality table — that is this data edit plus the spec edit.
const nativeTierTargets = {'ios', 'android'};

const _skipDirs = {
  '.git', '.dart_tool', 'build', 'node_modules', 'Pods', '.symlinks',
  'DerivedData', '.claude',
};

GateResult fidelityGate(GateContext ctx) {
  final repoRoot = ctx.repoRoot;
  final appRoot = ctx.appRoot ?? repoRoot;
  final failures = <String>[];
  final notes = <String>[];

  // --- Load config fidelity map -------------------------------------------
  final configFile = File(ctx.configFile);
  Map<String, dynamic> config = const {};
  if (configFile.existsSync()) {
    try {
      config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      return GateResult.env('fidelity: unparseable ${ctx.configFile}: ${e.message}');
    }
  }
  final rawMap = config['fidelity'];
  if (rawMap == null) {
    // Spec default: absent map == all targets `mix`. Nothing to drift against
    // (mix is also the const default), nothing to lint. Lawful.
    return GateResult.ok(
        'fidelity: no map declared — all targets default `mix` (spec §1)');
  }
  if (rawMap is! Map) {
    return GateResult.fail(
        'fidelity: config `fidelity` must be an object of target→mode',
        ['got ${rawMap.runtimeType}: $rawMap']);
  }
  final map = <String, String>{};
  rawMap.forEach((k, v) => map['$k'] = '$v');

  // --- Known-target universe from the derivation table --------------------
  final derivationFile =
      File('$repoRoot/pipeline/state/targets.derivation.json');
  Set<String> knownTargets = const {};
  if (derivationFile.existsSync()) {
    try {
      final d = jsonDecode(derivationFile.readAsStringSync());
      final t = (d as Map<String, dynamic>)['targets'];
      if (t is Map) knownTargets = t.keys.map((k) => '$k').toSet();
    } on FormatException {
      // Derivation health is the coverage gate's finding; don't double-report.
    }
  }

  // --- 1. Map legality ----------------------------------------------------
  map.forEach((target, mode) {
    if (knownTargets.isNotEmpty && !knownTargets.contains(target)) {
      failures.add('fidelity.unknown_target: `$target` is not in '
          'targets.derivation.json (${knownTargets.toList()..sort()})');
    }
    if (!_modes.contains(mode)) {
      failures.add('fidelity.bad_mode: `$target: $mode` — mode must be '
          'flutter|mix|native (spec §1)');
    } else if (mode != 'flutter' && !nativeTierTargets.contains(target)) {
      failures.add('fidelity.illegal_mode: `$target: $mode` — `mix`/`native` '
          'are illegal where no native tier exists (spec §1 legality table); '
          'only $nativeTierTargets have one today');
    }
  });

  // --- 2. iOS deployment floor for `native` -------------------------------
  if (map['ios'] == 'native') {
    final iosDir = Directory('$appRoot/ios');
    if (!iosDir.existsSync()) {
      notes.add('fidelity: ios declared `native` but $appRoot/ios is absent — '
          'floor check deferred (project presence is the coverage gate\'s job)');
    } else {
      final pbxproj = File('$appRoot/ios/Runner.xcodeproj/project.pbxproj');
      if (!pbxproj.existsSync()) {
        failures.add('fidelity.ios_floor: ios is `native` but '
            'ios/Runner.xcodeproj/project.pbxproj is missing — cannot prove '
            'the iOS 26 floor the scaffolder must write (spec §1)');
      } else {
        final floors = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*([\d.]+)')
            .allMatches(pbxproj.readAsStringSync())
            .map((m) => m.group(1)!)
            .toSet();
        final low = floors
            .where((f) => (double.tryParse(f) ?? 0) < 26)
            .toList()
          ..sort();
        if (floors.isEmpty) {
          failures.add('fidelity.ios_floor: ios is `native` but no '
              'IPHONEOS_DEPLOYMENT_TARGET found in project.pbxproj');
        } else if (low.isNotEmpty) {
          failures.add('fidelity.ios_floor: ios is `native` — Liquid Glass '
              'gate is iosMajor >= 26, but project.pbxproj declares '
              'IPHONEOS_DEPLOYMENT_TARGET $low');
        }
      }
    }
  }

  // --- 3. Const-drift: emitted defines vs declared modes ------------------
  final declared = map.values.toSet();
  final defineRe = RegExp(r'APPBOX_FIDELITY=([A-Za-z_]+)');
  final defineHits = <String>[]; // "path:line value"
  final foundValues = <String>{};
  for (final f in _walk(appRoot, exts: const {
    '.sh', '.json', '.yaml', '.yml', '.xcconfig', '.gradle', '.kts',
    '.mk', '.toml',
  }, alsoNames: const {'Makefile'})) {
    final lines = _safeLines(f);
    for (var i = 0; i < lines.length; i++) {
      for (final m in defineRe.allMatches(lines[i])) {
        final v = m.group(1)!;
        foundValues.add(v);
        defineHits.add('${_rel(f.path, appRoot)}:${i + 1} $v');
      }
    }
  }
  for (final v in foundValues) {
    final legal = declared.isEmpty ? _modes : declared;
    if (!legal.contains(v)) {
      failures.add('fidelity.define_drift: emitted APPBOX_FIDELITY=$v matches '
          'no declared mode ${declared.toList()..sort()} — '
          '${defineHits.where((h) => h.endsWith(' $v')).join('; ')}');
    }
  }
  final nonMix = map.entries.where((e) => e.value != 'mix').toList();
  if (nonMix.isNotEmpty && defineHits.isEmpty) {
    failures.add('fidelity.define_drift: '
        '${nonMix.map((e) => '${e.key}: ${e.value}').join(', ')} declared but '
        'no APPBOX_FIDELITY= define emitted anywhere under $appRoot — the kit '
        'const silently folds to its `mix` default (spec §2)');
  }

  // --- 4. preferFlutterTier lint under `native` ---------------------------
  final nativeTargets =
      map.entries.where((e) => e.value == 'native').map((e) => e.key).toList()
        ..sort();
  if (nativeTargets.isNotEmpty) {
    final pftRe = RegExp(r'preferFlutterTier\s*:\s*true');
    final hits = <String>[];
    for (final f in _walk('$appRoot/lib', exts: const {'.dart'})) {
      final lines = _safeLines(f);
      for (var i = 0; i < lines.length; i++) {
        if (pftRe.hasMatch(lines[i])) {
          hits.add('${_rel(f.path, appRoot)}:${i + 1}');
        }
      }
    }
    if (hits.isNotEmpty) {
      failures.add('fidelity.prefer_flutter_in_native: mode is `native` for '
          '$nativeTargets but per-widget `preferFlutterTier: true` contradicts '
          'the declared mode (spec §2): ${hits.join(', ')}');
    }
  }

  // --- Sanctioned exception (QF-4): name it, never police it --------------
  for (final e in map.entries.where((e) => e.value == 'flutter')) {
    notes.add('fidelity: `${e.key}: flutter` — native-tier wiring absence is '
        'lawful under the sanctioned exception (QF-4; liquid-glass-allowlist.md '
        '"Sanctioned exception — app fidelity mode"; m3e-law.md rule 5)');
  }

  if (failures.isNotEmpty) {
    return GateResult.fail(
        'fidelity: ${failures.length} violation(s)', [...failures, ...notes]);
  }
  final desc = (map.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)))
      .map((e) => '${e.key}: ${e.value}')
      .join(', ');
  return GateResult.ok('fidelity: map lawful ($desc)', notes);
}

Iterable<File> _walk(String root,
    {required Set<String> exts, Set<String> alsoNames = const {}}) sync* {
  final dir = Directory(root);
  if (!dir.existsSync()) return;
  final entries = dir.listSync(recursive: true, followLinks: false);
  for (final e in entries) {
    if (e is! File) continue;
    final parts = e.path.split(Platform.pathSeparator);
    if (parts.any(_skipDirs.contains)) continue;
    final name = parts.last;
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 ? name.substring(dot) : '';
    if (exts.contains(ext) || alsoNames.contains(name)) yield e;
  }
}

List<String> _safeLines(File f) {
  try {
    return f.readAsLinesSync();
  } on FileSystemException {
    return const [];
  } on FormatException {
    return const []; // binary masquerading under a text extension
  }
}

String _rel(String path, String root) =>
    path.startsWith('$root/') ? path.substring(root.length + 1) : path;
