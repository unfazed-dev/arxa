// mem_b — the MEM-B writer (docs/plans/architecture.md §4).
//
// MEM-A is the repo's own memory/ (how arxa behaves). MEM-B is the memory
// file that TRAVELS WITH the delivered app (`MEM-B.md` at the app root):
// what happened to THIS app — assembled at scaffold time from the curated
// MEM-A memory relevant to the build (memory/facts/, memory/stages/) plus the
// pipeline state, and written write-on-diff like the other emitters.
// Readable by someone who has never installed arxa; neither file reads the
// other (MEM-A works with the app deleted).
//
// TODO(MEM-B): §4's full shape also records per-app decision history —
// deviations from the frozen design + their approvals, what the client
// rejected. That needs a per-app decision event stream that does not exist
// yet; this is the honest core (assemble + write + idempotent).

import 'dart:convert';
import 'dart:io';

/// Assembles the MEM-B.md content for [appName] from the repo memory under
/// [repoRoot]. Deterministic — no timestamps — so the write-on-diff emitter
/// stays idempotent: same inputs, same bytes.
String assembleMemB(
  String repoRoot, {
  required String appName,
  List<String> surfaces = const [],
  List<String> targets = const [],
  List<String> factors = const [],
}) {
  final out = StringBuffer()
    ..writeln('# MEM-B — $appName')
    ..writeln()
    ..writeln('> arxa MEM-B (architecture §4): what happened to THIS app. '
        'Travels with the delivered codebase and is readable without arxa '
        'installed. Regenerated write-on-diff at scaffold time — edit the '
        'sources (repo memory/, pipeline state), not this file.');

  out
    ..writeln()
    ..writeln('## Build')
    ..writeln('- targets: ${targets.isEmpty ? '(none recorded)' : targets.join(', ')}')
    ..writeln('- derived form factors: ${factors.isEmpty ? '(none recorded)' : factors.join(', ')}')
    ..writeln('- surfaces scaffolded: ${surfaces.length}'
        '${surfaces.isEmpty ? '' : ' (${surfaces.join(', ')})'}');

  // Pipeline state: one line of measured history, never fabricated — absent
  // scorecard means no recorded runs.
  final scorecard = File('$repoRoot/pipeline/state/scorecard.jsonl');
  out
    ..writeln()
    ..writeln('## Pipeline state');
  if (scorecard.existsSync()) {
    var runs = 0, passed = 0, failed = 0;
    for (final line in scorecard.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        final entry = (jsonDecode(line) as Map).cast<String, dynamic>();
        runs++;
        if (entry['gate_pass'] == true) passed++;
        if (entry['gate_pass'] == false) failed++;
      } on FormatException {
        // A corrupt scorecard line is skipped, not fatal.
      }
    }
    out.writeln('- stage runs recorded: $runs '
        '(gate pass $passed, gate fail $failed) — pipeline/state/scorecard.jsonl');
  } else {
    out.writeln('- no recorded stage runs (pipeline/state/scorecard.jsonl absent)');
  }

  // MEM-A facts (memory/facts/*.json — lists of {fact, source, ts}).
  final factsDir = Directory('$repoRoot/memory/facts');
  final facts = <String>[];
  if (factsDir.existsSync()) {
    final files = factsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      try {
        for (final entry in jsonDecode(file.readAsStringSync()) as List) {
          final fact = (entry as Map)['fact'];
          if (fact is String && fact.isNotEmpty) facts.add(fact);
        }
      } on FormatException {
        // A corrupt facts file is skipped, not fatal.
      }
    }
  }
  out
    ..writeln()
    ..writeln('## Facts (MEM-A — memory/facts/)');
  if (facts.isEmpty) {
    out.writeln('- (none recorded)');
  } else {
    for (final fact in facts) {
      out.writeln('- $fact');
    }
  }

  // MEM-A stage lessons (memory/stages/<stage>.LESSONS.md, '-' lines only).
  final stagesDir = Directory('$repoRoot/memory/stages');
  out
    ..writeln()
    ..writeln('## Stage lessons (MEM-A — memory/stages/)');
  var anyLessons = false;
  if (stagesDir.existsSync()) {
    final files = stagesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.LESSONS.md'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final stage = file.path.split('/').last.replaceAll('.LESSONS.md', '');
      final lessons = file
          .readAsLinesSync()
          .where((l) => l.startsWith('- '))
          .toList();
      if (lessons.isEmpty) continue;
      anyLessons = true;
      out.writeln('### $stage');
      for (final lesson in lessons) {
        out.writeln(lesson);
      }
    }
  }
  if (!anyLessons) out.writeln('- (none recorded)');

  return out.toString();
}

/// Writes [content] to `<appRoot>/MEM-B.md`, write-on-diff like the other
/// emitters. Returns true when the file was (re)written.
bool writeMemB(String appRoot, String content) {
  final file = File('$appRoot/MEM-B.md');
  if (file.existsSync() && file.readAsStringSync() == content) return false;
  file.writeAsStringSync(content);
  return true;
}
