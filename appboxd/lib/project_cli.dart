// project_cli — CLI entry for `appbox project`.
//
//   appbox project init <name> [--targets ios,android] [--locales en]
//   appbox project init --repo <dir> --kind site|app [--name n]
//                        [--targets web] [--locales en,fr]
//   appbox project sync <dir>  (kind/targets/locales from intake answers)
//   appbox project resolve     (report repo-mode binding from cwd)
//   appbox project use <name>
//   appbox project list
//
// The appbox law in two modes: `init <name>` creates an appbox-NATIVE
// project under APPBOX_HOME (no repo behind it); `init --repo` binds an
// EXISTING repo app dir as the single home of its pipeline state — all 8
// stage folders + kind-aware READMEs land in that dir, and a same-named
// ~/.appbox shadow is a hard error (repo_project.dart).
//
// All commands honor APPBOX_HOME (see project.dart). Exit: 0 ok · 2 usage.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/project.dart';
import 'package:appboxd/repo_project.dart';

int projectMain(List<String> args) {
  if (args.isEmpty) return _usage();
  switch (args.first) {
    case 'init':
      return _init(args.sublist(1));
    case 'sync':
      return _sync(args.sublist(1));
    case 'resolve':
      try {
        stdout.writeln(resolutionReport());
        return 0;
      } on StateError catch (e) {
        stderr.writeln(e.message);
        return 2;
      }
    case 'use':
      return _use(args.sublist(1));
    case 'list':
      for (final name in listProjects()) {
        stdout.writeln('${name == currentProject() ? '* ' : '  '}$name');
      }
      return 0;
    default:
      return _usage();
  }
}

int _init(List<String> args) {
  if (args.isEmpty) return _usage();
  // Repo mode: `init --repo <dir> --kind site|app ...` — the appbox law.
  if (args.first == '--repo') return _initRepo(args.sublist(1));
  final name = args.first;
  var targets = const ['ios', 'android'];
  var locales = const ['en'];
  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--targets':
        if (i + 1 >= args.length) return _missing('--targets');
        targets = args[++i].split(',').map((s) => s.trim()).toList();
      case '--locales':
        if (i + 1 >= args.length) return _missing('--locales');
        locales = args[++i].split(',').map((s) => s.trim()).toList();
      default:
        stderr.writeln('appbox project init: unknown flag ${args[i]}');
        return 2;
    }
  }
  try {
    ensureProject(name, targets: targets, locales: locales);
  } on ArgumentError catch (e) {
    stderr.writeln('appbox project init: ${e.message}');
    return 2;
  }
  stdout.writeln('project init: $name -> ${projectDir(name)}');
  return 0;
}

int _initRepo(List<String> args) {
  String? dir;
  String? kind;
  String? name;
  var targets = const <String>[];
  var locales = const <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--repo':
        if (i + 1 >= args.length) return _missing('--repo');
        dir = args[++i];
      case '--kind':
        if (i + 1 >= args.length) return _missing('--kind');
        kind = args[++i];
      case '--name':
        if (i + 1 >= args.length) return _missing('--name');
        name = args[++i];
      case '--targets':
        if (i + 1 >= args.length) return _missing('--targets');
        targets = args[++i].split(',').map((s) => s.trim()).toList();
      case '--locales':
        if (i + 1 >= args.length) return _missing('--locales');
        locales = args[++i].split(',').map((s) => s.trim()).toList();
      default:
        stderr.writeln('appbox project init --repo: unknown flag ${args[i]}');
        return 2;
    }
  }
  if (dir == null) {
    stderr.writeln('appbox project init --repo: --repo <dir> is required');
    return 2;
  }
  if (kind == null) {
    stderr.writeln('appbox project init --repo: --kind site|app is required '
        '(it decides the whole stack downstream)');
    return 2;
  }
  try {
    final p = ensureRepoProject(dir, name: name, kind: kind, targets: targets, locales: locales);
    stdout.writeln('project init (repo): ${p.name} [${p.kind}] -> ${p.dir}');
    stdout.writeln('stages: ${repoStages.join(', ')}');
    return 0;
  } on ArgumentError catch (e) {
    stderr.writeln('appbox project init --repo: ${e.message}');
    return 2;
  } on StateError catch (e) {
    stderr.writeln(e.message);
    return 2;
  }
}

/// Push intake answers into the repo marker: kind from product.kind, then
/// targets/locales from the answers' own groups (founder-stated SSOT wins
/// over init-time guesses, mirroring updateProjectSettings for home mode).
int _sync(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('appbox project sync: usage: sync <app-dir>');
    return 2;
  }
  final dir = args.first;
  final answersFile = File('$dir/intake/answers.json');
  if (!answersFile.existsSync()) {
    stderr.writeln('appbox project sync: no intake/answers.json under $dir — '
        'run intake first');
    return 2;
  }
  final Map<String, dynamic> answers;
  try {
    final v = jsonDecode(answersFile.readAsStringSync());
    if (v is! Map) throw const FormatException('answers not an object');
    answers = v.cast<String, dynamic>();
  } on FormatException catch (e) {
    stderr.writeln('appbox project sync: cannot read answers ($e)');
    return 2;
  }
  String? kind;
  final product = answers['product'];
  if (product is Map && product['kind'] is String) kind = product['kind'] as String;
  List<String>? targets;
  final t = answers['targets'];
  if (t is List) targets = t.cast<String>().toList();
  List<String>? locales;
  final l = answers['locales'];
  if (l is List) locales = l.cast<String>().toList();
  if (kind == null && targets == null && locales == null) {
    stderr.writeln('appbox project sync: nothing to sync (no product.kind, '
        'targets, or locales in answers)');
    return 2;
  }
  try {
    updateRepoProject(dir, kind: kind, targets: targets, locales: locales);
  } on ArgumentError catch (e) {
    stderr.writeln('appbox project sync: ${e.message}');
    return 2;
  }
  final done = [
    if (kind != null) 'kind=$kind',
    if (targets != null) 'targets=${targets.join(',')}',
    if (locales != null) 'locales=${locales.join(',')}',
  ].join(' ');
  stdout.writeln('project sync: $dir <- $done');
  return 0;
}

int _use(List<String> args) {
  if (args.isEmpty) return _usage();
  try {
    useProject(args.first);
  } on ArgumentError catch (e) {
    stderr.writeln('appbox project use: ${e.message}');
    return 2;
  }
  stdout.writeln('current project: ${args.first}');
  return 0;
}

int _missing(String flag) {
  stderr.writeln('appbox project: $flag requires a value');
  return 2;
}

int _usage() {
  stderr.writeln('''
Usage: appbox project <sub> [options]

Subcommands:
  init <name> [--targets ios,android] [--locales en]
               Create ~/.appbox/projects/<name>/ (intake/design/build/settings)
               — appbox-NATIVE projects only; never for a repo-backed app
  init --repo <dir> --kind site|app [--name n] [--targets web]
               [--locales en,fr]
               Bind an EXISTING repo app dir as the single home of its
               pipeline state: appbox.json marker + the 8 stage folders
               (intake moodboard design scaffold build test review deploy)
               with kind-aware READMEs. HARD ERROR when a same-named project
               shadows it in ~/.appbox/projects/ — the appbox law
  sync <dir>   Push kind/targets/locales from <dir>/intake/answers.json
               into the appbox.json marker
  resolve      Report repo-mode binding from cwd (or ~/.appbox fallback)
  use <name>   Make <name> the current project
  list         List projects (* = current)

Honors APPBOX_HOME (default ~/.appbox).''');
  return 2;
}
