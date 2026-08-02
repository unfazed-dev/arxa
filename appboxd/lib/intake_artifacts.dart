// appbox intake artifacts — the four project-shell files intake emits BESIDES
// brief.md / registry.json / flows.json (Slice B1).
//
//   intake/personas.json    who the app is for, one entry per elicited user type
//   intake/map.json         releases / epics / features / stories + counts
//   intake/moodboard.json   boards / references / shots, src precomputed
//   intake/direction.json   adjectives / avoids, provenance promoted per item
//
// THE CONTRACT THIS MODULE INHERITS FROM intake.dart
//   Every emitter here is a PURE function of the answers document. No clock, no
//   filesystem read, no network, no invented content — same answers in, same
//   bytes out, and idempotent over its own output. `project.dart:13` states the
//   determinism rule; `moodboard.curated` (a date) was dropped from the spec for
//   exactly that reason, so nothing in this file may reintroduce a timestamp.
//
// WHY THESE READ ANSWER GROUPS RATHER THAN DERIVING
//   A story map, a moodboard and a persona set are NOT derivable from the core
//   intake fields. `audience` is one JTBD sentence; it carries no name, no role,
//   no goals. Manufacturing three personas from it is the confident fiction §22
//   forbids — it would read as authoritative and nobody could tell it apart from
//   an elicited one. So each emitter reads an OPTIONAL group off the answers
//   (`personas`, `map`, `moodboard`, `direction`) and, when the group is absent,
//   emits the empty shape. Absent must never be an error: every project that
//   existed before Slice B has all four groups missing, and re-emitting one of
//   those must keep working.
//
// WHY THE EMITTERS SPREAD RATHER THAN ENUMERATE
//   Task #29: an emitter that listed the keys it knew about silently dropped
//   `element` and `feedback` — legal, validated fields the literal simply forgot
//   — and corrupted the user's real project four times before anyone noticed.
//   `emitFlows` fixed that with a spread; the same rule applies here and matters
//   MORE, because intake does not own `map`/`moodboard` at all. Those documents
//   are authored by appbox-story-mapper and appbox-moodboarder; intake is only
//   republishing them into the project shell with ids and counts added. A
//   republisher that drops the author's fields is the bug, not the safeguard.
//
//   The trade-off this makes, stated plainly: `emitFlows` pairs its spread with
//   a CLOSED key set (`edgeKeys`) so nothing unrecognised can ride along. There
//   is no closed set here, because intake is not the authority on these two
//   documents and a gate that refused a field the story-mapper legitimately
//   added would block the owning skill from evolving. Unknown keys therefore
//   pass through. That is the deliberate choice: carrying a stray key forward is
//   recoverable, deleting an authored one is not.

import 'dart:convert';
import 'dart:io';

/// Every key a persona may carry — the 9 the studio's persona cards read.
/// `id` is DERIVED from `name` by convention (like `comp` from a surface id),
/// so an answers document does not author it; an explicit `id` still wins, the
/// same override `story_map.dart:258` allows a feature to pin its surface id.
const personaKeys = [
  'id',
  'name',
  'role',
  'goals',
  'frustrations',
  'contexts',
  'proficiency',
  'accessibility',
  'provenance',
];

/// The persona list fields. Absent → `[]`, never null: a card that renders a
/// list must not have to type-test every read.
const _personaLists = ['goals', 'frustrations', 'contexts'];

/// The top-level keys [emitStoryMap] owns. Anything else on a prior `map.json`
/// belongs to another stage and is carried across by [mergeStoryMap].
const storyMapEmittedKeys = ['releases', 'epics', 'counts', 'statuses'];

/// Where moodboard shots are served from. The studio's `generate.mjs` computes
/// the same path; precomputing it HERE means every reader is a dumb field
/// selector and no JS has to know the convention.
const moodboardAssetRoot = '/assets/images/moodboard';

/// Words that are not part of a slug. Kept as a single ascii-word matcher so a
/// name with punctuation, an ampersand or an em dash slugs the same way on
/// every platform (a locale-sensitive lowercase would not be deterministic).
final _slugWordRe = RegExp(r'[a-z0-9]+');

/// Full kebab slug of [name] — every ascii word, joined by `-`.
///
/// NOT `story_map.dart`'s [slugify], which takes the FIRST word only. That is
/// right for a surface id (`shop.cart`) and wrong here: story names are whole
/// sentences, so first-word-only would collide on nearly every pair and the
/// collision suffix would end up carrying the meaning.
String slugSegment(String name) {
  final words = _slugWordRe.allMatches(name.toLowerCase()).map((m) => m.group(0)!);
  final slug = words.join('-');
  // A name with no ascii word at all (CJK, emoji) still needs an id. 'x' is a
  // placeholder the collision suffix then disambiguates — better than throwing
  // in an emitter that must never fail on odd but legal input.
  return slug.isEmpty ? 'x' : slug;
}

/// Reserve [base], suffixing `-2`, `-3`, … only if it is genuinely taken.
///
/// Story ids are CONTENT-derived on purpose. The studio seed numbers them
/// `s-1..s-34` sequentially across the whole document, so inserting one story
/// renumbers every story after it — statuses, links and review comments all
/// shift onto the wrong rows. A content-derived id moves only when its own
/// text changes, which is the only time a renumber is honest.
String _reserve(String base, Set<String> used) {
  if (used.add(base)) return base;
  var n = 2;
  while (!used.add('$base-$n')) {
    n++;
  }
  return '$base-$n';
}

List<Object?> _list(Object? v) => v is List ? v : const [];

List<String> _strings(Object? v) =>
    v is List ? [for (final x in v) if (x is String) x] : const <String>[];

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

// ------------------------------------------------------------------ personas

/// Emit `personas.json` from the optional `personas` answer group.
///
/// Variable N by design (Slice B decision, 2026-08-02): the respondent names as
/// many user types as they have. There is no padding to three — a padded
/// persona is an invented one, and an invented persona is indistinguishable
/// from an elicited one once it is on a card.
///
/// Absent group → `[]`. Every project created before Slice B has no `personas`
/// key, and re-emitting one of those must degrade to an empty list rather than
/// to an error.
List<Map<String, dynamic>> emitPersonas(Map<String, dynamic> answers) {
  final declared = answers['personas'];
  if (declared is! List) return const [];
  final used = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final p in declared) {
    if (p is! Map) continue;
    final persona = p.cast<String, dynamic>();
    final name = persona['name'] is String ? persona['name'] as String : '';
    final authoredId = persona['id'];
    final id = authoredId is String && authoredId.isNotEmpty
        ? _reserve(authoredId, used)
        : _reserve('persona-${slugSegment(name)}', used);
    out.add(<String, dynamic>{
      // Spread first (task #29): a key the respondent supplied that this
      // literal has not heard of still reaches the card.
      ...persona,
      'id': id,
      'name': name,
      'role': persona['role'] is String ? persona['role'] : null,
      for (final k in _personaLists) k: _strings(persona[k]),
      'proficiency': persona['proficiency'] is String ? persona['proficiency'] : null,
      'accessibility':
          persona['accessibility'] is String ? persona['accessibility'] : null,
      // No provenance stated means it was not elicited, which is 'inferred'.
      // There is no fourth value (see intake.dart's `provenance`).
      'provenance': persona['provenance'] is String ? persona['provenance'] : 'inferred',
    });
  }
  return out;
}

// ----------------------------------------------------------------- story map

/// Emit `map.json` from the optional `map` answer group — appbox-story-mapper's
/// document, republished into the project shell with ids and counts baked in.
///
/// Ids are content-derived: `slug(epic)` / `slug(epic).slug(feature)` /
/// `slug(epic).slug(feature).slug(story)`, with `-2`/`-3` only where two
/// entries genuinely collide. See [_reserve] for why sequential ids were
/// rejected.
///
/// `feature.surfaceId` is deliberately NOT emitted (Slice B decision): no JS
/// does that name-matching today, so it would be a stored field with no reader
/// and no test, and a wrong value would go unnoticed. Additive later.
///
/// Absent group → the empty shape (`releases: []`, `epics: []`, zeroed counts,
/// `statuses: {}`), never an error.
Map<String, dynamic> emitStoryMap(Map<String, dynamic> answers) {
  final src = _map(answers['map']);
  final usedEpic = <String>{};
  final usedFeature = <String>{};
  final usedStory = <String>{};

  var featureCount = 0;
  var storyCount = 0;
  final byPriority = <String, int>{};
  final byRelease = <String, int>{};
  final storiesPerRelease = <String, int>{};

  final epics = <Map<String, dynamic>>[];
  for (final e in _list(src['epics'])) {
    if (e is! Map) continue;
    final epic = e.cast<String, dynamic>();
    final epicName = epic['name'] is String ? epic['name'] as String : '';
    final epicId = _reserve(slugSegment(epicName), usedEpic);
    var epicStories = 0;

    final features = <Map<String, dynamic>>[];
    for (final f in _list(epic['features'])) {
      if (f is! Map) continue;
      final feature = f.cast<String, dynamic>();
      final featureName = feature['name'] is String ? feature['name'] as String : '';
      final featureId = _reserve('$epicId.${slugSegment(featureName)}', usedFeature);
      featureCount++;

      final stories = <Map<String, dynamic>>[];
      for (final s in _list(feature['stories'])) {
        if (s is! Map) continue;
        final story = s.cast<String, dynamic>();
        final storyName = story['name'] is String ? story['name'] as String : '';
        final storyId = _reserve('$featureId.${slugSegment(storyName)}', usedStory);
        final priority = story['priority'] is String ? story['priority'] as String : null;
        final release = story['release'] is String ? story['release'] as String : null;
        if (priority != null) byPriority[priority] = (byPriority[priority] ?? 0) + 1;
        if (release != null) {
          byRelease[release] = (byRelease[release] ?? 0) + 1;
          storiesPerRelease[release] = (storiesPerRelease[release] ?? 0) + 1;
        }
        storyCount++;
        epicStories++;
        stories.add(<String, dynamic>{
          ...story,
          'id': storyId,
          'name': storyName,
          'priority': priority,
          'release': release,
          'provenance': story['provenance'] is String ? story['provenance'] : 'inferred',
        });
      }
      features.add(<String, dynamic>{
        ...feature,
        'id': featureId,
        'name': featureName,
        'stories': stories,
      });
    }
    epics.add(<String, dynamic>{
      ...epic,
      'id': epicId,
      'name': epicName,
      'storyCount': epicStories,
      'provenance': epic['provenance'] is String ? epic['provenance'] : 'inferred',
      'features': features,
    });
  }

  final releases = <Map<String, dynamic>>[];
  for (final r in _list(src['releases'])) {
    if (r is! Map) continue;
    final release = r.cast<String, dynamic>();
    final name = release['name'] is String ? release['name'] as String : '';
    releases.add(<String, dynamic>{
      // The spec's release field list is {name, stories, provenance}, but the
      // story-mapper also writes `description`. Enumerating the three would
      // delete the fourth — task #29 again — so spread, then overlay.
      ...release,
      'name': name,
      'stories': storiesPerRelease[name] ?? 0,
      'provenance': release['provenance'] is String ? release['provenance'] : 'inferred',
    });
  }

  return <String, dynamic>{
    'releases': releases,
    'epics': epics,
    'counts': <String, dynamic>{
      'epics': epics.length,
      'features': featureCount,
      'stories': storyCount,
      // MoSCoW buckets are reported as counts, zero included, so a reader can
      // render the bar without testing for the key. Any OTHER priority word the
      // story-mapper used is reported too — intake does not own that vocabulary
      // and silently zeroing an unrecognised bucket would hide stories.
      'must': byPriority['must'] ?? 0,
      'should': byPriority['should'] ?? 0,
      'could': byPriority['could'] ?? 0,
      for (final k in (byPriority.keys.toList()..sort()))
        if (!const ['must', 'should', 'could'].contains(k)) k: byPriority[k],
      // Sorted: a map literal built in iteration order would make the bytes
      // depend on story order rather than story content.
      'byRelease': <String, dynamic>{
        for (final k in (byRelease.keys.toList()..sort())) k: byRelease[k],
      },
    },
    // Authored by the studio (a reviewer marking a story done), never by
    // intake. Emitted empty and re-united with the prior file by
    // [mergeStoryMap] at the write step.
    'statuses': <String, dynamic>{},
  };
}

/// Carry forward the `map.json` fields emit does not own.
///
/// Same shape of bug as [mergeRegistry] in intake.dart, and the same reason it
/// exists: `statuses` is authored in the studio (a reviewer marks a story done)
/// and lives ONLY in the generated file. Writing the pure result straight over
/// map.json would delete every status with nothing to restore them from —
/// which is precisely how portalo lost its `kits` column.
///
/// Orphan statuses (an id whose story was renamed away) are KEPT, unlike
/// [mergeRegistry] which drops foreign keys for ids no longer emitted. Registry
/// ids are permanent by validation so that never bites there; story ids are
/// content-derived and DO change when their text is edited. Dropping on rename
/// would turn a typo fix into silent data loss, and a stale key costs nothing.
Map<String, dynamic> mergeStoryMap(Map<String, dynamic> emitted, String existingPath) {
  final f = File(existingPath);
  if (!f.existsSync()) return emitted;
  Map<String, dynamic> prior;
  try {
    final raw = jsonDecode(f.readAsStringSync());
    if (raw is! Map) return emitted;
    prior = raw.cast<String, dynamic>();
  } catch (_) {
    // A corrupt or hand-mangled map must never block a re-emit. The pure result
    // is still correct; it just carries nothing forward.
    return emitted;
  }
  final statuses = <String, dynamic>{
    ..._map(prior['statuses']),
    ..._map(emitted['statuses']),
  };
  return <String, dynamic>{
    ...emitted,
    for (final kv in prior.entries)
      if (!storyMapEmittedKeys.contains(kv.key)) kv.key: kv.value,
    'statuses': <String, dynamic>{
      for (final k in (statuses.keys.toList()..sort())) k: statuses[k],
    },
  };
}

// ----------------------------------------------------------------- moodboard

/// Emit `moodboard.json` from the optional `moodboard` answer group.
///
/// Two renames the spec calls for, both because the seed's field does not mean
/// what its name says:
///   * top-level `provenance` → **`method`**. The seed's value is free-text
///     methodology ("docs/moodboards · appbox lens captures · every shot
///     verified on disk"), NOT the `client|founder|inferred` enum. Leaving it
///     called `provenance` would make a reader parse prose as an enum. Real
///     per-reference provenance is emitted separately and does use the enum.
///   * `curated` is DROPPED. It is a date, and `project.dart:13` bans clock
///     fields — an emitted artifact must be byte-identical for identical input.
///
/// `board.file` is dropped too: it points at the studio's authoring markdown,
/// which does not exist inside a user project.
///
/// `shot.id` and `shot.src` are precomputed here, the job `generate.mjs` does
/// for the studio fixture, so every reader stays a dumb field selector.
Map<String, dynamic> emitMoodboard(Map<String, dynamic> answers) {
  final src = _map(answers['moodboard']);
  var referenceCount = 0;
  var shotCount = 0;
  final boards = <Map<String, dynamic>>[];
  for (final b in _list(src['boards'])) {
    if (b is! Map) continue;
    final board = b.cast<String, dynamic>();
    final boardId = board['id'] is String ? board['id'] as String : '';
    final references = <Map<String, dynamic>>[];
    for (final r in _list(board['references'])) {
      if (r is! Map) continue;
      final reference = r.cast<String, dynamic>();
      referenceCount++;
      final shot = _map(reference['shot']);
      final file = shot['file'] is String ? shot['file'] as String : '';
      Map<String, dynamic>? emittedShot;
      if (file.isNotEmpty) {
        shotCount++;
        final dot = file.lastIndexOf('.');
        final stem = dot > 0 ? file.substring(0, dot) : file;
        emittedShot = <String, dynamic>{
          ...shot,
          'file': file,
          'id': '$boardId--$stem',
          'src': '$moodboardAssetRoot/$boardId/$file',
        };
      }
      references.add(<String, dynamic>{
        ...reference,
        'shot': ?emittedShot,
        'provenance':
            reference['provenance'] is String ? reference['provenance'] : 'inferred',
      });
    }
    boards.add(<String, dynamic>{
      ...board,
      'id': boardId,
      'references': references,
    }..remove('file'));
  }
  return <String, dynamic>{
    'method': src['provenance'] is String ? src['provenance'] : null,
    'boards': boards,
    'counts': <String, dynamic>{
      'boards': boards.length,
      'references': referenceCount,
      'shots': shotCount,
    },
  };
}

// ----------------------------------------------------------------- direction

/// Emit `direction.json` from the `direction` answer group.
///
/// `answers.direction` carries ONE provenance for the whole field, while every
/// facade reader wants it per item — a client-stated adjective and an inferred
/// one must not look alike on a chip. Promoting the field's provenance onto
/// each item at emit time is a restatement of a recorded fact, not an
/// inference: each item genuinely has the provenance its field was given.
///
/// `references` stays `[]` until a moodboard-to-direction link is elicited.
/// Guessing which board informed which adjective is exactly what §22 forbids.
Map<String, dynamic> emitDirection(Map<String, dynamic> answers) {
  final node = _map(answers['direction']);
  final value = _map(node['value']);
  final prov = node['provenance'] is String ? node['provenance'] as String : 'inferred';
  List<Map<String, dynamic>> items(Object? raw) => [
        for (final x in _list(raw))
          if (x is String)
            <String, dynamic>{'value': x, 'provenance': prov}
          // Already per-item {value, provenance}: keep the item's own
          // provenance. The field's is the DEFAULT, not an override — a
          // confirmed item must not be re-stamped by a later field edit.
          else if (x is Map)
            <String, dynamic>{
              ...x.cast<String, dynamic>(),
              'value': x['value'],
              'provenance': x['provenance'] is String ? x['provenance'] : prov,
            },
      ];
  return <String, dynamic>{
    'adjectives': items(value['adjectives']),
    'avoids': items(value['avoids']),
    'references': _list(value['references'])
        .whereType<Map>()
        .map((r) => r.cast<String, dynamic>())
        .toList(),
  };
}

// ---------------------------------------------------------------- validation

/// Validate the optional `personas` group (Slice B2).
///
/// Called from `validateIntake` as its own check, NOT through `_fieldTitles`:
/// that loop demands a `{value, provenance}` object and drives the brief's
/// section order, so a list-shaped group routed through it would be reported as
/// a type error and would grow a brief section nobody asked for.
///
/// Absent is VALID. Every project that existed before Slice B has no `personas`
/// key, and making the field required would turn `intake emit` into a hard
/// failure on all of them.
List<String> validatePersonas(Map<String, dynamic> answers) {
  final personas = answers['personas'];
  if (personas == null) return const []; // absent → emitter yields []
  if (personas is! List) {
    return [
      'personas: must be a list of user types (variable N — as many as the '
          'client named; omit the key entirely if none were elicited)'
    ];
  }
  final errs = <String>[];
  final seen = <String>{};
  for (var i = 0; i < personas.length; i++) {
    final where = 'personas[$i]';
    final p = personas[i];
    if (p is! Map) {
      errs.add('$where: expected an object');
      continue;
    }
    final name = p['name'];
    if (name is! String || name.isEmpty) {
      errs.add("$where: missing 'name' (what the client calls this user type)");
    } else if (!seen.add(name)) {
      errs.add("$where: duplicate name '$name' — two personas with the same "
          'name derive the same id and one would shadow the other');
    }
    if (!const ['client', 'founder', 'inferred'].contains(p['provenance'])) {
      errs.add("$where: provenance '${p['provenance']}' is not one of "
          '[client, founder, inferred]');
    }
    for (final k in _personaLists) {
      final v = p[k];
      if (v != null && (v is! List || v.any((x) => x is! String))) {
        errs.add('$where: $k must be a list of strings');
      }
    }
    for (final k in const ['role', 'proficiency', 'accessibility', 'id']) {
      final v = p[k];
      // proficiency is NOT a closed vocabulary. `states` is closed because a
      // gate matches on it; nothing matches on proficiency, and inventing a
      // three-word scale here would reject a client who said "power user".
      if (v != null && v is! String) errs.add('$where: $k must be a string');
    }
  }
  return errs;
}
