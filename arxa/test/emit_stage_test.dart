// emit_stage test — write-on-diff semantics, gating, stamping, idempotency, binary.
//
// Ports the discriminating behaviours of tools/vendor/stages/emit.py:
//   - new-app greenfield write + stamp
//   - idempotency (a second unchanged run writes nothing)
//   - extension points preserved; generated overwritten on arxa replay
//   - arbitrary existing target: dry-run blocks, apply writes, no stamp w/o adopt
//   - binary (png) round-trip + skip-on-identical

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arxa/emit_stage.dart';
import 'package:test/test.dart';

/// Shared manifest fixture. `platforms: ['ios']` keeps the Android-Compose helper
/// out of these tests (no android/ scaffold); no web/ keeps passkeys/drift no-op.
final defaultManifest = <String, dynamic>{
  'factoryVersion': '1.2.3',
  'source': 'design-v1',
  'stack': 'stacked',
  'lastMode': 'new-app',
  'blueprintHash': 'abc123',
  'templatesVersion': '2026-07-30',
  'appName': 'myapp',
  'displayName': 'MyApp',
  'platforms': ['ios'],
  'generatedLayer': ['lib/main.dart', 'lib/generated.dart'],
  'extensionPoints': ['lib/login_view.dart'],
};

/// Plant a blueprint package (manifest.json + 3 templates) and return its path.
String plantBlueprint(Directory tmp, {Map<String, dynamic>? manifest}) {
  final bp = '${tmp.path}/bp';
  Directory('$bp/templates/lib').createSync(recursive: true);
  File('$bp/manifest.json').writeAsStringSync(jsonEncode(manifest ?? defaultManifest));
  File('$bp/templates/lib/main.dart').writeAsStringSync('// main\n');
  File('$bp/templates/lib/generated.dart').writeAsStringSync('// generated\n');
  File('$bp/templates/lib/login_view.dart').writeAsStringSync('// extension stub\n');
  return bp;
}

/// Empty target dir.
String newTarget(Directory tmp, String name) {
  final t = '${tmp.path}/$name';
  Directory(t).createSync(recursive: true);
  return t;
}

Map<String, dynamic> readReport(String bp) =>
    jsonDecode(File('$bp/report.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('emit-stage-test-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('greenfield new-app writes generated + extension, stamps, emits report.json', () {
    final bp = plantBlueprint(tmp);
    final t = newTarget(tmp, 'greenfield');

    expect(emitStage(bp, t), 0, reason: 'new-app emits cleanly');

    // every template written verbatim
    expect(File('$t/lib/main.dart').readAsStringSync(), '// main\n');
    expect(File('$t/lib/generated.dart').readAsStringSync(), '// generated\n');
    expect(File('$t/lib/login_view.dart').readAsStringSync(), '// extension stub\n');

    // arxa stamp carries the blueprint metadata
    final stamp =
        jsonDecode(File('$t/.arxa/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    expect(stamp['factoryVersion'], '1.2.3');
    expect(stamp['blueprintHash'], 'abc123');
    expect(stamp['appName'], 'myapp');
    expect(stamp['displayName'], 'MyApp');

    // report.json (in the blueprint dir) reports the greenfield adoption
    final report = readReport(bp);
    expect(report['isNewApp'], true);
    expect(report['replay'], true);
    expect(report['applied'], false);
    expect(report['stamped'], true);
    expect((report['written'] as List).cast<String>(),
        containsAll(['lib/main.dart', 'lib/generated.dart', 'lib/login_view.dart']));
    expect(report['skipped_identical'], isEmpty);
    expect(report['blocked_dryrun'], isEmpty);
  });

  test('idempotent: a second unchanged run writes nothing', () {
    final bp = plantBlueprint(tmp);
    final t = newTarget(tmp, 'idempotent');
    emitStage(bp, t);

    final mainBefore = File('$t/lib/main.dart').readAsStringSync();
    final stampBefore = File('$t/.arxa/manifest.json').readAsStringSync();

    expect(emitStage(bp, t), 0);

    // templates skipped as identical; nothing newly written
    final report = readReport(bp);
    expect((report['written'] as List), isEmpty);
    expect((report['skipped_identical'] as List).cast<String>(),
        containsAll(['lib/main.dart', 'lib/generated.dart', 'lib/login_view.dart']));

    // the first run stamped the target, so the second run detects it as arxa-built
    // (ADR-0002 #3 — .arxa/manifest.json present) and still replays freely.
    expect((report['isArxa'] as Map)['isArxa'], true);
    expect(report['replay'], true);
    expect(report['stamped'], true);

    // file bytes unchanged by the no-op replay
    expect(File('$t/lib/main.dart').readAsStringSync(), mainBefore);
    expect(File('$t/.arxa/manifest.json').readAsStringSync(), stampBefore);
  });

  test('extension points preserved; generated overwritten on arxa replay', () {
    final bp = plantBlueprint(tmp);
    final t = newTarget(tmp, 'replay');
    // make it an existing arxa-built target (stamped + has a pubspec)
    Directory('$t/.arxa').createSync(recursive: true);
    File('$t/.arxa/manifest.json').writeAsStringSync(jsonEncode({'factoryVersion': 'old'}));
    File('$t/pubspec.yaml').writeAsStringSync('name: myapp\n');
    // pre-existing extension point carrying OPERATOR business logic (≠ template)
    Directory('$t/lib').createSync(recursive: true);
    File('$t/lib/login_view.dart').writeAsStringSync('// OPERATOR business logic\n');
    // pre-existing generated file that has drifted from the template
    File('$t/lib/generated.dart').writeAsStringSync('// stale generated\n');

    expect(emitStage(bp, t), 0);

    // extension point untouched (operator owns it); generated refreshed; absent written
    expect(File('$t/lib/login_view.dart').readAsStringSync(), '// OPERATOR business logic\n');
    expect(File('$t/lib/generated.dart').readAsStringSync(), '// generated\n');
    expect(File('$t/lib/main.dart').readAsStringSync(), '// main\n');

    final report = readReport(bp);
    expect(report['replay'], true);
    expect(report['isNewApp'], false);
    expect((report['preserved_extension'] as List).cast<String>(), ['lib/login_view.dart']);
    final written = (report['written'] as List).cast<String>();
    expect(written, containsAll(['lib/main.dart', 'lib/generated.dart']));
    expect(written, isNot(contains('lib/login_view.dart')));
    expect(report['stamped'], true);
  });

  test('arbitrary existing target: dry-run blocks generated, then apply writes it', () {
    final bp = plantBlueprint(tmp);
    final t = newTarget(tmp, 'arbitrary');
    File('$t/pubspec.yaml').writeAsStringSync('name: existing\n'); // existing app, no .arxa
    Directory('$t/lib').createSync(recursive: true);
    File('$t/lib/generated.dart').writeAsStringSync('// user code\n'); // differs from template

    // dry-run (apply defaults to false): a differing generated file is blocked,
    // while absent files (main + the extension stub) are written additively.
    expect(emitStage(bp, t), 0);
    expect(File('$t/lib/generated.dart').readAsStringSync(), '// user code\n', reason: 'blocked');
    expect(File('$t/lib/main.dart').readAsStringSync(), '// main\n', reason: 'absent → written');
    expect(File('$t/lib/login_view.dart').readAsStringSync(), '// extension stub\n');

    var report = readReport(bp);
    expect(report['replay'], false);
    expect(report['isNewApp'], false);
    expect((report['blocked_dryrun'] as List).cast<String>(), ['lib/generated.dart']);
    expect(report['stamped'], false, reason: 'arbitrary target: no stamp without adopt');
    expect(File('$t/.arxa/manifest.json').existsSync(), isFalse);

    // apply: the differing generated file is now written; the extension point
    // (now present, identical) is skipped, not preserved.
    expect(emitStage(bp, t, apply: true), 0);
    expect(File('$t/lib/generated.dart').readAsStringSync(), '// generated\n');

    report = readReport(bp);
    expect(report['applied'], true);
    expect((report['written'] as List).cast<String>(), ['lib/generated.dart']);
    expect((report['blocked_dryrun'] as List), isEmpty);
    expect(report['stamped'], false, reason: 'apply alone never stamps an arbitrary target');
  });

  test('mode line: arbitrary target is not reported as arxa-replay', () {
    // capture print() output
    final lines = <String>[];
    String run(void Function() body) {
      lines.clear();
      runZoned(body,
          zoneSpecification: ZoneSpecification(
              print: (self, parent, zone, line) => lines.add(line)));
      return lines.join('\n');
    }

    // arbitrary existing target: mode must be 'arbitrary' (or 'new-app'),
    // never 'arxa-replay' — the {'isArxa': false} map is not truthy.
    final bp = plantBlueprint(tmp);
    final t = newTarget(tmp, 'mode-arbitrary');
    File('$t/pubspec.yaml').writeAsStringSync('name: existing\n');
    var out = run(() => emitStage(bp, t, apply: true));
    expect(out, contains('[mode=arbitrary'));

    // stamped arxa target: mode is 'arxa-replay'
    final t2 = newTarget(tmp, 'mode-arxa');
    Directory('$t2/.arxa').createSync(recursive: true);
    File('$t2/.arxa/manifest.json')
        .writeAsStringSync(jsonEncode({'factoryVersion': 'old'}));
    File('$t2/pubspec.yaml').writeAsStringSync('name: myapp\n');
    out = run(() => emitStage(bp, t2));
    expect(out, contains('[mode=arxa-replay'));
  });

  test('binary (png) assets round-trip raw and skip-on-identical', () {
    final bp = '${tmp.path}/bp_png';
    Directory('$bp/templates/assets/png').createSync(recursive: true);
    // a PNG-shaped header (0x89 50 4E 47 …) that would break a UTF-8 text read
    final bytes =
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
    File('$bp/templates/assets/png/brand_google.png').writeAsBytesSync(bytes);
    File('$bp/manifest.json').writeAsStringSync(jsonEncode({
      ...defaultManifest,
      'generatedLayer': ['assets/png/brand_google.png'],
      'extensionPoints': <String>[],
    }));

    final t = newTarget(tmp, 'png');
    expect(emitStage(bp, t), 0);
    expect(File('$t/assets/png/brand_google.png').readAsBytesSync(), bytes,
        reason: 'binary copied byte-for-byte');

    // second run: byte-identical → skipped, never decoded as text
    expect(emitStage(bp, t), 0);
    final report = readReport(bp);
    expect((report['skipped_identical'] as List).cast<String>(),
        ['assets/png/brand_google.png']);
    expect((report['written'] as List), isEmpty);
    expect(File('$t/assets/png/brand_google.png').readAsBytesSync(), bytes);
  });
}
