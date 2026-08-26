// crud — the one write path for feature CRUD on the authored layer.
//
// Dart port of archives/tooling-pre-dart/tools/crud/crud.py (architecture §18).
// A feature IS a registry entry. This module writes the AUTHORED layer only:
//
//   models/screens_model/registry.json     the feature list (identity)
//   ui/views/<shell>/<short>/              the _view.html + _viewmodel.js pair
//   models/screens_model/migrations.json   rename lineage (lazy; renames only)
//
// It NEVER writes structure.json or lib/** — those are GENERATED, emitted
// downstream by emit_structure and the scaffolder. Editing generated output
// would create a second writer and kill the regenerate-and-diff gate.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// ---- authored-layer layout (derived from the design root; never hardcoded) --
const registryRel = 'models/screens_model/registry.json';
const migrationsRel = 'models/screens_model/migrations.json';
const viewsRel = 'ui/views';

// Entry key order — frozen so round-trips are byte-stable. Matches the existing
// registry.json: id, label, surface, shell, comp.
const _entryKeys = ['id', 'label', 'surface', 'shell', 'comp'];

// The surfaceId declaration is the authoritative join back to the registry.
final _surfaceIdRe = RegExp("surfaceId\\s*=\\s*['\"]([^'\"]+)['\"]");

// Pair templates (CRUD is the only writer of these two files).
const _pairView = '<!-- {label} — authored view (CRUD writes this; never hand-edit\n'
    '     generated lib/** output, which is emitted downstream). -->\n'
    '<section class="view" data-surface="{surface}">{label}</section>\n';

const _pairVm = '// {label} — authored viewmodel. The surfaceId declaration is what\n'
    '// removes the fuzzy (shell, short) join: a view resolves to its registry entry by\n'
    '// assertion, not by name matching (§14 / feature-crud.md Create step 2).\n'
    "export const surfaceId = '{id}';\n";

/// Thrown by [_fail]; [crudMain] catches it and converts to `crud: <msg>` on
/// stderr + exit 1. Lets the operations stay linear like the Python `fail()`.
class CrudError implements Exception {
  const CrudError(this.message);
  final String message;
  @override
  String toString() => message;
}

Never _fail(String msg) => throw CrudError(msg);

// ---- load / save (atomic writes; a crash never leaves a half-written file) --

String _path(String root, String rel) => p.join(root, rel);

List<Map<String, dynamic>> loadRegistry(String root) {
  final file = File(_path(root, registryRel));
  if (!file.existsSync()) {
    _fail('$registryRel not found under $root — a tool that cannot find '
        'its input never passes quietly; point --root at a design folder.');
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } catch (e) {
    _fail('$registryRel does not parse — $e');
  }
  if (decoded is! List) {
    _fail('$registryRel must be a JSON array of feature entries');
  }
  return [for (final e in decoded) e as Map<String, dynamic>];
}

void _atomicWriteJson(String path, Object obj) {
  // indent=2 + trailing newline matches the hand-authored style and keeps
  // round-trips byte-identical. Temp file then rename → a crash mid-write
  // cannot corrupt the file.
  Directory(p.dirname(path)).createSync(recursive: true);
  final text = '${const JsonEncoder.withIndent('  ').convert(obj)}\n';
  final tmp = '$path.tmp';
  File(tmp).writeAsStringSync(text);
  File(tmp).renameSync(path);
}

void saveRegistry(String root, List<Map<String, dynamic>> entries) =>
    _atomicWriteJson(_path(root, registryRel), entries);

List<Map<String, dynamic>> loadMigrations(String root) {
  final file = File(_path(root, migrationsRel));
  if (!file.existsSync()) return [];
  try {
    final m = jsonDecode(file.readAsStringSync());
    if (m is List) return [for (final e in m) e as Map<String, dynamic>];
    return [];
  } catch (_) {
    return [];
  }
}

void saveMigrations(String root, List<Map<String, dynamic>> events) {
  final path = _path(root, migrationsRel);
  if (events.isEmpty) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    return;
  }
  _atomicWriteJson(path, events);
}

// ---- derivation ------------------------------------------------------------
/// The directory short-name is the last '.'-segment of the id — a stable,
/// documented derivation (contract: `ui/views/<shell>/<short>/`).
String shortOf(String eid) => eid.split('.').last;

/// Relative pair dir, or null when surface is null/empty (declared exclusion ⇒
/// no pair is ever created or expected).
String? pairRel(Map<String, dynamic> entry) {
  final surface = entry['surface'];
  if (surface == null || (surface is String && surface.isEmpty)) return null;
  return '$viewsRel/${entry['shell']}/${shortOf(entry['id'] as String)}';
}

Map<String, dynamic>? findEntry(List<Map<String, dynamic>> entries, String id) {
  for (final e in entries) {
    if (e['id'] == id) return e;
  }
  return null;
}

Set<String> liveIds(List<Map<String, dynamic>> entries) =>
    {for (final e in entries) e['id'] as String};

// ---- pair emission ---------------------------------------------------------
String _fmt(String tpl, Map<String, String> vars) =>
    // single-pass (matches str.format; no re-scan of substituted text)
    tpl.replaceAllMapped(RegExp(r'\{(label|surface|id)\}'), (m) => vars[m[1]]!);

String? writePair(String root, Map<String, dynamic> entry) {
  final rel = pairRel(entry);
  if (rel == null) return null; // surface:null ⇒ declared exclusion, no pair
  final dir = _path(root, rel);
  Directory(dir).createSync(recursive: true);
  final short = shortOf(entry['id'] as String);
  final label = (entry['label'] as String?) ?? '';
  final surface = entry['surface'] as String;
  final id = entry['id'] as String;
  File(p.join(dir, '${short}_view.html'))
      .writeAsStringSync(_fmt(_pairView, {'label': label, 'surface': surface}));
  File(p.join(dir, '${short}_viewmodel.js'))
      .writeAsStringSync(_fmt(_pairVm, {'label': label, 'id': id}));
  return rel;
}

void removePair(String root, Map<String, dynamic> entry) {
  final rel = pairRel(entry);
  if (rel == null) return;
  _removePairDir(root, rel, shortOf(entry['id'] as String));
}

void _removePairDir(String root, String rel, String short) {
  final dir = _path(root, rel);
  if (!Directory(dir).existsSync()) return;
  // Remove only the pair we authored; leave siblings untouched.
  for (final name in ['${short}_view.html', '${short}_viewmodel.js']) {
    final f = File(p.join(dir, name));
    if (f.existsSync()) f.deleteSync();
  }
  // Walk bottom-up from the pair dir, dropping now-empty ancestors. A rename
  // that emptied a shell folder must leave no empty dir behind — that empty dir
  // is exactly the debris the orphan assertion would flag forever. Stops at the
  // first non-empty ancestor and never ascends past the design root.
  var cur = dir;
  for (var i = 0; i < '/'.allMatches(rel).length + 1; i++) {
    final d = Directory(cur);
    if (d.existsSync() && d.listSync().isEmpty) {
      d.deleteSync();
    } else {
      break;
    }
    cur = p.dirname(cur);
  }
}

/// A migration {from->to} is live only while `to` is still a feature. Once the
/// lineage is deleted, the record is stale debris — remove it so round-trips
/// stay byte-identical.
List<Map<String, dynamic>> pruneMigrations(
        List<Map<String, dynamic>> events, List<Map<String, dynamic>> entries) {
  final live = liveIds(entries);
  return [for (final m in events) if (live.contains(m['to'])) m];
}

// ---- orphan sweep (verify) -------------------------------------------------
/// Yields (surfaceId, pairDirRel) for every _viewmodel.js under ui/views/.
Iterable<(String, String)> scanPairs(String root) sync* {
  final base = _path(root, viewsRel);
  if (!Directory(base).existsSync()) return;
  for (final f in Directory(base).listSync(recursive: true)) {
    if (f is! File) continue;
    if (!f.path.endsWith('_viewmodel.js')) continue;
    String src;
    try {
      src = f.readAsStringSync();
    } catch (_) {
      continue;
    }
    final m = _surfaceIdRe.firstMatch(src);
    if (m == null) continue;
    yield (m[1]!, p.relative(f.parent.path, from: root).replaceAll('\\', '/'));
  }
}

/// Pair dirs whose surfaceId maps to no live entry — the §18 orphan assertion,
/// at the authored layer.
List<(String, String)> orphans(String root, List<Map<String, dynamic>> entries) {
  final live = liveIds(entries);
  return [
    for (final (sid, rel) in scanPairs(root))
      if (!live.contains(sid)) (sid, rel),
  ];
}

// ============================================================================
// operations — each returns 0 on success; hard failures throw via [_fail].
// ============================================================================
int opList(String root) {
  final reg = loadRegistry(root);
  for (final e in reg) {
    final surf = e['surface'];
    final tag = (surf == null || (surf is String && surf.isEmpty))
        ? 'exclude'
        : 'frozen';
    final id = (e['id'] as String?) ?? '';
    final label = (e['label'] as String?) ?? '';
    print('  ${id.padRight(28)} [$tag] $label');
  }
  print('${reg.length} feature(s)');
  return 0;
}

int opShow(String root, String id) {
  final reg = loadRegistry(root);
  final e = findEntry(reg, id);
  if (e == null) _fail("no entry with id '$id'");
  print(const JsonEncoder.withIndent('  ').convert(e));
  final rel = pairRel(e);
  print('  pair: ${rel ?? "(none — declared exclusion)"}');
  return 0;
}

String? _coerceSurface(String? s) {
  if (s == null) return null;
  if (s == 'null' || s.isEmpty) return null;
  return s;
}

int opCreate(
  String root, {
  required String id,
  required String shell,
  required String comp,
  String? surface,
  String label = '',
}) {
  final reg = loadRegistry(root);
  if (findEntry(reg, id) != null) {
    // id-stability (§18): an id may never be reused. A duplicate create would
    // silently re-point every generated artifact that referenced it.
    _fail("id '$id' already exists — id is a stable key and is never "
        'reused (§18). Use `rename` to retire it, or pick a new id.');
  }
  final entry = <String, dynamic>{
    'id': id,
    'label': label,
    'surface': _coerceSurface(surface),
    'shell': shell,
    'comp': comp,
  };
  reg.add(entry);
  saveRegistry(root, reg);
  final rel = writePair(root, entry);
  final kind = rel == null ? 'declared exclusion (no pair)' : 'pair at $rel/';
  print('created $id — $kind');
  return 0;
}

int opUpdate(String root, String id, String? label) {
  final reg = loadRegistry(root);
  final e = findEntry(reg, id);
  if (e == null) _fail("no entry with id '$id'");
  // id and surface are identity — immutable on an existing entry (§18).
  if (label != null) {
    e['label'] = label;
  }
  // Re-serialize in canonical order, preserving any extra keys.
  final ordered = <String, dynamic>{};
  for (final k in _entryKeys) {
    if (e.containsKey(k)) ordered[k] = e[k];
  }
  for (final entry in e.entries) {
    ordered.putIfAbsent(entry.key, () => entry.value);
  }
  reg[reg.indexWhere((x) => x['id'] == id)] = ordered;
  saveRegistry(root, reg);
  writePair(root, ordered); // content edits may require the pair label to refresh
  print('updated $id');
  return 0;
}

int opRename(String root, String fromId, String toId, String? surface) {
  final reg = loadRegistry(root);
  final old = findEntry(reg, fromId);
  if (old == null) _fail("rename --from '$fromId': no such entry");
  if (findEntry(reg, toId) != null) {
    _fail("rename --to '$toId' already exists — id is never reused (§18)");
  }
  final newSurface =
      surface != null ? _coerceSurface(surface) : old['surface'] as String?;

  // never delete before the replacement exists (§18 prior art: a fixer that
  // deleted first once left a project with no service locator).
  final newEntry = <String, dynamic>{
    'id': toId,
    'label': (old['label'] as String?) ?? '',
    'surface': newSurface,
    'shell': old['shell'],
    'comp': old['comp'],
  };
  reg.add(newEntry);
  saveRegistry(root, reg);
  writePair(root, newEntry);

  // NOW the old entry is retired and its pair removed — the new pair exists, so
  // the tree is never left without the feature.
  reg.removeWhere((e) => e['id'] == fromId);
  saveRegistry(root, reg);
  removePair(root, old);

  final events = loadMigrations(root);
  events.add({
    'op': 'rename',
    'from': fromId,
    'to': toId,
    'surface': old['surface'],
  });
  saveMigrations(root, pruneMigrations(events, reg));
  print('renamed $fromId -> $toId (migration recorded)');
  return 0;
}

int opDelete(String root, String id, String confirm) {
  if (confirm.isEmpty) {
    // delete is the one operation behind a human confirm — removing authored
    // code is not recoverable by re-running a stage (§18). With no token, the
    // delete path refuses to run unattended and changes nothing.
    _fail("refusing to delete '$id' without --confirm — removal is not "
        'recoverable by re-running a stage (§18). Mint a token at the gate.');
  }
  final reg = loadRegistry(root);
  final entry = findEntry(reg, id);

  // Idempotent on the DESIRED END STATE, not on 'was this touched': a crash
  // mid-delete (registry written, pair not yet removed) must be repaired by the
  // next run. So we converge regardless of starting point.
  reg.removeWhere((e) => e['id'] == id);
  saveRegistry(root, reg);

  // Remove the pair the entry points at...
  if (entry != null) removePair(root, entry);
  // ...AND sweep any orphaned pair whose surfaceId is now dead (covers the
  // crash case where the entry was already gone but the pair lingers).
  for (final (sid, rel) in orphans(root, reg)) {
    _removePairDir(root, rel, shortOf(sid));
  }

  saveMigrations(root, pruneMigrations(loadMigrations(root), reg));
  print('deleted $id${entry == null ? ' (swept orphan pair)' : ''}');
  return 0;
}

int opVerify(String root, {bool fix = false, String confirm = ''}) {
  final reg = loadRegistry(root);
  final events = loadMigrations(root);
  final bad = orphans(root, reg);
  final live = liveIds(reg);
  final stale = [for (final m in events) if (!live.contains(m['to'])) m];

  if (fix) {
    if (confirm.isEmpty) {
      _fail('verify --fix removes authored files — requires --confirm (§18)');
    }
    for (final (sid, rel) in bad) {
      _removePairDir(root, rel, shortOf(sid));
    }
    saveMigrations(root, pruneMigrations(events, reg));
    if (bad.isNotEmpty) print('verify --fix: removed ${bad.length} orphan pair(s)');
    if (stale.isNotEmpty) print('verify --fix: pruned ${stale.length} stale migration(s)');
    if (bad.isEmpty && stale.isEmpty) print('verify --fix: nothing to repair (tree is clean)');
    return 0;
  }

  var errs = 0;
  for (final (sid, rel) in bad) {
    stderr.writeln("FAIL: orphan pair $rel/ declares surfaceId '$sid' but no "
        'registry entry has that id — the authored-layer orphan assertion (§18).');
    errs++;
  }
  for (final m in stale) {
    stderr.writeln("FAIL: stale migration ${m['from']} -> ${m['to']} whose "
        'target is no longer a feature — rename debris.');
    errs++;
  }
  if (errs > 0) return 1;
  print('verify OK — ${reg.length} feature(s), no orphans, no stale migrations');
  return 0;
}

// ============================================================================
// entry point — arg parsing + dispatch
// ============================================================================
int crudMain(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('crud: missing operation');
    stderr.writeln(_usage);
    return 2;
  }
  final op = args.first;
  final rest = args.sublist(1);
  try {
    switch (op) {
      case 'list':
        final a = _parse(rest, {});
        if (a.positional.length != 1) return _usageErr('list needs <root>');
        return opList(a.positional.first);
      case 'show':
        final a = _parse(rest, {});
        if (a.positional.length != 2) return _usageErr('show needs <root> <id>');
        return opShow(a.positional[0], a.positional[1]);
      case 'create':
        final a = _parse(rest, {});
        if (a.positional.length != 1) return _usageErr('create needs <root>');
        if (!a.has('id')) return _usageErr('create requires --id');
        if (!a.has('shell')) return _usageErr('create requires --shell');
        if (!a.has('comp')) return _usageErr('create requires --comp');
        return opCreate(
          a.positional.first,
          id: a.get('id')!,
          shell: a.get('shell')!,
          comp: a.get('comp')!,
          surface: a.get('surface'),
          label: a.get('label') ?? '',
        );
      case 'update':
        final a = _parse(rest, {});
        if (a.positional.length != 1) return _usageErr('update needs <root>');
        if (!a.has('id')) return _usageErr('update requires --id');
        return opUpdate(a.positional.first, a.get('id')!, a.get('label'));
      case 'rename':
        final a = _parse(rest, {});
        if (a.positional.length != 1) return _usageErr('rename needs <root>');
        if (!a.has('from')) return _usageErr('rename requires --from');
        if (!a.has('to')) return _usageErr('rename requires --to');
        return opRename(
            a.positional.first, a.get('from')!, a.get('to')!, a.get('surface'));
      case 'delete':
        final a = _parse(rest, {});
        if (a.positional.length != 1) return _usageErr('delete needs <root>');
        if (!a.has('id')) return _usageErr('delete requires --id');
        return opDelete(a.positional.first, a.get('id')!, a.get('confirm') ?? '');
      case 'verify':
        final a = _parse(rest, {'fix'});
        if (a.positional.length != 1) return _usageErr('verify needs <root>');
        return opVerify(a.positional.first,
            fix: a.has('fix'), confirm: a.get('confirm') ?? '');
      default:
        stderr.writeln("crud: unknown operation '$op'");
        stderr.writeln(_usage);
        return 2;
    }
  } on CrudError catch (e) {
    stderr.writeln('crud: ${e.message}');
    return 1;
  }
}

class _Args {
  _Args(this.positional, this.options);
  final List<String> positional;
  final Map<String, String> options;
  bool has(String k) => options.containsKey(k);
  String? get(String k) => options[k];
}

/// Minimal flag parser: supports `--flag value`, `--flag=value`, boolean
/// `--flag` (when named in [boolFlags]). Positional args go to `.positional`.
_Args _parse(List<String> args, Set<String> boolFlags) {
  final positional = <String>[];
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--')) {
      final eq = a.indexOf('=');
      if (eq >= 0) {
        options[a.substring(2, eq)] = a.substring(eq + 1);
        continue;
      }
      final name = a.substring(2);
      if (boolFlags.contains(name) || i + 1 >= args.length) {
        options[name] = '';
      } else {
        options[name] = args[++i];
      }
    } else {
      positional.add(a);
    }
  }
  return _Args(positional, options);
}

int _usageErr(String msg) {
  stderr.writeln('crud: $msg');
  stderr.writeln(_usage);
  return 2;
}

const _usage = '''
Usage: arxa crud <op> <args>

Operations:
  list   <root>                         Read the registry
  show   <root> <id>                    Show one feature
  create <root> --id --shell --comp [--surface] [--label]
  update <root> --id [--label TEXT]
  rename <root> --from --to [--surface]
  delete <root> --id --confirm TOK
  verify <root> [--fix --confirm TOK]   orphan sweep (the §18 assertion)''';
