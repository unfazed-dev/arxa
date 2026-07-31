// kb_build.dart — render the knowledge base from kb/sources.json +
// memory/facts, and generate the playbooks index. Combined port of the two
// Python tools tools/kb_build.py and tools/build_toc.py.
//
// buildKb:
//   - writes kb/KB.md (index + per-kit coverage table) and kb/<domain>.md pages
//   - mines each kit's backingPackages into per-kit pub.dev source refs
//   - injects a generated References block into every <kit>/<kit>_playbook.mdx
//     between the <!-- kb:begin --> / <!-- kb:end --> markers (idempotent — the
//     block is deterministic, so a second run writes nothing)
//
// buildToc:
//   - writes playbooks.md (human TOC) + llms.txt (agent entry point) from facts
//
// Branding: the Python source emitted "stacked_kit"; this port emits "appbox kit".
// The fact schema is the kit schema the Python tools expect
// ({kit, name, description?, readmeFirst?, readmeLines?, backingPackages}), NOT
// the array-of-{fact,source,ts} notes used elsewhere in this repo's memory/.

library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// domain key -> (page filename under kb/, page heading). A page is written for
/// each of the five domains even when it has zero sources.
const domains = <String, ({String file, String heading})>{
  'stacked': (file: 'stacked.md', heading: 'Stacked framework'),
  'flutter': (file: 'flutter.md', heading: 'Flutter'),
  'dart': (file: 'dart.md', heading: 'Dart'),
  'mcp': (file: 'mcp.md', heading: 'MCP servers'),
  'community': (file: 'community.md', heading: 'Community sources'),
};

/// A curated source — one row of kb/sources.json, or a mined package ref.
class Source {
  final String id;
  final String title;
  final String url;
  final String kind; // official | package | mcp | community | ...
  final String domain;
  final List<String> kits; // kit folder names, or ["*"] for all kits
  final String? notes;

  const Source({
    required this.id,
    required this.title,
    required this.url,
    required this.kind,
    required this.domain,
    required this.kits,
    this.notes,
  });

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        id: j['id'] as String,
        title: j['title'] as String,
        url: j['url'] as String,
        kind: j['kind'] as String,
        domain: j['domain'] as String,
        kits: ((j['kits'] as List?) ?? const []).cast<String>(),
        notes: j['notes'] as String?,
      );
}

/// A kit fact — `memory/facts/<kit>.json` (the kit schema, not the notes schema).
class Fact {
  final String kit;
  final String name;
  final String? description;
  final String? readmeFirst;
  final int? readmeLines;
  final List<String> backingPackages;

  const Fact({
    required this.kit,
    required this.name,
    this.description,
    this.readmeFirst,
    this.readmeLines,
    this.backingPackages = const [],
  });

  factory Fact.fromJson(Map<String, dynamic> j) => Fact(
        kit: j['kit'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        readmeFirst: j['readmeFirst'] as String?,
        readmeLines: j['readmeLines'] as int?,
        backingPackages:
            ((j['backingPackages'] as List?) ?? const []).cast<String>(),
      );
}

/// Outcome of [buildKb]. Mirrors the two lines the Python main() printed.
class KbBuildResult {
  /// Sources read from kb/sources.json (excludes mined package refs).
  final int registrySources;

  /// Total backing-package refs mined from facts.
  final int minedPackageRefs;

  /// Always 5 — one page per entry in [domains].
  final int domainPages;

  /// Number of `` `<kit>_playbook.mdx` `` files found on disk (and processed).
  final int injectedPlaybooks;

  const KbBuildResult({
    required this.registrySources,
    required this.minedPackageRefs,
    required this.domainPages,
    required this.injectedPlaybooks,
  });
}

/// Outcome of [buildToc]. Carries the generated content so callers (and tests)
/// can inspect it without re-reading the files.
class TocResult {
  final int kitCount;
  final String playbooksMd;
  final String llmsTxt;

  const TocResult({
    required this.kitCount,
    required this.playbooksMd,
    required this.llmsTxt,
  });
}

/// Builds KB index + domain pages from sources.json + facts, and injects
/// References blocks into each kit playbook.
///
/// [repoRoot] is the app-box root. Reads `kb/sources.json` and
/// `memory/facts/*.json`; writes `kb/KB.md`, `kb/<domain>.md`, and rewrites any
/// `<repoRoot>/<kit>/<kit>_playbook.mdx`. Creates `kb/` if it does not exist.
KbBuildResult buildKb(String repoRoot) {
  final kbDir = p.join(repoRoot, 'kb');
  final factsDir = p.join(repoRoot, 'memory', 'facts');
  Directory(kbDir).createSync(recursive: true);

  final facts = _loadFacts(factsDir);
  final srcs = _loadSources(kbDir);
  final registryN = srcs.length;
  final mined = <Source>[];
  for (final kit in facts.keys.toList()..sort()) {
    mined.addAll(_kitPackageSources(kit, facts[kit]!));
  }
  srcs.addAll(mined);

  _buildDomainPages(repoRoot, srcs);
  _buildIndex(kbDir, srcs, facts);
  final injected = injectReferences(repoRoot, srcs, facts);

  return KbBuildResult(
    registrySources: registryN,
    minedPackageRefs: mined.length,
    domainPages: domains.length,
    injectedPlaybooks: injected,
  );
}

/// Generates playbooks.md + llms.txt from facts.
///
/// [repoRoot] is the app-box root. Reads `memory/facts/*.json`; writes
/// `playbooks.md` and `llms.txt` at the repo root.
TocResult buildToc(String repoRoot) {
  final facts = _loadFacts(p.join(repoRoot, 'memory', 'facts'));
  final playbooksMd = _buildPlaybooksMd(facts);
  final llmsTxt = _buildLlmsTxt(facts);
  File(p.join(repoRoot, 'playbooks.md')).writeAsStringSync(playbooksMd);
  File(p.join(repoRoot, 'llms.txt')).writeAsStringSync(llmsTxt);
  return TocResult(
    kitCount: facts.length,
    playbooksMd: playbooksMd,
    llmsTxt: llmsTxt,
  );
}

// ---------------------------------------------------------------------------
// kb_build half
// ---------------------------------------------------------------------------

/// Load kb/sources.json. A missing file (fresh kb/ dir) yields an empty list.
List<Source> _loadSources(String kbDir) {
  final f = File(p.join(kbDir, 'sources.json'));
  if (!f.existsSync()) return <Source>[]; // growable: buildKb appends mined refs
  final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final list = (raw['sources'] as List?) ?? const [];
  return list.map((e) => Source.fromJson(e as Map<String, dynamic>)).toList();
}

/// Load every memory/facts/*.json, keyed by fact.kit. Missing dir -> empty.
/// File order is sorted so the result is deterministic regardless of listdir
/// order (the Python tools re-sort by kit in every consumer anyway).
Map<String, Fact> _loadFacts(String factsDir) {
  final facts = <String, Fact>{};
  final d = Directory(factsDir);
  if (!d.existsSync()) return facts;
  final files = d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final fact = Fact.fromJson(raw);
    facts[fact.kit] = fact;
  }
  return facts;
}

/// Per-kit package sources mined from a fact's backingPackages (pub.dev links).
List<Source> _kitPackageSources(String kit, Fact fact) {
  return fact.backingPackages
      .map((pkg) => Source(
            id: 'pkg-$kit-$pkg',
            title: '$pkg (pub.dev)',
            url: 'https://pub.dev/packages/$pkg',
            kind: 'package',
            domain: 'flutter',
            kits: [kit],
            notes: '$pkg — backing dependency of ${fact.name}.',
          ))
      .toList();
}

/// Format a markdown list-item link from a source, with an optional
/// `" — <notes>"` suffix when notes are present.
String mdLink(Source s) {
  final note = (s.notes == null || s.notes!.isEmpty) ? '' : ' — ${s.notes}';
  return '- [${s.title}](${s.url})$note';
}

/// Write `kb/<domain>.md` for each of the five domains, grouping package sources
/// by kit for readability (mirrors the Python page layout, blank lines and all).
void _buildDomainPages(String repoRoot, List<Source> srcs) {
  final byDomain = <String, List<Source>>{};
  for (final s in srcs) {
    byDomain.putIfAbsent(s.domain, () => []).add(s);
  }
  for (final entry in domains.entries) {
    final domain = entry.key;
    final page = entry.value;
    final items = byDomain[domain] ?? const <Source>[];
    final body = <String>[
      '# ${page.heading}',
      '',
      '${items.length} curated source(s).',
      '',
    ];
    final pkgs = items.where((s) => s.kind == 'package').toList();
    final others = items.where((s) => s.kind != 'package').toList();
    for (final s in others) {
      body.add(mdLink(s));
    }
    if (pkgs.isNotEmpty) {
      body.add('\n## Backing packages (per kit)\n');
      final byKit = <String, List<Source>>{};
      for (final s in pkgs) {
        for (final k in s.kits) {
          byKit.putIfAbsent(k, () => []).add(s);
        }
      }
      for (final k in byKit.keys.toList()..sort()) {
        body.add('\n**$k**\n');
        for (final s in byKit[k]!) {
          body.add(mdLink(s));
        }
      }
    }
    File(p.join(repoRoot, 'kb', page.file))
        .writeAsStringSync('${body.join('\n')}\n');
  }
}

/// Write kb/KB.md — the index + per-kit coverage table. Coverage: a source with
/// kits ["*"] counts for every kit that has a fact; otherwise only its explicit
/// kit matches count. Kits below 3 sources are flagged.
void _buildIndex(String kbDir, List<Source> srcs, Map<String, Fact> facts) {
  final kits = facts.keys.toList()..sort();
  final coverage = {for (final k in kits) k: <String, String>{}};
  for (final s in srcs) {
    final targets = s.kits.contains('*')
        ? kits
        : s.kits.where((k) => coverage.containsKey(k)).toList();
    for (final k in targets) {
      coverage[k]![s.id] = s.title;
    }
  }
  final rows = <String>[];
  for (final k in kits) {
    final n = coverage[k]!.length;
    final flag = n >= 3 ? '' : ' **< 3 — add sources**';
    rows.add('| $k | $n | [`${k}_playbook.mdx`](../$k/${k}_playbook.mdx) |$flag');
  }
  final body = <String>[
    '# appbox kit knowledge base',
    '',
    'Curated appbox kit / Flutter / Dart documentation, MCP servers, and per-kit',
    'backing-package references. Generated from `kb/sources.json` — edit the',
    'registry, not the pages.',
    '',
    '## Domains',
    '',
    '- [Stacked framework](stacked.md) · [Flutter](flutter.md) · [Dart](dart.md) · [MCP servers](mcp.md) · [Community](community.md)',
    '',
    '## Per-kit coverage (target: >= 3 sources each)',
    '',
    '| Kit | Sources | Playbook | Notes |',
    '| --- | ---: | --- | --- |',
    ...rows,
    '',
    '## Registry',
    '',
    'The source of truth is `kb/sources.json`. Add an entry with `id`, `title`, `url`,',
    '`kind`, `domain`, `kits` (kit folder names or `"*"`), then rebuild.',
    '',
  ];
  File(p.join(kbDir, 'KB.md')).writeAsStringSync('${body.join('\n')}\n');
}

/// Markdown References block for one kit: framework-wide sources first (wildcard
/// kits whose kind is official/package/mcp), then this kit's own non-wildcard
/// sources.
String referencesFor(String kit, List<Source> srcs) {
  final framework = srcs
      .where((s) =>
          s.kits.contains('*') &&
          (s.kind == 'official' || s.kind == 'package' || s.kind == 'mcp'))
      .toList();
  final own =
      srcs.where((s) => s.kits.contains(kit) && !s.kits.contains('*')).toList();
  final lines = <String>['Official docs and tooling:', ''];
  for (final s in framework) {
    lines.add(mdLink(s));
  }
  if (own.isNotEmpty) {
    lines.add('\nKit-specific:');
    lines.add('');
    for (final s in own) {
      lines.add(mdLink(s));
    }
  }
  return lines.join('\n');
}

/// Inject the References block into each kit playbook between the kb markers
/// (first marker pair only). Idempotent: the generated block is deterministic,
/// so a second run produces identical output and writes nothing. Returns the
/// count of `` `<kit>_playbook.mdx` `` files found on disk.
int injectReferences(
    String repoRoot, List<Source> srcs, Map<String, Fact> facts) {
  final pattern = RegExp(r'<!-- kb:begin -->.*?<!-- kb:end -->', dotAll: true);
  var found = 0;
  for (final kit in facts.keys.toList()..sort()) {
    final path = p.join(repoRoot, kit, '${kit}_playbook.mdx');
    final f = File(path);
    if (!f.existsSync()) continue;
    found++;
    final txt = f.readAsStringSync();
    final refs = referencesFor(kit, srcs);
    final block = '<!-- kb:begin -->\n### References\n\n$refs\n<!-- kb:end -->';
    final replaced = txt.replaceFirstMapped(pattern, (_) => block);
    if (replaced != txt) {
      f.writeAsStringSync(replaced);
    }
  }
  return found;
}

// ---------------------------------------------------------------------------
// build_toc half
// ---------------------------------------------------------------------------

/// First sentence of [desc]: everything up to the first ". ", trailing dots
/// trimmed, then a single "." appended. Empty/null desc -> ''.
String firstSentence(String? desc) {
  if (desc == null || desc.isEmpty) return '';
  final first = desc.split('. ').first;
  return '${first.replaceFirst(RegExp(r'\.+$'), '')}.';
}

/// Role line for a kit in playbooks.md: first sentence of description, else
/// readmeFirst, else the kit name.
String _playbookRole(Fact f) {
  final d = firstSentence(f.description);
  if (d.isNotEmpty) return d;
  if (f.readmeFirst != null && f.readmeFirst!.isNotEmpty) return f.readmeFirst!;
  return f.name;
}

String _buildPlaybooksMd(Map<String, Fact> facts) {
  final lines = <String>[
    '# appbox kit — playbooks index',
    '',
    'Generated from `memory/facts/*.json`. Do not edit by hand.',
    'Each kit ships a `<kit>/<kit>_playbook.mdx` (visual-plan) next to its README.',
    '',
    '## Kits',
    '',
    '| Kit | Role | Playbook | README | Status |',
    '| --- | --- | --- | --- | --- |',
  ];
  for (final kit in facts.keys.toList()..sort()) {
    final f = facts[kit]!;
    final role = _playbookRole(f);
    final pb = '[${kit}_playbook.mdx]($kit/${kit}_playbook.mdx)';
    final rm = (f.readmeLines != null && f.readmeLines! > 0)
        ? '[README]($kit/README.md)'
        : '—';
    lines.add('| `${f.name}` | $role | $pb | $rm | active |');
  }
  lines.addAll([
    '',
    '## Knowledge base',
    '',
    '- [kb/KB.md](kb/KB.md) — curated appbox kit/Flutter/Dart docs + MCP servers + per-kit package refs',
    '- [llms.txt](llms.txt) — agent entry point',
    '',
  ]);
  return '${lines.join('\n')}\n';
}

String _buildLlmsTxt(Map<String, Fact> facts) {
  final lines = <String>[
    '# appbox kit',
    '',
    '> A curated set of standalone capability kits for Flutter apps on the appbox kit '
        'MVVM architecture: payments, analytics, maps, deploy, forms, media, security, '
        'and more. Each kit is plugin-neutral and documented by a visual-plan playbook.',
    '',
    '## Playbooks',
    '',
  ];
  for (final kit in facts.keys.toList()..sort()) {
    final f = facts[kit]!;
    // llms.txt role = first sentence of description, else name (no readmeFirst
    // fallback, unlike playbooks.md).
    final fs = firstSentence(f.description);
    final role = fs.isNotEmpty ? fs : f.name;
    lines.add('- [${f.name} playbook]($kit/${kit}_playbook.mdx): $role');
  }
  lines.addAll([
    '',
    '## Knowledge base',
    '',
    '- [kb/KB.md](kb/KB.md): curated official/community documentation index with per-kit coverage',
    '- [kb/sources.json](kb/sources.json): the machine-readable source registry',
    '- [kb/mcp.md](kb/mcp.md): Dart & Flutter MCP server setup',
    '',
    '## Orientation',
    '',
    '- [playbooks.md](playbooks.md): human-readable index of every playbook',
    '- [AGENTS.md](AGENTS.md): how agents work in this repo',
    '',
    '## Optional',
    '',
    '- [memory/MEMORY.md](memory/MEMORY.md): curated cross-kit lessons (read at session start)',
    '',
  ]);
  return '${lines.join('\n')}\n';
}
