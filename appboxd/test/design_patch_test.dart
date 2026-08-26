// Tests for design_patch.dart — the structured-patch verb. Item 15's law
// under test: patches are structured edits against a data-arxa-id-addressed
// element; everything outside that element's opening tag is byte-identical.
library;

import 'dart:io';

import 'package:appboxd/design_patch.dart';
import 'package:appboxd/design_draft.dart';
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

    test('write-through onto a real widget invocation (name= anchor, no id)',
        () {
      // The suczka shape: PascalCase component, name= anchor, class only —
      // data-arxa-id lives in RENDERED markup, never in source widgets.
      // rest() in primitives.tsx forwards unknown props (style=) to the DOM,
      // so an inline style committed here renders and overrides the class.
      final dir = Directory.systemTemp.createTempSync('patch_test');
      try {
        File('${dir.path}/widgets.tsx').writeAsStringSync(
            'export const IntroWordMark = () => (\n'
            '  <Box name="intro-wordmark" class="mod-scroll__intro__logo logo c-black">\n'
            '    <span>suczka</span>\n'
            '  </Box>\n'
            ');\n');
        final res = patchMain([
          dir.path,
          '--el',
          'intro-wordmark',
          '--style',
          'font-size=12rem'
        ]);
        expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
        final out = File('${dir.path}/widgets.tsx').readAsStringSync();
        expect(out, contains('name="intro-wordmark"'));
        expect(out, contains('style="font-size: 12rem"'));
        expect(out,
            contains('class="mod-scroll__intro__logo logo c-black"'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('media swap: --set src= rewrites the asset path in place', () {
      final dir = Directory.systemTemp.createTempSync('patch_test');
      try {
        File('${dir.path}/media.tsx').writeAsStringSync(
            '<Img name="hero-shot" class="cover" src="assets/images/old.jpg" />');
        final res = patchMain([
          dir.path,
          '--el',
          'hero-shot',
          '--set',
          'src=assets/images/unsplash/abc123.jpg'
        ]);
        expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
        final out = File('${dir.path}/media.tsx').readAsStringSync();
        expect(out, contains('src="assets/images/unsplash/abc123.jpg"'));
        expect(out, isNot(contains('old.jpg')));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
  group('SSOT routing: --text on t()-backed elements (2026-08-24)', () {
    test('routes to every l10n ARB and preserves the tsx binding', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_arb');
      try {
        Directory('${dir.path}/l10n').createSync();
        const tsx = "<p data-arxa-id=\"home-e6\">{t('brand.copyright')}</p>";
        File('${dir.path}/a.tsx').writeAsStringSync(tsx);
        File('${dir.path}/l10n/app_en.arb').writeAsStringSync(
            '{\n  "brand.copyright": "OLD EN",\n  "other": "x"\n}');
        File('${dir.path}/l10n/app_pl.arb')
            .writeAsStringSync('{"brand.copyright": "OLD PL"}');
        final res = patchMain(
            [dir.path, 'home-e6', '--text', 'DOMKA TO STUDIO \u00a92026']);
        expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
        expect(res.stdoutLines.first, contains('l10n key "brand.copyright"'));
        expect(File('${dir.path}/l10n/app_en.arb').readAsStringSync(),
            contains('"brand.copyright": "DOMKA TO STUDIO \u00a92026"'));
        expect(File('${dir.path}/l10n/app_pl.arb').readAsStringSync(),
            contains('"brand.copyright": "DOMKA TO STUDIO \u00a92026"'));
        expect(File('${dir.path}/a.tsx').readAsStringSync(), tsx);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('--text refuses expression-backed (non-t) elements loudly', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_expr');
      try {
        File('${dir.path}/a.tsx').writeAsStringSync(
            '<p data-arxa-id="home-e7">{computeCopyright()}</p>');
        final res = patchMain([dir.path, 'home-e7', '--text', 'X']);
        expect(res.exitCode, 5);
        expect(res.stderrLines.join(), contains('expression-backed'));
        expect(File('${dir.path}/a.tsx').readAsStringSync(),
            contains('{computeCopyright()}'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
  group('token SSOT routing (2026-08-24)', () {
    test('--token rewrites the base :root only; media blocks untouched', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_tok');
      try {
        Directory('${dir.path}/ui/styles/common').createSync(recursive: true);
        const css = ':root {\n  --red: #DB5C59;\n  --beige: #ECE4DA;\n}\n'
            ' @media (max-width: 1024px) { :root { --red: #FF0000; } }';
        File('${dir.path}/ui/styles/common/tokens.css').writeAsStringSync(css);
        final res = patchMain(
            [dir.path, '--token', '--red=#00FF00', '--rm-token', '--beige']);
        expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
        final out = File('${dir.path}/ui/styles/common/tokens.css')
            .readAsStringSync();
        expect(out, contains('--red: #00FF00;'));
        expect(out, isNot(contains('--beige')));
        expect(out, contains('--red: #FF0000;')); // media block untouched
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    // Regression: the no-stylesheet fallback used
    // `orElse: () => null as File`, which threw a TypeError instead of
    // returning null, so the CmdResult(5) below it was unreachable.
    test('--token with no :root stylesheet exits 5, does not throw', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_tok_none');
      try {
        Directory('${dir.path}/ui/styles/common').createSync(recursive: true);
        // a .css file that exists but has no :root — the scan must reject it
        File('${dir.path}/ui/styles/common/other.css')
            .writeAsStringSync('.a { color: red; }');
        final res = patchMain([dir.path, '--token', '--red=#00FF00']);
        expect(res.exitCode, 5);
        expect(res.stderrLines.join(' '), contains('no tokens.css'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('--token inserts a brand-new custom property', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_tok2');
      try {
        Directory('${dir.path}/ui/styles/common').createSync(recursive: true);
        File('${dir.path}/ui/styles/common/tokens.css')
            .writeAsStringSync(':root {\n  --red: #DB5C59;\n}');
        final res = patchMain([dir.path, '--token', '--accent=#123456']);
        expect(res.exitCode, 0);
        expect(File('${dir.path}/ui/styles/common/tokens.css')
            .readAsStringSync(), contains('--accent: #123456;'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });


  group('seed SSOT routing (2026-08-24)', () {
    late Directory dir;
    late String seedEnBefore;
    late String seedPlBefore;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('patch_test_seed');
      Directory('${dir.path}/models/project_model').createSync(recursive: true);
      const projectEnA = '{"slug": "saska-kepa", "href": "/projects/saska-kepa",'
          ' "role": "Architecture", "name": "Saska Kepa",'
          ' "tagline": "Light near the river"}';
      const projectEnB = '{"slug": "oliwa-wzgorze", "href": "",'
          ' "role": "Architecture", "name": "Oliwa Wzgorze",'
          ' "tagline": "Under the birches"}';
      const projectPlA = '{"slug": "saska-kepa", "href": "/pl/projects/saska-kepa",'
          ' "role": "Architektura", "name": "Saska Kepa",'
          ' "tagline": "Swiatlo nad rzeka"}';
      const projectPlB = '{"slug": "oliwa-wzgorze", "href": "",'
          ' "role": "Architektura", "name": "Oliwa Wzgorze",'
          ' "tagline": "Pod brzozami"}';
      seedEnBefore = '[\n  $projectEnA,\n  $projectEnB\n]';
      seedPlBefore = '[\n  $projectPlA,\n  $projectPlB\n]';
      File('${dir.path}/models/project_model/project_seed.en.json')
          .writeAsStringSync(seedEnBefore);
      File('${dir.path}/models/project_model/project_seed.pl.json')
          .writeAsStringSync(seedPlBefore);
      File('${dir.path}/models/project_model/project_fixtures.en.json')
          .writeAsStringSync('{"projects": [\n  $projectEnA,\n  $projectEnB\n]}');
      File('${dir.path}/models/project_model/project_fixtures.pl.json')
          .writeAsStringSync('{"projects": [\n  $projectPlA,\n  $projectPlB\n]}');
      File('${dir.path}/cards.tsx').writeAsStringSync(
          '<div data-arxa-id="cards-e1">'
          '<h3 data-arxa-id="cards-e2">{project.name}</h3>'
          '<p data-arxa-id="cards-e3">{project.tagline}</p>'
          '<span data-arxa-id="cards-e4">{project.role}</span>'
          '</div>');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('unique resolve infers the locale; writes its seed AND fixture',
        () {
      final res = patchMain([
        dir.path, 'cards-e3', '--text', 'DAYLIGHT BY THE RIVER',
        '--was', 'Light near the river',
      ]);
      expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
      expect(res.stdoutLines.first, contains('project_seed.0.tagline'));
      final en = File('${dir.path}/models/project_model/project_seed.en.json')
          .readAsStringSync();
      expect(en, contains('"tagline": "DAYLIGHT BY THE RIVER"'));
      expect(en, contains('"tagline": "Under the birches"')); // sibling intact
      // Locale inference: --was matches ONLY the en value -> the en pair
      // alone is written; pl keeps its own language untouched.
      final plSeed = File(
              '${dir.path}/models/project_model/project_seed.pl.json')
          .readAsStringSync();
      expect(plSeed, contains('"tagline": "Swiatlo nad rzeka"'));
      expect(plSeed, isNot(contains('DAYLIGHT')));
      // fixtures kept in sync with their seeds, per locale
      expect(
          File('${dir.path}/models/project_model/project_fixtures.en.json')
              .readAsStringSync(),
          contains('"tagline": "DAYLIGHT BY THE RIVER"'));
      expect(
          File('${dir.path}/models/project_model/project_fixtures.pl.json')
              .readAsStringSync(),
          contains('"tagline": "Swiatlo nad rzeka"'));
      expect(res.stdoutLines.first, contains('(en; also in spine: pl)'));
      expect(File('${dir.path}/cards.tsx').readAsStringSync(),
          contains('{project.tagline}')); // binding preserved
      // surgical: seed.en is exactly the original with one value swapped
      expect(en,
          seedEnBefore.replaceAll('Light near the river', 'DAYLIGHT BY THE RIVER'));
    });

    test('ambiguous same-value paths narrow by --page slug correlation', () {
      final res = patchMain([
        dir.path, 'cards-e4', '--text', 'Interiors & structures',
        '--was', 'Architecture', '--page', '/projects/saska-kepa',
      ]);
      expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
      expect(res.stdoutLines.first, contains('project_seed.0.role'));
      final en = File('${dir.path}/models/project_model/project_seed.en.json')
          .readAsStringSync();
      expect(en, contains('"role": "Interiors & structures"'));
      expect(
          File('${dir.path}/models/project_model/project_seed.pl.json')
              .readAsStringSync(),
          contains('"role": "Architektura"')); // pl untouched
      expect(en, contains('"role": "Architecture"')); // project B untouched
    });

    test('ambiguous paths narrow by --nth ordinal under a shared parent', () {
      final res = patchMain([
        dir.path, 'cards-e4', '--text', 'Coming soon', '--was', 'Architecture',
        '--nth', '1',
      ]);
      expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
      expect(res.stdoutLines.first, contains('project_seed.1.role'));
      final en = File('${dir.path}/models/project_model/project_seed.en.json')
          .readAsStringSync();
      expect(en, contains('"role": "Architecture"')); // project A untouched
      expect(en, contains('"role": "Coming soon"'));
    });

    test('stale anchor refuses loudly and changes nothing', () {
      final res = patchMain([
        dir.path, 'cards-e3', '--text', 'X', '--was', 'DRIFTED TEXT',
      ]);
      expect(res.exitCode, 5);
      expect(res.stderrLines.join(), contains('no seed path matched'));
      expect(File('${dir.path}/models/project_model/project_seed.en.json')
          .readAsStringSync(), seedEnBefore);
    });

    test('no anchor at all refuses with guidance instead of guessing', () {
      final res = patchMain([dir.path, 'cards-e4', '--text', 'X']);
      expect(res.exitCode, 5);
      expect(res.stderrLines.join(), contains('--was <previous text>'));
    });
  });

  group('draft provenance fields (2026-08-24)', () {
    test('DraftPatch round-trips was/nth/page through json', () {
      final d = DraftOverlay.fromJson(const {
        'patches': {
          'x-e1': {'text': 'NEW', 'was': 'OLD', 'nth': 1, 'page': '/pl/projects'}
        }
      }, artifact: 'a');
      final p = d.patches['x-e1']!;
      expect(p.text, 'NEW');
      expect(p.was, 'OLD');
      expect(p.nth, 1);
      expect(p.page, '/pl/projects');
      expect(d.toJson()['patches'], {
        'x-e1': {'text': 'NEW', 'was': 'OLD', 'nth': 1, 'page': '/pl/projects'}
      });
    });

    test('bad nth is a FormatException, not a silent accept', () {
      expect(
          () => DraftOverlay.fromJson(const {
                'patches': {
                  'x-e1': {'text': 'N', 'nth': -2}
                }
              }, artifact: 'a'),
          throwsFormatException);
    });

    test('apply() patches ONLY the nth instance when nth rides along', () {
      final d = DraftOverlay.fromJson(const {
        'patches': {
          'row-e9': {'text': 'PICKED', 'nth': 1}
        }
      }, artifact: 'a');
      const html = '<p data-arxa-id="row-e9">one</p>'
          '<div>x</div><p data-arxa-id="row-e9">two</p>';
      final r = d.apply(html);
      expect(r.applied, 1);
      expect(r.html, contains('>one<'));
      expect(r.html, contains('PICKED'));
    });
  });


  group('locale targeting (2026-08-24 caveat fixes)', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('patch_test_locale');
      Directory('${dir.path}/models/project_model').createSync(recursive: true);
      const enA = '{"slug": "saska-kepa", "name": "Saska Kepa",'
          ' "tagline": "Light near the river"}';
      const plA = '{"slug": "saska-kepa", "name": "Saska Kepa",'
          ' "tagline": "Swiatlo nad rzeka"}';
      File('${dir.path}/models/project_model/project_seed.en.json')
          .writeAsStringSync('[\n  $enA\n]');
      File('${dir.path}/models/project_model/project_seed.pl.json')
          .writeAsStringSync('[\n  $plA\n]');
      File('${dir.path}/models/project_model/project_fixtures.en.json')
          .writeAsStringSync('{"projects": [\n  $enA\n]}');
      File('${dir.path}/models/project_model/project_fixtures.pl.json')
          .writeAsStringSync('{"projects": [\n  $plA\n]}');
      File('${dir.path}/cards.tsx').writeAsStringSync(
          '<div data-arxa-id="cards-e1">'
          '<h3 data-arxa-id="cards-e2">{project.name}</h3>'
          '<p data-arxa-id="cards-e3">{project.tagline}</p>'
          '</div>');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('--locale writes ONLY that locale pair', () {
      final res = patchMain([
        dir.path, 'cards-e3', '--text', 'NAD RZEKA',
        '--was', 'Swiatlo nad rzeka', '--locale', 'pl',
      ]);
      expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
      final en = File('${dir.path}/models/project_model/project_seed.en.json')
          .readAsStringSync();
      expect(en, contains('"tagline": "Light near the river"'));
      expect(en, isNot(contains('NAD RZEKA')));
      final pl = File('${dir.path}/models/project_model/project_seed.pl.json')
          .readAsStringSync();
      expect(pl, contains('"tagline": "NAD RZEKA"'));
      expect(File('${dir.path}/models/project_model/project_fixtures.pl.json')
          .readAsStringSync(), contains('NAD RZEKA'));
      expect(res.stdoutLines.first, contains('(pl; also in spine: en)'));
    });

    test('the edited locale is inferred from --was alone', () {
      final res = patchMain([
        dir.path, 'cards-e3', '--text', 'NAD RZEKA',
        '--was', 'Swiatlo nad rzeka',
      ]);
      expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
      final en = File('${dir.path}/models/project_model/project_seed.en.json')
          .readAsStringSync();
      expect(en, contains('"tagline": "Light near the river"'));
      expect(en, isNot(contains('NAD RZEKA')));
      expect(File('${dir.path}/models/project_model/project_fixtures.pl.json')
          .readAsStringSync(), contains('"tagline": "NAD RZEKA"'));
      expect(res.stdoutLines.first, contains('(pl; also in spine: en)'));
    });

    test('identical cross-locale values keep the every-locale law', () {
      final res = patchMain([
        dir.path, 'cards-e2', '--text', 'ONE STUDIO',
        '--was', 'Saska Kepa',
      ]);
      expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
      expect(File('${dir.path}/models/project_model/project_seed.en.json')
          .readAsStringSync(), contains('"name": "ONE STUDIO"'));
      expect(File('${dir.path}/models/project_model/project_seed.pl.json')
          .readAsStringSync(), contains('"name": "ONE STUDIO"'));
      expect(File('${dir.path}/models/project_model/project_fixtures.en.json')
          .readAsStringSync(), contains('ONE STUDIO'));
      expect(res.stdoutLines.first, contains('(en, pl)'));
    });

    test('an unknown locale slice refuses loudly', () {
      final res = patchMain([
        dir.path, 'cards-e3', '--text', 'X',
        '--was', 'Light near the river', '--locale', 'zz',
      ]);
      expect(res.exitCode, 5);
      expect(res.stderrLines.join(), contains('no slice'));
    });

    test('DraftPatch locale rides json; bad codes throw', () {
      final d = DraftOverlay.fromJson(const {
        'patches': {
          'k-e1': {'text': 'X', 'locale': 'pl'}
        }
      }, artifact: 'a');
      expect(d.patches['k-e1']!.locale, 'pl');
      expect(d.toJson()['patches'], {
        'k-e1': {'text': 'X', 'locale': 'pl'}
      });
      expect(
          () => DraftOverlay.fromJson(const {
                'patches': {
                  'k-e1': {'locale': 'polish'}
                }
              }, artifact: 'a'),
          throwsFormatException);
    });
  });

  group('expression routes: templates, subscripts, ternaries (2026-08-24)', () {
    test('dynamic t() template resolves by --was; infers the locale', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_tpl');
      try {
        Directory('${dir.path}/l10n').createSync();
        File('${dir.path}/l10n/app_en.arb').writeAsStringSync(
            '{"saska.place": "By the river",'
            ' "oliwa.place": "Under birches"}');
        File('${dir.path}/l10n/app_pl.arb').writeAsStringSync(
            '{"saska.place": "Nad rzeka",'
            ' "oliwa.place": "Pod brzozami"}');
        File('${dir.path}/a.tsx').writeAsStringSync(r'<p data-arxa-id="place-e1">{t(`${project.key}.place`)}</p>');
        final res = patchMain([
          dir.path, 'place-e1', '--text', 'PRZY RZECE', '--was', 'Nad rzeka',
        ]);
        expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
        final en = File('${dir.path}/l10n/app_en.arb').readAsStringSync();
        expect(en, contains('"saska.place": "By the river"'));
        expect(en, isNot(contains('PRZY RZECE')));
        final pl = File('${dir.path}/l10n/app_pl.arb').readAsStringSync();
        expect(pl, contains('"saska.place": "PRZY RZECE"'));
        expect(res.stdoutLines.first, contains('key "saska.place"'));
        expect(res.stdoutLines.first, contains('template tail'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('ambiguous template values refuse listing candidate keys', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_tpl2');
      try {
        Directory('${dir.path}/l10n').createSync();
        File('${dir.path}/l10n/app_en.arb').writeAsStringSync(
            '{"a.place": "Same spot", "b.place": "Same spot"}');
        File('${dir.path}/a.tsx').writeAsStringSync(r'<p data-arxa-id="place-e2">{t(`${project.key}.place`)}</p>');
        final res = patchMain([
          dir.path, 'place-e2', '--text', 'MOVED', '--was', 'Same spot',
        ]);
        expect(res.exitCode, 5);
        final err = res.stderrLines.join();
        expect(err, contains('ARB keys hold that value'));
        expect(err, contains('a.place'));
        expect(err, contains('b.place'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('subscript bindings ride the seed ladder', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_sub');
      try {
        Directory('${dir.path}/models/m_model').createSync(recursive: true);
        const enRow = '{"t": "Pier old"}';
        const plRow = '{"t": "Pier stary"}';
        File('${dir.path}/models/m_model/m_seed.en.json')
            .writeAsStringSync('[\n  $enRow\n]');
        File('${dir.path}/models/m_model/m_seed.pl.json')
            .writeAsStringSync('[\n  $plRow\n]');
        File('${dir.path}/models/m_model/m_fixtures.en.json')
            .writeAsStringSync('{"rows": [\n  $enRow\n]}');
        File('${dir.path}/models/m_model/m_fixtures.pl.json')
            .writeAsStringSync('{"rows": [\n  $plRow\n]}');
        File('${dir.path}/a.tsx').writeAsStringSync(
            "<li data-arxa-id=\"sub-e1\">{row['t']}</li>");
        final res = patchMain([
          dir.path, 'sub-e1', '--text', 'PIER NEW', '--was', 'Pier old',
        ]);
        expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
        expect(res.stdoutLines.first, contains('_seed.0.t'));
        expect(File('${dir.path}/models/m_model/m_seed.en.json')
            .readAsStringSync(), contains('PIER NEW'));
        expect(File('${dir.path}/models/m_model/m_seed.pl.json')
            .readAsStringSync(), contains('"t": "Pier stary"'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('conditional branches splice exactly the --was literal', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_tern');
      try {
        File('${dir.path}/a.tsx').writeAsStringSync(
            "<p data-arxa-id=\"tern-e1\">{open ? 'Open now' : 'Closed'}</p>");
        final res = patchMain([
          dir.path, 'tern-e1', '--text', 'OPEN 24/7', '--was', 'Open now',
        ]);
        expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
        final out = File('${dir.path}/a.tsx').readAsStringSync();
        expect(out, contains("{open ? 'OPEN 24/7' : 'Closed'}"));
        expect(res.stdoutLines.first, contains('conditional branch'));
        // a stale anchor refuses without touching either branch
        final res2 = patchMain([
          dir.path, 'tern-e1', '--text', 'Y', '--was', 'Shut',
        ]);
        expect(res2.exitCode, 5);
        expect(res2.stderrLines.join(), contains('no branch matching'));
        expect(File('${dir.path}/a.tsx').readAsStringSync(),
            contains("{open ? 'OPEN 24/7' : 'Closed'}"));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('name-anchored source routing (2026-08-24)', () {
    test('--el falls back to a single name= site (literal splice)', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_name');
      try {
        File('${dir.path}/w.tsx').writeAsStringSync(
            '<Box name="card-note">Studio note</Box>');
        final res = patchMain(
            [dir.path, '--el', 'card-note', '--text', 'NOTE TWO']);
        expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
        expect(res.stdoutLines.first, contains('name-anchored'));
        final out = File('${dir.path}/w.tsx').readAsStringSync();
        expect(out, contains('>NOTE TWO<'));
        expect(out, contains('name="card-note"'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('--el onto a binding routes through the seed spine', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_namex');
      try {
        Directory('${dir.path}/models/p_model').createSync(recursive: true);
        const enA = '{"tagline": "River light"}';
        const plA = '{"tagline": "Rzeka swiatlo"}';
        File('${dir.path}/models/p_model/p_seed.en.json')
            .writeAsStringSync('[\n  $enA\n]');
        File('${dir.path}/models/p_model/p_seed.pl.json')
            .writeAsStringSync('[\n  $plA\n]');
        File('${dir.path}/models/p_model/p_fixtures.en.json')
            .writeAsStringSync('{"projects": [\n  $enA\n]}');
        File('${dir.path}/models/p_model/p_fixtures.pl.json')
            .writeAsStringSync('{"projects": [\n  $plA\n]}');
        File('${dir.path}/w.tsx').writeAsStringSync(
            '<Box name="card-title">{project.tagline}</Box>');
        final res = patchMain([
          dir.path, '--el', 'card-title', '--text', 'RIVER LIT',
          '--was', 'River light',
        ]);
        expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
        expect(res.stdoutLines.first, contains('_seed.0.tagline'));
        expect(File('${dir.path}/w.tsx').readAsStringSync(),
            contains('{project.tagline}'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('two name= sites refuse loudly with locations', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_namedup');
      try {
        File('${dir.path}/a.tsx')
            .writeAsStringSync('<Box name="dup-el">one</Box>');
        File('${dir.path}/b.tsx')
            .writeAsStringSync('<Box name="dup-el">two</Box>');
        final res =
            patchMain([dir.path, '--el', 'dup-el', '--text', 'Y']);
        expect(res.exitCode, 4);
        final err = res.stderrLines.join();
        expect(err, contains('refusing to guess'));
        expect(err, contains('a.tsx'));
        expect(err, contains('b.tsx'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('zero stamp and zero name= sites exits 3 mentioning name=', () {
      final dir = Directory.systemTemp.createTempSync('patch_test_namenope');
      try {
        File('${dir.path}/empty.tsx').writeAsStringSync('');
        final res = patchMain(
            [dir.path, '--el', 'ghost', '--style', 'color=red']);
        expect(res.exitCode, 3);
        expect(res.stderrLines.join(), contains('name="ghost"'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('conditional t() branches + name-site scan (2026-08-24)', () {
    late Directory cdir;
    setUp(() => cdir = Directory.systemTemp.createTempSync('condt'));
    tearDown(() => cdir.deleteSync(recursive: true));

    test('a pure-t conditional writes the matched key; infers locale', () {
      Directory('${cdir.path}/l10n').createSync(recursive: true);
      File('${cdir.path}/l10n/app_en.arb').writeAsStringSync(
          '{\n "state.a": "Open now",\n "state.b": "Shut"\n}');
      File('${cdir.path}/l10n/app_pl.arb').writeAsStringSync(
          '{\n "state.a": "Otwarte",\n "state.b": "Zamkniete"\n}');
      File('${cdir.path}/w.tsx').writeAsStringSync("<p data-arxa-id=\"ternt-e1\">"
          "{open ? t('state.a') : t('state.b')}</p>");
      final res = patchMain([
        cdir.path, 'ternt-e1', '--text', 'OPEN 24/7', '--was', 'Open now',
      ]);
      expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
      expect(res.stdoutLines.join(), contains('l10n key "state.a"'));
      expect(res.stdoutLines.join(), contains('conditional branch'));
      expect(File('${cdir.path}/l10n/app_en.arb').readAsStringSync(),
          contains('OPEN 24/7'));
      expect(File('${cdir.path}/l10n/app_pl.arb').readAsStringSync(),
          contains('"state.a": "Otwarte"')); // pl untouched by inference
      expect(File('${cdir.path}/w.tsx').readAsStringSync(),
          contains("t('state.a')")); // expression structure preserved
    });

    test('a mixed literal/t conditional routes whichever branch matches', () {
      Directory('${cdir.path}/l10n').createSync(recursive: true);
      File('${cdir.path}/l10n/app_en.arb').writeAsStringSync(
          '{\n "state.closed": "Closed"\n}');
      File('${cdir.path}/w.tsx').writeAsStringSync(
          "<p data-arxa-id=\"mixt-e1\">{live ? 'Open now' : t('state.closed')}</p>");
      final res = patchMain([
        cdir.path, 'mixt-e1', '--text', 'SHUT FOREVER', '--was', 'Closed',
      ]);
      expect(res.exitCode, 0, reason: res.stderrLines.join('; '));
      expect(res.stdoutLines.join(), contains('"state.closed"'));
      final out = File('${cdir.path}/w.tsx').readAsStringSync();
      expect(out, contains("'Open now'")); // literal branch untouched
      expect(out, contains("t('state.closed')"));
    });

    test('cross-kind ambiguity refuses enumerating both candidate kinds', () {
      Directory('${cdir.path}/l10n').createSync(recursive: true);
      File('${cdir.path}/l10n/app_en.arb').writeAsStringSync(
          '{\n "state.a": "Open now"\n}');
      File('${cdir.path}/w.tsx').writeAsStringSync(
          "<p data-arxa-id=\"amb-e1\">{open ? 'Open now' : t('state.a')}</p>");
      final res = patchMain([
        cdir.path, 'amb-e1', '--text', 'X', '--was', 'Open now',
      ]);
      expect(res.exitCode, 5);
      expect(res.stderrLines.join(), contains('branch literal'));
      expect(res.stderrLines.join(), contains('l10n key'));
    });

    test('a t()-bearing conditional with no match refuses loudly', () {
      Directory('${cdir.path}/l10n').createSync(recursive: true);
      File('${cdir.path}/l10n/app_en.arb').writeAsStringSync(
          '{\n "state.a": "Open now"\n}');
      File('${cdir.path}/w.tsx').writeAsStringSync(
          "<p data-arxa-id=\"zero-e1\">{open ? t('state.a') : t('state.b')}</p>");
      final res = patchMain([
        cdir.path, 'zero-e1', '--text', 'X', '--was', 'Nope',
      ]);
      expect(res.exitCode, 5);
      expect(res.stderrLines.join(), contains('no branch matching --was'));
    });

    test('nameSiteLocations counts and locates authored anchors', () {
      File('${cdir.path}/a.tsx').writeAsStringSync(
          '<Box name="dup-el2">x</Box>\n<Label name="uni-el9">y</Label>\n');
      File('${cdir.path}/b.tsx').writeAsStringSync(
          '<Box name="dup-el2">z</Box>\n');
      final dup = nameSiteLocations(cdir, 'dup-el2');
      expect(dup.length, 2);
      expect(dup.map((s) => s.$1), contains(endsWith('b.tsx')));
      expect(dup.first.$3, greaterThanOrEqualTo(1)); // line numbers sane
      expect(nameSiteLocations(cdir, 'uni-el9'), hasLength(1));
      expect(nameSiteLocations(cdir, 'ghost-el'), isEmpty);
    });
  });

}
