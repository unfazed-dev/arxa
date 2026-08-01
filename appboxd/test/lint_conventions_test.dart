// Tests for the repo convention linter — the R2 + R3 Dart port.
//
// Each case builds a throwaway tree (config rule files + source fixtures)
// and asserts lintConventions flags or passes as expected. The rule files
// mirror the real contents of config/forbidden_abs_prefixes.txt and
// config/stripped_names.txt so the fixtures lint against the shipped rules.

import 'dart:io';

import 'package:appboxd/lint_conventions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lint_conventions_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // Real shipped rule contents.
  const absPrefixes = '# R3 prefixes\n/Volumes/\n/Users/\n';
  const strippedNames =
      '# R2 names\nflutter-crew\nkimi-design-htmx\nkimi-design\nbaoyu\nhuashu\np2\nasko\ncrew\n';

  /// Seeds [files] (repo-relative path → contents) plus the two rule files,
  /// and returns the temp root lintConventions should scan.
  String seed(Map<String, String> files) {
    for (final entry in {
      ...files,
      'config/forbidden_abs_prefixes.txt': absPrefixes,
      'config/stripped_names.txt': strippedNames,
    }.entries) {
      final f = File(p.join(tmp.path, entry.key));
      f.createSync(recursive: true);
      f.writeAsStringSync(entry.value);
    }
    return tmp.path;
  }

  group('R3 — absolute path literals', () {
    test('flags an absolute path literal outside config/', () {
      final root = seed({
        'lib/app.dart': 'const home = "/Volumes/dev/project";\n',
      });
      final result = lintConventions(root);
      expect(result.ok, isFalse);
      expect(
          result.violations,
          contains(predicate<LintViolation>((v) =>
              v.file == 'lib/app.dart' && v.message.contains('R3'))));
    });

    test('allows a literal inside config/ (the rule\'s own home)', () {
      final root = seed({
        'config/paths.json': '{"root": "/Volumes/x"}\n',
      });
      expect(lintConventions(root).ok, isTrue);
    });

    test('allows a path on a comment line', () {
      final root = seed({
        'lib/app.dart': '# see /Volumes/dev/project\n',
      });
      expect(lintConventions(root).ok, isTrue);
    });
  });

  group('R2 — stripped upstream names', () {
    test('flags a stripped name in file content', () {
      final root = seed({
        'lib/app.dart': 'final brand = "kimi-design";\n',
      });
      final result = lintConventions(root);
      expect(result.ok, isFalse);
      expect(
          result.violations,
          contains(predicate<LintViolation>((v) =>
              v.file == 'lib/app.dart' &&
              v.message.contains('kimi-design') &&
              v.message.contains('R2'))));
    });

    test('flags a stripped name in a file path', () {
      final root = seed({
        'lib/crew.dart': 'class A {}\n',
      });
      final result = lintConventions(root);
      expect(result.ok, isFalse);
      expect(
          result.violations,
          contains(predicate<LintViolation>(
              (v) => v.file == 'lib/crew.dart' && v.message.contains('path'))));
    });

    test('a stripped substring that is not a whole token is allowed', () {
      // "asko" appears only inside "askother" — not a whole word.
      final root = seed({
        'lib/app.dart': 'final x = askother();\n',
      });
      expect(lintConventions(root).ok, isTrue);
    });
  });

  test('clean source passes with no violations', () {
    final root = seed({
      'lib/app.dart': 'class App {}\n',
      'lib/main.dart': "void main() => print('hi');\n",
      'README.md': '# project\n', // .md is exempt
    });
    final result = lintConventions(root);
    expect(result.violations, isEmpty);
    expect(result.scanned, greaterThanOrEqualTo(2));
    expect(result.ok, isTrue);
  });

  group('exemptions', () {
    test('archives/ is skipped (frozen historical material)', () {
      final root = seed({
        'archives/old/tool.sh':
            'ROOT="/Volumes/dev/project" # flutter-crew era\n',
      });
      expect(lintConventions(root).ok, isTrue);
    });

    test('an SRI-pinned vendored artifact (manifest-listed) is skipped', () {
      final root = seed({
        'runtime/vendor/manifest.json':
            '[{"file": "upstream.min.js", "package": "x", "integrity": "sha384-abc"}]\n',
        // Mangled identifier in minified upstream code, not an authored ref.
        'runtime/vendor/upstream.min.js': 'function p2(){return p2+1}\n',
      });
      expect(lintConventions(root).ok, isTrue);
    });

    test('a file NOT listed in the sibling manifest is still linted', () {
      final root = seed({
        'runtime/vendor/manifest.json':
            '[{"file": "upstream.min.js", "package": "x", "integrity": "sha384-abc"}]\n',
        'runtime/vendor/glue_island.js': '// p2 reference\n',
      });
      final result = lintConventions(root);
      expect(result.ok, isFalse);
      expect(
          result.violations,
          contains(predicate<LintViolation>((v) =>
              v.file == 'runtime/vendor/glue_island.js' &&
              v.message.contains('p2'))));
    });
  });
}
