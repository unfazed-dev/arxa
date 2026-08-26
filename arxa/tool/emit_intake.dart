// emit_intake — emit the DERIVED intake artifacts into a REPO app dir.
//
// The repo-mode bridge while `arxa intake emit --project` still targets
// ~/.arxa (which repo mode must never touch — the shadow law): this tool
// runs the same pure emitters over <app-dir>/intake/answers.json and writes
// the derived set IN PLACE. It never touches the elicited/committed files
// (answers.json, brief.md, registry.json, story-map outputs) and skips any
// derived file that already exists — this is a catch-up tool, not a
// regenerator; re-emitting over committed history is a decision, not a
// default.
//
//   dart run tool/emit_intake.dart <app-dir> [--force]
//
// --force overwrites existing derived files (moodboard.json included) for
// deliberate re-emits after an answers edit — that is what the landing
// token edits use; without it the tool only fills gaps.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/intake.dart';
import 'package:arxa/intake_artifacts.dart';
import 'package:arxa/decision_log.dart';
import 'package:arxa/prd_adr.dart';

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('usage: dart run tool/emit_intake.dart <app-dir> [--force]');
    exit(64);
  }
  final dir = args.first;
  final force = args.contains('--force');
  final answersFile = File('$dir/intake/answers.json');
  if (!answersFile.existsSync()) {
    stderr.writeln('no intake/answers.json under $dir');
    exit(1);
  }
  final answers =
      (jsonDecode(answersFile.readAsStringSync()) as Map).cast<String, dynamic>();
  final errs = validateIntake(answers).errors;
  if (errs.isNotEmpty) {
    for (final e in errs) {
      stderr.writeln('ERROR $e');
    }
    exit(1);
  }
  const json = JsonEncoder.withIndent('  ');
  void put(String rel, String bytes) {
    final f = File('$dir/intake/$rel');
    if (f.existsSync() && !force) {
      stdout.writeln('skip (exists): $rel');
      return;
    }
    f.writeAsStringSync(bytes);
    stdout.writeln('wrote: $rel');
  }

  put('flows.json', '${json.convert(emitFlows(answers))}\n');
  put('personas.json', '${json.convert(emitPersonas(answers))}\n');
  put('map.json',
      '${json.convert(mergeStoryMap(emitStoryMap(answers), '$dir/intake/map.json'))}\n');
  put('direction.json', '${json.convert(emitDirection(answers))}\n');
  put('moodboard.json', '${json.convert(emitMoodboard(answers))}\n');
  put('prd.md', emitPrd(answers));
  writeDecisionLog('$dir/intake', collectDecisions(answers));
  stdout.writeln('decision log refreshed (decisions.json + adr/)');
}
