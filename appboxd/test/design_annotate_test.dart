// Tests for design_annotate.dart — the machine-derived semantic layer.
// The invariant: qualifying elements (interactive OR direct-text) with no
// identity gain data-el + the inspect set with fn provenance=inferred;
// already-annotated elements are never touched.
library;

import 'dart:io';

import 'package:appboxd/design_annotate.dart';
import 'package:test/test.dart';

void main() {
  group('annotateSource', () {
    test('button with aria-label: fn comes from the label, marked inferred', () {
      final res = annotateSource(
          '<div role="button" aria-label="Previous testimonial" class="arrow">'
          '<img src="x.svg" alt=""/></div>');
      expect(res.annotated, 1);
      expect(res.code, contains('data-el="button:Previous testimonial"'));
      expect(res.code, contains('data-inspect-role="button"'));
      expect(res.code, contains('data-inspect-style="arrow"'));
      expect(res.code,
          contains('data-inspect-fn="Previous testimonial"'));
      expect(res.code, contains('data-inspect-fn-provenance="inferred"'));
    });

    test('link with text content is annotated from its text', () {
      final res = annotateSource('<a href="/book" class="cta">Book a tour</a>');
      expect(res.annotated, 1);
      expect(res.code, contains('data-el="link:Book a tour"'));
      expect(res.code, contains('data-inspect-role="link"'));
      expect(res.code, contains('data-inspect-fn="link: Book a tour"'));
    });

    test('plain text-bearing element is annotated as text', () {
      final res = annotateSource('<p class="lede">We are open.</p>');
      expect(res.annotated, 1);
      expect(res.code, contains('data-el="text:We are open."'));
      expect(res.code, contains('data-inspect-fn="Shows: We are open."'));
    });

    test('bare empty container is NOT annotated (not inspect-mandatory)', () {
      final res = annotateSource('<div class="row"><span></span></div>');
      expect(res.annotated, 0);
    });

    test('expression debris after a tag is not text', () {
      final res = annotateSource(
          '<div class="x">{items.map((it) => (<Row key={it}/>))}</div>');
      expect(res.annotated, 0);
    });

    test('already-annotated elements are carried, never rewritten', () {
      const src = '<button data-el="button:Save" data-inspect-role="button">'
          'Save</button>';
      final res = annotateSource(src);
      expect(res.annotated, 0);
      expect(res.carried, 1);
      expect(res.code, src);
    });

    test('inspectAttrs spread counts as identity (suczka shape)', () {
      const src = '<section {...inspectAttrs("list:Items", {role: "list"})}>'
          '<p>hi</p></section>';
      final res = annotateSource(src);
      expect(res.carried, 1);
      expect(res.annotated, 1); // the <p> inside is text-bearing, unannotated
    });

    test('re-annotate is a byte-identical no-op', () {
      const src = '<a href="/x">Go</a><p>Text here</p>';
      final first = annotateSource(src);
      final second = annotateSource(first.code);
      expect(second.code, first.code);
      expect(second.annotated, 0);
      expect(second.carried, 2);
    });

    test('template-literal markup is never annotated', () {
      final res = annotateSource('{raw(`<button>Save</button>`)}');
      expect(res.annotated, 0);
    });

    test('textless link labels from its href, never the bare tag', () {
      final res = annotateSource('<a href="/book" class="w-inline-block"></a>');
      expect(res.annotated, 1);
      expect(res.code, contains('data-el="link:/book"'));
      expect(res.code, isNot(contains('data-el="link:a"')));
    });

    test('double quotes in derived text are neutralized', () {
      final res = annotateSource('<a href="/x">Say "hi" now</a>');
      expect(res.code, isNot(contains('data-el="link:Say "hi"')));
      expect(res.annotated, 1);
    });
  });

  group('annotateMain', () {
    test('annotates a tree in place and reports', () {
      final dir = Directory.systemTemp.createTempSync('annotate_test');
      try {
        File('${dir.path}/w.tsx').writeAsStringSync(
            '<a href="/x">Go</a><div class="empty"></div>');
        final res = annotateMain([dir.path]);
        expect(res.exitCode, 0);
        final out = File('${dir.path}/w.tsx').readAsStringSync();
        expect(out, contains('data-el="link:Go"'));
        expect(out, contains('provenance="inferred"'));
        final again = annotateMain([dir.path]);
        expect(File('${dir.path}/w.tsx').readAsStringSync(), out);
        expect(again.stdoutLines.last, contains('0 derived'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('missing dir is a loud exit 2', () {
      expect(annotateMain(['/no/such/dir']).exitCode, 2);
    });
  });
}
