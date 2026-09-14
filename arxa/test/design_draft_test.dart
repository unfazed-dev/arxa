import 'dart:convert';
import 'package:arxa/design_draft.dart';
import 'package:test/test.dart';

void main() {
  group('DraftOverlay json', () {
    test('roundtrip preserves tokens, patches, removals, text', () {
      final d = DraftOverlay(artifact: 'hello-hda', tokens: {
        '--brand': '#ff0000',
      }, patches: {
        'home-e1': DraftPatch(
          style: {'color': 'red', 'margin-top': null},
          attrs: {'title': 'hi', 'hidden': null},
          text: 'New label',
        ),
      });
      final back = DraftOverlay.fromJson(
          jsonDecode(jsonEncode(d.toJson())), artifact: 'hello-hda');
      expect(back.tokens['--brand'], '#ff0000');
      final p = back.patches['home-e1']!;
      expect(p.style['color'], 'red');
      expect(p.style.containsKey('margin-top'), isTrue);
      expect(p.style['margin-top'], isNull);
      expect(p.attrs['title'], 'hi');
      expect(p.attrs['hidden'], isNull);
      expect(p.text, 'New label');
    });

    test('rejects bad token names, markup-breaking values, oversize', () {
      DraftOverlay bad(Map<String, dynamic> j) =>
          DraftOverlay.fromJson(j, artifact: 'a');
      expect(() => bad({'tokens': {'brand': 'x'}}), throwsFormatException);
      expect(
          () => bad({'tokens': {'--a': '</style>'}}), throwsFormatException);
      expect(
          () => bad({
                'patches': {
                  'e1': {'style': {'bad name': 'x'}}
                }
              }),
          throwsFormatException);
      expect(
          () => bad({
                'patches': {
                  'e1': {'style': {'color': 'r"ed'}}
                }
              }),
          throwsFormatException);
      expect(
          () => bad({
                'patches': {
                  'e1': {'text': 'x' * 4001}
                }
              }),
          throwsFormatException);
      expect(
          () => bad({
                'patches': {
                  for (var i = 0; i < 129; i++)
                    'e$i': {'style': {'color': 'red'}}
                }
              }),
          throwsFormatException);
    });
  });

  group('DraftOverlay.apply', () {
    const page = '<html><head></head><body>'
        '<div data-arxa-id="page-e1" class="frame">'
        '<span data-arxa-id="page-e2" style="color: blue">Old</span>'
        '<ul><li data-arxa-id="page-e3">a</li>'
        '<li data-arxa-id="page-e3">b</li></ul>'
        '<img data-arxa-id="page-e4" src="x.png">'
        '</div></body></html>';

    test('style merges into the quoted style attribute', () {
      final d = DraftOverlay(artifact: 'a', patches: {
        'page-e2': DraftPatch(style: {'color': 'red', 'font-size': '20px'}),
      });
      final r = d.apply(page);
      expect(r.html, contains('style="color: red; font-size: 20px"'));
      expect(r.applied, 1);
      expect(r.stale, isEmpty);
    });

    test('attrs set and remove; text replaces pure-text content', () {
      final d = DraftOverlay(artifact: 'a', patches: {
        'page-e2': DraftPatch(attrs: {'title': 'tip'}, text: 'New & <b>'),
      });
      final r = d.apply(page);
      expect(r.html, contains('title="tip"'));
      expect(r.html, contains('>New &amp; &lt;b&gt;</span>'));
    });

    test('loop-shared ids patch EVERY rendered instance', () {
      final d = DraftOverlay(artifact: 'a', patches: {
        'page-e3': DraftPatch(style: {'font-weight': 'bold'}),
      });
      final r = d.apply(page);
      expect(r.applied, 2);
      expect('style="font-weight: bold"'.allMatches(r.html).length, 2);
    });

    test('text on nested markup refuses loudly and keeps the draft', () {
      final d = DraftOverlay(artifact: 'a', patches: {
        'page-e1': DraftPatch(text: 'nuke'),
      });
      final r = d.apply(page);
      expect(r.refused.single, contains('nested markup'));
      expect(r.html, page); // nothing touched
    });

    test('el:-keyed patches bind the authored identity (amended 2026-08-24)',
        () {
      // one machine id (page-e5), two authored meanings — the divergence the
      // amendment exists for: the el: patch must touch ONLY its own slot.
      const div = '<div data-arxa-id="page-e5" data-el="wordmark-lead">SUCZKA</div>'
          '<div data-arxa-id="page-e5" data-el="intro-copyright">SUCZKA TO STUDIO ©2026</div>';
      final d = DraftOverlay(artifact: 'a', patches: {
        'el:intro-copyright': DraftPatch(text: 'KORMORAN TO STUDIO ©2026'),
      });
      final r = d.apply(div);
      expect(r.applied, 1);
      expect(r.html, contains('>KORMORAN TO STUDIO ©2026</div>'));
      expect(r.html, contains('data-el="wordmark-lead">SUCZKA</div>'));
    });

    test('a malformed el: key is rejected at parse, not silently id-targeted',
        () {
      expect(
          () => DraftOverlay.fromJson({
                'patches': {
                  'el:': {'text': 'x'}
                  // ignore: avoid_print
                }
              }, artifact: 'a'),
          throwsFormatException);
    });

    test('text on a void element refuses', () {
      final d = DraftOverlay(artifact: 'a', patches: {
        'page-e4': DraftPatch(text: 'alt?'),
      });
      final r = d.apply(page);
      expect(r.refused.single, contains('void element'));
    });

    test('a missing id is stale, not lost', () {
      final d = DraftOverlay(artifact: 'a', patches: {
        'page-e9': DraftPatch(style: {'color': 'red'}),
      });
      final r = d.apply(page);
      expect(r.stale, ['page-e9']);
      expect(r.html, page);
    });

    test('tokens land in one :root override before </body>', () {
      final d = DraftOverlay(artifact: 'a', tokens: {'--brand': '#0af'});
      final r = d.apply(page);
      expect(
          r.html,
          contains('<style id="arxa-draft-tokens">:root{--brand: #0af}'
              '</style></body>'));
    });
  });
}
