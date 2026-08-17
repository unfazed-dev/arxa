// commission — compile the designer's binding mandate from the intake chain.
//
// The energize lesson, made structural: the designer authored a bland site
// because nothing FED it — the moodboard record was a zeros stub, no
// selection existed, and "cinematic (animated 3D backgrounds)" sat unsigned
// in direction.json while the hero deferred 3D to a later stage. This
// compiler refuses to run in that state:
//
//   appbox design commission <app-dir>
//
//   · moodboard.json must carry boards + criteria + selectionStatus approved
//   · every board must hold >= 1 selected reference
//   · every LOCKED criterion must be fed (a selected ref scoring >= 3)
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

import 'package:appboxd/moodboard_check.dart' show checkMoodboardRecord;

int commissionMain(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('Usage: appbox design commission <app-dir>');
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
  final failures = checkMoodboardRecord(rec);
  if (rec['selectionStatus'] != 'approved') {
    failures.add('selectionStatus is "${rec['selectionStatus']}" — the human '
        'selection gate has not approved this moodboard');
  }
  if (failures.isNotEmpty) {
    stderr.writeln('design commission: the mandate is not ready — fix these first:');
    for (final f in failures) {
      stderr.writeln('  · $f');
    }
    stderr.writeln('Run: appbox moodboard check $intake');
    return 2;
  }

  final marker = _readJson('$appDir/appbox.json');
  final answers = _readJson('$intake/answers.json');
  final direction = _readJson('$intake/direction.json');
  final personas = _readJson('$intake/personas.json');
  final registry = _readJson('$intake/registry.json');

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
  Map<String, dynamic> personas,
  Map<String, dynamic> registry,
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
  final personaList = (personas['personas'] as List? ?? personas['list'] as List? ?? const [])
      .whereType<Map>()
      .toList();
  if (personaList.isNotEmpty) {
    buf.writeln('- Personas:');
    for (final p in personaList) {
      final label = p['name'] ?? p['label'] ?? p['id'] ?? '?';
      final note = p['summary'] ?? p['value'] ?? '';
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

  // ---- context layer
  buf.writeln('## Context');
  final surfaces = (registry['surfaces'] as List? ?? const []).whereType<Map>().toList();
  buf.writeln('- Surfaces in the registry: ${surfaces.length}');
  final constraints = answers['constraints'];
  if (constraints is List && constraints.isNotEmpty) {
    buf.writeln('- Constraints:');
    for (final c in constraints.whereType<Map>()) {
      if (c['value'] is String) buf.writeln('    - ${c['value']}');
    }
  }
  final layout = answers['layoutTemplate'];
  if (layout is Map && layout['value'] is String) {
    buf.writeln('- Layout template (founder-signed): ${layout['value']}');
  } else if (layout is String) {
    buf.writeln('- Layout template (founder-signed): $layout');
  }
  buf.writeln();
  buf.writeln('--- compiled deterministically from the intake chain; regenerate with');
  buf.writeln('    appbox design commission <app-dir>');
  return buf.toString();
}

String _promptMd(Map<String, dynamic> marker) {
  final name = marker['name'] ?? 'unnamed';
  final kind = marker['kind'] ?? 'site';
  return '''# Designer entry prompt — $name

You are the appbox designer for **$name** (kind: **$kind**). Before you
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
  vary structure, not just color.
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
