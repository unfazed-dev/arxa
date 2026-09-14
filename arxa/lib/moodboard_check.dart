// moodboard_check — the deterministic gate over intake/moodboard.json.
//
// The moodboarder's subagents SCORE references by judgment; this check owns
// the arithmetic and the law, so a scoring mistake cannot silently starve
// the designer of references (the energize failure: 88 shots on disk, a
// zeros stub on record, nothing selected, 3D deferred).
//
//   arxa moodboard check <intake-dir> [--floor 3.0]
//
// Green requires, when a record has boards:
//   scores      every per-criterion score is an int 0..5
//   totals      every recorded total matches Σ(score×weight)/Σweight,
//               recomputed here (2-decimal compare)
//   floor       every selected reference's total >= floor
//   locked      every locked criterion (weight starred in criteria) has at
//               least one SELECTED reference scoring >= 3 on it
//   selection   selectionStatus 'approved' implies >= 1 selected reference
//               on every board that has references
//   suitors     NEW-STYLE records only (non-empty 'suitors'): exactly three
//               directions labeled A/B/C, leads resolving to SELECTED
//               references, measured suitors carrying evidence that resolves
//               on disk, suitorChoice ordered after selection approval and
//               remixing only the closed attribute vocabulary. A suitor's
//               tokens.palette recorded as the derived OBJECT (the palette
//               plane, Q7/Q9) validates whole: swatch exactly 5 valid
//               hexes, anchors complete (dark/accent/field/beige/paper),
//               paletteSource resolving to a SELECTED reference, provenance
//               measured|judged with judged legal only when the credited
//               reference has neither url nor shot, measured palettes citing
//               at least one evidence entry (the derivation JSON), and
//               palette evidence resolving on disk. A prose palette STRING is the pre-plane
//               shape and stays legal under the law of its day. Records
//               without suitors — everything recorded before the direction
//               audition landed, energize included — are validated by the
//               law of their day: the gate applies from its landing, never
//               retroactively.
//   lockedProof NEW-STYLE records only: a score >= 3 on a LOCKED criterion
//               must cite lens evidence naming that criterion. A reference
//               you cannot capture or measure scores <= 2 on the lock — the
//               cap is the proof requirement's shadow, not a second rule.
// A record with no boards (intake ran before moodboarding) is green-empty —
// that is a pipeline position, not a corruption.

import 'dart:convert';
import 'dart:io';

int moodboardCheckMain(List<String> args) {
  // The dispatch forwards everything after `moodboard` — strip a leading
  // `check` verb so both `arxa moodboard check <dir>` and a direct call work.
  final rest = args.isNotEmpty && args.first == 'check' ? args.sublist(1) : args;
  if (rest.isEmpty) {
    stderr.writeln('Usage: arxa moodboard check <intake-dir> [--floor 3.0]');
    return 2;
  }
  final dir = rest.first;
  var floor = 3.0;
  for (var i = 1; i < rest.length; i++) {
    if (args[i] == '--floor' && i + 1 < args.length) {
      floor = double.tryParse(args[++i]) ?? floor;
    } else {
      stderr.writeln('arxa moodboard check: unknown flag ${args[i]}');
      return 2;
    }
  }
  final f = File('$dir/moodboard.json');
  if (!f.existsSync()) {
    stderr.writeln('arxa moodboard check: no moodboard.json under $dir');
    return 2;
  }
  final Map<String, dynamic> rec;
  try {
    final v = jsonDecode(f.readAsStringSync());
    if (v is! Map) throw const FormatException('not an object');
    rec = v.cast<String, dynamic>();
  } on FormatException catch (e) {
    stderr.writeln('arxa moodboard check: cannot read moodboard.json ($e)');
    return 2;
  }
  // Evidence files live under the moodboard/ stage folder — the sibling of
  // the intake dir this check was pointed at (<app-dir>/intake ->
  // <app-dir>/moodboard). Legacy records carry no evidence fields, so a
  // missing folder harms nothing; a new-style record citing files that do
  // not resolve is exactly the lie this path exists to catch.
  final moodboardDir = '${Directory(dir).parent.path}/moodboard';
  final failures =
      checkMoodboardRecord(rec, floor: floor, moodboardDir: moodboardDir);
  if (failures.isEmpty) {
    final boards = (rec['boards'] as List? ?? const []).length;
    stdout.writeln('moodboard check: ok ($boards boards, floor $floor)');
    return 0;
  }
  for (final fail in failures) {
    stderr.writeln('moodboard check: FAIL $fail');
  }
  return 2;
}

/// Pure check: list of failure strings (empty = green). Exposed for tests.
///
/// [moodboardDir] is the `<app-dir>/moodboard` stage folder evidence
/// files resolve against; null skips file-resolution checks (shape-only
/// validation).
List<String> checkMoodboardRecord(Map<String, dynamic> rec,
    {double floor = 3.0, String? moodboardDir}) {
  final failures = <String>[];
  final boards = (rec['boards'] as List? ?? const []).whereType<Map>().toList();
  if (boards.isEmpty) return failures; // green-empty (pre-moodboard record)

  // Criteria: the scoring rubric recorded at moodboard time.
  final criteria = <String, double>{};
  final locked = <String>{};
  for (final c in (rec['criteria'] as List? ?? const []).whereType<Map>()) {
    final id = c['id'];
    if (id is! String || id.isEmpty) {
      failures.add('criterion without an id');
      continue;
    }
    criteria[id] = (c['weight'] is num) ? (c['weight'] as num).toDouble() : 1.0;
    if (c['locked'] == true) locked.add(id);
  }
  if (criteria.isEmpty) {
    failures.add('boards exist but no criteria — the rubric is missing');
  }

  final selectionStatus = rec['selectionStatus'];
  if (selectionStatus is! String ||
      !['pending', 'approved'].contains(selectionStatus)) {
    failures.add('selectionStatus must be pending|approved, got "$selectionStatus"');
  }
  // Pipeline position: a PENDING record (scored, not yet selected) validates
  // scoring only; an APPROVED record additionally validates the selection.
  // Conflating them would make every honest post-scoring record red.
  final approved = selectionStatus == 'approved';

  for (final b in boards.cast<Map<String, dynamic>>()) {
    final boardId = b['id'] ?? '?';
    for (final r in (b['references'] as List? ?? const []).whereType<Map>()) {
      final ref = r.cast<String, dynamic>();
      final refName = ref['name'] ?? ref['url'] ?? '?';
      final scores = (ref['scores'] as Map? ?? const {}).cast<String, dynamic>();
      if (scores.isEmpty) {
        failures.add('$boardId/$refName: no scores');
        continue;
      }
      for (final e in scores.entries) {
        final v = e.value;
        if (v is! num || v < 0 || v > 5 || v != v.roundToDouble()) {
          failures.add('$boardId/$refName: score ${e.key}=$v not an int 0..5');
        }
      }
      // Recompute the weighted total over the RECORDED criteria (a missing
      // score reads as 0 — an unscored criterion is a fail, not a skip).
      final total = _weightedTotal(scores, criteria);
      final recorded = ref['total'];
      if (recorded is num) {
        if ((recorded.toDouble() - total).abs() > 0.011) {
          failures.add('$boardId/$refName: recorded total $recorded != computed ${total.toStringAsFixed(2)}');
        }
      } else {
        failures.add('$boardId/$refName: no recorded total');
      }
      if (ref['selected'] == true && total < floor) {
        failures.add('$boardId/$refName: selected but total ${total.toStringAsFixed(2)} < floor $floor');
      }
    }
    // Per-board selectedCount is intentionally NOT enforced: selection is a
    // global human choice, and a board may honestly contribute nothing (its
    // patterns stay mandated by the board's own pattern list). What IS
    // enforced: an approved record with zero selections anywhere starves the
    // designer — checked after the loop.
  }

  if (approved &&
      boards.every((b) => (b['references'] as List? ?? const []).isEmpty ||
          !(b['references'] as List).any((r) => r is Map && r['selected'] == true))) {
    failures.add('approved selection contains no references at all — the designer gets nothing');
  }

  // Locked intake criteria must be FED. While PENDING, feasibility is enough
  // (some reference scoring >= 3 exists); once APPROVED, a SELECTED reference
  // must carry it — an intake-locked requirement is about to be dropped
  // otherwise.
  for (final id in locked) {
    var feasible = false;
    var fed = false;
    for (final b in boards.cast<Map<String, dynamic>>()) {
      for (final r in (b['references'] as List? ?? const []).whereType<Map>()) {
        final ref = r.cast<String, dynamic>();
        final s = (ref['scores'] as Map? ?? const {})[id];
        if (s is num && s >= 3) {
          feasible = true;
          if (ref['selected'] == true) fed = true;
        }
      }
    }
    if (!feasible) {
      failures.add('locked criterion "$id" has NO reference scoring >= 3 anywhere — '
          're-gather: the board cannot feed an intake-locked requirement');
    } else if (approved && !fed) {
      failures.add('locked criterion "$id" has no SELECTED reference scoring >= 3 — '
          'an intake-locked requirement is about to be dropped again');
    }
  }

  // ---- suitors (the direction audition — new-style records only)
  final suitors = (rec['suitors'] as List? ?? const []).whereType<Map>().toList();
  final hasSuitors = suitors.isNotEmpty;
  final rawChoice = rec['suitorChoice'];
  if (rawChoice != null && rawChoice is! Map) {
    failures.add('suitorChoice must be an object {primary, remix}');
  }
  final choice = rawChoice is Map ? rawChoice.cast<String, dynamic>() : null;
  if (choice != null && !hasSuitors) {
    failures.add('suitorChoice present but no suitors recorded — a choice '
        'without an audition is the unauditioned synthesis this gate exists '
        'to prevent');
  }
  if (hasSuitors) {
    failures.addAll(
        _checkSuitors(suitors, boards: boards, moodboardDir: moodboardDir));
    if (choice != null) {
      failures.addAll(
          _checkSuitorChoice(choice, suitors, selectionApproved: approved));
    }
    // The locked-proof law rides the same new-style marker: under the old
    // record a hallucinated 5 starved nobody, under an audition it parades
    // as measured direction it never had.
    failures.addAll(_checkLockedProof(boards, locked, moodboardDir: moodboardDir));
  }
  return failures;
}

/// The closed remix vocabulary — attribute-scoped amendments only. A clause
/// outside this set is a fourth, hidden suitor wearing an amendment's clothes.
const suitorRemixAttributes = {
  'palette',
  'type',
  'radius',
  'motion',
  'layout-register',
};

List<String> _checkSuitors(List<Map> suitors,
    {required List<Map> boards, String? moodboardDir}) {
  final failures = <String>[];
  if (suitors.length != 3) {
    failures.add('suitors: exactly 3 directions are auditioned (A/B/C), got '
        '${suitors.length} — 2 is a coin flip, 5 is another moodboard');
  }
  final ids = suitors.map((s) => s['id']).whereType<String>().toSet();
  if (ids.length != suitors.length ||
      !ids.containsAll(const ['A', 'B', 'C'])) {
    failures
        .add('suitors: ids must be exactly A, B, C — got {${ids.join(', ')}}');
  }
  // Suitors lead only with references the human already selected — the
  // audition is built from the chosen material, never the boards' leftovers.
  final selectedRefs = <String>{};
  final selectedRefObjects = <String, Map<String, dynamic>>{};
  for (final b in boards) {
    final boardId = (b['id'] ?? '?').toString();
    for (final r in (b['references'] as List? ?? const []).whereType<Map>()) {
      if (r['selected'] == true) {
        final key = '$boardId/${r['name'] ?? r['url'] ?? '?'}';
        selectedRefs.add(key);
        selectedRefObjects[key] = r.cast<String, dynamic>();
      }
    }
  }
  for (final s in suitors) {
    final suitor = s.cast<String, dynamic>();
    final id = suitor['id'] ?? '?';
    if (suitor['name'] is! String || (suitor['name'] as String).isEmpty) {
      failures.add('suitor $id: no name');
    }
    final spread = suitor['spread'];
    if (spread is! String || spread.isEmpty) {
      failures.add('suitor $id: no spread statement — each direction must '
          'name the register it owns that the others do not (three clones is '
          'a finding to surface, not an audition)');
    }
    final leads = (suitor['leads'] as List? ?? const []).whereType<String>();
    if (leads.isEmpty) {
      failures.add('suitor $id: no lead references');
    }
    for (final lead in leads) {
      if (!selectedRefs.contains(lead)) {
        failures.add('suitor $id: lead "$lead" is not a selected reference '
            '(format <boardId>/<reference name>; suitors synthesize from the '
            'SELECTED set only)');
      }
    }
    final tokens = suitor['tokens'];
    final hasToken = tokens is Map &&
        (const ['palette', 'type', 'radius', 'motion'].any(
                (k) => tokens[k] is String && (tokens[k] as String).isNotEmpty) ||
            tokens['palette'] is Map);
    if (!hasToken) {
      failures.add('suitor $id: no tokens — a direction without a token set '
          '(palette/type/radius/motion, at least one) cannot be auditioned');
    }
    if (tokens is Map) {
      failures.addAll(_checkSuitorPalette(tokens['palette'],
          id: '$id',
          selectedRefs: selectedRefObjects,
          moodboardDir: moodboardDir));
    }
    failures.addAll(_checkEvidence(suitor['evidence'],
        owner: 'suitor $id', moodboardDir: moodboardDir));
    final provenance = suitor['provenance'];
    if (provenance is! String ||
        !['measured', 'judged'].contains(provenance)) {
      failures.add('suitor $id: provenance must be measured|judged — a '
          'memory-judgment direction must say so, not wear measured clothes');
    } else if (provenance == 'measured' &&
        (suitor['evidence'] as List? ?? const []).whereType<Map>().isEmpty) {
      failures.add('suitor $id: provenance measured but no evidence — '
          'measured means captured (extractTokens) or watched (two settle '
          'states / burst frames)');
    }
  }
  return failures;
}

final _paletteHex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// The palette-plane law (Q7/Q9): a suitor's tokens.palette recorded as the
/// derived OBJECT must validate whole — half an object is a prose string
/// wearing new clothes. A prose palette STRING is the pre-plane shape and
/// stays legal under the law of its day (the gate applies from its landing,
/// never retroactively); anything else is neither law.
List<String> _checkSuitorPalette(Object? palette,
    {required String id,
    required Map<String, Map<String, dynamic>> selectedRefs,
    String? moodboardDir}) {
  final failures = <String>[];
  if (palette == null || palette is String) return failures;
  if (palette is! Map) {
    failures.add('suitor $id: tokens.palette must be the derived palette '
        'object {name, swatch, anchors, paletteSource, provenance} — a prose '
        'string is the pre-plane shape, anything else is neither law');
    return failures;
  }
  final p = palette.cast<String, dynamic>();
  // Exactly 5 — the plane's variable width (3–7) never reaches the
  // moodboard side: derivation decimates/interpolates to the five roles,
  // and a judged palette must still declare 5.
  final swatch = p['swatch'];
  if (swatch is! List || swatch.length != 5) {
    failures.add('suitor $id: palette swatch must be exactly 5 hexes, got '
        '${swatch is List ? swatch.length : 'none'} — the engine '
        'decimates/interpolates every source to the plane\'s five roles');
  } else {
    for (final h in swatch) {
      if (h is! String || !_paletteHex.hasMatch(h)) {
        failures.add('suitor $id: palette swatch "$h" is not a valid '
            'hex — 6-digit hexes with the # prefix, verbatim from the engine');
      }
    }
  }
  final anchors = p['anchors'];
  const roles = ['dark', 'accent', 'field', 'beige', 'paper'];
  if (anchors is! Map) {
    failures.add('suitor $id: palette anchors must carry the five '
        'template-family roles (${roles.join('/')}) — complete or the '
        'object is invalid');
  } else {
    final bad = [
      for (final r in roles)
        if (anchors[r] is! String || !_paletteHex.hasMatch(anchors[r])) r
    ];
    if (bad.isNotEmpty) {
      failures.add('suitor $id: palette anchors missing or not valid '
          'hexes: ${bad.join(', ')} — the lightness-rank law assigns all '
          'five roles, complete or the object is invalid');
    }
  }
  // paletteSource resolves exactly like a lead: the SELECTED set only.
  final source = p['paletteSource'];
  final ref = source is String ? selectedRefs[source] : null;
  if (source is! String || !selectedRefs.containsKey(source)) {
    failures.add('suitor $id: paletteSource "$source" is not a selected '
        'reference (format <boardId>/<reference name>; suitors derive '
        'palette from the SELECTED set only)');
  }
  final provenance = p['provenance'];
  if (provenance is! String || !['measured', 'judged'].contains(provenance)) {
    failures.add('suitor $id: palette provenance must be measured|judged — '
        'derivation IS measurement; memory-judgment must say so, not wear '
        'measured clothes');
  } else if (provenance == 'judged' && ref != null) {
    final hasUrl = ref['url'] is String && (ref['url'] as String).isNotEmpty;
    final hasShot = ref['shot'] != null;
    if (hasUrl || hasShot) {
      failures.add('suitor $id: palette judged but "$source" has '
          '${hasUrl ? 'a url' : 'a shot'} — derivation was possible (arxa '
          'palette derive over the reference); judged stays legal only when '
          'the reference has neither');
    }
  } else if (provenance == 'measured' &&
      (p['evidence'] as List? ?? const []).whereType<Map>().isEmpty) {
    failures.add('suitor $id: palette provenance measured but no evidence — '
        'derivation IS measurement and the engine JSON it produces is the '
        'proof; measured with no citation is a lie-shaped record');
  }
  failures.addAll(_checkEvidence(p['evidence'],
      owner: 'suitor $id palette', moodboardDir: moodboardDir));
  return failures;
}

List<String> _checkSuitorChoice(
    Map<String, dynamic> choice, List<Map> suitors,
    {required bool selectionApproved}) {
  final failures = <String>[];
  if (!selectionApproved) {
    failures.add('suitorChoice recorded while selectionStatus is not '
        'approved — the audition comes AFTER the reference selection gate');
  }
  final ids = suitors.map((s) => s['id']).whereType<String>().toSet();
  final primary = choice['primary'];
  if (primary is! String || !ids.contains(primary)) {
    failures.add('suitorChoice.primary "$primary" is not one of the '
        'auditioned suitors ({${ids.join(', ')}})');
  }
  for (final r in (choice['remix'] as List? ?? const []).whereType<Map>()) {
    final remix = r.cast<String, dynamic>();
    final attribute = remix['attribute'];
    if (attribute is! String || !suitorRemixAttributes.contains(attribute)) {
      failures.add('suitorChoice.remix attribute "$attribute" outside the '
          'closed vocabulary (${suitorRemixAttributes.join(', ')})');
    }
    final from = remix['from'];
    if (from is! String || !ids.contains(from)) {
      failures.add('suitorChoice.remix "$attribute" from "$from" — not an '
          'auditioned suitor');
    } else if (primary is String && from == primary) {
      failures.add('suitorChoice.remix "$attribute" from the primary suitor '
          "itself — a remix clause amends the primary with a sibling's attribute");
    }
  }
  return failures;
}

/// The locked-proof law: on new-style records a score >= 3 on a LOCKED
/// criterion must cite lens evidence naming that criterion. A hallucinated
/// 5 passes the old record's arithmetic — it cannot pass an audition.
List<String> _checkLockedProof(
    List<Map> boards, Set<String> locked,
    {String? moodboardDir}) {
  final failures = <String>[];
  if (locked.isEmpty) return failures;
  for (final b in boards) {
    final boardId = b['id'] ?? '?';
    for (final r in (b['references'] as List? ?? const []).whereType<Map>()) {
      final ref = r.cast<String, dynamic>();
      final refName = ref['name'] ?? ref['url'] ?? '?';
      final scores = (ref['scores'] as Map? ?? const {});
      for (final id in locked) {
        final s = scores[id];
        if (s is! num || s < 3) continue;
        final citing = (ref['evidence'] as List? ?? const [])
            .whereType<Map>()
            .where((e) => e['criterion'] == id)
            .toList();
        if (citing.isEmpty) {
          failures.add('$boardId/$refName: scores $id=$s (locked) with no '
              'lens evidence citing it — capture or measure the behavior, or '
              'score <= 2');
        } else if (moodboardDir != null) {
          for (final e in citing) {
            final file = e['file'];
            if (file is String &&
                !File('$moodboardDir/$file').existsSync()) {
              failures.add('$boardId/$refName: evidence file "$file" '
                  '(criterion $id) does not resolve under $moodboardDir');
            }
          }
        }
      }
    }
  }
  return failures;
}

List<String> _checkEvidence(Object? raw,
    {required String owner, String? moodboardDir}) {
  final failures = <String>[];
  for (final e in (raw as List? ?? const []).whereType<Map>()) {
    final entry = e.cast<String, dynamic>();
    final kind = entry['kind'];
    if (kind is! String || kind.isEmpty) {
      failures.add('$owner: evidence entry without a kind '
          '(tokens|motion|capture)');
    }
    final file = entry['file'];
    if (file is! String || file.isEmpty) {
      failures.add('$owner: evidence entry without a file');
    } else if (moodboardDir != null &&
        !File('$moodboardDir/$file').existsSync()) {
      failures.add('$owner: evidence file "$file" does not resolve under '
          '$moodboardDir');
    }
  }
  return failures;
}

double _weightedTotal(Map<String, dynamic> scores, Map<String, double> criteria) {
  if (criteria.isEmpty) return 0.0;
  var sum = 0.0;
  var weights = 0.0;
  for (final e in criteria.entries) {
    final s = scores[e.key];
    final v = (s is num) ? s.toDouble() : 0.0;
    sum += v * e.value;
    weights += e.value;
  }
  return weights == 0 ? 0 : sum / weights;
}
