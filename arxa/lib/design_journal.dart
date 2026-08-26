/// The Design Journal — undo/redo for the Draft Overlay
/// (locked plan `docs/plans/arxa-dial-undo-redo.md`, 2026-08-26).
///
/// Locked facts that shape this file:
///   - decision 1: a per-artifact journal file beside the draft, surviving
///     reload and server restart; commit is the barrier — the journal never
///     crosses it, and it never rewrites git;
///   - decision 2: gesture coalescing — consecutive writes carrying the same
///     island-minted gesture id against the same key merge into one step;
///     the island decides when a gesture ends (focus move, ~1s idle, tier
///     change) by minting a new id, so the server never runs a timer;
///   - decision 4: `_commitDraft()` clears the journal in the transaction
///     that consumes the overlay;
///   - decision 5: linear redo — recording a new step truncates the undone
///     tail (array + cursor, no undo tree).
///
/// Single-writer rule: the dial server owns this file. The island only
/// marks step boundaries (gesture ids) and renders `{undoDepth, redoDepth}`.
///
/// A step stores full JSON snapshots of ONE overlay entry — a token value
/// or a patch — before and after the gesture (`null` = entry absent). Undo
/// writes `before` back into the overlay; redo writes `after`. Snapshots
/// re-enter the overlay through the same `DraftPatch.fromJson` /
/// token-validation law as the `/draft` API, so a corrupt journal can
/// never smuggle in what a hostile draft could not.
///
/// Storage: one JSON file per artifact under ~/.arxa/journal/, keyed like
/// the draft (basename + path hash). Unreadable journal ⇒ warn and start
/// blank — history is a convenience and must never break a serve.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'design_draft.dart';
import 'project.dart' show arxaHome;

/// Validation caps. A journal is bounded by the draft it shadows — each
/// snapshot obeys DraftCaps — so these only bound step count and label
/// sizes against a runaway or hostile file.
abstract class JournalCaps {
  /// Max retained steps; recording past this drops the oldest step.
  static const steps = 200;

  /// Max length of a gesture id or step key.
  static const label = 160;
}

/// Which overlay map a step touches.
enum JournalScope { token, patch }

/// One undoable step: the before/after snapshots of a single overlay entry.
class JournalStep {
  const JournalStep({
    required this.gesture,
    required this.scope,
    required this.key,
    required this.before,
    required this.after,
  });

  /// Island-minted opaque id marking the gesture this step belongs to.
  final String gesture;

  final JournalScope scope;

  /// Token name (`--x`) or patch key (`el:...` etc.).
  final String key;

  /// JSON snapshot of the entry before the gesture; null = absent.
  /// Tokens: a String value. Patches: a `DraftPatch.toJson()` map.
  final Object? before;

  /// JSON snapshot after the gesture; null = absent.
  final Object? after;

  Map<String, dynamic> toJson() => {
        'gesture': gesture,
        'scope': scope.name,
        'key': key,
        if (before != null) 'before': before,
        if (after != null) 'after': after,
      };

  static JournalStep fromJson(Object? raw, int i) {
    if (raw is! Map) {
      throw FormatException('journal step $i must be an object');
    }
    final gesture = '${raw['gesture'] ?? ''}';
    final key = '${raw['key'] ?? ''}';
    if (gesture.isEmpty || gesture.length > JournalCaps.label) {
      throw FormatException('journal step $i has a bad gesture id');
    }
    if (key.isEmpty || key.length > JournalCaps.label) {
      throw FormatException('journal step $i has a bad key');
    }
    final scope = JournalScope.values.asNameMap()['${raw['scope']}'];
    if (scope == null) {
      throw FormatException('journal step $i has a bad scope');
    }
    final before = _snapshot(raw['before'], scope, key, i, 'before');
    final after = _snapshot(raw['after'], scope, key, i, 'after');
    return JournalStep(
        gesture: gesture, scope: scope, key: key, before: before, after: after);
  }

  /// Validates a snapshot through the SAME law the draft API enforces:
  /// token values via a probe overlay, patches via DraftPatch.fromJson.
  static Object? _snapshot(
      Object? raw, JournalScope scope, String key, int i, String what) {
    if (raw == null) return null;
    switch (scope) {
      case JournalScope.token:
        if (raw is! String) {
          throw FormatException('journal step $i.$what must be a string');
        }
        // Reuses draft validation by round-tripping a one-entry overlay.
        DraftOverlay.fromJson({
          'tokens': {key: raw}
        }, artifact: 'probe');
        return raw;
      case JournalScope.patch:
        return DraftPatch.fromJson(raw, key).toJson();
    }
  }
}

/// The journal: an append array + cursor. `cursor` counts applied steps —
/// steps[0..cursor) are undoable, steps[cursor..] are the redo tail.
class DesignJournal {
  DesignJournal({required this.artifact, List<JournalStep>? steps, int? cursor})
      : steps = steps ?? [],
        cursor = cursor ?? (steps?.length ?? 0);

  static const version = 1;

  final String artifact;
  final List<JournalStep> steps;
  int cursor;

  int get undoDepth => cursor;
  int get redoDepth => steps.length - cursor;

  /// Records one draft write. Truncates the redo tail (decision 5), then
  /// either coalesces into the last step (same gesture + scope + key,
  /// decision 2 — keeping its `before`, replacing its `after`) or appends
  /// a new step. Over JournalCaps.steps the oldest step falls off.
  void record({
    required String gesture,
    required JournalScope scope,
    required String key,
    required Object? before,
    required Object? after,
  }) {
    steps.removeRange(cursor, steps.length);
    final last = steps.isEmpty ? null : steps.last;
    if (last != null &&
        last.gesture == gesture &&
        last.scope == scope &&
        last.key == key) {
      steps[steps.length - 1] = JournalStep(
          gesture: gesture,
          scope: scope,
          key: key,
          before: last.before,
          after: after);
      return;
    }
    steps.add(JournalStep(
        gesture: gesture, scope: scope, key: key, before: before, after: after));
    if (steps.length > JournalCaps.steps) steps.removeAt(0);
    cursor = steps.length;
  }

  /// Moves the cursor back and applies the step's `before` to [overlay].
  /// Returns the applied step, or null at the barrier (nothing to undo).
  JournalStep? undo(DraftOverlay overlay) {
    if (cursor == 0) return null;
    final step = steps[--cursor];
    _write(overlay, step, step.before);
    return step;
  }

  /// Re-applies the next undone step's `after`. Null when no redo tail.
  JournalStep? redo(DraftOverlay overlay) {
    if (cursor == steps.length) return null;
    final step = steps[cursor++];
    _write(overlay, step, step.after);
    return step;
  }

  static void _write(DraftOverlay overlay, JournalStep step, Object? snap) {
    switch (step.scope) {
      case JournalScope.token:
        if (snap == null) {
          overlay.tokens.remove(step.key);
        } else {
          overlay.tokens[step.key] = snap as String;
        }
      case JournalScope.patch:
        if (snap == null) {
          overlay.patches.remove(step.key);
        } else {
          final patch = DraftPatch.fromJson(snap, step.key);
          if (patch.isEmpty) {
            overlay.patches.remove(step.key);
          } else {
            overlay.patches[step.key] = patch;
          }
        }
    }
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'artifact': artifact,
        'cursor': cursor,
        'steps': [for (final s in steps) s.toJson()],
      };

  static DesignJournal fromJson(Object? raw, {required String artifact}) {
    if (raw is! Map) {
      throw const FormatException('journal must be an object');
    }
    final rawSteps = raw['steps'];
    final steps = <JournalStep>[];
    if (rawSteps != null) {
      if (rawSteps is! List) {
        throw const FormatException('journal.steps must be an array');
      }
      if (rawSteps.length > JournalCaps.steps) {
        throw FormatException(
            'journal holds over ${JournalCaps.steps} steps');
      }
      for (var i = 0; i < rawSteps.length; i++) {
        steps.add(JournalStep.fromJson(rawSteps[i], i));
      }
    }
    final rawCursor = raw['cursor'];
    if (rawCursor is! int || rawCursor < 0 || rawCursor > steps.length) {
      throw const FormatException('journal.cursor is out of range');
    }
    return DesignJournal(artifact: artifact, steps: steps, cursor: rawCursor);
  }
}

/// File IO — mirrors DraftFileStore: one JSON file per artifact under
/// ~/.arxa/journal/, keyed by the artifact's absolute path. A moved
/// checkout starts fresh history, exactly as it starts a fresh draft.
class JournalFileStore {
  JournalFileStore({required String artifactDir, String? home})
      : artifact = p.basename(artifactDir),
        file = File(p.join(
            home ?? arxaHome(),
            'journal',
            '${_safe(p.basename(artifactDir))}-${_key(artifactDir)}.json'));

  final String artifact;
  final File file;

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  static String _key(String dir) =>
      sha256.convert(utf8.encode(p.normalize(dir))).toString().substring(0, 8);

  Future<DesignJournal> load() async {
    try {
      if (!await file.exists()) return DesignJournal(artifact: artifact);
      return DesignJournal.fromJson(jsonDecode(await file.readAsString()),
          artifact: artifact);
    } catch (e) {
      // Unreadable history must never break a serve — say so and start
      // blank; the file stays on disk until the next save overwrites it.
      stderr.writeln('[design-server] journal unreadable '
          '(${file.path}): $e — starting blank');
      return DesignJournal(artifact: artifact);
    }
  }

  Future<void> save(DesignJournal journal) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(journal.toJson()));
    await tmp.rename(file.path);
  }

  /// Clear-on-commit (decision 4): called inside `_commitDraft()` in the
  /// same operation that consumes the overlay.
  Future<void> clear() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A journal that refuses deletion must not 500 the commit; the next
      // load will report it if it is also unreadable.
    }
  }
}
