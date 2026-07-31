// Tests for kb_check — schema validation, per-kit coverage (>=3 sources),
// and playbook References-block detection. Each case builds a throwaway tree
// (kb/sources.json + memory/facts + per-kit playbooks) and asserts the
// ported checker flags or passes as expected.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/kb_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kb_check_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Writes [relPath] (repo-relative) with [contents], creating parent dirs.
  File f(String relPath, String contents) {
    final file = File(p.join(tmp.path, relPath))..createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  /// Seeds a kit: a fact file and (by default) a well-formed playbook.
  void kit(String name, {bool playbook = true, String fact = '{}'}) {
    f('memory/facts/$name.json', fact);
    if (playbook) {
      f('$name/${name}_playbook.mdx',
          '# $name\n\n<!-- kb:begin -->\n- [x] refs\n<!-- kb:end -->\n');
    }
  }

  group('schema validation', () {
    test('flags a source missing a required key', () {
      kit('acme');
      f('kb/sources.json', jsonEncode({
        'sources': [
          {'id': 'a', 'title': 'A', 'url': 'https://a', 'kind': 'official',
           'kits': ['acme']},
          // 'title' missing.
          {'id': 'b', 'url': 'https://b', 'kind': 'api', 'kits': ['acme']},
          {'id': 'c', 'title': 'C', 'url': 'https://c', 'kind': 'package',
           'kits': ['acme']},
        ]
      }));
      final r = kbCheck(tmp.path);
      expect(r.ok, isFalse);
      expect(r.errors, anyElement(contains('b: missing {title}')));
    });

    test('flags a bad kind and a bad url', () {
      kit('acme');
      f('kb/sources.json', jsonEncode({
        'sources': [
          {'id': 'a', 'title': 'A', 'url': 'not-a-url', 'kind': 'bogus',
           'kits': ['acme']},
        ]
      }));
      final r = kbCheck(tmp.path);
      expect(r.ok, isFalse);
      expect(r.errors, anyElement(contains('a: bad kind')));
      expect(r.errors, anyElement(contains('a: bad url')));
    });

    test('flags a duplicate id', () {
      kit('acme');
      f('kb/sources.json', jsonEncode({
        'sources': [
          {'id': 'dup', 'title': 'A', 'url': 'https://a', 'kind': 'official',
           'kits': ['acme']},
          {'id': 'dup', 'title': 'B', 'url': 'https://b', 'kind': 'api',
           'kits': ['acme']},
          {'id': 'c', 'title': 'C', 'url': 'https://c', 'kind': 'package',
           'kits': ['acme']},
        ]
      }));
      final r = kbCheck(tmp.path);
      expect(r.errors, anyElement(contains('duplicate id: dup')));
    });
  });

  group('coverage', () {
    test('errors when a kit has fewer than three sources', () {
      kit('acme');
      f('kb/sources.json', jsonEncode({
        'sources': [
          {'id': 'a', 'title': 'A', 'url': 'https://a', 'kind': 'official',
           'kits': ['acme']},
          {'id': 'b', 'title': 'B', 'url': 'https://b', 'kind': 'api',
           'kits': ['acme']},
        ]
      }));
      final r = kbCheck(tmp.path);
      expect(r.ok, isFalse);
      expect(r.errors, anyElement(contains('acme: only 2 source(s)')));
    });

    test('passes when every kit has at least three sources', () {
      kit('acme');
      f('kb/sources.json', jsonEncode({
        'sources': [
          {'id': 'a', 'title': 'A', 'url': 'https://a', 'kind': 'official',
           'kits': ['acme']},
          {'id': 'b', 'title': 'B', 'url': 'https://b', 'kind': 'api',
           'kits': ['acme']},
          {'id': 'c', 'title': 'C', 'url': 'https://c', 'kind': 'package',
           'kits': ['acme']},
        ]
      }));
      expect(kbCheck(tmp.path).ok, isTrue);
    });

    test("a '*' kit list covers every known kit", () {
      kit('acme');
      kit('beta');
      f('kb/sources.json', jsonEncode({
        'sources': [
          {'id': 'wild', 'title': 'W', 'url': 'https://w', 'kind': 'official',
           'kits': const ['*']},
        ]
      }));
      // The single wildcard covers all kits → >= 3 only if exactly one source
      // is counted; both kits get exactly 1 source, so both must error.
      final r = kbCheck(tmp.path);
      expect(r.errors, anyElement(contains('acme: only 1 source(s)')));
      expect(r.errors, anyElement(contains('beta: only 1 source(s)')));
    });
  });

  group('playbook references', () {
    test('errors when a kit playbook is missing', () {
      kit('acme', playbook: false);
      f('kb/sources.json', jsonEncode({
        'sources': List.generate(3, (i) => {
              'id': 's$i', 'title': 'S$i', 'url': 'https://s$i',
              'kind': 'official', 'kits': ['acme'],
            })
      }));
      final r = kbCheck(tmp.path);
      expect(r.errors,
          anyElement(contains('acme: missing acme_playbook.mdx')));
    });

    test('errors when the References block markers are absent', () {
      kit('acme', playbook: false);
      f('acme/acme_playbook.mdx', '# Acme\nNo references here.\n');
      f('kb/sources.json', jsonEncode({
        'sources': List.generate(3, (i) => {
              'id': 's$i', 'title': 'S$i', 'url': 'https://s$i',
              'kind': 'official', 'kits': ['acme'],
            })
      }));
      final r = kbCheck(tmp.path);
      expect(r.errors,
          anyElement(contains('missing kb:begin/kb:end References block')));
    });
  });
}
