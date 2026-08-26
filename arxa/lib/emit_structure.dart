// emit_structure — Dart port of tools/emit_structure/emit_structure.py (385 lines).
//
// Derives <design-root>/structure.json from the authored layer:
//   - models/screens_model/registry.json (id/shell/comp/surface per screen,
//     plus an optional `kits` list of kit dir names, validated against
//     config/kit-registry.json)
//   - models/screens_model/flows.json (OPTIONAL — the triad's flows lens:
//     journeys as {from,to,trigger} edges over registry ids; every endpoint
//     must resolve to a registry entry, absent = no flows lens)
//   - app.routes.js (shellRoots map)
//   - ui/views/**/*_viewmodel.js (surfaceId + deps)
//
// Pure data: no browser, no render. Join is on exported surfaceId, not filename.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'intake.dart' show feedbackKinds, surfaceStates;
import 'scaffold.dart' show findRepoRoot;

/// The document's `$schema` stamp (emitted at `:462`). Provenance and version
/// only — NO runtime consumer validates it on the way back IN, so bumping it
/// rejects no old document and gates no new one. The literal is pinned by
/// `test/scaffold_test.dart`; that test, not a reader, is what makes a silent
/// bump fail. Give it teeth only by adding a reader that asserts on it.
const banner = 'arxa/structure@2';

// ── structure@2 ───────────────────────────────────────────────────────────
// @2 adds three OPTIONAL top-level keys, each emitted only when its authored
// source exists (same optionality contract as `flows`, so a design root that
// authors none of them still emits a valid document):
//
//   theme    — models/theme.json, the accent-swatch SSOT: 5 swatches x 5
//              semantic roles. Two colors are AUTHORED per mode (accent, soft)
//              plus on-accent; the other three roles (accent-surface,
//              accent-text, accent-muted) are DERIVED by color-mix from the
//              `roles` mix percentages. We pass the mixes through rather than
//              resolving them: resolution needs oklab against a --bg/--tx the
//              design root owns per mode, and baking one number here would
//              fork the SSOT that services/theme_tokens.js already owns.
//   fonts    — models/fonts.json when present (declared families, never the
//              assets/fonts/ filenames: subset+weight names like
//              `lexend-deca-500-latin-ext` are build detail, not contract).
//   widgets  — design/surfaces/**.html, the authored surface partials. Widget
//              identity is (file, kind, occurrence index) — the same identity
//              services/repositories/widget_repository.js resolves against, so
//              a designer edit and a pipeline read name the same element.
//
// Widget note: `widgets` is present only for design roots that ARE live-read
// projects (~/.arxa/projects/<name>, which carry design/surfaces/). The
// studio's own root authors no surface partials, so its structure.json has no
// `widgets` key — absent, not empty.

// export const surfaceId = 'stage.shell'
final _surfaceIdRe = RegExp("export\\s+const\\s+surfaceId\\s*=\\s*['\"]([^'\"]+)['\"]");

/// Shell viewmodels (v2 grammar) export shellId only — chrome frames, not
/// joinable surfaces. The sweep skips them instead of failing the join.
final _shellIdRe = RegExp("export\\s+const\\s+shellId\\s*=");

// export const shellRoots = { proj: '/', stage: '/' }
final _shellRootsRe = RegExp("export\\s+const\\s+shellRoots\\s*=\\s*\\{([^}]*)\\}", dotAll: true);
final _pairRe = RegExp("([A-Za-z_][\\w-]*)\\s*:\\s*['\"]([^'\"]+)['\"]");

// from '.../services/facades/...' or '.../services/repositories/...'
final _depRe = RegExp("from\\s+['\"]([^'\"]*(?:services/facades|services/repositories)/[^'\"]+)['\"]");

/// Build the structure dict from the authored layer at [designRoot].
/// Returns null on hard failure (with error printed to stderr).
Map<String, dynamic>? buildStructure(String designRoot) {
  final root = Directory(designRoot);

  // ---- registry (v1 List of screens, or v2 Map projection) ----
  final regFile = File('${root.path}/models/screens_model/registry.json');
  if (!regFile.existsSync()) {
    stderr.writeln('FAIL: no registry at models/screens_model/registry.json '
        '— not a design root, or the producer has no authored layer');
    return null;
  }
  List registry;
  try {
    final parsed = jsonDecode(regFile.readAsStringSync());
    if (parsed is List) {
      registry = parsed;
    } else if (parsed is Map<String, dynamic>) {
      // v2: models/screens_model/registry.json is the DERIVED projection
      // (stages/shells); the screen-level SSOT is the authoring surface at
      // intake/registry.json (entries[]). Read it and project to the v1
      // screen shape: comp is derived PascalCase from the surface name.
      final ssot = File('${root.path}/intake/registry.json');
      if (!ssot.existsSync()) {
        stderr.writeln('FAIL: v2 Map projection but no authoring SSOT at '
            'intake/registry.json — the projection is derived, not authored');
        return null;
      }
      final authored = jsonDecode(ssot.readAsStringSync());
      final entries = authored is Map<String, dynamic> ? authored['entries'] : null;
      if (entries is! List || entries.isEmpty) {
        stderr.writeln('FAIL: intake/registry.json has no entries[] — nothing to emit');
        return null;
      }
      registry = [
        for (final e in entries)
          if (e is Map<String, dynamic>)
            {
              ...e,
              'comp': _compOf(e['surface'] as String?),
              // v2 names surfaces <app>_<short>_view under ui/views/<shell>/ —
              // the shell id IS the dir, so no _shell_ slicing applies.
              '_shellDir': e['shell'],
            }
          else
            e,
      ];
    } else {
      stderr.writeln('FAIL: registry.json is neither a list (v1) nor an object (v2)');
      return null;
    }
  } catch (e) {
    stderr.writeln('FAIL: registry.json does not parse as JSON — $e');
    return null;
  }
  if (registry.isEmpty) {
    stderr.writeln('FAIL: registry.json must be a non-empty list of screen entries');
    return null;
  }

  // ---- the app-shell roster law ----
  final missingRoster = missingAppShellRoster(registry);
  if (missingRoster.isNotEmpty) {
    stderr.writeln('FAIL: registry leaves app-shell roster roles unfilled: '
        '${missingRoster.join(', ')} — every frozen design fills the splash, '
        'startup and unknown roles (plus access when any surface carries '
        'requiresAuth), by literal app.<role> id or a per-entry role field');
    return null;
  }

  // ---- flows (optional): the triad's flows lens, edges over registry ids ----
  List? flows;
  // v1 keeps flows beside the registry; v2 keeps them with the authoring
  // SSOT (intake/flows.json). Both checked — a design may hold either.
  final flowsFile = File('${root.path}/models/screens_model/flows.json');
  final flowsFileV2 = File('${root.path}/intake/flows.json');
  if (flowsFile.existsSync() || flowsFileV2.existsSync()) {
    final source = flowsFile.existsSync() ? flowsFile : flowsFileV2;
    try {
      final parsed = jsonDecode(source.readAsStringSync());
      if (parsed is List) {
        flows = parsed;
      } else if (parsed is Map<String, dynamic> && parsed['edges'] is List) {
        // v2: a flat {edges:[...]} over registry ids — one implicit journey.
        flows = [
          {'id': 'studio', 'edges': parsed['edges']},
        ];
      } else {
        stderr.writeln('FAIL: flows.json is neither a journeys list (v1) '
            'nor a flat edges object (v2)');
        return null;
      }
    } catch (e) {
      stderr.writeln('FAIL: flows.json does not parse as JSON — $e');
      return null;
    }
    final ids = {for (final e in registry) (e as Map)['id']};
    for (final f in flows) {
      if (f is! Map) {
        stderr.writeln('FAIL: flows.json entries must be objects');
        return null;
      }
      final edges = f['edges'];
      if (edges is! List) {
        stderr.writeln("FAIL: flow '${f['id']}' has no edges list");
        return null;
      }
      for (final edge in edges) {
        if (edge is! Map || edge['trigger'] is! String) {
          stderr.writeln("FAIL: flow '${f['id']}' has an edge without a trigger");
          return null;
        }
        // `element` is OPTIONAL and names the thing a user touches to take this
        // edge — it joins to a `data-el` value on the surface (e.g.
        // "button:Continue"). It exists because `trigger` is prose written for
        // a human reader: "continue" happens to name an element, "App launch"
        // and "Add to bag, then review bag" do not. The flow-walk island uses
        // element when present and fuzzy-matches trigger when it is absent, so
        // omitting it degrades matching rather than breaking the flow.
        // Validated for TYPE only: whether the value resolves to a real
        // data-el lives in the rendered surface, which structure.json cannot
        // see from here.
        if (edge.containsKey('element') &&
            edge['element'] != null &&
            edge['element'] is! String) {
          stderr.writeln("FAIL: flow '${f['id']}' edge "
              "'${edge['from']}' -> '${edge['to']}' has a non-string element "
              '(expected a data-el value like "button:Continue")');
          return null;
        }
        // `feedback` is OPTIONAL and names the toast this TRANSITION fires —
        // `{kind, text}` with a closed `kind`. It lives on the edge and not in
        // the screen's `states` because a toast is a consequence of moving,
        // not a way a screen can look (kit/ui_library vs kit/state).
        if (edge.containsKey('feedback') && edge['feedback'] != null) {
          final fb = edge['feedback'];
          if (fb is! Map) {
            stderr.writeln("FAIL: flow '${f['id']}' edge '${edge['from']}' -> "
                "'${edge['to']}' has a non-object feedback (expected "
                '{kind, text})');
            return null;
          }
          if (!feedbackKinds.contains(fb['kind'])) {
            stderr.writeln("FAIL: flow '${f['id']}' edge '${edge['from']}' -> "
                "'${edge['to']}' has feedback.kind '${fb['kind']}' — not one "
                'of $feedbackKinds');
            return null;
          }
          final text = fb['text'];
          if (text is! String || text.trim().isEmpty) {
            stderr.writeln("FAIL: flow '${f['id']}' edge '${edge['from']}' -> "
                "'${edge['to']}' has an empty feedback.text (the words the "
                'user actually reads)');
            return null;
          }
        }
        for (final k in const ['from', 'to']) {
          final ep = edge[k];
          if (!ids.contains(ep)) {
            stderr.writeln("FAIL: flow '${f['id']}' edge $k '$ep' is not a "
                'registry id — flows name screens the registry declares');
            return null;
          }
        }
      }
    }
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
        if (_shellIdRe.hasMatch(src)) {
          // v2 shell viewmodels declare shellId only — they are the shell's
          // chrome frame, not a joinable surface; the surface viewmodels
          // under them carry the surfaceIds.
          continue;
        }
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
      final sd = (entry['_shellDir'] as String?) ?? shellDir(surface);
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
  Set<String>? kitDirs; // lazily loaded from config/kit-registry.json
  for (final e in registry) {
    final entry = e as Map<String, dynamic>;
    // v1 joins on the entry id; v2's viewmodels export the SURFACE short
    // name as surfaceId (studio_startup for studio_startup_view), so the
    // join key comes from the surface when the entry is v2-sourced.
    final surface = entry['surface'] as String?;
    final authoringId = entry['id'] as String?;
    final sid = (entry['_shellDir'] != null && surface != null)
        ? surface.replaceAll(RegExp(r'_view$'), '')
        : authoringId;

    // ---- optional per-screen kits declaration ----
    List<String>? kits;
    if (entry.containsKey('kits')) {
      final k = entry['kits'];
      if (k is! List || k.any((i) => i is! String || i.isEmpty)) {
        stderr.writeln("FAIL: screen '$sid' declares 'kits' but it is not a "
            'list of non-empty kit names');
        return null;
      }
      if (kitDirs == null) {
        kitDirs = _loadKitDirs(designRoot);
        if (kitDirs == null) return null;
      }
      for (final name in k.cast<String>()) {
        if (!kitDirs.contains(name)) {
          stderr.writeln("FAIL: screen '$sid' declares unknown kit '$name' — "
              'not a kits[].dir in config/kit-registry.json');
          return null;
        }
      }
      kits = k.cast<String>();
    }

    // ---- optional per-screen states (the CLOSED screen-state vocabulary) ----
    // A state is a way the SCREEN can look; the vocabulary is closed so that
    // every value maps to something kit/state actually implements. Validated
    // here as well as in intake because the authored layer can be hand-edited
    // without ever passing through intake.
    List<String>? states;
    if (entry.containsKey('states')) {
      final st = entry['states'];
      if (st is! List || st.any((i) => i is! String)) {
        stderr.writeln("FAIL: screen '$sid' declares 'states' but it is not a "
            'list of strings');
        return null;
      }
      for (final s in st) {
        if (!surfaceStates.contains(s)) {
          stderr.writeln("FAIL: screen '$sid' declares state '$s' — not one of "
              '$surfaceStates (the screen-state vocabulary is closed; a toast '
              'is not a screen state, put it on a flow edge as `feedback`)');
          return null;
        }
      }
      states = st.cast<String>();
    }
    // A toast is a consequence of a TRANSITION, so it never sits on a screen.
    if (entry.containsKey('feedback')) {
      stderr.writeln("FAIL: screen '$sid' declares 'feedback' — feedback is an "
          'EDGE key (flows[].edges[].feedback), not a screen key');
      return null;
    }
    final statesProvenance = entry['statesProvenance'];

    if (surface != null && surface.isNotEmpty) {
      final vm = viewmodels[sid];
      if (vm == null) {
        stderr.writeln("FAIL: screen '$sid' declares a surface but no viewmodel "
            "exports surfaceId '$sid'");
        return null;
      }
      final screen = <String, dynamic>{
        // The authoring entry id (v2: studio_startup_shell.startup), NOT the
        // join key — consumers key screens by id and flows join on ids too.
        'id': authoringId,
        'shell': entry['shell'],
        'comp': entry['comp'],
        'shellDir': (entry['_shellDir'] as String?) ?? shellDir(surface),
        'surface': surface,
        'viewmodel': vm['path'],
        'deps': vm['deps'],
      };
      if (entry['_shellDir'] != null) {
        // v2 marker: the surfaceId the viewmodel exports (the join key).
        screen['surfaceKey'] = sid;
      }
      if (kits != null) screen['kits'] = kits;
      if (states != null) screen['states'] = states;
      if (statesProvenance != null) screen['statesProvenance'] = statesProvenance;
      screens.add(screen);
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
  // v1: the screen id IS the surfaceId join key. v2 screens carry an
  // explicit surfaceKey (the short name their viewmodel exports).
  final claimed = screens
      .where((s) => s['surface'] != null)
      .map((s) => (s['surfaceKey'] ?? s['id']) as String)
      .toSet();
  final orphans = viewmodels.keys.where((s) => !claimed.contains(s)).toList()..sort();
  if (orphans.isNotEmpty) {
    final one = orphans.first;
    stderr.writeln("FAIL: viewmodel ${viewmodels[one]!['path']} exports surfaceId '$one' "
        "but the registry declares no such screen");
    return null;
  }

  // ---- structure@2: theme / fonts / widgets (each optional) ----
  // Hard-fail on a source that EXISTS but is malformed; stay silent when it is
  // simply absent. A typo in theme.json must not silently drop the theme key
  // and let the gate call the result "in sync".
  final theme = loadTheme(designRoot);
  if (theme == null && File('$designRoot/models/theme.json').existsSync()) {
    return null; // loadTheme already explained why on stderr
  }
  final fonts = loadFonts(designRoot);
  if (fonts == null && File('$designRoot/models/fonts.json').existsSync()) {
    return null;
  }
  final widgets = scanWidgets(designRoot);

  return {
    r'$schema': banner,
    'registry': 'models/screens_model/registry.json',
    'shellRoots': shellRoots,
    'screens': screens,
    'flows': ?flows,
    'theme': ?theme,
    'fonts': ?fonts,
    'widgets': ?widgets,
  };
}

/// The accent-swatch SSOT (models/theme.json) lifted into structure@2.
///
/// Passed through by VALUE, not reinterpreted: theme.json is the SSOT and
/// services/theme_tokens.js is its only other reader. We validate the shape a
/// consumer depends on (5 roles resolvable per swatch per mode) and drop the
/// designer-only `comment`/`$schema` noise.
///
/// Returns null when the file is absent (caller omits the key) OR malformed
/// (caller hard-fails) — the two are distinguished by the caller testing
/// existsSync, so a malformed theme can never be mistaken for an absent one.
Map<String, dynamic>? loadTheme(String designRoot) {
  final f = File('$designRoot/models/theme.json');
  if (!f.existsSync()) return null;

  Map<String, dynamic> raw;
  try {
    final decoded = jsonDecode(f.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      stderr.writeln('FAIL: models/theme.json is not a JSON object');
      return null;
    }
    raw = decoded;
  } catch (e) {
    stderr.writeln('FAIL: models/theme.json does not parse — $e');
    return null;
  }

  final roles = raw['roles'];
  if (roles is! Map) {
    stderr.writeln('FAIL: models/theme.json has no `roles` mix map '
        '(surfaceMix/textMix/mutedMix)');
    return null;
  }
  for (final k in const ['surfaceMix', 'textMix', 'mutedMix']) {
    if (roles[k] is! num) {
      stderr.writeln('FAIL: models/theme.json roles.$k must be a number '
          '(a color-mix percentage)');
      return null;
    }
  }

  final swatches = raw['swatches'];
  if (swatches is! List || swatches.isEmpty) {
    stderr.writeln('FAIL: models/theme.json has no `swatches` list');
    return null;
  }
  final names = <String>[];
  final out = <Map<String, dynamic>>[];
  for (final s in swatches) {
    if (s is! Map || s['name'] is! String) {
      stderr.writeln('FAIL: models/theme.json swatch without a `name`');
      return null;
    }
    final name = s['name'] as String;
    if (names.contains(name)) {
      stderr.writeln("FAIL: models/theme.json declares swatch '$name' twice");
      return null;
    }
    names.add(name);
    final modes = <String, dynamic>{};
    for (final mode in const ['light', 'dark']) {
      final m = s[mode];
      if (m is! Map) {
        stderr.writeln("FAIL: models/theme.json swatch '$name' has no "
            "`$mode` mode — every swatch is a light+dark pair");
        return null;
      }
      // accent + soft are authored; `on` is the on-accent of role 1.
      for (final key in const ['accent', 'soft', 'on']) {
        if (m[key] is! String) {
          stderr.writeln("FAIL: models/theme.json swatch '$name'.$mode "
              "is missing the `$key` color");
          return null;
        }
      }
      modes[mode] = {
        'accent': m['accent'],
        'soft': m['soft'],
        'on': m['on'],
      };
    }
    out.add({
      'name': name,
      if (s['dot'] is String) 'dot': s['dot'],
      'light': modes['light'],
      'dark': modes['dark'],
    });
  }

  final def = raw['default'];
  if (def is! String || !names.contains(def)) {
    stderr.writeln("FAIL: models/theme.json `default` must name one of "
        "its swatches (${names.join(', ')})");
    return null;
  }

  return {
    'default': def,
    'roles': {
      'surfaceMix': roles['surfaceMix'],
      'textMix': roles['textMix'],
      'mutedMix': roles['mutedMix'],
    },
    'swatches': out,
  };
}

/// Declared font families (models/fonts.json) lifted into structure@2.
///
/// DECLARED, never scanned: emitting from assets/fonts/ filenames would put
/// subset and weight detail (`lexend-deca-500-latin-ext`) into the pipeline
/// contract, and a re-subset would then read as a structure change.
Map<String, dynamic>? loadFonts(String designRoot) {
  final f = File('$designRoot/models/fonts.json');
  if (!f.existsSync()) return null;

  Map<String, dynamic> raw;
  try {
    final decoded = jsonDecode(f.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      stderr.writeln('FAIL: models/fonts.json is not a JSON object');
      return null;
    }
    raw = decoded;
  } catch (e) {
    stderr.writeln('FAIL: models/fonts.json does not parse — $e');
    return null;
  }

  final families = raw['families'];
  if (families is! List || families.isEmpty) {
    stderr.writeln('FAIL: models/fonts.json has no `families` list');
    return null;
  }
  final out = <Map<String, dynamic>>[];
  final seen = <String>[];
  for (final fam in families) {
    // `id` is the contract key (the [data-font] attribute value), NOT `label`:
    // a menu label may be renamed without breaking anything downstream.
    if (fam is! Map || fam['id'] is! String) {
      stderr.writeln('FAIL: models/fonts.json family without an `id`');
      return null;
    }
    final id = fam['id'] as String;
    if (seen.contains(id)) {
      stderr.writeln("FAIL: models/fonts.json declares family id '$id' twice");
      return null;
    }
    seen.add(id);
    if (fam['cssName'] is! String) {
      stderr.writeln("FAIL: models/fonts.json family '$id' has no `cssName`");
      return null;
    }
    // Emitted: identity + the name a renderer resolves + the role slot.
    // Deliberately NOT emitted: files[], stack/displayStack/monoStack,
    // declaredIn, vendored — vendoring and CSS cascade are design-side build
    // detail owned by inc4; a re-subset or a stylesheet move must not read as
    // a structure change.
    out.add({
      'id': id,
      if (fam['label'] is String) 'label': fam['label'],
      'cssName': fam['cssName'],
      if (fam['role'] is String) 'role': fam['role'],
      if (fam['license'] is String) 'license': fam['license'],
    });
  }

  final def = raw['default'];
  if (def is! String || !seen.contains(def)) {
    stderr.writeln("FAIL: models/fonts.json `default` must name one of its "
        "family ids (${seen.join(', ')})");
    return null;
  }
  return {'default': def, 'families': out};
}

// Every open tag carrying data-el, in source order. Templated markup ({{ }}
// in legacy .html, JSX expressions in .tsx) is not strictly parseable as
// HTML, but an OPEN TAG is: attributes may hold template braces, never a bare
// `>`. Ported from widget_repository.js `elsIn` — the two MUST agree on
// identity or a designer edit and a pipeline read would name different
// elements.
final _tagRe = RegExp(r'<([a-zA-Z][\w-]*)((?:"[^"]*"|' "'[^']*'" r'|[^>"' "'" r'])*)>');
final _elRe = RegExp('data-el="([^":]+)(:|")');

/// The auto-layout attributes the widget manager reads and writes.
/// Ported verbatim from widget_repository.js LAYOUT_ATTRS.
const layoutAttrs = <String>[
  'data-layout',
  'data-flow',
  'data-wrap',
  'data-clip',
  'data-gap',
  'data-pad',
  'data-resize-x',
  'data-resize-y',
];

/// Widget definitions scanned from the authored surface partials.
///
/// Returns null when this design root authors no design/surfaces/ (the studio's
/// own root, and any root that is not a live-read project) — the caller then
/// omits the key entirely rather than emitting an empty list, so "no widget
/// layer" and "a widget layer that is empty" stay distinguishable.
///
/// Identity is (file, kind, index), matching widget_repository.resolveWidget:
/// `index` disambiguates repeated same-kind elements in one file.
List<Map<String, dynamic>>? scanWidgets(String designRoot) {
  final dir = Directory('$designRoot/design/surfaces');
  if (!dir.existsSync()) return null;

  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.html'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final out = <Map<String, dynamic>>[];
  for (final f in files) {
    final rel = p
        .relative(f.path, from: designRoot)
        .split(p.separator)
        .join('/');
    final src = f.readAsStringSync();
    final perKind = <String, int>{};
    for (final m in _tagRe.allMatches(src)) {
      final attrs = m.group(2)!;
      final el = _elRe.firstMatch(attrs);
      if (el == null) continue;
      final kind = el.group(1)!;
      final index = perKind[kind] ?? 0;
      perKind[kind] = index + 1;

      final layout = <String, String>{};
      for (final a in layoutAttrs) {
        final am = RegExp('$a(?:="([^"]*)")?(?=[\\s>/]|\$)').firstMatch(attrs);
        if (am != null) layout[a] = am.group(1) ?? '';
      }
      out.add({
        'file': rel,
        'kind': kind,
        'index': index,
        'tag': m.group(1),
        'layout': layout,
      });
    }
  }
  out.sort((a, b) {
    final f = (a['file'] as String).compareTo(b['file'] as String);
    if (f != 0) return f;
    final k = (a['kind'] as String).compareTo(b['kind'] as String);
    if (k != 0) return k;
    return (a['index'] as int).compareTo(b['index'] as int);
  });
  return out;
}

/// Derive shell dir from surface: "stage_shell_projects_home_view" → "stage_shell".
/// The application hub is the lawful exception (hub law, locked-laws.md): it
/// sits FLAT at `ui/views/<app>_application_hub/` with no _shell suffix, so
/// "studio_application_hub_view" → "studio_application_hub".
String? shellDir(String surface) {
  final idx = surface.indexOf('_shell_');
  if (idx < 0) {
    return surface.endsWith('_application_hub_view')
        ? surface.replaceAll(RegExp('_view\$'), '')
        : null;
  }
  return '${surface.substring(0, idx)}_shell';
}

// ── the app-shell roster law ──────────────────────────────────────────────
// The roster is ROLES, not literal ids (canon amended 2026-08-12, grill D2).
// Every frozen design fills these roles with real surfaces:
//   splash  — the branded splash view
//   startup — the startup/loading view
//   unknown — the unknown-route (404) view
// `access` (the sign-in gate) joins the roster iff any registry surface
// carries `requiresAuth`. An entry fills a role either by literal id
// `app.<role>` (the classic app-level shell, no declaration needed) or by
// carrying a per-entry `role: "<role>"` field (e.g. studio-v2's
// `studio_startup.splash` fills `splash`). Enforced here at freeze and
// mirrored in the structure gate, which calls this same function so the two
// can never disagree on what the roster demands.
const appShellRoles = ['splash', 'startup', 'unknown'];

/// Roster roles [registry] fails to fill — no entry claims the role (by
/// `app.<role>` id or `role` field), or the claiming entries all carry
/// `surface: null` (an excluded splash routes to nothing, so exclusion does
/// not satisfy the law). Empty when the design is compliant.
List<String> missingAppShellRoster(List registry) {
  final filled = <String>{};
  var needsAccess = false;
  for (final e in registry) {
    if (e is! Map) continue;
    final ra = e['requiresAuth'];
    if (ra != null && ra != false) needsAccess = true;
    final surface = e['surface'];
    if (e['id'] is! String || surface is! String || surface.isEmpty) continue;
    final id = e['id'] as String;
    if (id.startsWith('app.')) filled.add(id.substring(4));
    final role = e['role'];
    if (role is String && role.isNotEmpty) filled.add(role);
  }
  return [
    for (final role in [...appShellRoles, if (needsAccess) 'access'])
      if (!filled.contains(role)) role,
  ];
}

/// Derive the PascalCase component name from a v2 surface name:
/// studio_splash_view -> StudioSplash (v1 carried `comp` in the registry;
/// v2's authoring SSOT names only the surface, so comp is derived).
String? _compOf(String? surface) {
  if (surface == null || surface.isEmpty) return null;
  final base = surface.replaceAll(RegExp(r'_view$'), '');
  return base
      .split('_')
      .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
      .join();
}

/// Load the valid kit dir names from config/kit-registry.json at the repo root
/// (located by the shared config/arxa.config.json walk-up). Returns null on
/// failure (error printed to stderr).
///
/// Repo-mode projects (an arxa.json marker, no config/ of their own) resolve
/// the registry from the CLI's own checkout instead — the same executable
/// walk-up the runtime assets use. The kit vocabulary is arxa's, never the
/// project's.
Set<String>? _loadKitDirs(String designRoot) {
  var path = '${findRepoRoot(designRoot)}/config/kit-registry.json';
  if (!File(path).existsSync()) {
    var dir = File(Platform.executable).parent.absolute;
    while (true) {
      final candidate = '${dir.path}/config/kit-registry.json';
      if (File(candidate).existsSync()) {
        path = candidate;
        break;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  final f = File(path);
  if (!f.existsSync()) {
    stderr.writeln("FAIL: a screen declares 'kits' but no kit registry exists "
        'at $path');
    return null;
  }
  try {
    final decoded = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return {
      for (final k in decoded['kits'] as List) (k as Map)['dir'] as String,
    };
  } catch (e) {
    stderr.writeln('FAIL: $path does not parse as the kit registry — $e');
    return null;
  }
}

/// Serialize structure data as indented JSON + newline (matches Python json.dumps(indent=2)).
String _serialize(Map<String, dynamic> data) {
  return '${const JsonEncoder.withIndent('  ').convert(data)}\n';
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
