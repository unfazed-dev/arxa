// Tests for the data-arxa-id stamper (design_stamp.dart) — the machine
// identity layer. The invariant under test, from the 2026-08-22 decision:
// every host element carries EXACTLY ONE data-arxa-id, stable across re-stamps.
library;

import 'dart:io';

import 'package:appboxd/design_stamp.dart';
import 'package:test/test.dart';

void main() {
  group('stampSource', () {
    test('stamps every host element, id immediately after the tag name', () {
      final res = stampSource(
        '<div class="x"><span>hi</span><br/><a href="/y">go</a></div>',
        'surfaces-home',
      );
      expect(res.stamped, 4);
      expect(res.carried, 0);
      expect(res.code, contains('<div data-arxa-id="surfaces-home-e1" class="x">'));
      expect(res.code, contains('<span data-arxa-id="surfaces-home-e2">hi</span>'));
      expect(res.code, contains('<br data-arxa-id="surfaces-home-e3"/>'));
      expect(res.code, contains('<a data-arxa-id="surfaces-home-e4" href="/y">go</a>'));
    });

    test('skips fragments, closing tags, and component invocations', () {
      final res = stampSource(
        '<><Label text="x"/><div>t</div></Label></>',
        'p',
      );
      // Only the <div> is a host element: <> and </> are fragments, and
      // <Label> is a capitalized component invocation (its closing tag is
      // skipped as a closing tag).
      expect(res.stamped, 1);
      expect(res.code, contains('<div data-arxa-id="p-e1">t</div>'));
    });

    test('comments are never stamped (all four forms)', () {
      final res = stampSource(
        '{/* <div>jsx</div> */}\n/* <span>block</span> */\n'
        '<!-- <p>html</p> -->\n// <b>line</b>\n<div>real</div>',
        'p',
      );
      expect(res.stamped, 1);
      expect(res.code, contains('<div data-arxa-id="p-e1">real</div>'));
    });

    test('apostrophe in JSX text does not eat the following tag', () {
      final res = stampSource(
        "<p>Don\'t stop</p><span>next</span>",
        'p',
      );
      expect(res.stamped, 2);
      expect(res.code, contains('<span data-arxa-id="p-e2">next</span>'));
    });

    test('> inside expressions and quoted values does not truncate the tag', () {
      final res = stampSource(
        '<button onClick={() => a > b} title="x > y">go</button>',
        'p',
      );
      expect(res.stamped, 1);
      expect(res.code,
          '<button data-arxa-id="p-e1" onClick={() => a > b} title="x > y">go</button>');
    });

    test('re-stamp is a byte-identical no-op (idempotent)', () {
      const src = '<div><span>a</span><section><p>b</p></section></div>';
      final first = stampSource(src, 'p');
      final second = stampSource(first.code, 'p');
      expect(second.code, first.code);
      expect(second.stamped, 0);
      expect(second.carried, 4);
    });

    test('carry-forward: existing ids kept, new elements get max+1', () {
      const src = '<div data-arxa-id="p-e3"><span>new</span></div>';
      final res = stampSource(src, 'p');
      expect(res.stamped, 1);
      expect(res.carried, 1);
      expect(res.code, contains('<div data-arxa-id="p-e3">'));
      expect(res.code, contains('<span data-arxa-id="p-e4">new</span>'));
    });

    test('an id anywhere in the opening tag suppresses double-stamping', () {
      const src = '<div class="x" data-arxa-id="p-e9">t</div>';
      final res = stampSource(src, 'p');
      expect(res.stamped, 0);
      expect(res.carried, 1);
      expect(res.code, src);
    });

    test('spaced comparison a < b is not markup', () {
      final res = stampSource('{items.map((x) => a < b ? x : x)}', 'p');
      expect(res.stamped, 0);
      expect(res.code, '{items.map((x) => a < b ? x : x)}');
    });

    test('lowercase TS generic is not markup', () {
      final res = stampSource('final x = useMemo<div>(() => v, []);', 'p');
      expect(res.stamped, 0);
    });
  });

  group('idPrefixFor', () {
    test('artifact-relative path becomes the prefix', () {
      expect(idPrefixFor('surfaces/cart.tsx'), 'surfaces-cart');
      expect(idPrefixFor('widgets/label.tsx'), 'widgets-label');
    });
  });

  group('stampMain', () {
    test('stamps a tree in place and reports', () {
      final dir = Directory.systemTemp.createTempSync('stamp_test');
      try {
        Directory('${dir.path}/surfaces').createSync();
        File('${dir.path}/surfaces/home.tsx')
            .writeAsStringSync('<div><p>hi</p></div>');
        final res = stampMain([dir.path]);
        expect(res.exitCode, 0);
        final out = File('${dir.path}/surfaces/home.tsx').readAsStringSync();
        expect(out, contains('<div data-arxa-id="surfaces-home-e1">'));
        expect(out, contains('<p data-arxa-id="surfaces-home-e2">hi</p>'));
        // and the second run is a no-op
        final again = stampMain([dir.path]);
        expect(File('${dir.path}/surfaces/home.tsx').readAsStringSync(), out);
        expect(again.stdoutLines.last, contains('0 new ids'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('missing dir is a loud exit 2, not a vacuous pass', () {
      final res = stampMain(['/no/such/dir/exists']);
      expect(res.exitCode, 2);
      expect(res.stderrLines.single, contains('no such dir'));
    });
  });
}
