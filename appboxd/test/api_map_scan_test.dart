// api_map_scan test — verifies the Dart port matches api_map_scan.sh.
// Covers map-grammar parsing (7 fields, ```map fence, # comments), enforced
// (E) detection, advisory (A) skipping, wildcard tokens, comment stripping,
// and the clean-lib pass.

import 'dart:io';

import 'package:appboxd/api_map_scan.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('apimap-test-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('enforced row banned token is flagged with sanctioned + problem class',
      () {
    final map = _map(tmp, [
      'flat-button | E | FlatButton | ElevatedButton | — | — | —',
    ]);
    _file(tmp, 'lib/main.dart', "Widget b() => FlatButton(onPressed: null, child: const Text('x'));\n");
    final v = scanApiMap(tmp.path, map);
    expect(v, hasLength(1));
    expect(v.single.token, 'FlatButton');
    expect(v.single.sanctioned, 'ElevatedButton');
    expect(v.single.problemClass, 'flat-button');
    expect(v.single.file, 'lib/main.dart');
  });

  test('advisory (mode A) rows are skipped (enforced row still scans)', () {
    final map = _map(tmp, [
      'flat-button | E | FlatButton | ElevatedButton | — | — | —',
      'will-pop | A | WillPopScope | PopScope | — | — | —',
    ]);
    // Both a banned E token and a banned A token appear; only the E one flags.
    _file(tmp, 'lib/main.dart',
        'Widget a() => FlatButton(onPressed: null, child: Container());\n'
        'Widget b() => WillPopScope(child: Container());\n');
    final v = scanApiMap(tmp.path, map);
    expect(v.map((e) => e.token).toList(), ['FlatButton'],
        reason: 'mode A (WillPopScope) is advisory and must not be scanned');
  });

  test('clean lib with no banned tokens returns empty', () {
    final map = _map(tmp, [
      'flat-button | E | FlatButton | ElevatedButton | — | — | —',
    ]);
    _file(tmp, 'lib/main.dart', 'Widget b() => ElevatedButton(onPressed: null, child: const Text("x"));\n');
    expect(scanApiMap(tmp.path, map), isEmpty);
  });

  test('wildcard token (*) matches via .*?', () {
    final map = _map(tmp, [
      'theme-getter | E | title*2018 | bodyLarge | — | — | —',
    ]);
    _file(tmp, 'lib/main.dart', 'final t = theme.titleLarge2018;\n');
    final v = scanApiMap(tmp.path, map);
    expect(v, hasLength(1));
    expect(v.single.token, 'title*2018');
  });

  test('Dart comments are stripped before matching', () {
    final map = _map(tmp, [
      'flat-button | E | FlatButton | ElevatedButton | — | — | —',
    ]);
    _file(
      tmp,
      'lib/main.dart',
      '// Widget b() => FlatButton(...);\n'
      '/* FlatButton legacy */\n'
      'Widget b() => ElevatedButton(onPressed: null, child: const Text("x"));\n',
    );
    expect(scanApiMap(tmp.path, map), isEmpty);
  });

  test('multiple tokens in one row are all detected, deduped + sorted', () {
    final map = _map(tmp, [
      'legacy-widgets | E | FlatButton,RaisedButton | ElevatedButton | — | — | —',
    ]);
    // Same token twice in one file → deduped; two distinct tokens → two hits.
    _file(tmp, 'lib/b.dart',
        'var a = FlatButton(onPressed: null);\nvar b = FlatButton(onPressed: null);\n');
    _file(tmp, 'lib/a.dart', 'var c = RaisedButton(onPressed: null);\n');
    final v = scanApiMap(tmp.path, map);
    expect(v.map((e) => '${e.file}|${e.token}').toList(), <String>[
      'lib/a.dart|RaisedButton',
      'lib/b.dart|FlatButton',
    ]);
    expect(v.every((e) => e.sanctioned == 'ElevatedButton'), isTrue);
  });

  test('malformed map row throws FormatException', () {
    final map = _map(tmp, [
      'too-few | E | FlatButton | ElevatedButton', // 4 fields, not 7
    ]);
    _file(tmp, 'lib/main.dart', 'FlatButton(...);\n');
    expect(() => scanApiMap(tmp.path, map), throwsA(isA<FormatException>()));
  });
}

/// Write the FLUTTER_API_MAP.md with a ```map fence around [rows].
String _map(Directory tmp, List<String> rows) {
  final buf = StringBuffer()
    ..writeln('# Flutter API Map')
    ..writeln()
    ..writeln('```map')
    ..writeln('# problem-class | mode | banned-tokens | material | cupertino | kit | urls');
    for (final r in rows) {
      buf.writeln(r);
    }
    buf.writeln('```');
  final path = '${tmp.path}/FLUTTER_API_MAP.md';
  File(path).writeAsStringSync(buf.toString());
  return path;
}

/// Create a file (with parent dirs) and write [content].
void _file(Directory tmp, String relPath, String content) {
  final f = File('${tmp.path}/$relPath');
  f.createSync(recursive: true);
  f.writeAsStringSync(content);
}
