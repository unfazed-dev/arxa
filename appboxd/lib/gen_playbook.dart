// gen_playbook.dart — render a per-kit <kit>_playbook.mdx from its facts.
//
// Dart port of
// archives/tooling-pre-dart/tools/vendor/gen_playbook/gen_playbook.py.
//
// Produces a visual-plan MDX playbook that lets a human OR an LLM use, wire,
// and extend an appbox kit WITHOUT reading its source. Mechanical sections
// (API table, integration map, features checklist) come from the kit's facts;
// narrative sections are mined from the README and mapped by header. Any
// section without a source emits a `<!-- TODO(prose): ... -->` marker for the
// prose pass.
//
// Branding: packages are `appbox_kit_*` (the facts `name`). The Stacked MVVM
// *framework* is still named where it is a genuine runtime dependency — that is
// the framework, not the `stacked_kit` repo brand, which never appears.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A README header line: 1–6 `#`, whitespace, then the title.
final RegExp _headerRe = RegExp(r'^(#{1,6})\s+(.*)');

/// Generates a playbook (.mdx content) for a kit from its facts.
///
/// [facts] is the parsed JSON from extract_facts. Recognized keys:
///   - `name` (e.g. "appbox_kit_core"), `version`, `description`, `readmeFirst`
///   - `hasTesting` (bool)
///   - `publicSurface`: list of `{name, kind, file}` (the barrel exports)
///   - `frameworkDeps`, `backingPackages`, `kitDeps`: lists of package names
///   - optional `readme`: raw README.md text — folds prose into the narrative
///     sections (Overview, Usage & wiring, Architecture, Gotchas, Testing,
///     Decisions) mined by header.
///
/// Returns the playbook markdown content as a string. Never throws on missing
/// keys — sections without a source emit a `<!-- TODO(prose): ... -->` marker.
String generatePlaybook(Map<String, dynamic> facts) {
  final name = (facts['name'] as String?) ?? 'appbox_kit';
  final slug = _slug(name);
  final desc = facts['description'] as String? ?? '';
  final readme = facts['readme'] as String? ?? '';
  final readmeFirst = (facts['readmeFirst'] as String?) ?? '';

  // README narrative mining (Python read_readme + find_section).
  final parsed = readme.isNotEmpty ? _readReadme(readme) : null;
  var intro = parsed?.intro ?? '';
  if (intro.isEmpty) intro = readmeFirst.isNotEmpty ? readmeFirst : name;
  final body = parsed?.body ?? const <String, List<String>>{};
  final hdrs = parsed?.headers ?? const <String>[];

  // Overview = description + (README intro, unless it is just the title).
  final overviewParts = <String>[];
  if (desc.isNotEmpty) overviewParts.add(desc);
  final introS = intro.trim();
  if (introS.isNotEmpty &&
      introS != name &&
      introS != readmeFirst &&
      introS != '# $name' &&
      introS != '# $name ' &&
      !introS.startsWith('#')) {
    overviewParts.add(introS);
  }
  final overview = overviewParts.join('\n\n');

  final usage =
      _find(body, hdrs, ['usage', 'quick start', 'example', 'examples']);
  final wiring = _find(
      body, hdrs, ['setup', 'install', 'wiring', 'registration', 'register']);
  final arch = _find(body, hdrs,
      ['architecture', 'dependency direction', 'design', 'layer']);
  final gotchas = _find(body, hdrs, [
    'gotcha',
    'caveat',
    'known issue',
    'note',
    'notes',
    'platform',
    'maintenance',
    'native'
  ]);
  final testingSec = _find(body, hdrs, ['testing', 'test']);
  final decisions =
      _find(body, hdrs, ['decision', 'adr', 'rationale']);

  final (api, testDoubles) = _splitSurface(facts['publicSurface']);
  final apiRows = api
      .map((s) => [s['name'] ?? '', s['kind'] ?? '', s['file'] ?? ''])
      .toList();
  final apiTable = _table(
    apiRows.isEmpty
        ? const [
            ['—', '—', 'no public symbols extracted']
          ]
        : apiRows,
    ['Symbol', 'Kind', 'Defined in'],
    '$slug-api',
  );
  final testMd = _testMarkdown(facts, testDoubles);

  final integTable = _table(
    [
      [
        _join(facts['frameworkDeps'], '—'),
        _join(facts['backingPackages'], '— (SDK only / pure Dart)'),
        _join(facts['kitDeps'], '— (standalone)'),
      ]
    ],
    ['Stacked framework deps', 'Backing SDK packages', 'Depends on (kit)'],
    '$slug-integration',
  );

  final feats = _featuresChecklist(slug, api);
  final hasTesting = facts['hasTesting'] == true;
  final testingBody = testingSec.isNotEmpty
      ? testingSec
      : (hasTesting ? '`$name` ships `lib/testing.dart`.' : '');

  final role =
      desc.isNotEmpty ? desc.split('.')[0] : (readmeFirst.isNotEmpty ? readmeFirst : name);

  final out = <String>[];
  out.add('<Callout id="header" tone="info">\n');
  out.add('# $name — Per-Package Playbook\n\n');
  out.add('`$name` v**${facts['version'] ?? '?'}** · '
      "`publish_to: 'none'` · status: **active**\n\n");
  out.add('**Role (one line):** $role.\n\n');
  out.add('**Scope of this document:** lets a human OR an LLM use, wire, and '
      'extend `$name` **without reading its source**. The public surface below '
      'was extracted from the barrel; README content is folded into the '
      'narrative sections.\n\n');
  out.add('## Table of contents\n\n'
      '0. Header & TOC — *you are here* · 1. Overview & role · 2. Public '
      'surface · 3. Usage & wiring · 4. Integration map · 5. Architecture · '
      '6. Gotchas · 7. Testing · 8. Features · 9. Decisions · 10. References '
      '· 11. Open questions\n\n');
  out.add('</Callout>\n');

  out.add(_block('Overview & role', overview,
      'summarize what $name does and when to reach for it, from the barrel doc comment and README intro'));
  out.add(_block(
      'Public surface',
      'Exported from `lib/$name.dart`:\n\n$apiTable$testMd',
      'document each exported symbol’s purpose from its doc comment'));
  out.add(_block(
      'Usage & wiring',
      [usage, wiring].where((s) => s.isNotEmpty).join('\n\n'),
      'show install + registration (locator/StackedApp) + a minimal usage snippet, from the README Usage/Setup sections'));
  out.add(_block(
      'Integration map',
      '$integTable\n\nSee `kit_matrix.md` for the full routing + dependency graph.',
      'annotate the integration map'));
  out.add(_block('Architecture', arch,
      'describe the port/adapter or service structure and dependency direction of $name'));
  out.add(_block(
      'Gotchas', gotchas,
      'list platform setup (native permissions/manifest keys), maintenance risks, and known pitfalls from the README'));
  out.add(_block('Testing', testingBody,
      'explain the test seam: how fakes are scripted and what call-counts are asserted'));
  out.add(_block('Features', feats, 'annotate the feature checklist'));
  out.add(_block(
      'Decisions / ADRs', decisions,
      'record why $name chose its backing packages / standalone stance, from the README and kit_matrix decisions log'));

  out.add('<!-- kb:begin -->\n### References\n<!-- kb:end -->\n');
  out.add(_qform(slug));
  out.add('\n');
  return out.join('\n');
}

/// Loads a kit's facts from disk and folds its README in for narrative mining.
///
/// [factsFile] is the JSON produced by extract_facts (e.g.
/// `memory/facts/<kit>.json`). [kitDir] is the kit's source directory; its
/// `README.md`, when present, is attached as `facts['readme']`. Pass the
/// returned map to [generatePlaybook].
Map<String, dynamic> loadKitFacts(File factsFile, Directory kitDir) {
  final facts =
      jsonDecode(factsFile.readAsStringSync()) as Map<String, dynamic>;
  final readme = File(p.join(kitDir.path, 'README.md'));
  if (readme.existsSync()) {
    facts['readme'] = readme.readAsStringSync();
  }
  return facts;
}

// --- module helpers ---------------------------------------------------------

/// Short id slug for a kit: `appbox_kit_core` -> `core`.
String _slug(String name) {
  const prefix = 'appbox_kit_';
  return name.startsWith(prefix) ? name.substring(prefix.length) : name;
}

/// `['a','b']` -> `"a, b"`; empty/null -> [empty].
String _join(dynamic list, String empty) {
  if (list is! List || list.isEmpty) return empty;
  return list.map((e) => e.toString()).join(', ');
}

/// A `### Title` section: the body when present, else a prose TODO marker.
String _block(String title, String body, String fallbackTodo) {
  final b = body.trim();
  if (b.isNotEmpty) return '\n### $title\n\n$b\n';
  return '\n### $title\n\n<!-- TODO(prose): $fallbackTodo -->\n';
}

/// `<Table id=... columns={[...]} rows={[[...]]} />`.
String _table(List<List<String>> rows, List<String> columns, String blockId) {
  return '<Table id="$blockId" columns={${jsonEncode(columns)}} '
      'rows={${jsonEncode(rows)}} />';
}

/// `<Checklist id=... items={[{id,label}, ...]} />`.
String _checklist(List<({String id, String label})> items, String blockId) {
  final objs = items
      .map((it) => <String, String>{'id': it.id, 'label': it.label})
      .toList();
  return '<Checklist id="$blockId" items={${jsonEncode(objs)}} />';
}

/// First 12 public symbols as a feature checklist; a placeholder when empty.
String _featuresChecklist(String slug, List<Map<String, String>> api) {
  final items = <({String id, String label})>[
    for (var i = 0; i < api.length && i < 12; i++)
      (
        id: '$slug-feat-$i',
        label: '`${api[i]['name']}` — ${api[i]['kind']}',
      ),
  ];
  if (items.isEmpty) {
    items.add((id: '$slug-feat-0', label: 'See README for the feature list'));
  }
  return _checklist(items, '$slug-features');
}

/// Prose about test doubles + the call-count note when the kit ships testing.
String _testMarkdown(
    Map<String, dynamic> facts, List<Map<String, String>> testDoubles) {
  var md = '';
  if (testDoubles.isNotEmpty) {
    md = '\n\nTest doubles in `lib/testing.dart`: '
        '${testDoubles.map((s) => '`${s['name']}`').join(', ')}.';
  }
  if (facts['hasTesting'] == true) {
    md += '\n\nScripts and call-counts — tests never touch platform channels.';
  }
  return md;
}

/// `<QuestionForm id="open-questions" .../>` (JS-object syntax, not JSON).
String _qform(String slug) {
  return '<QuestionForm id="open-questions" questions={[\n'
      '  {\n'
      '    id: "q-$slug-gaps",\n'
      '    title: "What is unclear or missing from this playbook?",\n'
      '    mode: "freeform",\n'
      '    placeholder: "Note anything a new contributor or agent would need that is not covered above.",\n'
      '  },\n'
      ']} />';
}

/// Splits a barrel's public surface into API symbols vs test doubles.
/// A symbol is a test double when it lives in `testing.dart` or its name
/// begins with a fake/recording/scripted/stub prefix.
(List<Map<String, String>>, List<Map<String, String>>) _splitSurface(
    dynamic raw) {
  final api = <Map<String, String>>[];
  final test = <Map<String, String>>[];
  if (raw is! List) return (api, test);
  for (final e in raw) {
    if (e is! Map) continue;
    final s = <String, String>{
      for (final entry in e.entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    };
    final isTest = (s['file'] ?? '') == 'testing.dart' ||
        const ['Fake', 'Recording', 'Scripted', 'Stub']
            .any((pre) => (s['name'] ?? '').startsWith(pre));
    (isTest ? test : api).add(s);
  }
  return (api, test);
}

/// Parses a README into (intro, {header: bodyLines}, headers-in-order).
/// Only level-1/2 headers open a section (matches the Python port).
({String intro, Map<String, List<String>> body, List<String> headers})
    _readReadme(String readme) {
  final intro = <String>[];
  final body = <String, List<String>>{};
  final headers = <String>[];
  String? cur;
  for (final ln in readme.split('\n')) {
    final m = _headerRe.firstMatch(ln);
    if (m != null && m.group(1)!.length <= 2) {
      cur = m.group(2)!.trim();
      body[cur] = <String>[];
      headers.add(cur);
    } else if (cur == null) {
      intro.add(ln);
    } else {
      body[cur]!.add(ln);
    }
  }
  return (intro: intro.join('\n').trim(), body: body, headers: headers);
}

/// First README section whose header contains any of [needles] (substring,
/// case-insensitive); '' when none matches.
String _find(Map<String, List<String>> body, List<String> headers,
    List<String> needles) {
  for (final h in headers) {
    final hl = h.toLowerCase();
    if (needles.any((n) => hl.contains(n))) {
      return (body[h] ?? const <String>[]).join('\n').trim();
    }
  }
  return '';
}
