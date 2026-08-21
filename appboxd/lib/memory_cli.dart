// appbox memory — project-scoped memory verbs (arxa H5, engine side).
//
//   appbox memory add    --project <dir> --topic <t> --source <stage> "fact"
//   appbox memory recall --project <dir> [--topic <t>] [--grep <q>]
//   appbox memory why    --project <dir> <topic> <index>
//
// The store is `<project>/memory/` — the same layout and `{fact, source, ts}`
// schema as the engine's own repo memory (one vocabulary, one curator class).
// The engine owns memory; harnesses are its hands: the dsh plugin and Pi
// extension call these verbs rather than touching files
// (docs/plans/arxa-harness-and-distribution.md, G.17).
//
// Write-path doctrine (appbox-memory-and-payment.md M1): every fact carries a
// mandatory source — stages write memory as pipeline output, and a write with
// no provenance is refused rather than accepted quietly.

import 'dart:io';

import 'package:appboxd/memory_curate.dart';

const _usage = '''
usage: appbox memory <verb> [options]

  add    --project <dir> --topic <t> --source <stage-or-event> "<fact>"
  recall --project <dir> [--topic <t>] [--grep <substring>]
  why    --project <dir> <topic> <index>

The store is <project>/memory/facts/<topic>.json; --project defaults to the
current directory. Every fact records {fact, source, ts}; `why` answers with
the provenance recall elides.
''';

int _fail(String msg) {
  stderr.writeln('appbox memory: $msg');
  return 64;
}

Future<int> memoryCli(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    stdout.write(_usage);
    return args.isEmpty ? 64 : 0;
  }
  final verb = args.first;
  String project = Directory.current.path;
  String? topic;
  String? source;
  String? grep;
  final positional = <String>[];
  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--project':
        if (++i >= args.length) return _fail('--project needs a value');
        project = args[i];
      case '--topic':
        if (++i >= args.length) return _fail('--topic needs a value');
        topic = args[i];
      case '--source':
        if (++i >= args.length) return _fail('--source needs a value');
        source = args[i];
      case '--grep':
        if (++i >= args.length) return _fail('--grep needs a value');
        grep = args[i];
      default:
        positional.add(args[i]);
    }
  }
  if (!Directory(project).existsSync()) {
    return _fail('no such project dir: $project');
  }
  final curator = MemoryCurator(Directory('$project/memory'));

  switch (verb) {
    case 'add':
      if (topic == null) return _fail('add needs --topic');
      if (source == null) {
        return _fail('add needs --source — every fact must name the stage or '
            'event that produced it');
      }
      if (positional.length != 1) {
        return _fail('add takes exactly one fact string');
      }
      try {
        curator.addFact(topic, positional.single, source: source);
      } on Error catch (e) {
        return _fail('$e');
      } on Exception catch (e) {
        return _fail('$e');
      }
      stdout.writeln('$topic#${curator.readFacts(topic).length - 1} recorded');
      return 0;

    case 'recall':
      final topics = topic != null ? [topic] : curator.topics();
      var shown = 0;
      for (final t in topics) {
        final List<Map<String, dynamic>> facts;
        try {
          facts = curator.readFacts(t);
        } catch (e) {
          return _fail('facts/$t.json does not parse — $e');
        }
        for (var i = 0; i < facts.length; i++) {
          final fact = facts[i]['fact'] as String? ?? '';
          if (grep != null &&
              !fact.toLowerCase().contains(grep.toLowerCase())) {
            continue;
          }
          stdout.writeln('[$t#$i] $fact');
          shown++;
        }
      }
      if (shown == 0) {
        stdout.writeln(topic != null && !curator.topics().contains(topic)
            ? 'no topic "$topic" (topics: ${curator.topics().join(', ')})'
            : 'no matching facts');
      }
      return 0;

    case 'why':
      if (positional.length != 2) {
        return _fail('why takes <topic> <index>');
      }
      final t = positional[0];
      final idx = int.tryParse(positional[1]);
      if (idx == null) return _fail('index must be a number');
      final List<Map<String, dynamic>> facts;
      try {
        facts = curator.readFacts(t);
      } catch (_) {
        return _fail('no topic "$t" (topics: ${curator.topics().join(', ')})');
      }
      if (idx < 0 || idx >= facts.length) {
        return _fail('$t has ${facts.length} facts — index $idx is out of '
            'range');
      }
      final f = facts[idx];
      stdout.writeln('fact:   ${f['fact']}');
      stdout.writeln('source: ${f['source']}');
      stdout.writeln('ts:     ${f['ts']}');
      return 0;

    default:
      return _fail('unknown verb "$verb"\n$_usage');
  }
}
