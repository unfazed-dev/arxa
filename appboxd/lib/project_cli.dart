// project_cli — CLI entry for `appbox project`.
//
//   appbox project init <name> [--targets 390,744,1280] [--locales en,pl]
//   appbox project use <name>
//   appbox project list
//
// All commands honor APPBOX_HOME (see project.dart). Exit: 0 ok · 2 usage.

import 'dart:io';

import 'package:appboxd/project.dart';

int projectMain(List<String> args) {
  if (args.isEmpty) return _usage();
  switch (args.first) {
    case 'init':
      return _init(args.sublist(1));
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
  final name = args.first;
  var targets = const ['390', '744', '1280'];
  var locales = const ['en', 'pl'];
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
  init <name> [--targets 390,744,1280] [--locales en,pl]
               Create ~/.appbox/projects/<name>/ (intake/design/build/settings)
  use <name>   Make <name> the current project
  list         List projects (* = current)

Honors APPBOX_HOME (default ~/.appbox).''');
  return 2;
}
