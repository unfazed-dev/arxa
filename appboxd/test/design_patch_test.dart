// Tests for design_patch.dart — the structured-patch verb. Item 15's law
// under test: patches are structured edits against a data-arxa-id-addressed
// element; everything outside that element's opening tag is byte-identical.
library;

import 'dart:io';

import 'package:appboxd/design_patch.dart';
import 'package:test/test.dart';

const _src = '''
export const Home = () => (
  <div data-arxa-id="surfaces-home-e1" class="shell">
    <h1 data-arxa-id="surfaces-home-e2" data-el="hero:Title"
        style="display: flex; color: red">Title</h1>
    <p data-arxa-id="surfaces-home-e3">body</p>
  </div>
);
''';

void main() {
  group('patchSource', () {
    test('set replaces an existing attribute, preserving everything else', () {
      final res = patchSource(
          _src, 'surfaces-home-e1', const PatchEdits(attrs: {'class': 'frame'}));
      expect(res.found, isTrue);
      expect(res.code, contains('<div data-arxa-id="surfaces-home-e1" class="frame">'));
      expect(res.code, contains('style="display: flex; color: red"'));
    });

    test('set inserts a missing attribute right after the tag name', () {
      final res = patchSource(
          _src, 'surfaces-home-e3', const PatchEdits(attrs: {'role': 'note'}));
      expect(res.code,
          contains('<p role="note" data-arxa-id="surfaces-home-e3">body</p>'));
    });

    test('rm removes the attribute and its whitespace', () {
      final res = patchSource(
          _src, 'surfaces-home-e2', const PatchEdits(attrs: {'data-el': null}));
      expect(res.code, isNot(contains('data-el')));
      expect(res.code, contains('data-arxa-id="surfaces-home-e2"'));
    });

    test('style merge sets one prop and keeps the others', () {
      final res = patchSource(_src, 'surfaces-home-e2',
          const PatchEdits(style: {'color': 'blue'}));
      expect(res.code,
          contains('style="display: flex; color: blue"'));
    });

    test('style merge appends a new prop to an existing style', () {
      final res = patchSource(_src, 'surfaces-home-e2',
          const PatchEdits(style: {'gap': '1rem'}));
      expect(res.code,
          contains('style="display: flex; color: red; gap: 1rem"'));
    });

    test('style merge creates the attribute when absent', () {
      final res = patchSource(_src, 'surfaces-home-e3',
          const PatchEdits(style: {'margin': '0'}));
      expect(res.code, contains(
          '<p style="margin: 0" data-arxa-id="surfaces-home-e3">body</p>'));
    });

    test('rm-style drops the prop; empty style removes the attribute', () {
      final one = patchSource(_src, 'surfaces-home-e2',
          const PatchEdits(style: {'display': null}));
      expect(one.code, contains('style="color: red"'));
      final two = patchSource(one.code, 'surfaces-home-e2',
          const PatchEdits(style: {'color': null}));
      expect(two.code, isNot(contains('style=')));
    });

    test('unknown id is found:false and changes nothing', () {
      final res = patchSource(
          _src, 'surfaces-nope-e9', const PatchEdits(attrs: {'a': 'b'}));
      expect(res.found, isFalse);
      expect(res.code, _src);
    });

    test('a style {...} expression bails loudly instead of corrupting', () {
      const expr = '<div data-arxa-id="x-e1" style={compute()}>t</div>';
      final res = patchSource(
          expr, 'x-e1', const PatchEdits(style: {'color': 'red'}));
      expect(res.error, contains('expression'));
      expect(res.code, expr);
    });

    test('a <b inside an attribute expression does not mislead the walk-back', () {
      // Unspaced: the <b IS a lowercase-tag-shaped candidate, so this fixture
      // genuinely guards the walk-back's extent check — accept the first <
      // and the patch lands on a phantom <b> tag (or bails) instead of the div.
      const tricky =
          '<div class={a <b ? "x" : "y"} data-arxa-id="t-e1">t</div>';
      final res = patchSource(
          tricky, 't-e1', const PatchEdits(attrs: {'role': 'note'}));
      expect(res.code,
          '<div role="note" class={a <b ? "x" : "y"} data-arxa-id="t-e1">t</div>');
    });
  });

  group('patchMain', () {
    test('patches the one matching file in a tree', () {
      final dir = Directory.systemTemp.createTempSync('patch_test');
      try {
        Directory('${dir.path}/surfaces').createSync();
        File('${dir.path}/surfaces/a.tsx').writeAsStringSync(_src);
        File('${dir.path}/surfaces/b.tsx')
            .writeAsStringSync('<div data-arxa-id="surfaces-b-e1">b</div>');
        final res = patchMain(
            [dir.path, 'surfaces-b-e1', '--set', 'class', '=', 'card']);
        // --set takes name=value as ONE arg
        expect(res.exitCode, 2); // bad usage shape on purpose above
        final ok = patchMain(
            [dir.path, 'surfaces-b-e1', '--set', 'class=card']);
        expect(ok.exitCode, 0);
        expect(File('${dir.path}/surfaces/b.tsx').readAsStringSync(),
            '<div class="card" data-arxa-id="surfaces-b-e1">b</div>');
        // the other file is untouched
        expect(File('${dir.path}/surfaces/a.tsx').readAsStringSync(), _src);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('unknown id exits 3, nothing written', () {
      final dir = Directory.systemTemp.createTempSync('patch_test');
      try {
        File('${dir.path}/a.tsx').writeAsStringSync(_src);
        final res = patchMain([dir.path, 'nope-e1', '--set', 'x=y']);
        expect(res.exitCode, 3);
        expect(File('${dir.path}/a.tsx').readAsStringSync(), _src);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('authored-identity targeting (el:, amended 2026-08-24)', () {
    test('patchSource with attr data-el binds the authored identity', () {
      final res = patchSource(_src, 'hero:Title',
          const PatchEdits(style: {'color': 'blue'}), attr: 'data-el');
      expect(res.found, isTrue);
      expect(res.code,
          contains('style="display: flex; color: blue"'));
      // machine-id siblings untouched
      expect(res.code, contains('data-arxa-id="surfaces-home-e2"'));
    });

    test('patchAllRendered with attr data-el patches every same-el row', () {
      const html = '<li data-el="row" data-arxa-id="w-e1">a</li>'
          '<li data-el="row" data-arxa-id="w-e1">b</li>'
          '<li data-el="other" data-arxa-id="w-e1">c</li>';
      final res = patchAllRendered(
          html, 'row', const PatchEdits(style: {'color': 'red'}),
          attr: 'data-el');
      expect(res.applied, 2);
      expect(res.code.indexOf('color: red'),
          isNot(res.code.lastIndexOf('color: red'))); // two applications
      // the divergent sibling ('other') is NOT patched — that is the law
      expect(res.code, contains('<li data-el="other" data-arxa-id="w-e1">c</li>'));
    });

    test('patchAllRendered default stays machine-id fan-out', () {
      const html = '<b data-arxa-id="w-e9" data-el="x">1</b>'
          '<i data-arxa-id="w-e9" data-el="y">2</i>';
      final res = patchAllRendered(
          html, 'w-e9', const PatchEdits(style: {'color': 'red'}));
      expect(res.applied, 2);
    });

    test('patchMain --el targets the authored identity', () {
      final dir = Directory.systemTemp.createTempSync('patch_test');
      try {
        File('${dir.path}/a.tsx').writeAsStringSync(_src);
        final res = patchMain(
            [dir.path, '--el', 'hero:Title', '--style', 'color=teal']);
        expect(res.exitCode, 0);
        expect(File('${dir.path}/a.tsx').readAsStringSync(),
            contains('style="display: flex; color: teal"'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('patchMain --el with an unknown data-el exits 3', () {
      final dir = Directory.systemTemp.createTempSync('patch_test');
      try {
        File('${dir.path}/a.tsx').writeAsStringSync(_src);
        final res =
            patchMain([dir.path, '--el', 'nope', '--style', 'color=teal']);
        expect(res.exitCode, 3);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
