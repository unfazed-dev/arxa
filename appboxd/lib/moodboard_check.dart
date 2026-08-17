// moodboard_check — the deterministic gate over intake/moodboard.json.
//
// The moodboarder's subagents SCORE references by judgment; this check owns
// the arithmetic and the law, so a scoring mistake cannot silently starve
// the designer of references (the energize failure: 88 shots on disk, a
// zeros stub on record, nothing selected, 3D deferred).
//
//   appbox moodboard check <intake-dir> [--floor 3.0]
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
// A record with no boards (intake ran before moodboarding) is green-empty —
// that is a pipeline position, not a corruption.

import 'dart:convert';
import 'dart:io';

int moodboardCheckMain(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: appbox moodboard check <intake-dir> [--floor 3.0]');
    return 2;
  }
  final dir = args.first;
  var floor = 3.0;
  for (var i = 1; i < args.length; i++) {
    if (args[i] == '--floor' && i + 1 < args.length) {
      floor = double.tryParse(args[++i]) ?? floor;
    } else {
      stderr.writeln('appbox moodboard check: unknown flag ${args[i]}');
      return 2;
    }
  }
  final f = File('$dir/moodboard.json');
  if (!f.existsSync()) {
    stderr.writeln('appbox moodboard check: no moodboard.json under $dir');
    return 2;
  }
  final Map<String, dynamic> rec;
  try {
    final v = jsonDecode(f.readAsStringSync());
    if (v is! Map) throw const FormatException('not an object');
    rec = v.cast<String, dynamic>();
  } on FormatException catch (e) {
    stderr.writeln('appbox moodboard check: cannot read moodboard.json ($e)');
    return 2;
  }
  final failures = checkMoodboardRecord(rec, floor: floor);
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
List<String> checkMoodboardRecord(Map<String, dynamic> rec, {double floor = 3.0}) {
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

  for (final b in boards.cast<Map<String, dynamic>>()) {
    final boardId = b['id'] ?? '?';
    var selectedCount = 0;
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
      if (ref['selected'] == true) {
        selectedCount++;
        if (total < floor) {
          failures.add('$boardId/$refName: selected but total ${total.toStringAsFixed(2)} < floor $floor');
        }
      }
    }
    if ((b['references'] as List? ?? const []).isNotEmpty && selectedCount == 0) {
      failures.add('$boardId: no selected reference — the designer gets nothing from this board');
    }
  }

  // Locked intake criteria must be FED: at least one selected reference
  // scoring >= 3 on the locked criterion, anywhere in the record.
  for (final id in locked) {
    var fed = false;
    for (final b in boards.cast<Map<String, dynamic>>()) {
      for (final r in (b['references'] as List? ?? const []).whereType<Map>()) {
        final ref = r.cast<String, dynamic>();
        if (ref['selected'] == true) {
          final s = (ref['scores'] as Map? ?? const {})[id];
          if (s is num && s >= 3) fed = true;
        }
      }
    }
    if (!fed) {
      failures.add('locked criterion "$id" has no selected reference scoring >= 3 — '
          'an intake-locked requirement is about to be dropped again');
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
