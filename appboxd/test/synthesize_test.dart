// synthesize test — ports the Python self-test's discriminating cases,
// exercised end-to-end through the public `synthesize` entry point.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/synthesize.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String catalogDir;
  late String outDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('synthesize-test-');
    catalogDir = '${tmp.path}/catalog';
    Directory(catalogDir).createSync(recursive: true);
    // canonical: the primitive ids the tests are permitted to use.
    File('$catalogDir/primitives-canonical.json').writeAsStringSync(jsonEncode({
      'version': 'canon-1',
      'primitives': [
        {'id': 'action.button'},
        {'id': 'surface.card'},
        {'id': 'nav.tab'},
      ],
    }));
    const catFiles = {
      'ios': 'ios-liquid-glass.json',
      'android': 'android-m4-expressive.json',
      'web': 'web-shadcn-ui.json',
    };
    for (final entry in catFiles.entries) {
      File('$catalogDir/${entry.value}')
          .writeAsStringSync(jsonEncode({'version': '${entry.key}-v1'}));
    }
    outDir = '${tmp.path}/out';
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // Plant the three pipeline inputs; return the exit code from synthesize.
  int run(Map<String, dynamic> prims, Map<String, dynamic> maps, String html) {
    File('${tmp.path}/primitives.json').writeAsStringSync(jsonEncode(prims));
    File('${tmp.path}/maps.json').writeAsStringSync(jsonEncode(maps));
    File('${tmp.path}/design.html').writeAsStringSync(html);
    return synthesize('${tmp.path}/primitives.json', '${tmp.path}/maps.json',
        '${tmp.path}/design.html', catalogDir, outDir);
  }

  Map<String, dynamic> readBreakdown() =>
      jsonDecode(File('$outDir/breakdown.json').readAsStringSync())
          as Map<String, dynamic>;

  // ──────────── 1. join: hit + miss + variant keying ────────────

  test(
      'join: hit attaches mapping; miss is flagged (not dropped); variant keyed; '
      'openQuestions + meta versions', () {
    final prims = {
      'pages': [
        {
          'id': 'home',
          'components': [
            {
              'id': 'card',
              'name': 'Card',
              'primitives': [
                {'ref': 'r1', 'id': 'action.button', 'variant': ''},
                {'ref': 'r2', 'id': 'action.button', 'variant': 'outline'},
                {'ref': 'r3', 'id': 'surface.card', 'variant': ''},
              ],
            },
          ],
        },
      ],
      'sharedComponents': [],
      'screenFlow': [],
      'skipped': [],
    };
    // mappings: plain action.button + its variant. NO entry for surface.card.
    final maps = {
      'mappings': {
        'action.button': {
          'ios': {'bridge': 'platformView'},
          'android': {'bridge': 'platformView'},
          'web': {'bridge': 'platformView'},
        },
        'action.button.outline': {
          'ios': {'bridge': 'pureFlutter'},
          'android': {'bridge': 'platformView'},
          'web': {'bridge': 'platformView'},
        },
      },
    };

    expect(run(prims, maps, '<html></html>'), 0);

    final primsOut =
        (readBreakdown()['pages'] as List)[0]['components'][0]['primitives']
            as List;
    expect(primsOut.length, 3, reason: 'a join miss must NOT drop the primitive');
    // 1. join HIT: plain action.button gets its mapping
    expect(primsOut[0]['mapping']['ios']['bridge'], 'platformView');
    // 2. variant keying: action.button.outline resolved via "id.variant"
    expect(primsOut[1]['mapping']['ios']['bridge'], 'pureFlutter');
    // 3. join MISS: fabricated bridge:none + unconfirmed + flagged notes
    expect(primsOut[2]['mapping']['ios']['bridge'], 'none');
    expect(primsOut[2]['mapping']['ios']['unconfirmed'], true);
    expect(primsOut[2]['mapping']['ios']['notes'], contains('surface.card'));

    // openQuestions: one per platform for the unconfirmed surface.card — keyed
    // by the primitive's *ref* (r3) + its owner path, matching the Python.
    final oq = readBreakdown()['openQuestions'] as List;
    expect(oq.length, 3);
    expect(
        oq.every((q) =>
            (q as String).startsWith('r3 @ home/card: confirm')), true);

    // meta carries catalog + canonical versions and resolved platforms
    final meta = readBreakdown()['meta'] as Map<String, dynamic>;
    expect(meta['canonicalVersion'], 'canon-1');
    expect(meta['catalogVersions'],
        {'ios': 'ios-v1', 'android': 'android-v1', 'web': 'web-v1'});
    expect(meta['platforms'], ['ios', 'android', 'web']);
  });

  // ──────────── 2. tokens: last-wins vs first-wins dedup ────────────

  test(
      'tokens: colors/fonts/spacing last-wins; radii/shadows first-wins dedup; '
      'non-color custom props ignored', () {
    const html = '<style>\n'
        '  :root {\n'
        '    --primary: #ff0000;\n'
        '    --primary: #00ff00;\n'
        '    --bg: rgb(10,20,30);\n'
        '    --text: hsl(0,0%,100%);\n'
        '    --gap: 16px;\n'
        '  }\n'
        '  .a { border-radius: 8px; border-radius: 12px; padding: 4px; margin: 8px; }\n'
        '  .b { font-family: Inter; font-size: 14px; font-weight: 700; '
        'box-shadow: 0 1px 2px black; padding: 6px; }\n'
        '</style>\n'
        '<div style="border-radius: 4px; --accent: #abc;"></div>\n';

    expect(run({'pages': [], 'sharedComponents': [], 'screenFlow': [], 'skipped': []},
        {'mappings': {}}, html), 0);

    final tokens = readBreakdown()['tokens'] as Map<String, dynamic>;
    // colors: --primary twice → last wins; --gap is not a color; --accent from inline
    expect(tokens['colors'], {
      'primary': '#00ff00',
      'bg': 'rgb(10,20,30)',
      'text': 'hsl(0,0%,100%)',
      'accent': '#abc',
    });
    // radii: distinct values deduped into a self-map (first-wins per value)
    expect(tokens['radii'], {'8px': '8px', '12px': '12px', '4px': '4px'});
    // typography: last-wins per property
    expect(tokens['typography'],
        {'family': 'Inter', 'size': '14px', 'weight': '700'});
    // shadows: deduped self-map
    expect(tokens['shadows'], {'0 1px 2px black': '0 1px 2px black'});
    // spacing: last-wins (padding 4px then 6px → 6px); gap matched off --gap
    expect(tokens['spacing'], {'padding': '6px', 'margin': '8px', 'gap': '16px'});
  });

  // ──────────── 3. primaryNav: sfSymbol translation + badge + dangling drop ────────────

  test(
      'primaryNav: icon→sfSymbol translation, shop tab carries cart badge, '
      'tab targeting a screen absent from screenFlow is dropped', () {
    final prims = {
      'pages': [],
      'sharedComponents': [],
      'screenFlow': [
        {'id': 'home'},
        {'id': 'shop'},
        {'id': 'support'},
      ],
      'skipped': [],
      'primaryNav': {
        'kind': 'surface.tabbar',
        'tabs': [
          {'screen': 'home', 'label': 'Train', 'icon': 'bolt'},
          {'screen': 'shop', 'label': 'Shop', 'icon': 'shop'},
          {'screen': 'support', 'label': 'Support', 'icon': 'heart'},
          {'screen': 'ghost', 'label': 'Ghost', 'icon': 'bell'}, // not in flow
        ],
      },
    };

    expect(run(prims, {'mappings': {}}, '<html></html>'), 0);

    final pn = readBreakdown()['primaryNav'] as Map<String, dynamic>;
    expect(pn['kind'], 'surface.tabbar');
    final tabs = pn['tabs'] as List;
    // ghost dropped (not in screenFlow); 3 survive (≥2 → nav shell present)
    expect(tabs.length, 3);
    expect((tabs[0] as Map)['sfSymbol'], 'bolt.fill');
    final shopTab = tabs.firstWhere((t) => (t as Map)['id'] == 'shop') as Map;
    expect(shopTab['sfSymbol'], 'bag.fill'); // 'shop' icon → bag.fill
    expect(shopTab['badgeField'], 'cartCount'); // shop tab carries the cart badge
    final homeTab = tabs.firstWhere((t) => (t as Map)['id'] == 'home') as Map;
    expect(homeTab.containsKey('badgeField'), isFalse,
        reason: 'non-shop tab must not carry a badge');
  });

  test('primaryNav: absent hint → breakdown omits primaryNav entirely', () {
    expect(
        run(
            {'pages': [], 'sharedComponents': [], 'screenFlow': [], 'skipped': []},
            {'mappings': {}},
            '<html></html>'),
        0);
    expect(readBreakdown().containsKey('primaryNav'), isFalse);
  });

  // ──────────── 4. hallucination guard ────────────

  test('non-canonical primitive id → returns 1, writes no output', () {
    final prims = {
      'pages': [
        {
          'id': 'p',
          'components': [
            {
              'id': 'c',
              'primitives': [
                {'ref': 'r', 'id': 'action.button'},
                {'ref': 'r2', 'id': 'fake.widget'}, // not in canon
              ],
            },
          ],
        },
      ],
      'sharedComponents': [],
      'screenFlow': [],
      'skipped': [],
    };
    expect(run(prims, {'mappings': {}}, '<html></html>'), 1);
    expect(File('$outDir/breakdown.json').existsSync(), isFalse,
        reason: 'no output written on hallucination failure');
  });

  // ──────────── 5. mock.html render + name backfill + uses coercion ────────────

  test(
      'mock.html: page/component/shared sections render; name backfilled from id; '
      'shared uses coerced; count matches breakdown', () {
    final prims = {
      'pages': [
        {
          'id': 'home',
          'components': [
            {
              'id': 'hero',
              'name': 'Hero',
              'primitives': [
                {'ref': 'r1', 'id': 'action.button', 'variant': ''},
                {'ref': 'r2', 'id': 'action.button', 'variant': 'outline'},
              ],
            },
          ],
        },
      ],
      'sharedComponents': [
        {
          'id': 'chip-bar',
          'kind': 'bar',
          'uses': '7 (filtered)', // descriptive string → leading digits
          'primitives': [
            {'ref': 'r3', 'id': 'surface.card', 'variant': ''},
          ],
        },
      ],
      'screenFlow': [],
      'skipped': [],
    };

    expect(run(prims, {'mappings': {}}, '<html></html>'), 0);

    final mock = File('$outDir/mock.html').readAsStringSync();
    // page name straight from id
    expect(mock, contains('<h2>Home</h2>'));
    expect(mock, contains('<h3>Hero</h3>'));
    // primitive labels: id (+ variant suffix when present)
    expect(mock, contains('action.button</div>'));
    expect(mock, contains('action.button.outline'));
    // shared section header + name backfilled from 'chip-bar' → 'Chip Bar', kind shown
    expect(mock, contains('Shared components'));
    expect(mock, contains('<h3>Chip Bar (bar)</h3>'));

    // shared uses coercion: '7 (filtered)' → 7
    final sharedOut = readBreakdown()['sharedComponents'] as List;
    expect(sharedOut[0]['uses'], 7);
  });

  test('shared uses: non-numeric string → conservative 1', () {
    final prims = {
      'pages': [],
      'sharedComponents': [
        {
          'id': 'x',
          'uses': 'none-numeric',
          'primitives': [],
        },
      ],
      'screenFlow': [],
      'skipped': [],
    };
    expect(run(prims, {'mappings': {}}, '<html></html>'), 0);
    final sharedOut = readBreakdown()['sharedComponents'] as List;
    expect(sharedOut[0]['uses'], 1);
  });
}
