// gen_freshness test — verifies the Dart port's comparator + discovery halves.
//
// build_runner cannot run offline (needs Flutter), so the build step is injected
// via BuildRunnerFn. The tests exercise file discovery, drift detection,
// identical-file pass, the empty-target short-circuit, and the build-failed
// path. Mirrors gen_freshness.py's `_self_test` (the COMPARATOR half).

import 'dart:io';

import 'package:arxa/gen_freshness.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gen-freshness-test-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // A build step that produces NO fresh output. Used to observe which files
  // _genFiles discovered: every discovered generated file is then reported as
  // "committed but not regenerated" (the orphan case).
  Future<({bool ok, String log})> emptyBuild(String _, String _) async =>
      (ok: true, log: '');

  test('empty target (no generated files) passes without invoking build',
      () async {
    _file(tmp, 'lib/app/app_view.dart', '// hand-written\n');
    // gen is empty → build_runner is never invoked; no buildRunner injected.
    final r = await genFreshness(tmp.path);
    expect(r.passed, isTrue);
    expect(r.freshN, 0);
    expect(r.drifted, isEmpty);
  });

  test('discovery — only .router/.locator/.gen.dart are checked', () async {
    _file(tmp, 'lib/app/app.router.dart', '// r\n');
    _file(tmp, 'lib/app/app.locator.dart', '// l\n');
    _file(tmp, 'lib/presentation/x.gen.dart', '// g\n');
    _file(tmp, 'lib/presentation/x_view.dart',
        '// hand-written — must be ignored\n');
    // build/ subtrees are never descended into (regenerable, not source).
    _file(tmp, 'lib/build/skip.gen.dart', '// must be skipped\n');

    final r = await genFreshness(tmp.path, buildRunner: emptyBuild);
    expect(r.freshN, 3);
    expect(r.passed, isFalse);
    final files = r.drifted.map((d) => d['file']).toSet();
    expect(files, {
      'app/app.router.dart',
      'app/app.locator.dart',
      'presentation/x.gen.dart',
    });
    expect(files, isNot(contains('presentation/x_view.dart')));
    expect(files, isNot(contains('build/skip.gen.dart')));
    // every drifted entry is the orphan case (fresh output absent).
    for (final d in r.drifted) {
      expect(d['reason'], 'committed but not regenerated');
    }
  });

  test('diff detection — committed differs from fresh → drift', () async {
    // committed (STALE): homeShellView = '/' (the real atlet bug shape)
    const committed = "  static const homeShellView = '/';\n";
    // fresh (CORRECT): splashView = '/' (initial) — simulate build_runner output
    const fresh = "  static const splashView = '/';\n";
    _file(tmp, 'lib/app/app.router.dart', committed);

    final r = await genFreshness(tmp.path, buildRunner: (src, work) async {
      _file(Directory(work), 'lib/app/app.router.dart', fresh);
      return (ok: true, log: '');
    });

    expect(r.passed, isFalse);
    expect(r.drifted, hasLength(1));
    expect(r.drifted.single['file'], 'app/app.router.dart');
    expect(r.drifted.single['committedSha'],
        isNot(equals(r.drifted.single['freshSha'])));
    expect(r.drifted.single['committedSha']!.length, 12);
  });

  test('identical files → no drift', () async {
    const content = "  static const splashView = '/';\n";
    _file(tmp, 'lib/app/app.router.dart', content);

    final r = await genFreshness(tmp.path, buildRunner: (src, work) async {
      _file(Directory(work), 'lib/app/app.router.dart', content);
      return (ok: true, log: '');
    });

    expect(r.passed, isTrue);
    expect(r.drifted, isEmpty);
    expect(r.freshN, 1);
  });

  test('build_runner failure → buildFailed result with log tail', () async {
    _file(tmp, 'lib/app/app.router.dart', '// r\n');
    final r = await genFreshness(tmp.path,
        buildRunner: (src, work) async => (ok: false, log: 'build_runner boom'));
    expect(r.passed, isFalse);
    expect(r.buildFailed, isTrue);
    expect(r.logTail, 'build_runner boom');
    expect(r.freshN, 0);
  });
}

/// Create a file (with parent dirs) and write [content].
void _file(Directory root, String relPath, String content) {
  final f = File('${root.path}/$relPath');
  f.createSync(recursive: true);
  f.writeAsStringSync(content);
}
