// appbox-intake — the elicitation engine (Dart port of
// `skills/appbox-intake/intake.py`).
//
// Architecture §22: intake ELICITS requirements; it NEVER generates design or
// code. This is the single engine both the headless phase and the desktop
// wizard drive ("one engine" — if the two front ends can disagree, plan 10 has
// failed). It does three things and only three things:
//
//   1. validate — check an answers document, where every field carries
//      provenance (client | founder | inferred).
//   2. emit     — turn validated answers into docs/design/brief.md (every
//      `inferred` field visibly marked) and a seeded registry.json (ids,
//      shells, comps; surface ALWAYS null — intake names, never designs).
//   3. seed     — accept a HAND-WRITTEN brief (plan 10.7: intake is optional)
//      and derive the registry seed from its surface table, without rewriting
//      a word of the brief.
//
// THE CONTRACT THIS MODULE EXISTS TO ENFORCE
//   Emission is a PURE function of its input. [emitBrief]/[emitRegistry] add
//   no content that was not elicited: no new surfaces, no new field values, no
//   invented copy. The only things derived are mechanical naming (comp from
//   id, by the convention in declare-structure) and the structural default
//   surface=null. Everything else is the client's words, passed through.

import 'dart:convert';
import 'dart:io';

/// Who supplied a field. `inferred` = NOT elicited; a placeholder the brief must
/// visibly flag. There is no fourth value — 'guessed', 'assumed', 'default' are
/// all 'inferred'.
const provenance = ['client', 'founder', 'inferred'];

/// Surface id is `<shell>.<short>`, both lowercase alnum (see
/// intake.schema.json).
final _idRe = RegExp(r'^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$');

/// The visible marker the emitted brief puts on any `inferred` field. A reader
/// who skims must not miss it — that is the entire point of marking inference.
const inferredMark = '> **[inferred]** — not stated by the client; confirm or correct.';

/// Ordered brief sections (the brief renders them in this order).
const _fieldTitles = <(String, String)>[
  ('product', 'Product'),
  ('audience', 'Audience'),
  ('appMustDo', 'What the app must do'),
  ('existingSystems', 'Existing systems'),
  ('targets', 'Targets'),
  ('brand', 'Brand'),
  ('constraints', 'Constraints'),
  ('outOfScope', 'Out of scope'),
  ('layoutTemplate', 'Layout template'),
];

const _listFields = {'appMustDo', 'constraints', 'outOfScope'};

final _tableSplit = RegExp(r'\s*\|\s*');
const _sepChars = {'-', ':', ' '};

// ---------------------------------------------------------------- validation

/// Validate [answers]; returns the list of human-readable error strings
/// (empty = valid). Structural + semantic checks that the JSON Schema cannot
/// express on their own; each error names the offending field.
ValidationResult validateIntake(Map<String, dynamic> answers) {
  final errs = <String>[];

  for (final key in const ['product', 'audience', 'appMustDo', 'targets']) {
    if (!answers.containsKey(key)) {
      errs.add('$key: required field is missing');
    }
  }

  for (final (key, _) in _fieldTitles) {
    if (!answers.containsKey(key)) continue;
    final node = answers[key];
    if (node is! Map) {
      errs.add('$key: expected {value, provenance}, got ${_pyTypeName(node)}');
      continue;
    }
    final prov = node['provenance'];
    if (!provenance.contains(prov)) {
      errs.add("$key: provenance '$prov' is not one of $provenance "
          "(there is no fourth value — unstated means 'inferred')");
    }
    final val = node['value'];
    if (_listFields.contains(key)) {
      if (val is! List || val.any((x) => x is! String)) {
        errs.add('$key: value must be a list of strings');
      }
    } else if (key == 'targets') {
      if (val is! List || val.any((x) => x is! String)) {
        errs.add('$key: value must be a list of platform strings (§11)');
      }
    } else if (key == 'layoutTemplate') {
      errs.addAll(_validateLayoutTemplate(val));
    } else {
      if (val is! String) {
        errs.add('$key: value must be a string');
      }
    }
  }

  // surfaces: shape + the shell==id-prefix invariant + uniqueness
  var surfaces = answers['surfaces'];
  if (surfaces is! List) {
    errs.add('surfaces: must be a list');
    surfaces = const [];
  }
  final seen = <String>{};
  for (var i = 0; i < surfaces.length; i++) {
    final s = surfaces[i];
    final where = 'surfaces[$i]';
    if (s is! Map) {
      errs.add('$where: expected an object');
      continue;
    }
    for (final req in const ['id', 'label', 'shell', 'provenance']) {
      if (!s.containsKey(req)) {
        errs.add("$where: missing '$req'");
      }
    }
    final sid = s['id'].toString();
    final m = _idRe.firstMatch(sid);
    if (m == null) {
      errs.add("$where: id '$sid' must be <shell>.<short> (lowercase alnum, "
          'e.g. projects.home)');
    } else {
      final shellFromId = m.group(1)!;
      if (s['shell'] != shellFromId) {
        errs.add("$where: shell '${s['shell']}' must equal the id's first "
            "segment '$shellFromId'");
      }
    }
    if (!provenance.contains(s['provenance'])) {
      errs.add("$where: provenance '${s['provenance']}' is not one of $provenance");
    }
    if (seen.contains(sid)) {
      errs.add("$where: duplicate id '$sid' (ids are permanent — add a new "
          'one, do not reuse)');
    }
    seen.add(sid);
  }

  return ValidationResult(errs);
}

List<String> _validateLayoutTemplate(Object? val) {
  // Shape-check a layoutTemplate value. Membership in the closed lists is the
  // schema's job (enums); here we guard the structure the brief renderer relies
  // on.
  if (val is! Map) {
    return [
      'layoutTemplate: value must be an object '
          '{category, archetype, areas, containers} '
          '(copied verbatim from layout_templates.json)'
    ];
  }
  final errs = <String>[];
  for (final req in const ['category', 'archetype', 'areas', 'containers']) {
    if (!val.containsKey(req)) {
      errs.add("layoutTemplate: value is missing '$req'");
    }
  }
  final areas = val['areas'];
  if (areas is! Map) {
    errs.add('layoutTemplate: areas must be an object keyed by rung');
  } else {
    for (final rung in const ['compact', 'medium', 'expanded']) {
      final rows = areas[rung];
      if (rows is! List || rows.any((r) => r is! String)) {
        errs.add('layoutTemplate: areas.$rung must be a list of '
            'grid-template-areas row strings');
      }
    }
  }
  if (val['containers'] is! Map) {
    errs.add('layoutTemplate: containers must be an object '
        '(named container -> {type, hints})');
  }
  return errs;
}

// ----------------------------------------------------------- naming (derived)

/// comp = PascalCase(shell) + PascalCase(short), the declare-structure
/// convention (shop.cart -> ShopCart). Purely mechanical; not design.
String deriveComp(String surfaceId) {
  final m = _idRe.firstMatch(surfaceId);
  if (m == null) {
    throw ArgumentError("cannot derive comp from malformed id '$surfaceId'");
  }
  return _cap(m.group(1)!) + _cap(m.group(2)!);
}

String _cap(String seg) => seg[0].toUpperCase() + seg.substring(1);

// --------------------------------------------------------------- emission

/// Seed registry: one entry per elicited surface, surface ALWAYS null.
///
/// Keys are exactly {id, label, shell, comp, surface} in that order (matches
/// the Python emit). No entry is invented and none is dropped:
/// `out.length == answers['surfaces'].length`.
List<Map<String, dynamic>> emitRegistry(Map<String, dynamic> answers) {
  final out = <Map<String, dynamic>>[];
  final surfaces = answers['surfaces'];
  if (surfaces is! List) return out;
  for (final s in surfaces) {
    final surf = s as Map;
    out.add({
      'id': surf['id'],
      'label': surf['label'],
      'shell': surf['shell'],
      'comp': deriveComp(surf['id'] as String),
      'surface': null, // intake names; design binds. Never non-null here.
    });
  }
  return out;
}

List<String> _block(String title, Map<String, dynamic>? node) {
  // Render one brief section. An `inferred` field gets the visible mark;
  // client/founder provenance is noted quietly underneath (transparency, not
  // noise). The value is passed through verbatim — never rephrased.
  final lines = <String>['## $title', ''];
  if (node == null) {
    lines.add('_Not stated._');
    return lines;
  }
  final val = node['value'];
  final prov = node['provenance'];
  if (prov == 'inferred') {
    lines.add(inferredMark);
    lines.add('');
  }
  if (val is Map) {
    lines.addAll(_layoutTemplateLines(val));
  } else if (val is List) {
    if (val.isNotEmpty) {
      for (final item in val) {
        lines.add('- $item');
      }
    } else {
      lines.add('_None stated._');
    }
  } else {
    lines.add(val.toString());
  }
  lines.add('');
  lines.add('_provenance: ${prov}_');
  lines.add('');
  return lines;
}

List<String> _layoutTemplateLines(Map val) {
  // Render a layoutTemplate value readably: category, archetype, the
  // grid-template-areas per rung of the viewport ladder, and the named
  // containers. The value is passed through verbatim — never reworded.
  final out = <String>[
    '- category: ${val['category']}',
    '- archetype: ${val['archetype']}',
    '',
  ];
  final areas = val['areas'];
  if (areas is Map) {
    out.add('Grid template areas per rung (viewport ladder):');
    out.add('');
    for (final rung in const ['compact', 'medium', 'expanded']) {
      final rows = areas[rung];
      if (rows is! List || rows.isEmpty) continue;
      out.add('$rung:');
      out.add('```');
      for (final row in rows) {
        out.add('"$row"');
      }
      out.add('```');
      out.add('');
    }
  }
  final containers = val['containers'];
  if (containers is Map && containers.isNotEmpty) {
    out.add('Named containers:');
    out.add('');
    for (final entry in containers.entries) {
      final name = entry.key;
      final meta = entry.value;
      if (meta is Map) {
        final ctype = (meta['type'] ?? '').toString();
        final hints = (meta['hints'] ?? '').toString();
        if (hints.isNotEmpty) {
          out.add('- `$name` — $ctype: $hints');
        } else {
          out.add('- `$name` — $ctype');
        }
      } else {
        out.add('- `$name` — $meta');
      }
    }
    out.add('');
  }
  return out;
}

/// Render the brief markdown. Every `inferred` field is visibly marked; the
/// header states the rule once. No prose is generated beyond section scaffolding
/// and the provenance notes — field VALUES come straight from the answers.
String emitBrief(Map<String, dynamic> answers) {
  final productNode = answers['product'];
  final product = (productNode is Map && productNode['value'] != null)
      ? productNode['value'].toString()
      : '(unnamed product)';
  final lines = <String>[
    '# $product — design brief',
    '',
    '> Emitted by appbox-intake from elicited answers.',
    '> **Intake elicits; it does not generate** (architecture §22).',
    '> Fields marked **[inferred]** were not stated by the client and MUST',
    '> be confirmed before design consumes this brief.',
    '',
  ];
  for (final (key, title) in _fieldTitles) {
    lines.addAll(_block(title, _asNode(answers[key])));
  }

  // surface inventory — the registry seed (surface null everywhere)
  final surfaces = answers['surfaces'];
  final surfaceList = surfaces is List ? surfaces : const [];
  final hasSurfaces = surfaceList.isNotEmpty;
  lines.add('## Surface inventory — the registry seed');
  lines.add('');
  if (!hasSurfaces) {
    lines.add('_No surfaces named at intake. The designer authors the registry._');
  } else {
    lines.add('| id | shell | comp | label | surface |');
    lines.add('|---|---|---|---|---|');
    for (final s in surfaceList) {
      final surf = s as Map;
      lines.add('| `${surf['id']}` | ${surf['shell']} | '
          '${deriveComp(surf['id'] as String)} | ${surf['label']} | _null_ |');
    }
    lines.add('');
    lines.add('Every `surface` is `null` — intake names what the client asked for; '
        'design binds a surface to each.');
  }
  lines.add('');
  return lines.join('\n');
}

Map<String, dynamic>? _asNode(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

// ----------------------------------------------------- hand-written brief (10.7)

/// Plan 10.7: a hand-written brief is valid input. Derive the registry seed from
/// its surface-inventory table WITHOUT rewriting the brief. Rows whose first
/// (id) cell matches the `<shell>.<short>` pattern become seed entries; surface
/// is null. A brief with no such table yields an empty seed and that is NOT an
/// error — intake is optional.
List<Map<String, dynamic>> seedFromBrief(String md) {
  final seed = <Map<String, dynamic>>[];
  var inTable = false;
  var headerIdx = <String, int>{};
  for (final line in md.split(RegExp(r'\r\n|\r|\n'))) {
    final stripped = line.trim();
    final isRow = stripped.startsWith('|') &&
        stripped.endsWith('|') &&
        stripped.length > 2 &&
        stripped.substring(1, stripped.length - 1).contains('|');
    if (!isRow) {
      inTable = false;
      continue;
    }
    final cells = _stripAll(stripped, '|')
        .split(_tableSplit)
        .map((c) => _stripAll(c.trim(), '`'))
        .toList();
    // separator row (|---|---|)
    if (cells.every(_isSeparatorCell)) {
      continue;
    }
    if (!inTable) {
      // this row is a header; remember column positions
      headerIdx = {};
      for (var i = 0; i < cells.length; i++) {
        if (cells[i].isNotEmpty) {
          headerIdx[cells[i].toLowerCase()] = i;
        }
      }
      inTable = true;
      continue;
    }
    final idCol = headerIdx['id'] ?? 0;
    if (idCol >= cells.length) continue;
    final sid = cells[idCol].trim();
    final m = _idRe.firstMatch(sid);
    if (m == null) continue;
    final shell = m.group(1)!;
    final short = m.group(2)!;
    final labelCol = headerIdx['label'];
    final label = (labelCol != null && labelCol < cells.length)
        ? cells[labelCol].trim()
        : _cap(short);
    final entry = <String, dynamic>{
      'id': sid,
      'label': label.isNotEmpty ? label : _cap(short),
      'shell': shell,
      'comp': deriveComp(sid),
      'surface': null,
    };
    // additive sibling metadata (never woven into the four required fields):
    // optional columns pass through — appbox-story-mapper emits priority/release.
    for (final opt in const ['priority', 'release']) {
      final col = headerIdx[opt];
      if (col != null && col < cells.length) {
        final val = cells[col].trim();
        if (val.isNotEmpty) entry[opt] = val;
      }
    }
    seed.add(entry);
  }
  // de-dup keeping first, preserving order
  final seen = <String>{};
  final deduped = <Map<String, dynamic>>[];
  for (final e in seed) {
    final id = e['id'] as String;
    if (seen.contains(id)) continue;
    seen.add(id);
    deduped.add(e);
  }
  return deduped;
}

// ----------------------------------------------------------------- results

/// Outcome of [IntakeEngine.validate] (and [validateIntake]).
class ValidationResult {
  const ValidationResult(this.errors);
  final List<String> errors;
  bool get ok => errors.isEmpty;
}

/// Outcome of [IntakeEngine.emit].
class EmitResult {
  EmitResult.ok({
    required this.briefPath,
    required this.registryPath,
    required this.entries,
    required this.inferredCount,
  })  : ok = true,
        errors = const [];
  EmitResult.failure(this.errors)
      : ok = false,
        briefPath = null,
        registryPath = null,
        entries = 0,
        inferredCount = 0;

  final bool ok;
  final List<String> errors;
  final String? briefPath;
  final String? registryPath;
  final int entries;
  final int inferredCount;
}

/// Outcome of [IntakeEngine.seed].
class SeedResult {
  const SeedResult(this.registry, {this.registryPath});
  final List<Map<String, dynamic>> registry;
  final String? registryPath;
  int get entries => registry.length;
}

// ----------------------------------------------------------------- engine

/// The intake engine: validate / emit / seed. Stateless; a `const` instance.
/// The rendering ([emitBrief]/[emitRegistry]/[seedFromBrief]) is a pure function
/// of its input; this class adds the file IO and default-path resolution.
class IntakeEngine {
  const IntakeEngine();

  ValidationResult validate(Map<String, dynamic> answers) => validateIntake(answers);

  /// Turn validated [answers] into brief.md + registry.json. On invalid input,
  /// writes nothing and returns [EmitResult.failure] (no partial artefacts).
  /// Paths fall back to `INTAKE_BRIEF_OUT`/`INTAKE_REGISTRY_OUT` then to
  /// `<repo>/docs/design/{brief.md,registry.json}`.
  EmitResult emit(
    Map<String, dynamic> answers, {
    String? briefOut,
    String? registryOut,
  }) {
    final errs = validateIntake(answers).errors;
    if (errs.isNotEmpty) return EmitResult.failure(errs);
    final briefPath = briefOut ?? defaultBriefOut();
    final registryPath = registryOut ?? defaultRegistryOut();
    _write(briefPath, emitBrief(answers));
    _write(
        registryPath, '${const JsonEncoder.withIndent('  ').convert(emitRegistry(answers))}\n');
    return EmitResult.ok(
      briefPath: briefPath,
      registryPath: registryPath,
      entries: (answers['surfaces'] is List) ? (answers['surfaces'] as List).length : 0,
      inferredCount: _countInferred(answers),
    );
  }

  /// Derive registry.json from a HAND-WRITTEN brief's surface table (10.7),
  /// without rewriting the brief.
  SeedResult seed(String briefPath, {String? registryOut}) {
    final md = File(briefPath).readAsStringSync();
    final registry = seedFromBrief(md);
    final out = registryOut ?? defaultRegistryOut();
    _write(out, '${const JsonEncoder.withIndent('  ').convert(registry)}\n');
    return SeedResult(registry, registryPath: out);
  }
}

int _countInferred(Map<String, dynamic> answers) {
  var n = 0;
  for (final (key, _) in _fieldTitles) {
    final node = answers[key];
    if (node is Map && node['provenance'] == 'inferred') n++;
  }
  final surfaces = answers['surfaces'];
  if (surfaces is List) {
    for (final s in surfaces) {
      if (s is Map && s['provenance'] == 'inferred') n++;
    }
  }
  return n;
}

// ----------------------------------------------------------------- io + paths

String defaultBriefOut() =>
    Platform.environment['INTAKE_BRIEF_OUT'] ?? '${repoRoot()}/docs/design/brief.md';

String defaultRegistryOut() =>
    Platform.environment['INTAKE_REGISTRY_OUT'] ?? '${repoRoot()}/docs/design/registry.json';

/// Repo root: walk up from the cwd for `config/appbox.config.json` (the same
/// discovery `appbox` uses), falling back to the cwd.
String repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/config/appbox.config.json').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}

void _write(String path, String text) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(text);
}

// ----------------------------------------------------------------- helpers

/// Strip all leading/trailing occurrences of [ch] (Python str.strip).
String _stripAll(String s, String ch) {
  final unit = ch.codeUnitAt(0);
  var start = 0, end = s.length;
  while (start < end && s.codeUnitAt(start) == unit) {
    start++;
  }
  while (end > start && s.codeUnitAt(end - 1) == unit) {
    end--;
  }
  return s.substring(start, end);
}

bool _isSeparatorCell(String c) {
  if (c.isEmpty) return false;
  for (final ch in c.split('')) {
    if (!_sepChars.contains(ch)) return false;
  }
  return true;
}

/// Python type names for JSON values, so error strings match the .py.
String _pyTypeName(Object? v) {
  if (v == null) return 'NoneType';
  if (v is bool) return 'bool';
  if (v is int) return 'int';
  if (v is double) return 'float';
  if (v is String) return 'str';
  if (v is List) return 'list';
  if (v is Map) return 'dict';
  return v.runtimeType.toString();
}
