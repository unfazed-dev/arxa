// commission — compile the designer's binding mandate from the intake chain.
//
// The energize lesson, made structural: the designer authored a bland site
// because nothing FED it — the moodboard record was a zeros stub, no
// selection existed, and "cinematic (animated 3D backgrounds)" sat unsigned
// in direction.json while the hero deferred 3D to a later stage. This
// compiler refuses to run in that state:
//
//   arxa design commission <app-dir>
//
//   · moodboard.json must carry boards + criteria + selectionStatus approved
//   · >= 1 selected reference somewhere in the record (per-board emptiness
//     is legal — a board may honestly contribute patterns only)
//   · every LOCKED criterion must be fed (a selected ref scoring >= 3)
//   · NEW-STYLE records (suitors recorded): suitorChoice must be present —
//     the direction audition ends with a human pick, and the chosen suitor
//     (+ attribute remixes) becomes the token layer's spine
//   (same law as moodboard_check — the compiler gates on the record)
//
// Output (deterministic, no clocks):
//   <app-dir>/design/commission.md        the mandate document
//   <app-dir>/design/commission-prompt.md the designer's entry prompt
//
// commission.md carries the four input layers the research converged on —
// identity (adjectives/avoids/personas), tokens-slot (palette/type/radius/
// motion direction extracted from selected references by the moodboarder's
// annotations — never invented here), judgment (dos/don'ts), context
// (constraints, layout template, targets/locales ladder). commission-prompt.md
// embeds the craft contract (adapted from JimLiu/baoyu-design, MIT) and points
// at the commission; the designer consumes BOTH before authoring anything.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/moodboard_check.dart' show checkMoodboardRecord;

int commissionMain(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('Usage: arxa design commission <app-dir>');
    return 2;
  }
  final appDir = Directory(args.first).absolute.path;
  final intake = '$appDir/intake';
  final moodboardFile = File('$intake/moodboard.json');
  if (!moodboardFile.existsSync()) {
    stderr.writeln('design commission: no intake/moodboard.json under $appDir — '
        'run the moodboard stage first');
    return 2;
  }
  Map<String, dynamic> rec;
  try {
    final v = jsonDecode(moodboardFile.readAsStringSync());
    if (v is! Map) throw const FormatException('not an object');
    rec = v.cast<String, dynamic>();
  } on FormatException catch (e) {
    stderr.writeln('design commission: cannot read moodboard.json ($e)');
    return 2;
  }
  // The record gate: the same failures moodboard check names.
  final failures =
      checkMoodboardRecord(rec, moodboardDir: '$appDir/moodboard');
  if (rec['selectionStatus'] != 'approved') {
    failures.add('selectionStatus is "${rec['selectionStatus']}" — the human '
        'selection gate has not approved this moodboard');
  }
  final hasSuitors = (rec['suitors'] as List? ?? const [])
      .whereType<Map>()
      .isNotEmpty;
  if (hasSuitors && rec['suitorChoice'] is! Map) {
    failures.add('suitors are recorded but suitorChoice is absent — the '
        'human suitor gate has not chosen a direction');
  }
  if (failures.isNotEmpty) {
    stderr.writeln('design commission: the mandate is not ready — fix these first:');
    for (final f in failures) {
      stderr.writeln('  · $f');
    }
    stderr.writeln('Run: arxa moodboard check $intake');
    return 2;
  }

  final marker = _readJson('$appDir/arxa.json');
  final answers = _readJson('$intake/answers.json');
  final direction = _readJson('$intake/direction.json');
  // personas.json and registry.json are emitted as BARE ARRAYS (v1 registry;
  // v2 wraps the list in `entries`) — a Map-only reader can never see them.
  final personas = _recordList(
      _readJsonRoot('$intake/personas.json'), const ['personas', 'list']);
  final registry = _recordList(
      _readJsonRoot('$intake/registry.json'), const ['entries', 'surfaces']);

  final md = _commissionMd(appDir, rec, marker, answers, direction, personas, registry);
  final prompt = _promptMd(marker);
  Directory('$appDir/design').createSync(recursive: true);
  File('$appDir/design/commission.md').writeAsStringSync(md);
  File('$appDir/design/commission-prompt.md').writeAsStringSync(prompt);
  stdout.writeln('design commission: wrote design/commission.md + '
      'design/commission-prompt.md (${_selectedCount(rec)} selected references)');
  return 0;
}

Map<String, dynamic> _readJson(String path) {
  final f = File(path);
  if (!f.existsSync()) return <String, dynamic>{};
  try {
    final v = jsonDecode(f.readAsStringSync());
    return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

/// Reads a JSON artifact whose root may be a List — [_readJson] is Map-only
/// and would silently drop personas.json and v1 registry.json entirely.
Object? _readJsonRoot(String path) {
  final f = File(path);
  if (!f.existsSync()) return null;
  try {
    return jsonDecode(f.readAsStringSync());
  } catch (_) {
    return null;
  }
}

/// Normalizes [root] to a record list: a bare array (the emitted shape of
/// personas.json and v1 registry.json) or an object wrapping it under one of
/// [wrapKeys] (v2 registry's `entries`).
List<Map<String, dynamic>> _recordList(Object? root, List<String> wrapKeys) {
  Object? list = root;
  if (root is Map) {
    list = null;
    for (final k in wrapKeys) {
      final w = root[k];
      if (w is List) {
        list = w;
        break;
      }
    }
  }
  if (list is! List) return const [];
  return [for (final e in list) if (e is Map) e.cast<String, dynamic>()];
}

/// Answer groups are envelopes — `{value: [...], provenance: ...}` — while
/// the pre-repo-mode shape was a bare list of `{value}` maps; accept both.
List<String> _answerStrings(Object? v) {
  final raw = v is Map ? v['value'] : v;
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is String)
        e
      else if (e is Map && e['value'] is String)
        e['value'] as String,
  ];
}

String _tok(Object? v, String label) =>
    v is String && v.isNotEmpty ? ' — $label: $v' : '';

int _selectedCount(Map<String, dynamic> rec) {
  var n = 0;
  for (final b in (rec['boards'] as List? ?? const []).whereType<Map>()) {
    for (final r in (b['references'] as List? ?? const []).whereType<Map>()) {
      if (r['selected'] == true) n++;
    }
  }
  return n;
}

List<String> _adjectives(Map<String, dynamic> direction) {
  final out = <String>[];
  for (final a in (direction['adjectives'] as List? ?? const []).whereType<Map>()) {
    if (a['value'] is String) out.add('${a['value']}');
  }
  return out;
}

List<String> _avoids(Map<String, dynamic> direction) {
  final out = <String>[];
  for (final a in (direction['avoids'] as List? ?? const []).whereType<Map>()) {
    if (a['value'] is String) out.add('${a['value']}');
  }
  return out;
}

String _commissionMd(
  String appDir,
  Map<String, dynamic> rec,
  Map<String, dynamic> marker,
  Map<String, dynamic> answers,
  Map<String, dynamic> direction,
  List<Map<String, dynamic>> personas,
  List<Map<String, dynamic>> registry,
) {
  final name = marker['name'] ?? 'unnamed';
  final kind = marker['kind'] ?? 'site';
  final targets = (marker['targets'] as List? ?? const []).join(', ');
  final locales = (marker['locales'] as List? ?? const []).join(', ');
  final product = answers['product'] is Map ? answers['product'] as Map : const {};
  final buf = StringBuffer();

  buf.writeln('# Design commission — $name');
  buf.writeln();
  buf.writeln('Kind **$kind** · targets $targets · locales $locales.');
  buf.writeln('This document BINDS the design run. Locked requirements below are');
  buf.writeln('non-deferrable: deferring one is a gate failure, not a style choice.');
  buf.writeln();

  // ---- identity layer
  buf.writeln('## Identity');
  if (product['value'] is String) {
    buf.writeln('- Product: ${product['value']}');
  }
  buf.writeln('- Tone adjectives (founder-signed): ${_adjectives(direction).join(', ')}');
  buf.writeln('- Avoids (founder-signed): ${_avoids(direction).join(', ')}');
  if (personas.isNotEmpty) {
    buf.writeln('- Personas:');
    for (final p in personas) {
      final label = p['name'] ?? p['label'] ?? p['id'] ?? '?';
      final note = p['summary'] ?? p['value'] ?? p['role'] ?? '';
      buf.writeln('    - $label${note.toString().isNotEmpty ? ' — $note' : ''}');
    }
  }
  buf.writeln();

  // ---- locked requirements (from the criteria the record marked locked)
  buf.writeln('## Locked requirements — non-deferrable');
  final lockedIds = <String>[];
  for (final c in (rec['criteria'] as List? ?? const []).whereType<Map>()) {
    if (c['locked'] == true && c['id'] is String) lockedIds.add(c['id'] as String);
  }
  if (lockedIds.isEmpty) {
    buf.writeln('- (no locked criteria recorded — treat founder adjectives as the bar)');
  } else {
    for (final id in lockedIds) {
      buf.writeln('- **$id** — required by intake; the design must demonstrate it,');
      buf.writeln('  and the lens must be able to PROVE it (motion locks need two');
      buf.writeln('  settle-state captures that differ).');
    }
  }
  buf.writeln();

  // ---- layout template (founder-signed): the shell grid per rung binds
  // every surface — same rendering as the brief's, verbatim passthrough.
  final layout = answers['layoutTemplate'];
  final layoutValue = layout is Map ? layout['value'] : layout;
  if (layoutValue is Map) {
    buf.writeln('## Layout template — founder-signed, binds every surface');
    buf.writeln();
    if (layoutValue['category'] is String) {
      buf.writeln('- category: ${layoutValue['category']}');
    }
    if (layoutValue['archetype'] is String) {
      buf.writeln('- archetype: ${layoutValue['archetype']}');
    }
    buf.writeln();
    final areas = layoutValue['areas'];
    if (areas is Map) {
      buf.writeln('Grid template areas per rung (viewport ladder):');
      buf.writeln();
      for (final rung in const ['compact', 'medium', 'expanded']) {
        final rows = areas[rung];
        if (rows is! List || rows.isEmpty) continue;
        buf.writeln('$rung:');
        buf.writeln('```');
        for (final row in rows) {
          buf.writeln('"$row"');
        }
        buf.writeln('```');
        buf.writeln();
      }
    }
    final containers = layoutValue['containers'];
    if (containers is Map && containers.isNotEmpty) {
      buf.writeln('Named containers:');
      buf.writeln();
      for (final e in containers.entries) {
        final meta = e.value;
        if (meta is Map) {
          final hints = meta['hints'] ?? '';
          buf.writeln('- `${e.key}` — ${meta['type'] ?? ''}'
              '${hints.toString().isNotEmpty ? ': $hints' : ''}');
        } else {
          buf.writeln('- `${e.key}` — $meta');
        }
      }
      buf.writeln();
    }
  }

  // ---- visual mandate: ONLY selected references, with scores + why + shots
  buf.writeln('## Visual mandate — selected references only');
  buf.writeln('Scored 0-5 per criterion against the intake rubric; selected by the');
  buf.writeln('human gate. Cross-pollinate deliberately: layout from one, palette');
  buf.writeln('from another, motion from a third — never clone a single reference.');
  buf.writeln();
  for (final b in (rec['boards'] as List? ?? const []).whereType<Map>()) {
    final board = b.cast<String, dynamic>();
    final boardId = board['id'] ?? '?';
    final selected = (board['references'] as List? ?? const [])
        .whereType<Map>()
        .where((r) => r['selected'] == true)
        .toList();
    if (selected.isEmpty) continue;
    buf.writeln('### Board: $boardId');
    for (final r in selected.map((m) => m.cast<String, dynamic>())) {
      final refName = r['name'] ?? r['url'] ?? '?';
      final url = r['url'] ?? '';
      buf.writeln('- **$refName**${url.toString().isNotEmpty ? ' — $url' : ''} — total ${r['total'] ?? '?'}');
      final scores = (r['scores'] as Map? ?? const {});
      if (scores.isNotEmpty) {
        buf.writeln('  scores: ${scores.entries.map((e) => '${e.key}=${e.value}').join(', ')}');
      }
      if (r['why'] is String && (r['why'] as String).isNotEmpty) {
        buf.writeln('  why: ${r['why']}');
      }
      if (r['steal'] is String && (r['steal'] as String).isNotEmpty) {
        buf.writeln('  steal: ${r['steal']}');
      }
      final shot = r['shot'];
      if (shot is Map && shot['file'] is String) {
        buf.writeln('  shot: ../moodboard/shots/$boardId/${shot['file']}');
      }
    }
    buf.writeln();
  }

  // ---- the chosen direction (new-style records): the audition's winner
  // is the token layer's spine; the per-reference tokens below stay context.
  final suitorsById = <String, Map<String, dynamic>>{};
  for (final s in (rec['suitors'] as List? ?? const []).whereType<Map>()) {
    final suitor = s.cast<String, dynamic>();
    if (suitor['id'] is String) {
      suitorsById[suitor['id'] as String] = suitor;
    }
  }
  final rawChoice = rec['suitorChoice'];
  final choice = rawChoice is Map ? rawChoice.cast<String, dynamic>() : null;
  if (choice != null && suitorsById.isNotEmpty) {
    final primary =
        choice['primary'] is String ? choice['primary'] as String : '?';
    final suitor = suitorsById[primary];
    if (suitor != null) {
      buf.writeln(
          '## The chosen direction — suitor $primary: ${suitor['name'] ?? 'unnamed'}');
      buf.writeln('Chosen at the direction audition from three synthesized suitors;');
      buf.writeln('remix clauses amend the primary with named attributes from its');
      buf.writeln('siblings. This — not the per-reference tokens below — is the spine.');
      buf.writeln();
      if (suitor['spread'] is String) {
        buf.writeln('- spread: ${suitor['spread']}');
      }
      final t = (suitor['tokens'] as Map? ?? const {});
      for (final k in ['palette', 'type', 'radius', 'motion']) {
        if (t[k] is String && (t[k] as String).isNotEmpty) {
          buf.writeln('- $k: ${t[k]}');
        }
      }
      final leads = (suitor['leads'] as List? ?? const []).whereType<String>();
      if (leads.isNotEmpty) {
        buf.writeln('- leads: ${leads.join(', ')}');
      }
      for (final e
          in (suitor['evidence'] as List? ?? const []).whereType<Map>()) {
        final file = e['file'];
        final kind = e['kind'];
        if (file is String) {
          buf.writeln('- evidence: ../moodboard/$file'
              '${kind is String ? ' ($kind)' : ''}');
        }
      }
      for (final r in (choice['remix'] as List? ?? const []).whereType<Map>()) {
        final from = r['from'] is String ? r['from'] as String : '?';
        final attribute = r['attribute'];
        final fromTokens = suitorsById[from]?['tokens'];
        final value = fromTokens is Map ? fromTokens[attribute] : null;
        buf.writeln('- remixed $attribute <- suitor $from'
            '${value is String && value.isNotEmpty ? ' ($value)' : ''}');
      }
      final declined = suitorsById.keys.where((k) => k != primary).toList()
        ..sort();
      if (declined.isNotEmpty) {
        buf.writeln();
        buf.writeln('### Auditioned and declined');
        for (final k in declined) {
          final d = suitorsById[k]!;
          buf.writeln(
              '- suitor $k — ${d['name'] ?? 'unnamed'}: ${d['spread'] ?? ''}');
        }
      }
      buf.writeln();
    }
  }

  // ---- style tokens (extracted from the selected references)
  buf.writeln('## Style tokens — extracted from the selected references');
  buf.writeln('Fidelity ladder: tokens beat screenshots beat adjectives. These are');
  buf.writeln('EXTRACTED from the mandate above (the moodboarder\'s judgment), and the');
  buf.writeln('synthesis is a starting direction — the designer owns the final choice.');
  buf.writeln();
  for (final b in (rec['boards'] as List? ?? const []).whereType<Map>()) {
    final board = b.cast<String, dynamic>();
    final boardId = board['id'] ?? '?';
    for (final r in (board['references'] as List? ?? const []).whereType<Map>()) {
      final ref = r.cast<String, dynamic>();
      if (ref['selected'] != true) continue;
      final tokens = ref['tokens'];
      if (tokens is! Map || tokens.isEmpty) continue;
      final t = tokens.cast<String, dynamic>();
      buf.writeln('- **$boardId/${ref['name'] ?? '?'}**'
          '${_tok(t['palette'], 'palette')}${_tok(t['type'], 'type')}'
          '${_tok(t['radius'], 'radius')}${_tok(t['motion'], 'motion')}');
    }
  }
  // Legacy spine: the recorded synthesis renders only when no suitorChoice
  // exists — a chosen direction supersedes it.
  final synth = choice != null ? null : rec['tokenSynthesis'];
  if (synth is Map && synth.isNotEmpty) {
    final s = synth.cast<String, dynamic>();
    buf.writeln();
    buf.writeln('### Synthesis — the cross-pollinated starting direction');
    for (final key in ['palette', 'type', 'radius', 'elevation', 'motion', 'usage']) {
      if (s[key] is String && (s[key] as String).isNotEmpty) {
        buf.writeln('- **$key**: ${s[key]}');
      }
    }
  }
  buf.writeln();

  // ---- context layer
  buf.writeln('## Context');
  buf.writeln('- Surfaces in the registry: ${registry.length}');
  final constraints = _answerStrings(answers['constraints']);
  if (constraints.isNotEmpty) {
    buf.writeln('- Constraints:');
    for (final c in constraints) {
      buf.writeln('    - $c');
    }
  }
  if (layoutValue is String && layoutValue.isNotEmpty) {
    buf.writeln('- Layout template (founder-signed): $layoutValue');
  }
  buf.writeln();
  buf.writeln('--- compiled deterministically from the intake chain; regenerate with');
  buf.writeln('    arxa design commission <app-dir>');
  return buf.toString();
}

String _promptMd(Map<String, dynamic> marker) {
  final name = marker['name'] ?? 'unnamed';
  final kind = marker['kind'] ?? 'site';
  return '''# Designer entry prompt — $name

You are the arxa designer for **$name** (kind: **$kind**). Before you
write a single file, read `commission.md` next to this prompt — it is a
binding contract, not inspiration. The craft rules below are adapted from
JimLiu/baoyu-design (MIT) and are non-negotiable.

## Contract

1. Consume commission.md fully. Locked requirements are NON-DEFERRABLE — a
   design that defers one (e.g. ships a static hero when motion is locked)
   fails its gate regardless of how polished the rest is.
2. Never author from a blank box. The commission's selected references,
   scores, and shot paths are your visual context; consult the shots on disk
   at ../moodboard/shots/ before choosing any palette, type, or motion.
3. Ask your clarifying questions FIRST (fresh start — never assume a prior
   project's answers), state your early assumptions and layout logic, then
   build.

## Craft rules (the anti-slop contract)

- No default-token design: no Inter/Roboto/Arial/system font as the identity
  face, no default blue-purple gradient heroes, no `rounded-2xl shadow-lg`
  on everything. Choose a named type pairing with real contrast and ONE
  elevation vocabulary, and hold them.
- Bold direction: pick an extreme of the commission's tone adjectives, and
  give every surface one memorable element. If two variants you produce
  converge, you have designed the average, not the brand.
- Real content only: concrete claims and real sentences in the brand's
  voice — no "Empower your team" filler. Placeholder beats a fake asset.
- Motion is design: when a motion criterion is locked, the hero must move
  in the design artifact itself (CSS/WebGL), degrade poster-first, and be
  provable — lens captures at two settle states must differ.
- Produce 3 distinct variants for the hero/key surface before committing;
  vary structure, not just color. Variant exploration lives IN PAGE, not in
  file forks: expose the variants as a server-side switch (e.g. `?variant=b`)
  wired to CSS custom properties — zero client JS. File copies (v2) are for
  accepted revisions, never for exploring.
- Every major section carries a `data-screen-label` attribute so review can
  POINT at the element it means (lens shot + label = unambiguous feedback).
- Craft minimums: interactive targets >= 44px on every rung; body text
  >= 16px at compact; one type scale per ladder rung.
- Serve and verify: never present a file:// — serve, capture, check the
  console, fix, then present.

## Stack

- kind **site**: server-rendered htmx + islands, MVVM, zero custom
  client-side JavaScript; motion as named vendored islands in the build.
- kind **app**: Flutter surfaces on the ladder for ${marker['targets'] ?? 'the targets'},
  locales ${marker['locales'] ?? 'en'}.

Begin by quoting the locked requirements from commission.md and how each
will be demonstrated and proven. Then design.
''';
}
