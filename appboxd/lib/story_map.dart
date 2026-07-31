// story_map — Dart port of skills/appbox-story-mapper/scripts/generate_story_map.py
// (495 lines, pure stdlib). Emits the Epic → Feature → Story user story map
// (HTML + JSON + gate-compatible design brief) from a story-map.json input.
//
// Pure functions + File-based I/O; matches the package's top-level-function
// convention (emit_structure.dart, validate_docs.dart). Output must be
// byte-identical to the Python original so the intake gate (plan 10.7) sees
// the same surface ids + markup — the surface table is the traceability source.

import 'dart:convert';

// ── priorities ─────────────────────────────────────────────────────

const validPriorities = {'must', 'should', 'could', 'wont'};

const _priorityOrder = ['must', 'should', 'could', 'wont'];

class _PriMeta {
  const _PriMeta(this.label, this.color, this.bg, this.border);
  final String label;
  final String color;
  final String bg;
  final String border;
}

const priorityMeta = <String, _PriMeta>{
  'must': _PriMeta('Must Have', '#dc2626', '#fef2f2', '#fca5a5'),
  'should': _PriMeta('Should Have', '#ea580c', '#fff7ed', '#fdba74'),
  'could': _PriMeta('Could Have', '#2563eb', '#eff6ff', '#93c5fd'),
  'wont': _PriMeta("Won't Have", '#6b7280', '#f9fafb', '#d1d5db'),
};

const _priorityRank = <String, int>{
  'must': 0,
  'should': 1,
  'could': 2,
  'wont': 3,
};

// Reverse of _priorityRank — rank → priority string.
const _rankToPriority = <int, String>{0: 'must', 1: 'should', 2: 'could', 3: 'wont'};

const epicPalette = [
  '#6366f1',
  '#8b5cf6',
  '#06b6d4',
  '#10b981',
  '#f59e0b',
  '#ef4444',
  '#ec4899',
  '#14b8a6',
];

const colWidth = 210;

// `^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$` — the gate's registry id pattern.
// Surface ids emitted here MUST match it (lowercase alnum segments, no hyphens).
final idRe = RegExp(r'^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$');
final _slugWordRe = RegExp(r'[a-z0-9]+');

// ── data model ─────────────────────────────────────────────────────

/// One derived surface (Epic → shell, Feature → surface). A feature whose
/// stories are all "wont" is [OutOfScope], not a surface. [priority]/[release]
/// are the rollup: strongest live priority + earliest live release (blank when
/// the feature has no live stories).
class Surface {
  const Surface({
    required this.id,
    required this.label,
    required this.epic,
    required this.stories,
    required this.priority,
    required this.release,
  });
  final String id;
  final String label;
  final String epic;
  final List<Map<String, dynamic>> stories;
  final String priority;
  final String release;
}

/// A feature parked this cycle because every story is "wont".
class OutOfScope {
  const OutOfScope(this.epic, this.feature);
  final String epic;
  final String feature;

  @override
  bool operator ==(Object other) =>
      other is OutOfScope && other.epic == epic && other.feature == feature;
  @override
  int get hashCode => Object.hash(epic, feature);
  @override
  String toString() => 'OutOfScope($epic, $feature)';
}

/// Result of [deriveSurfaces]: live surfaces + parked features.
class Surfaces {
  const Surfaces(this.surfaces, this.outOfScope);
  final List<Surface> surfaces;
  final List<OutOfScope> outOfScope;
}

// ── validation ─────────────────────────────────────────────────────

/// Validate a story-map document. Returns the error list (empty = ok). Error
/// strings are part of the contract — gates/intake and the CLI match on them.
List<String> validateData(Map<String, dynamic> data) {
  final errors = <String>[];
  if (!_hasName(data['project'])) {
    errors.add("Missing required field: 'project'");
  }
  final releases = data['releases'];
  if (releases is! List || releases.isEmpty) {
    errors.add("Missing or empty 'releases' array");
  }
  final epics = data['epics'];
  if (epics is! List || epics.isEmpty) {
    errors.add("Missing or empty 'epics' array");
  }
  if (errors.isNotEmpty) return errors;

  final releaseNames = <String>{};
  for (var i = 0; i < releases.length; i++) {
    final rel = releases[i];
    if (_missingName(rel)) {
      errors.add("releases[$i]: missing 'name'");
    } else {
      releaseNames.add(rel['name'] as String);
    }
  }

  for (var ei = 0; ei < epics.length; ei++) {
    final epic = epics[ei];
    if (_missingName(epic)) {
      errors.add("epics[$ei]: missing 'name'");
      continue;
    }
    final feats = epic['features'];
    if (feats is! List || feats.isEmpty) {
      errors.add("Epic '${epic['name']}': missing or empty 'features'");
      continue;
    }
    for (var fi = 0; fi < feats.length; fi++) {
      final feat = feats[fi];
      if (_missingName(feat)) {
        errors.add("Epic '${epic['name']}' features[$fi]: missing 'name'");
        continue;
      }
      final storiesRaw = feat['stories'];
      final stories = storiesRaw is List ? storiesRaw : const [];
      for (var si = 0; si < stories.length; si++) {
        final story = stories[si];
        final tag = "'${feat['name']}' story[$si]";
        if (_missingName(story)) {
          errors.add('$tag: missing \'name\'');
          continue;
        }
        final pri = (story['priority'] as String?) ?? '';
        if (!validPriorities.contains(pri)) {
          errors.add("$tag '${story['name']}': invalid priority '$pri'");
        }
        final rel = (story['release'] as String?) ?? '';
        if (!releaseNames.contains(rel)) {
          errors.add("$tag '${story['name']}': unknown release '$rel'");
        }
      }
    }
  }
  return errors;
}

// ── surfaces ───────────────────────────────────────────────────────

/// First ascii word of [name] as a `[a-z][a-z0-9]*` slug; collisions get a digit
/// suffix (starting at 2). CJK-only names fall back to 's'. Mutates [used] so
/// callers share a namespace.
String slugify(String name, Set<String> used) {
  final words = _slugWordRe.allMatches(name.toLowerCase()).map((m) => m.group(0)!);
  String slug = 's';
  for (final w in words) {
    if (w.isNotEmpty && _isAlpha(w.codeUnitAt(0))) {
      slug = w;
      break;
    }
  }
  final base = slug;
  var n = 2;
  while (used.contains(slug)) {
    slug = '$base$n';
    n++;
  }
  used.add(slug);
  return slug;
}

bool _isAlpha(int c) => c >= 0x61 && c <= 0x7a; // a-z

/// True if [v] is a non-empty string — the "has a usable name" check used by
/// [validateData]. A missing/empty/non-string name is a validation defect.
bool _hasName(dynamic v) => v is String && v.isNotEmpty;

/// [v] is not a map, or its 'name' is missing/empty.
bool _missingName(dynamic v) {
  if (v is! Map<String, dynamic>) return true;
  return !_hasName(v['name']);
}

/// Derive surfaces + out-of-scope features from a validated [data] document.
Surfaces deriveSurfaces(Map<String, dynamic> data) {
  final usedShells = <String>{};
  final usedIds = <String>{};
  final relOrder = <String, int>{
    for (var i = 0; i < (data['releases'] as List).length; i++)
      ((data['releases'] as List)[i] as Map<String, dynamic>)['name'] as String: i,
  };
  final surfaces = <Surface>[];
  final outOfScope = <OutOfScope>[];
  for (final epic in (data['epics'] as List).cast<Map<String, dynamic>>()) {
    final shell = slugify(epic['name'] as String, usedShells);
    for (final feat
        in (epic['features'] as List).cast<Map<String, dynamic>>()) {
      final stories = ((feat['stories'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      if (stories.isNotEmpty &&
          stories.every((s) => s['priority'] == 'wont')) {
        outOfScope.add(OutOfScope(epic['name'] as String, feat['name'] as String));
        continue;
      }
      final live = stories.where((s) => s['priority'] != 'wont').toList();
      int? minRank;
      for (final s in live) {
        final r = _priorityRank[s['priority'] as String]!;
        if (minRank == null || r < minRank) minRank = r;
      }
      final priority = minRank == null ? '' : _rankToPriority[minRank]!;
      var release = '';
      int? minOrder;
      for (final s in live) {
        final rel = (s['release'] as String?) ?? '';
        final order = relOrder[rel] ?? relOrder.length;
        if (minOrder == null || order < minOrder) {
          minOrder = order;
          release = rel;
        }
      }
      surfaces.add(Surface(
        id: '$shell.${slugify(feat['name'] as String, usedIds)}',
        label: feat['name'] as String,
        epic: epic['name'] as String,
        stories: stories,
        priority: priority,
        release: release,
      ));
    }
  }
  return Surfaces(surfaces, outOfScope);
}

// ── brief ──────────────────────────────────────────────────────────

/// Render the gate-compatible design brief. Pass [derived] to reuse a prior
/// [deriveSurfaces] call (the CLI does, for the surface count); otherwise it
/// is derived here.
String renderBrief(Map<String, dynamic> data, [Surfaces? derived]) {
  final d = derived ?? deriveSurfaces(data);
  final lines = <String>[
    "# ${data['project']} — design brief",
    '',
    'Elicited via appbox-story-mapper; the full story map lives alongside',
    'this brief (`story-map.json`, `story_map.html`). Priorities are MoSCoW,',
    'grouped into release swimlanes. Every registry surface must trace to',
    'the surface inventory table below (gates/intake, plan 10.7).',
    '',
    '## Product',
    '',
    data['project'] as String,
    '',
    '## Releases',
    '',
  ];
  for (final rel in (data['releases'] as List).cast<Map<String, dynamic>>()) {
    final desc = rel['description'] is String
        ? ' — ${rel['description'] as String}'
        : '';
    lines.add("- **${rel['name']}**$desc");
  }
  lines
    ..add('')
    ..add('## The things the app must do')
    ..add('');
  for (final epic in (data['epics'] as List).cast<Map<String, dynamic>>()) {
    lines.add('### ${epic['name']}');
    lines.add('');
    for (final feat
        in ((epic['features'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      lines.add('#### ${feat['name']}');
      lines.add('');
      for (final s
          in ((feat['stories'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        final desc =
            s['description'] is String ? ' — ${s['description'] as String}' : '';
        final pri = (s['priority'] as String?) ?? '?';
        final rel = (s['release'] as String?) ?? '?';
        lines.add('- [$pri/$rel] ${s['name']}$desc');
      }
      lines.add('');
    }
  }
  lines
    ..add('## Surface inventory')
    ..add('')
    ..add('| id | label | priority | release |')
    ..add('|----|-------|----------|---------|');
  for (final s in d.surfaces) {
    lines.add('| `${s.id}` | ${s.label} | ${s.priority} | ${s.release} |');
  }
  lines.add('');
  if (d.outOfScope.isNotEmpty) {
    lines.add('## Out of scope');
    lines.add('');
    for (final o in d.outOfScope) {
      lines.add("- ${o.feature} (${o.epic}) — all stories Won't-have this cycle");
    }
    lines.add('');
  }
  return lines.join('\n');
}

// ── HTML ───────────────────────────────────────────────────────────

/// Python `html.escape` (quote=True): & < > " '.
String _esc(String s) {
  if (s.isEmpty) return s;
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

int _points(dynamic s) => s is num ? s.toInt() : 0;

/// Render the interactive story-map HTML. [now] pins the "Generated" stamp
/// (defaults to local now, matching the Python `datetime.now()`); callers that
/// need byte-stable output pass an explicit value.
String renderHtml(Map<String, dynamic> data, {String? now}) {
  final project = _esc(data['project'] as String);
  final releases = (data['releases'] as List).cast<Map<String, dynamic>>();
  final epics = (data['epics'] as List).cast<Map<String, dynamic>>();
  final nowStr = now ?? _formatNow(DateTime.now());

  // Flatten features with their epic index, in document order. The feature
  // index `fi` is the column key used by story_lookup.
  final featList = <_FeatureEntry>[];
  for (var ei = 0; ei < epics.length; ei++) {
    for (final feat
        in ((epics[ei]['features'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      featList.add(_FeatureEntry(ei, feat));
    }
  }
  final totalCols = featList.length;

  // story_lookup[(fi, releaseName)] -> stories; plus all-stories for the stats.
  final storyLookup = <String, List<Map<String, dynamic>>>{};
  final allStories = <Map<String, dynamic>>[];
  for (var fi = 0; fi < featList.length; fi++) {
    final stories =
        ((featList[fi].feat['stories'] as List?) ?? const []).cast<Map<String, dynamic>>();
    for (final story in stories) {
      final rel = (story['release'] as String?) ?? '';
      final key = '$fi|$rel';
      storyLookup.putIfAbsent(key, () => []).add(story);
      allStories.add(story);
    }
  }

  final totalStories = allStories.length;
  final totalPoints = allStories.fold<int>(0, (a, s) => a + _points(s['points']));

  String statsHtml() {
    final parts = <String>[
      '<span class="stat-item"><b>$totalStories</b> Stories</span>',
    ];
    if (totalPoints != 0) {
      parts.add('<span class="stat-item"><b>$totalPoints</b> Points</span>');
    }
    parts.add('<span class="stat-sep">|</span>');
    for (final p in _priorityOrder) {
      final m = priorityMeta[p]!;
      final cnt = allStories.where((s) => s['priority'] == p).length;
      final pts =
          allStories.fold<int>(0, (a, s) => a + (s['priority'] == p ? _points(s['points']) : 0));
      final badge = pts == 0 ? '$cnt' : '$cnt (${pts}pt)';
      parts.add('<span class="stat-badge" style="background:${m.bg};color:${m.color};'
          'border:1px solid ${m.border}">${_esc(m.label)} $badge</span>');
    }
    parts.add('<span class="stat-sep">|</span>');
    for (final rel in releases) {
      final rn = _esc(rel['name'] as String);
      final cnt = allStories.where((s) => s['release'] == rel['name']).length;
      parts.add('<span class="stat-item">$rn: <b>$cnt</b></span>');
    }
    return parts.join('\n');
  }

  String epicRow() {
    final cells = <String>[];
    for (var ei = 0; ei < epics.length; ei++) {
      final span = ((epics[ei]['features'] as List?) ?? const []).length;
      if (span == 0) continue;
      final color = epicPalette[ei % epicPalette.length];
      final w = span * colWidth;
      cells.add('<div class="epic-cell" style="width:${w}px;background:$color">'
          '${_esc(epics[ei]['name'] as String)}</div>');
    }
    return cells.join();
  }

  String featureRow() {
    final cells = <String>[];
    for (final fe in featList) {
      final color = epicPalette[fe.ei % epicPalette.length];
      cells.add('<div class="feat-cell" style="width:${colWidth}px;'
          'border-top:3px solid $color">${_esc(fe.feat['name'] as String)}</div>');
    }
    return cells.join();
  }

  String storyCard(Map<String, dynamic> story) {
    final pri = (story['priority'] as String?) ?? 'must';
    final m = priorityMeta[pri] ?? priorityMeta['must']!;
    final name = _esc((story['name'] as String?) ?? '');
    final desc = _esc((story['description'] as String?) ?? '');
    final pts = story['points'];
    final ptsHtml = (pts != null && pts != 0)
        ? '<span class="card-pts">$pts pt</span>'
        : '';
    final descHtml = desc.isNotEmpty ? '<div class="card-desc">$desc</div>' : '';
    final titleAttr = desc.isNotEmpty ? ' title="$desc"' : '';
    return '<div class="story-card" style="border-left:4px solid ${m.color};'
        'background:${m.bg}"$titleAttr>'
        '<div class="card-title">$name</div>'
        '$descHtml'
        '<div class="card-footer">'
        '<span class="card-pri" style="color:${m.color}">${_esc(m.label)}</span>'
        '$ptsHtml'
        '</div></div>';
  }

  String releaseSections() {
    final sections = <String>[];
    for (final rel in releases) {
      final rname = rel['name'] as String;
      final rdesc = rel['description'];
      var label = _esc(rname);
      if (rdesc is String && rdesc.isNotEmpty) {
        label += ' <span class="rel-desc">— ${_esc(rdesc)}</span>';
      }
      final cols = <String>[];
      for (var fi = 0; fi < totalCols; fi++) {
        final stories = storyLookup['$fi|$rname'] ?? const [];
        var cards = stories.map(storyCard).join();
        if (cards.isEmpty) cards = '<div class="empty-slot"></div>';
        cols.add('<div class="story-col" style="width:${colWidth}px">$cards</div>');
      }
      sections.add('<div class="release-section">'
          '<div class="release-divider">'
          '<div class="release-line"></div>'
          '<div class="release-badge">$label</div>'
          '</div>'
          '<div class="map-row stories-row">${cols.join()}</div>'
          '</div>');
    }
    return sections.join();
  }

  final legendHtml = _priorityOrder.map((p) {
    final m = priorityMeta[p]!;
    return '<span class="legend-item"><span class="legend-dot" '
        'style="background:${m.color}"></span>${_esc(m.label)}</span>';
  }).join();

  final stats = statsHtml();
  final epicRowHtml = epicRow();
  final featureRowHtml = featureRow();
  final releaseSectionsHtml = releaseSections();
  final mapW = totalCols * colWidth;

  return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$project — User Story Map</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,
"Noto Sans SC","PingFang SC","Microsoft YaHei",sans-serif;background:#f1f5f9;color:#1e293b;
line-height:1.5;min-height:100vh}
.container{max-width:100%;padding:20px}
header{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;
margin-bottom:16px;gap:12px}
h1{font-size:1.5rem;font-weight:700;color:#0f172a}
.meta{font-size:.8rem;color:#64748b}
.legend{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
.legend-item{display:flex;align-items:center;gap:4px;font-size:.78rem}
.legend-dot{width:12px;height:12px;border-radius:3px}
.stats-bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:10px 16px;
background:#fff;border-radius:8px;margin-bottom:16px;box-shadow:0 1px 3px rgba(0,0,0,.06);
font-size:.82rem}
.stat-item b{color:#0f172a}
.stat-sep{color:#cbd5e1;margin:0 2px}
.stat-badge{padding:2px 8px;border-radius:4px;font-size:.78rem;font-weight:500}
.map-scroll{overflow-x:auto;padding-bottom:16px}
.map-inner{min-width:${mapW}px}
.map-row{display:flex}
.epic-cell{color:#fff;font-weight:700;font-size:.92rem;padding:10px 12px;text-align:center;
border-radius:6px 6px 0 0;margin-right:1px}
.feat-cell{background:#fff;font-weight:600;font-size:.82rem;padding:8px 10px;text-align:center;
border-right:1px solid #e2e8f0;margin-bottom:0}
.release-section{margin-top:0}
.release-divider{position:relative;display:flex;align-items:center;margin:14px 0 8px}
.release-line{flex:1;height:2px;background:repeating-linear-gradient(
90deg,#94a3b8 0,#94a3b8 6px,transparent 6px,transparent 12px)}
.release-badge{position:absolute;left:0;background:#fff;padding:2px 14px;border-radius:12px;
font-size:.82rem;font-weight:700;color:#334155;border:2px solid #94a3b8;white-space:nowrap}
.release-badge .rel-desc{font-weight:400;color:#64748b;font-size:.78rem}
.stories-row{gap:1px}
.story-col{padding:4px 4px 8px;min-height:40px;display:flex;flex-direction:column;gap:6px}
.story-card{border-radius:6px;padding:8px 10px;cursor:default;transition:box-shadow .15s,
transform .15s;box-shadow:0 1px 2px rgba(0,0,0,.05)}
.story-card:hover{box-shadow:0 4px 12px rgba(0,0,0,.1);transform:translateY(-1px)}
.card-title{font-size:.82rem;font-weight:600;color:#1e293b;margin-bottom:2px}
.card-desc{font-size:.72rem;color:#64748b;margin-bottom:4px;display:-webkit-box;
-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.card-footer{display:flex;justify-content:space-between;align-items:center}
.card-pri{font-size:.7rem;font-weight:600}
.card-pts{font-size:.7rem;color:#475569;background:#f1f5f9;padding:1px 6px;border-radius:3px}
.empty-slot{min-height:20px}
.print-btn{position:fixed;bottom:20px;right:20px;padding:8px 20px;background:#6366f1;color:#fff;
border:none;border-radius:8px;font-size:.85rem;cursor:pointer;box-shadow:0 2px 8px rgba(99,102,241,.3);
z-index:100}
.print-btn:hover{background:#4f46e5}
@media print{
  body{background:#fff;-webkit-print-color-adjust:exact;print-color-adjust:exact}
  .container{padding:8px}
  .print-btn{display:none}
  .map-scroll{overflow:visible}
  @page{size:A3 landscape;margin:10mm}
}
</style>
</head>
<body>
<div class="container">
<header>
  <div>
    <h1>$project</h1>
    <div class="meta">User Story Map &middot; Generated $nowStr</div>
  </div>
  <div class="legend">
    $legendHtml
  </div>
</header>
<div class="stats-bar">
$stats
</div>
<div class="map-scroll">
<div class="map-inner">
  <div class="map-row epic-row-wrap">$epicRowHtml</div>
  <div class="map-row feat-row-wrap">$featureRowHtml</div>
  $releaseSectionsHtml
</div>
</div>
</div>
<button class="print-btn" onclick="window.print()">&#128424; Print</button>
</body>
</html>''';
}

class _FeatureEntry {
  const _FeatureEntry(this.ei, this.feat);
  final int ei;
  final Map<String, dynamic> feat;
}

String _formatNow(DateTime t) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
}

// ── data-out serialization ─────────────────────────────────────────

/// Serialize the validated story-map data as 2-space-indented UTF-8 JSON with a
/// trailing newline — matches Python `json.dump(..., ensure_ascii=False,
/// indent=2)` + `f.write("\n")`.
String serializeDataJson(Map<String, dynamic> data) {
  return '${const JsonEncoder.withIndent('  ').convert(data)}\n';
}
