import 'dart:convert';
import 'dart:io';

/// The curated memory layer (`memory/` at the repo root): durable facts and
/// per-stage lesson logs. appbox owns this tree — appbox kit's `memory/` is
/// the template, never a dependency (docs/plans/appbox-memory-and-payment.md,
/// M1).
///
/// Write-path doctrine: raw events are appended by deterministic writers
/// (gates, runner, gateway) to the appboxd data dir; curated lessons are
/// promoted only through here, and a write is refused unless triggered by an
/// observed gate failure. The mem0 production audit (97.8% junk memories in
/// 32 days) is what unconstrained "what's worth remembering" writes produce —
/// the write path is the bottleneck, not the model.
class MemoryCurator {
  MemoryCurator(this.root);

  /// The `memory/` directory (repo root in production; a temp dir in tests).
  final Directory root;

  /// Hard line cap per stage LESSONS.md (the Claude Code adherence ceiling).
  static const int lessonsCap = 200;

  /// Header marker: everything up to and including this line is preserved on
  /// cap enforcement; the oldest lesson lines below it are dropped first.
  static const String lessonsHeaderEnd = '## Lessons';

  File _lessonsFile(String stage) =>
      File('${root.path}/stages/$stage.LESSONS.md');

  File _factsFile(String topic) => File('${root.path}/facts/$topic.json');

  /// Appends [lesson] to the stage's LESSONS.md as one `- ` line, then
  /// enforces the 200-line cap by dropping the oldest lessons (header kept).
  ///
  /// Gate-triggered writes only: throws [StateError] unless [gateFailed] —
  /// an observed gate failure is the sole legitimate write trigger.
  void appendLesson(String stage, String lesson, {required bool gateFailed}) {
    if (!gateFailed) {
      throw StateError(
        'refused: lessons are written only on observed gate failure '
        '(gateFailed: false)',
      );
    }
    final file = _lessonsFile(stage);
    if (!file.existsSync()) {
      throw ArgumentError('no lessons file for stage: $stage');
    }
    final lines = file.readAsLinesSync();
    lines.add('- $lesson');
    final headerEnd = lines.indexOf(lessonsHeaderEnd);
    if (headerEnd < 0) {
      throw StateError(
          '${file.path} is missing the "$lessonsHeaderEnd" marker');
    }
    final overflow = lines.length - lessonsCap;
    if (overflow > 0) {
      lines.removeRange(headerEnd + 1, headerEnd + 1 + overflow);
    }
    file.writeAsStringSync('${lines.join('\n')}\n');
  }

  /// The lesson lines for [stage] (header excluded), for prompt assembly —
  /// they sit inside the stage prompt's static prefix, so they ride the
  /// provider prompt cache and cost ~0 on repeat runs.
  List<String> lessonsFor(String stage) {
    final file = _lessonsFile(stage);
    if (!file.existsSync()) return const [];
    final lines = file.readAsLinesSync();
    final headerEnd = lines.indexOf(lessonsHeaderEnd);
    if (headerEnd < 0) return const [];
    return [
      for (final l in lines.sublist(headerEnd + 1))
        if (l.trim().isNotEmpty) l,
    ];
  }

  /// The durable facts for [topic] from `facts/<topic>.json` — a list of
  /// `{fact, source, ts}` entries.
  List<Map<String, dynamic>> readFacts(String topic) {
    final decoded = jsonDecode(_factsFile(topic).readAsStringSync());
    return [
      for (final e in decoded as List) Map<String, dynamic>.from(e as Map),
    ];
  }
}
