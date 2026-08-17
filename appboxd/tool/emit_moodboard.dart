// emit_moodboard — re-emit intake/moodboard.json IN PLACE from answers.json.
//
// The repo-mode bridge while `appbox intake emit` still targets
// ~/.appbox projects: repo projects keep their intake/ in the repo, and the
// moodboard record must be (re)published whenever the moodboard answer group
// changes (scores, selection). Same pure emitter, same bytes as intake emit.
//
//   dart run tool/emit_moodboard.dart <intake-dir>

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/intake_artifacts.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/emit_moodboard.dart <intake-dir>');
    exit(64);
  }
  final dir = args.first;
  final answersFile = File('$dir/answers.json');
  if (!answersFile.existsSync()) {
    stderr.writeln('no answers.json under $dir');
    exit(1);
  }
  final answers = (jsonDecode(answersFile.readAsStringSync()) as Map).cast<String, dynamic>();
  final out = emitMoodboard(answers);
  const encoder = JsonEncoder.withIndent('  ');
  File('$dir/moodboard.json').writeAsStringSync('${encoder.convert(out)}\n');
  stdout.writeln('moodboard.json: ${encoder.convert(out['counts'])}');
}
