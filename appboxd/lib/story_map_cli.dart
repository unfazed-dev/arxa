// story_map_cli — `appbox emit story-map` entry module.
//
// Exposes [storyMapMain], the callable the dispatcher in bin/appbox.dart routes
// to. Parses flags, reads JSON (file or stdin), validates, and writes the HTML
// (+ optional data JSON + brief). Exit codes: 0 success, 1 validation/parse
// error, 64 usage (missing --output). `--self-test` runs the embedded check.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/story_map.dart';

const _usage = '''
Usage: appbox emit story-map [options]

Options:
  -i, --input <path>     Input JSON file (reads stdin if omitted)
  -o, --output <path>    Output HTML file (required, unless --self-test)
      --data-out <path>  Write the validated story-map data JSON here
      --brief-out <path> Write the gate-compatible design brief here
      --self-test        Run the embedded self-check and exit
''';

/// Entry point for `appbox emit story-map`. Returns the process exit code.
int storyMapMain(List<String> args) {
  String? input;
  String? output;
  String? dataOut;
  String? briefOut;
  var selfTest = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--input':
      case '-i':
        if (++i >= args.length) return _usageErr('flag $a needs a value');
        input = args[i];
        break;
      case '--output':
      case '-o':
        if (++i >= args.length) return _usageErr('flag $a needs a value');
        output = args[i];
        break;
      case '--data-out':
        if (++i >= args.length) return _usageErr('flag $a needs a value');
        dataOut = args[i];
        break;
      case '--brief-out':
        if (++i >= args.length) return _usageErr('flag $a needs a value');
        briefOut = args[i];
        break;
      case '--self-test':
        selfTest = true;
        break;
      case '-h':
      case '--help':
        stdout.write(_usage);
        return 0;
      default:
        return _usageErr('unknown flag $a');
    }
  }

  if (selfTest) {
    storyMapSelfTest();
    print('self-test OK');
    return 0;
  }

  if (output == null) {
    return _usageErr('--output is required (unless --self-test)');
  }

  Map<String, dynamic> data;
  try {
    final src = input != null
        ? File(input).readAsStringSync()
        : _readStdinSync();
    data = jsonDecode(src) as Map<String, dynamic>;
  } on FormatException catch (e) {
    stderr.writeln('JSON parse error: $e');
    return 1;
  } on PathNotFoundException {
    stderr.writeln('File not found: $input');
    return 1;
  }

  final errors = validateData(data);
  if (errors.isNotEmpty) {
    for (final err in errors) {
      stderr.writeln('Validation error: $err');
    }
    return 1;
  }

  File(output).writeAsStringSync(renderHtml(data));
  print('Story map generated: $output');

  if (dataOut != null) {
    File(dataOut).writeAsStringSync(serializeDataJson(data));
    print('Story-map data written: $dataOut');
  }

  if (briefOut != null) {
    final d = deriveSurfaces(data);
    File(briefOut).writeAsStringSync(renderBrief(data, d));
    print('Design brief written: $briefOut '
        '(${d.surfaces.length} surfaces, ${d.outOfScope.length} out-of-scope)');
  }
  return 0;
}

int _usageErr(String msg) {
  stderr.writeln('appbox emit story-map: $msg');
  stderr.write(_usage);
  return 64;
}

/// Read stdin fully as UTF-8 (byte-faithful). `Stdin` exposes no bulk sync
/// read, so collect bytes one at a time until EOF (-1); story maps are small.
String _readStdinSync() {
  final bytes = <int>[];
  int b;
  while ((b = stdin.readByteSync()) >= 0) {
    bytes.add(b);
  }
  return utf8.decode(bytes);
}

/// Embedded self-check — the same assertions as the Python `_self_test()`:
/// ids match the gate pattern, are unique, CJK → 's', all-wont → out-of-scope,
/// rollup = strongest priority + earliest release, storyless feature → blank
/// rollup, and the brief's surface table is exactly what the gate would parse.
/// Throws on any regression.
void storyMapSelfTest() {
  final sample = <String, dynamic>{
    'project': 'Self-Test App',
    'releases': [
      {'name': 'Release 1'},
      {'name': 'Release 2'},
    ],
    'epics': [
      {
        'name': 'User System',
        'features': [
          {
            'name': 'Registration & Login',
            'stories': [
              {'name': 'Phone signup', 'priority': 'must', 'release': 'Release 1'},
            ],
          },
          {
            'name': '注册',
            'stories': [
              {'name': 'Phone signup', 'priority': 'must', 'release': 'Release 1'},
            ],
          },
          {
            'name': 'Legacy SSO',
            'stories': [
              {'name': 'SAML login', 'priority': 'wont', 'release': 'Release 2'},
            ],
          },
        ],
      },
      {
        'name': 'User System',
        'features': [
          {'name': 'Registration & Login', 'stories': <Map<String, dynamic>>[]},
        ],
      },
    ],
  };

  if (validateData(sample).isNotEmpty) {
    throw StateError('sample must validate');
  }
  final d = deriveSurfaces(sample);
  final ids = d.surfaces.map((s) => s.id).toList();
  for (final id in ids) {
    if (!idRe.hasMatch(id)) {
      throw StateError('ids must match gate pattern: $ids');
    }
  }
  if (ids.toSet().length != ids.length) {
    throw StateError('duplicate ids: $ids');
  }
  if (ids.any((i) => i.contains('legacy'))) {
    throw StateError('all-wont feature must not be a surface');
  }
  if (!d.outOfScope.contains(OutOfScope('User System', 'Legacy SSO'))) {
    throw StateError('all-wont feature must be out-of-scope');
  }
  if (ids[0] != 'user.registration') {
    throw StateError('first-word slug: ${ids[0]}');
  }
  final byId = {for (final s in d.surfaces) s.id: s};
  if (byId['user.registration']!.priority != 'must') {
    throw StateError('rollup: strongest priority');
  }
  if (byId['user.registration']!.release != 'Release 1') {
    throw StateError('rollup: earliest release');
  }
  final empty = byId['user2.registration2']!;
  if (empty.priority != '' || empty.release != '') {
    throw StateError('no stories -> blank rollup');
  }
  final brief = renderBrief(sample, d);
  // Simulate the gate's table parse: first id-shaped cell per row.
  final sepRe = RegExp(r'^[-: ]+$');
  final found = <String>[];
  for (final line in brief.split('\n')) {
    final s = line.trim();
    if (!s.startsWith('|') || !s.endsWith('|')) continue;
    final stripped = s
        .replaceAll(RegExp(r'^\|+'), '')
        .replaceAll(RegExp(r'\|+$'), '');
    final cells = stripped
        .split('|')
        .map((c) => c.trim().replaceAll(RegExp(r'^`+'), '').replaceAll(RegExp(r'`+$'), ''))
        .toList();
    if (cells.isNotEmpty && cells.every((c) => c.isNotEmpty && sepRe.hasMatch(c))) {
      continue;
    }
    for (final c in cells) {
      if (idRe.hasMatch(c)) {
        found.add(c);
        break;
      }
    }
  }
  found.sort();
  final expected = ids.toSet().toList()..sort();
  if (found.length != expected.length ||
      !_listEq(found, expected)) {
    throw StateError('gate would see $found, expected $ids');
  }
  if (!brief.contains('Out of scope') || !brief.contains('Legacy SSO')) {
    throw StateError('brief missing out-of-scope section');
  }
  renderHtml(sample); // HTML path must not regress.
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
