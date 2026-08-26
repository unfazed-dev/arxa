// kit_facts test — verifies the Dart port of extract_facts.sh.
//
// Covers stripNoncode edge cases (line/block/nested-block comments,
// triple/single-quoted strings hiding a `class`, raw strings, ${}
// interpolation balance), pubspec multiline-description + dependency parsing,
// public-surface kind detection + dedup, the comment/string-can't-yield-a-
// symbol guarantee, dependency topology classification, and the atomic write.
// Each test builds a temp-dir kit fixture so nothing touches the real tree.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/kit_facts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kit-facts-test-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('stripNoncode', () {
    test('line comment hides a class declaration', () {
      const src = '// class Ghost {}\nclass Real {}\n';
      final out = stripNoncode(src);
      expect(out, contains('Real'));
      expect(out, isNot(contains('Ghost')));
    });

    test('block comment hides its contents', () {
      const src = '/* class Hidden {} */\nclass Shown {}\n';
      final out = stripNoncode(src);
      expect(out, isNot(contains('Hidden')));
      expect(out, contains('Shown'));
    });

    test('nested block comments — Dart allows /* /* */ */ nesting', () {
      const src =
          '/* outer /* class NestedHidden {} */ still comment */\nclass Outer {}\n';
      final out = stripNoncode(src);
      expect(out, isNot(contains('NestedHidden')));
      // 'still comment' is inside the outer block → stripped too.
      expect(out, isNot(contains('still comment')));
      expect(out, contains('Outer'));
    });

    test('triple-quoted string hides a class keyword inside', () {
      const src = "var s = '''class InString {}''';\nclass Real {}\n";
      final out = stripNoncode(src);
      expect(out, isNot(contains('InString')));
      expect(out, contains('Real'));
    });

    test('double-quoted single-line string hides its contents', () {
      const src = 'var x = "class NotASymbol";\nclass Yes {}\n';
      final out = stripNoncode(src);
      expect(out, isNot(contains('NotASymbol')));
      expect(out, contains('Yes'));
    });

    test(r'${} interpolation — all string contents stripped, code survives', () {
      // KEEPER + TAIL are the outer string's content; INNER is the interpolated
      // string's content. All three must vanish; the declaration after survives.
      const src = 'var x = "KEEPER\${ "INNER" }TAIL";\nclass RealClass {}\n';
      final out = stripNoncode(src);
      expect(out, isNot(contains('KEEPER')));
      expect(out, isNot(contains('INNER')));
      expect(out, isNot(contains('TAIL')));
      expect(out, contains('class RealClass'));
    });

    test('raw string — backslash is literal, content still stripped', () {
      // In a raw string backslash is NOT an escape; the scanner must still treat
      // everything up to the closing quote as string content.
      const src = r'var x = r"raw\nclass Fake {}";' '\nclass Real {}\n';
      final out = stripNoncode(src);
      expect(out, isNot(contains('Fake')));
      expect(out, isNot(contains('raw')));
      expect(out, contains('class Real'));
    });

    test('unterminated string/comment consumes to end without crashing', () {
      const src = 'var x = "never closed\nmore code class End {}';
      expect(() => stripNoncode(src), returnsNormally);
      // The unterminated string swallows everything after it.
      expect(stripNoncode(src), isNot(contains('End')));
    });
  });

  group('extractFacts — pubspec', () {
    test('multiline folded description is joined; deps parsed & classified', () {
      final kit = _kitDir(tmp, 'multi');
      _file(kit, 'pubspec.yaml', '''
name: arxa_kit_multi
description: >
  First line of the description.
  Second line continues here.
version: 0.2.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  stacked: ^3.5.0
  stacked_services: ^1.6.0
  arxa_kit_core:
    path: ../core
  rxdart: ^0.28.0
''');
      final f = extractFacts(tmp.path).single;
      expect(f['name'], 'arxa_kit_multi');
      expect(f['version'], '0.2.0');
      expect(f['description'],
          'First line of the description. Second line continues here.');

      final deps = f['dependencies'] as Map;
      expect(deps['stacked'], '^3.5.0');
      expect(deps['stacked_services'], '^1.6.0');
      expect(deps['rxdart'], '^0.28.0');
      // path/sdk deps collapse to the sentinel.
      expect(deps['arxa_kit_core'], '(path/sdk)');
      expect(deps['flutter'], '(path/sdk)');

      // Topology: kit↔kit, framework, backing.
      expect(f['kitDeps'], ['arxa_kit_core']);
      expect(f['frameworkDeps'], ['stacked', 'stacked_services']);
      expect(f['backingPackages'], ['rxdart']);
    });

    test('quote-wrapped single-line description is unwrapped', () {
      final kit = _kitDir(tmp, 'q');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_q\n'
          'description: "A quoted one-liner."\n');
      final f = extractFacts(tmp.path).single;
      expect(f['description'], 'A quoted one-liner.');
    });
  });

  group('extractFacts — public surface', () {
    test('kinds detected (class/enum/typedef/mixin/abstract/interface)', () {
      final kit = _kitDir(tmp, 'surf');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_surf\n');
      _file(kit, 'lib/a.dart', '''
class A {}
enum E { a, b }
typedef F = void Function();
mixin M {}
abstract class B {}
abstract interface class C {}
''');
      final f = extractFacts(tmp.path).single;
      final byName = {
        for (final s in (f['publicSurface'] as List).cast<Map>())
          s['name'] as String: s['kind'] as String,
      };
      expect(byName['A'], 'class');
      expect(byName['E'], 'enum');
      expect(byName['F'], 'typedef');
      expect(byName['M'], 'mixin');
      expect(byName['B'], 'abstract class');
      expect(byName['C'], 'abstract interface class');
    });

    test('kind with extra internal whitespace is normalized', () {
      final kit = _kitDir(tmp, 'ws');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_ws\n');
      // 'abstract  class' (two spaces) → kind 'abstract class' (one space).
      _file(kit, 'lib/a.dart', 'abstract  class TwoSpaces {}\n');
      final f = extractFacts(tmp.path).single;
      final s = (f['publicSurface'] as List).cast<Map>().single;
      expect(s['kind'], 'abstract class');
      expect(s['name'], 'TwoSpaces');
    });

    test('dedup — first occurrence wins (name unique, file from first)', () {
      final kit = _kitDir(tmp, 'dup');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_dup\n');
      _file(kit, 'lib/a.dart', 'class Dup {}\n');
      _file(kit, 'lib/b.dart', 'class Dup {}\n');
      final f = extractFacts(tmp.path).single;
      final surf = (f['publicSurface'] as List).cast<Map>();
      expect(surf, hasLength(1));
      expect(surf.single['name'], 'Dup');
      expect(surf.single['file'], 'a.dart');
    });

    test('walks subdirs; file path is relative to lib/', () {
      final kit = _kitDir(tmp, 'walk');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_walk\n');
      _file(kit, 'lib/app.dart', 'class App {}\n');
      _file(kit, 'lib/services/foo.dart', 'class FooService {}\n');
      final f = extractFacts(tmp.path).single;
      final byName = {
        for (final s in (f['publicSurface'] as List).cast<Map>())
          s['name'] as String: s['file'] as String,
      };
      expect(byName['App'], 'app.dart');
      expect(byName['FooService'], 'services/foo.dart');
    });

    test('commented / string-embedded class never yields a symbol', () {
      final kit = _kitDir(tmp, 'ghost');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_ghost\n');
      _file(kit, 'lib/g.dart', '''
// class Ghost {}
/* class Phantom {} */
var doc = "class InString {}";
const triple = """class TripleGhost {}""";
class Real {}
''');
      final f = extractFacts(tmp.path).single;
      final names = [
        for (final s in (f['publicSurface'] as List).cast<Map>())
          s['name'] as String,
      ];
      expect(names, ['Real']);
    });

    test('no lib/ → empty publicSurface', () {
      final kit = _kitDir(tmp, 'nolib');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_nolib\n');
      final f = extractFacts(tmp.path).single;
      expect(f['publicSurface'], isEmpty);
    });
  });

  group('extractFacts — readme + testing', () {
    test('readme first heading + line count; hasTesting true', () {
      final kit = _kitDir(tmp, 'meta');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_meta\n');
      _file(kit, 'lib/testing.dart', '// test helpers\n');
      _file(kit, 'README.md', '# Arxa Kit Meta\n\nSome body.\n');
      final f = extractFacts(tmp.path).single;
      expect(f['hasTesting'], isTrue);
      expect(f['readmeFirst'], 'Arxa Kit Meta');
      // '# Arxa Kit Meta\n\nSome body.\n'.split('\n') → 4 elements.
      expect(f['readmeLines'], 4);
    });

    test('readme leading-hash stripping handles deep heading levels', () {
      final kit = _kitDir(tmp, 'h');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_h\n');
      _file(kit, 'README.md', '### Deep Heading\n');
      final f = extractFacts(tmp.path).single;
      expect(f['readmeFirst'], 'Deep Heading');
    });

    test('missing README → readmeLines 0, readmeFirst empty; hasTesting false', () {
      final kit = _kitDir(tmp, 'noreadme');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_noreadme\n');
      final f = extractFacts(tmp.path).single;
      expect(f['readmeLines'], 0);
      expect(f['readmeFirst'], '');
      expect(f['hasTesting'], isFalse);
    });
  });

  group('extractFacts — I/O', () {
    test('nonexistent kitRoot → empty list', () {
      expect(extractFacts(p.join(tmp.path, 'does-not-exist')), isEmpty);
    });

    test('no factsDir → no files written, facts still returned', () {
      final kit = _kitDir(tmp, 'mem');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_mem\n');
      _file(kit, 'lib/a.dart', 'class A {}\n');
      final facts = extractFacts(tmp.path);
      expect(facts, hasLength(1));
      expect(facts.single['name'], 'arxa_kit_mem');
      // Nothing was written anywhere under tmp beyond the fixture itself.
      expect(Directory(p.join(tmp.path, 'memory')).existsSync(), isFalse);
    });

    test('atomic write — one JSON per kit, .tmp renamed away, round-trips', () {
      final kit = _kitDir(tmp, 'w');
      _file(kit, 'pubspec.yaml', 'name: arxa_kit_w\n');
      _file(kit, 'lib/a.dart', 'class Widget {}\nenum Kind { x }\n');
      final factsOut = Directory(p.join(tmp.path, 'facts'));

      final facts = extractFacts(tmp.path, factsDir: factsOut.path);

      final json = File(p.join(factsOut.path, 'w.json'));
      expect(json.existsSync(), isTrue);
      // The temp file was renamed away — no torn write left behind.
      expect(File('${json.path}.tmp').existsSync(), isFalse);

      final raw = json.readAsStringSync();
      // No trailing newline (matches Python json.dump, not json.dump+nl).
      expect(raw.endsWith('\n'), isFalse);
      // Round-trips and matches the in-memory fact.
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['name'], facts.single['name']);
      expect((decoded['publicSurface'] as List), hasLength(2));
    });

    test('discovers multiple kits in alphabetical order', () {
      final zebra = _kitDir(tmp, 'zebra');
      _file(zebra, 'pubspec.yaml', 'name: arxa_kit_zebra\n');
      final alpha = _kitDir(tmp, 'alpha');
      _file(alpha, 'pubspec.yaml', 'name: arxa_kit_alpha\n');
      final facts = extractFacts(tmp.path);
      expect(facts.map((f) => f['kit']).toList(), ['alpha', 'zebra']);
    });
  });
}

/// Create (mkdir -p) and return a kit dir directly under [root].
Directory _kitDir(Directory root, String name) =>
    Directory(p.join(root.path, name))..createSync(recursive: true);

/// Write [content] to `<dir>/<relPath>`, creating parent dirs as needed.
void _file(Directory dir, String relPath, String content) {
  File(p.join(dir.path, relPath))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}
