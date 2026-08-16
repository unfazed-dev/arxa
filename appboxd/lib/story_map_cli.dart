// story_map_cli — `appbox emit story-map` entry module.
//
// Exposes [storyMapMain], the callable the dispatcher in bin/appbox.dart routes
// to. Parses flags, reads JSON (file or stdin), validates, and writes the HTML
// (+ optional data JSON + brief). Exit codes: 0 success, 1 validation/parse
// error, 64 usage (missing --output). `--self-test` runs the embedded check.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/intake.dart' show repoRoot, validateIntake;
import 'package:appboxd/story_map.dart';

const _usage = '''
Usage: appbox emit story-map [options]

Options:
  -i, --input <path>     Input JSON file (reads stdin if omitted)
  -o, --output <path>    Output HTML file (required, unless --self-test)
      --data-out <path>  Write the validated story-map data JSON here
      --brief-out <path> Write the gate-compatible design brief here
      --answers <path>   Intake answers for the UNIFIED chain brief
                         (default: pipeline/state/run.intake.json, then
                         default.intake.json, under the repo root)
      --self-test        Run the embedded self-check and exit

Input JSON contract (validated before anything is written; exit 1 lists
every defect at once):
  project    string, required — the product name
  releases   non-empty array of {name} — release names are UNIQUE (each is
             a swimlane; a duplicate makes the order ambiguous)
  epics      non-empty array of {name, features}
  features   non-empty array of {name, id?, stories}
               id — optional explicit surface id (e.g. app.mediaRive);
               unique document-wide, no spaces/'|'/backticks. Without it
               the id is derived: <epic-slug>.<feature-slug>
  stories    array of {name, priority, release, description?, points?}
               priority — must|should|could|wont (MoSCoW)
               release  — must name one of the releases above
               name     — unique within its feature
  Duplicate epic/feature NAMES are fine (slug suffixing); duplicate release
  names, explicit feature ids and per-feature story names are errors.
''';

/// Writes [content] to [path], creating parent dirs as needed — emitters run
/// in from-scratch folders where docs/intake/ does not exist yet (this used
/// to crash with PathNotFoundException; the repo layout pre-created the dirs).
void _writeCreatingDirs(String path, String content) {
  final f = File(path);
  if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
}

/// Entry point for `appbox emit story-map`. Returns the process exit code.
int storyMapMain(List<String> args) {
  String? input;
  String? output;
  String? dataOut;
  String? briefOut;
  String? answersPath;
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
      case '--answers':
        if (++i >= args.length) return _usageErr('flag $a needs a value');
        answersPath = args[i];
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

  // Answers only matter when a brief is being written. Resolve + validate
  // BEFORE any artefact is written: invalid answers exit 1 writing nothing.
  Map<String, dynamic>? answers;
  if (briefOut != null) {
    if (answersPath != null && !File(answersPath).existsSync()) {
      stderr.writeln('Intake answers: file not found: $answersPath');
      return 1;
    }
    answers = _loadAnswers(answersPath);
    if (answers != null) {
      final aErrs = validateIntake(answers).errors;
      if (aErrs.isNotEmpty) {
        for (final err in aErrs) {
          stderr.writeln('Intake answers error: $err');
        }
        return 1;
      }
    }
  }

  _writeCreatingDirs(output, renderHtml(data));
  print('Story map generated: $output');

  if (dataOut != null) {
    _writeCreatingDirs(dataOut, serializeDataJson(data));
    print('Story-map data written: $dataOut');
  }

  if (briefOut != null) {
    final d = deriveSurfaces(data);
    _writeCreatingDirs(briefOut, renderBrief(data, derived: d, answers: answers));
    print('Design brief written: $briefOut '
        '(${d.surfaces.length} surfaces, ${d.outOfScope.length} out-of-scope)');
  }
  return 0;
}

/// Load intake answers for the unified brief. Explicit [path] wins; otherwise
/// auto-discover pipeline/state/run.intake.json then default.intake.json under
/// the repo root (same order as gate_intake's `_resolveAnswers`). A state file
/// wrapping answers under an "answers" key is unwrapped; anything that is not
/// an answers Map (missing file, `null` slot) means "no answers" — the brief
/// falls back to the standalone story-map rendering.
Map<String, dynamic>? _loadAnswers(String? path) {
  String? resolved = path;
  if (resolved == null) {
    final root = repoRoot();
    for (final rel in const [
      'pipeline/state/run.intake.json',
      'pipeline/state/default.intake.json',
    ]) {
      if (File('$root/$rel').existsSync()) {
        resolved = '$root/$rel';
        break;
      }
    }
  }
  if (resolved == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(File(resolved).readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('Intake answers $resolved: JSON parse error — $e');
    return null;
  }
  if (decoded is! Map) return null;
  final answers = decoded.containsKey('answers') ? decoded['answers'] : decoded;
  return answers is Map ? answers.cast<String, dynamic>() : null;
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
  final brief = renderBrief(sample, derived: d);
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

  // F1 — hostile client strings must not reach the brief as active markup.
  final hostile = <String, dynamic>{
    'project': 'P <script>alert(1)</script>',
    'releases': [
      {'name': 'R1'}
    ],
    'epics': [
      {
        'name': 'E',
        'features': [
          {
            'name': 'F **bold** [x](https://evil.example)',
            'stories': [
              {'name': 'S<b>b</b>', 'priority': 'must', 'release': 'R1'},
            ],
          },
        ],
      },
    ],
  };
  if (validateData(hostile).isNotEmpty) {
    throw StateError('hostile VALUES are not shape defects');
  }
  final hostileBrief = renderBrief(hostile);
  if (hostileBrief.contains('<script>') ||
      hostileBrief.contains('<b>') ||
      hostileBrief.contains('[x](https://evil.example)') ||
      hostileBrief.contains('**bold**')) {
    throw StateError('raw markup leaked into the brief');
  }
  if (!hostileBrief.contains('&lt;script&gt;')) {
    throw StateError('payload must stay visible, escaped');
  }

  // F3 — duplicates that shadow downstream are rejected, and the message
  // names the offender.
  final dup = <String, dynamic>{
    'project': 'P',
    'releases': [
      {'name': 'R1'},
      {'name': 'R1'},
    ],
    'epics': [
      {
        'name': 'E',
        'features': [
          {'name': 'F', 'id': 'app.x', 'stories': []},
          {'name': 'F2', 'id': 'app.x', 'stories': []},
          {
            'name': 'F3',
            'stories': [
              {'name': 'Same', 'priority': 'must', 'release': 'R1'},
              {'name': 'Same', 'priority': 'wont', 'release': 'R1'},
            ],
          },
        ],
      },
    ],
  };
  final dupErrs = validateData(dup);
  if (!dupErrs.any((e) => e.contains("duplicate release name 'R1'")) ||
      !dupErrs.any((e) => e.contains("duplicate feature id 'app.x'")) ||
      !dupErrs.any((e) => e.contains('duplicate story name'))) {
    throw StateError('duplicate detection incomplete: $dupErrs');
  }
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
