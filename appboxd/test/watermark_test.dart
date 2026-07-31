// Acceptance bar for the provenance/watermark pass (lib/watermark.dart):
// free tier injects the marker + watermark line into every supported file and
// emits a sha256 manifest; paid tier emits a clean provenance header with no
// watermark line. Idempotency, shebang/doctype preservation, and json-skip
// behaviour mirror the archived Node.js reference (tools/watermark/watermark.mjs).

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/watermark.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('appbox_watermark_');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Seed a small emitted tree spanning every supported extension plus json.
  void seed() {
    File(p.join(tmp.path, 'main.dart')).writeAsStringSync('void main() {}\n');
    File(p.join(tmp.path, 'app.js')).writeAsStringSync("console.log('hi');\n");
    File(p.join(tmp.path, 'conf.yaml')).writeAsStringSync('key: value\n');
    File(p.join(tmp.path, 'run.sh')).writeAsStringSync('#!/usr/bin/env bash\necho hi\n');
    File(p.join(tmp.path, 'index.html'))
        .writeAsStringSync('<!DOCTYPE html>\n<html></html>\n');
    File(p.join(tmp.path, 'data.json')).writeAsStringSync('{"a":1}\n');
    Directory(p.join(tmp.path, 'sub')).createSync();
    File(p.join(tmp.path, 'sub', 'note.ts')).writeAsStringSync('export const x = 1;\n');
  }

  test('free tier watermarks every supported file and skips unsupported/json', () {
    seed();
    final manifest = runPass(tmp.path, tier: 'free');

    expect(manifest['tier'], 'free');
    final files = (manifest['files'] as List).cast<Map<String, Object?>>();
    expect(files.length, 7); // 6 supported + json, .sh shebang preserved

    // The marker is present in every non-json supported file.
    for (final name in ['main.dart', 'app.js', 'conf.yaml', 'run.sh', 'index.html']) {
      final src = File(p.join(tmp.path, name)).readAsStringSync();
      expect(src.contains(marker), true, reason: name);
      expect(src.contains(watermarkLine), true, reason: name);
    }
    // Nested file is watermarked too.
    expect(File(p.join(tmp.path, 'sub', 'note.ts')).readAsStringSync().contains(marker),
        true);

    // JSON gets no inline marker; it carries a manifest note instead.
    final jsonSrc = File(p.join(tmp.path, 'data.json')).readAsStringSync();
    expect(jsonSrc.contains(marker), isFalse);
    final jsonEntry = files.firstWhere((e) => e['path'] == 'data.json');
    expect(jsonEntry['note'], isNotNull);
    expect((jsonEntry['sha256'] as String).length, 64);

    // Manifest written at root, not listed inside itself.
    final manifestFile = File(p.join(tmp.path, manifestName));
    expect(manifestFile.existsSync(), isTrue);
    final decoded = jsonDecode(manifestFile.readAsStringSync());
    expect((decoded as Map)['tier'], 'free');
  });

  test('paid tier emits provenance but no watermark line', () {
    seed();
    final manifest = runPass(tmp.path, tier: 'paid');

    expect(manifest['tier'], 'paid');
    final dart = File(p.join(tmp.path, 'main.dart')).readAsStringSync();
    expect(dart.startsWith('// $marker'), true);
    expect(dart.contains(watermarkLine), isFalse);
    expect(dart.contains('licence: paid'), true);
  });

  test('idempotent: a second pass does not re-inject', () {
    seed();
    runPass(tmp.path, tier: 'free');
    final before = File(p.join(tmp.path, 'main.dart')).readAsStringSync();
    final manifest = runPass(tmp.path, tier: 'free');
    final after = File(p.join(tmp.path, 'main.dart')).readAsStringSync();
    expect(after, before);
    // sha is stable across re-runs (content unchanged after first pass).
    final dartHash = (manifest['files'] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((e) => e['path'] == 'main.dart')['sha256'];
    expect(dartHash, isNotNull);
  });

  test('shebang stays on line 1; html block lands after <!DOCTYPE>', () {
    seed();
    runPass(tmp.path, tier: 'free');

    final sh = File(p.join(tmp.path, 'run.sh')).readAsStringSync();
    expect(sh.startsWith('#!/usr/bin/env bash\n'), true);
    expect(sh.contains('# $marker'), true);

    final html = File(p.join(tmp.path, 'index.html')).readAsStringSync();
    // No comment before the doctype (would trigger quirks mode).
    expect(html.startsWith('<!DOCTYPE html>'), true);
    expect(html.contains('<!-- $marker'), true);
  });

  test('unknown extension is skipped, manifest only lists handled files', () {
    File(p.join(tmp.path, 'logo.png')).writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);
    File(p.join(tmp.path, 'main.dart')).writeAsStringSync('void main() {}\n');
    final manifest = runPass(tmp.path, tier: 'free');
    final paths = (manifest['files'] as List)
        .map((e) => (e as Map<String, Object?>)['path'])
        .toSet();
    expect(paths, contains('main.dart'));
    expect(paths.any((n) => n.toString().endsWith('.png')), isFalse);
  });
}
