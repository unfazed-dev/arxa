// emit_structure — Dart port of tools/emit_structure/emit_structure.py (385 lines).
//
// Derives <design-root>/structure.json from the authored layer:
//   - models/screens_model/registry.json (id/shell/comp/surface per screen)
//   - app.routes.js (shellRoots map)
//   - ui/views/**/*_viewmodel.js (surfaceId + deps)
//
// Pure data: no browser, no render. Join is on exported surfaceId, not filename.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const banner = 'appbox/structure@1';

// export const surfaceId = 'stage.shell'
final _surfaceIdRe = RegExp("export\\s+const\\s+surfaceId\\s*=\\s*['\"]([^'\"]+)['\"]");

// export const shellRoots = { proj: '/', stage: '/' }
final _shellRootsRe = RegExp("export\\s+const\\s+shellRoots\\s*=\\s*\\{([^}]*)\\}", dotAll: true);
final _pairRe = RegExp("([A-Za-z_][\\w-]*)\\s*:\\s*['\"]([^'\"]+)['\"]");

// from '.../services/facades/...' or '.../services/repositories/...'
final _depRe = RegExp("from\\s+['\"]([^'\"]*(?:services/facades|services/repositories)/[^'\"]+)['\"]");

/// Build the structure dict from the authored layer at [designRoot].
/// Returns null on hard failure (with error printed to stderr).
Map<String, dynamic>? buildStructure(String designRoot) {
  final root = Directory(designRoot);

  // ---- registry ----
  final regFile = File('${root.path}/models/screens_model/registry.json');
  if (!regFile.existsSync()) {
    stderr.writeln('FAIL: no registry at models/screens_model/registry.json '
        '— not a design root, or the producer has no authored layer');
    return null;
  }
  List registry;
  try {
    registry = jsonDecode(regFile.readAsStringSync()) as List;
  } catch (e) {
    stderr.writeln('FAIL: registry.json does not parse as JSON — $e');
    return null;
  }
  if (registry.isEmpty) {
    stderr.writeln('FAIL: registry.json must be a non-empty list of screen entries');
    return null;
  }

  // ---- shellRoots from app.routes.js ----
  final routesFile = File('${root.path}/app.routes.js');
  if (!routesFile.existsSync()) {
    stderr.writeln('FAIL: no app.routes.js — cannot read the shellRoots map');
    return null;
  }
  final routesSrc = routesFile.readAsStringSync();
  final shellRootsMatch = _shellRootsRe.firstMatch(routesSrc);
  if (shellRootsMatch == null) {
    stderr.writeln('FAIL: app.routes.js exports no `shellRoots` map');
    return null;
  }
  final shellRoots = {
    for (final m in _pairRe.allMatches(shellRootsMatch.group(1)!))
      m.group(1)!: m.group(2)!,
  };
  if (shellRoots.isEmpty) {
    stderr.writeln('FAIL: shellRoots is empty — every shell needs a landing route');
    return null;
  }

  // ---- viewmodels: {surfaceId: {path, deps}} ----
  final viewmodels = <String, Map<String, dynamic>>{};
  final vmDir = Directory('${root.path}/ui/views');
  if (vmDir.existsSync()) {
    final vmFiles = vmDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_viewmodel.js'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final f in vmFiles) {
      final rel = f.path.substring(root.path.length + 1);
      final src = f.readAsStringSync();
      final sidMatch = _surfaceIdRe.firstMatch(src);
      if (sidMatch == null) {
        stderr.writeln('FAIL: $rel exports no surfaceId — the registry join needs one');
        return null;
      }
      final sid = sidMatch.group(1)!;
      if (viewmodels.containsKey(sid)) {
        stderr.writeln("FAIL: surfaceId '$sid' declared twice "
            "(${viewmodels[sid]!['path']} and $rel)");
        return null;
      }
      final deps = <String>{};
      for (final dm in _depRe.allMatches(src)) {
        final importPath = dm.group(1)!;
        // Resolve relative to the viewmodel's directory, then normalize to design-root-relative.
        // String-only path math — the referenced files need not exist (matches Python's os.path.normpath).
        final vmDirPath = f.parent.path;
        final joined = p.join(vmDirPath, importPath);
        final normalized = p.normalize(joined);
        final depRel = p.relative(normalized, from: root.path);
        deps.add(depRel.replaceAll('\\', '/'));
      }
      viewmodels[sid] = {'path': rel, 'deps': deps.toList()..sort()};
    }
  }

  // ---- shell-group → shell-dir table (derived from surfaces) ----
  final groupToDir = <String, String>{};
  for (final e in registry) {
    final entry = e as Map<String, dynamic>;
    final surface = entry['surface'] as String?;
    if (surface != null && surface.isNotEmpty) {
      final sd = shellDir(surface);
      if (sd == null) {
        stderr.writeln("FAIL: screen '${entry['id']}' has surface '$surface' "
            "with no <shell>_shell_ prefix");
        return null;
      }
      final group = entry['shell'] as String?;
      if (group != null && groupToDir.containsKey(group) && groupToDir[group] != sd) {
        stderr.writeln("FAIL: shell group '$group' maps to two shell dirs "
            "(${groupToDir[group]} and $sd) — group->dir must be pure");
        return null;
      }
      if (group != null) {
        groupToDir.putIfAbsent(group, () => sd);
      }
    }
  }

  // ---- assemble screens ----
  final screens = <Map<String, dynamic>>[];
  for (final e in registry) {
    final entry = e as Map<String, dynamic>;
    final sid = entry['id'] as String?;
    final surface = entry['surface'] as String?;
    if (surface != null && surface.isNotEmpty) {
      final vm = viewmodels[sid];
      if (vm == null) {
        stderr.writeln("FAIL: screen '$sid' declares a surface but no viewmodel "
            "exports surfaceId '$sid'");
        return null;
      }
      screens.add({
        'id': sid,
        'shell': entry['shell'],
        'comp': entry['comp'],
        'shellDir': shellDir(surface),
        'surface': surface,
        'viewmodel': vm['path'],
        'deps': vm['deps'],
      });
    } else {
      final group = entry['shell'] as String?;
      screens.add({
        'id': sid,
        'shell': group,
        'comp': entry['comp'],
        'shellDir': groupToDir[group],
        'surface': null,
        'viewmodel': null,
        'deps': <String>[],
      });
    }
  }

  // ---- orphan viewmodels ----
  final claimed = screens.where((s) => s['surface'] != null).map((s) => s['id'] as String).toSet();
  final orphans = viewmodels.keys.where((s) => !claimed.contains(s)).toList()..sort();
  if (orphans.isNotEmpty) {
    final one = orphans.first;
    stderr.writeln("FAIL: viewmodel ${viewmodels[one]!['path']} exports surfaceId '$one' "
        "but the registry declares no such screen");
    return null;
  }

  return {
    r'$schema': banner,
    'registry': 'models/screens_model/registry.json',
    'shellRoots': shellRoots,
    'screens': screens,
  };
}

/// Derive shell dir from surface: "stage_shell_projects_home_view" → "stage_shell".
String? shellDir(String surface) {
  final idx = surface.indexOf('_shell_');
  if (idx < 0) return null;
  return '${surface.substring(0, idx)}_shell';
}

/// Serialize structure data as indented JSON + newline (matches Python json.dumps(indent=2)).
String _serialize(Map<String, dynamic> data) {
  return const JsonEncoder.withIndent('  ').convert(data) + '\n';
}

/// Emit structure.json. Returns 0 on success, 1 on failure.
/// When [check] is true, compares in-memory without writing.
int emitStructure(String designRoot, {bool check = false}) {
  final data = buildStructure(designRoot);
  if (data == null) return 1;

  final text = _serialize(data);
  final outFile = File('$designRoot/structure.json');

  if (check) {
    final have = outFile.existsSync() ? outFile.readAsStringSync() : '';
    if (have != text) {
      stderr.writeln('FAIL: emit_structure --check: $outFile drifted from the authored '
          'layer (re-run emit_structure)');
      return 1;
    }
    print('in-sync ${outFile.path}');
    return 0;
  }

  if (outFile.existsSync() && outFile.readAsStringSync() == text) {
    print('unchanged ${outFile.path} (write-on-diff: content identical)');
  } else {
    outFile.writeAsStringSync(text);
    print('wrote ${outFile.path}');
  }
  final screens = data['screens'] as List;
  final n = screens.length;
  final c = screens.where((s) => (s as Map)['surface'] != null).length;
  final excl = screens.where((s) => (s as Map)['surface'] == null)
      .map((s) => (s as Map)['id'] as String).toList();
  print('  $n screens, $c with a surface, ${n - c} excluded (surface:null)');
  if (excl.isNotEmpty) {
    print('  exclusions: ${excl.join(', ')}');
  }
  return 0;
}
