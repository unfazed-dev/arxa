// Tests for the derivation engine (lib/palette_derive.dart) — arxa-
// palette-plane-universal.md Q3/Q5/Q6/Q7, incl. the 2026-09-10 N=1/N=2
// tonal ruling (N=2 interpolates DARK→PAPER, never accent→paper) and the
// Q6 first-wins arbitration. Every branch of the variable-width law,
// salient selection, the four-source orchestrator, and the slot-fill
// reseed.

import 'package:arxa/design_palettes.dart'
    show PaletteEntry, PaletteManifest, anchorsFor;
import 'package:arxa/lens/tokens.dart' show ColorCluster;
import 'package:arxa/palette.dart' show tonalRamp;
import 'package:arxa/palette_derive.dart';
import 'package:test/test.dart';

class _FakeClusters implements ClusterSource {
  _FakeClusters(this.byKind);
  final Map<DeriveKind, List<ColorCluster>> byKind;
  final calls = <(DeriveKind, String)>[];
  @override
  Future<List<ColorCluster>> clusters(DeriveKind kind, String input) async {
    calls.add((kind, input));
    return byKind[kind] ?? const [];
  }
}

Future<DerivedPalette> _hexes(String input, {List<RoleHint>? roleHints}) =>
    derive(DeriveKind.hexes, input, roleHints: roleHints);

/// The Q2 fallback five; Marine Blue rides SECOND on disk so a plan must
/// lift the manifest's own default first. Lavender Iris carries a sheet
/// to pin fallback-keeps-its-sheet in the non-default slots.
PaletteManifest _fallback() => PaletteManifest(defaultId: 'marine', palettes: [
      const PaletteEntry(
        id: 'c-6f58c9',
        name: 'Lavender Iris',
        swatch: ['#bdede0', '#bbdbd1', '#b6b8d6', '#7e78d2', '#6f58c9'],
        themeColor: '#7e78d2',
        seeded: true,
        sheet: '/assets/styles/palettes/palette-c-6f58c9.css',
      ),
      const PaletteEntry(
        id: 'marine',
        name: 'Marine Blue',
        swatch: ['#ccdbdc', '#9ad1d4', '#80ced7', '#007ea7', '#003249'],
        themeColor: '#007EA7',
        seeded: true,
      ),
      const PaletteEntry(
        id: 'c-2e1f27',
        name: 'Sunset Ember',
        swatch: ['#e7e393', '#f4c95d', '#dd7230', '#854d27', '#2e1f27'],
        themeColor: '#854d27',
        seeded: true,
      ),
      const PaletteEntry(
        id: 'c-8e518d',
        name: 'Orchid Bloom',
        swatch: ['#d7c0d0', '#f7c7db', '#f79ad3', '#c86fc9', '#8e518d'],
        themeColor: '#c86fc9',
        seeded: true,
      ),
      const PaletteEntry(
        id: 'c-293f14',
        name: 'Forest Neon',
        swatch: ['#d3f8e2', '#a9f5c8', '#6ee7a0', '#3ba55d', '#293f14'],
        themeColor: '#3ba55d',
        seeded: true,
      ),
    ]);

const _marine = ['#ccdbdc', '#9ad1d4', '#80ced7', '#007ea7', '#003249'];
const _coolors5 = ['#bdede0', '#bbdbd1', '#b6b8d6', '#7e78d2', '#6f58c9'];

void main() {
  group('hslMix', () {
    test('lerps s/l linearly through gray', () {
      expect(hslMix('#000000', '#ffffff', 0.5), '#808080');
    });
    test('takes the shortest hue arc across the 0/360 wrap', () {
      // 348° -> 12° crosses the wrap (24° arc through red); the long way
      // around would land near cyan (180°).
      expect(hslMix('#ff0033', '#ff3300', 0.5), '#ff0000');
    });
    test('endpoints round-trip exactly', () {
      expect(hslMix('#1b3a4b', '#eef4ed', 0), '#1b3a4b');
      expect(hslMix('#1b3a4b', '#eef4ed', 1), '#eef4ed');
    });
  });

  group('anchorsForN — the variable-width law (Q5)', () {
    test('N=1: accent = the seed, the rest ride its HCT ramp 10/50/90/99', () {
      final a = anchorsForN(['#1b6ca8']);
      final ramp = tonalRamp('#1b6ca8');
      expect(a['accent'], '#1b6ca8');
      expect(a['dark'], ramp[10]);
      expect(a['field'], ramp[50]);
      expect(a['beige'], ramp[90]);
      expect(a['paper'], ramp[99]);
    });
    test('N=2: dark/paper at the ends, accent = the more saturated', () {
      final a = anchorsForN(['#003249', '#ccdbdc']);
      expect(a['dark'], '#003249');
      expect(a['paper'], '#ccdbdc');
      expect(a['accent'], '#003249', reason: 'the navy out-saturates the mist');
    });
    test('N=2: saturation ties break darker', () {
      final a = anchorsForN(['#404040', '#c0c0c0']);
      expect(a['accent'], '#404040', reason: 'both grays have s=0');
      expect(a['dark'], '#404040');
      expect(a['paper'], '#c0c0c0');
    });
    test('N=2: mid-roles interpolate DARK→PAPER even when the light hex wins saturation',
        () {
      // The measured collapse that amended the law: #e9f5ec out-saturates
      // #264653 by a hair (37.50 vs 37.19), so accent == paper; field/beige
      // must still sit strictly between the endpoints.
      final a = anchorsForN(['#264653', '#e9f5ec']);
      expect(a['dark'], '#264653');
      expect(a['paper'], '#e9f5ec');
      expect(a['accent'], '#e9f5ec');
      expect(a['field'], hslMix('#264653', '#e9f5ec', 1 / 3));
      expect(a['beige'], hslMix('#264653', '#e9f5ec', 2 / 3));
      for (final mid in [a['field']!, a['beige']!]) {
        expect(mid, isNot(a['dark']));
        expect(mid, isNot(a['paper']));
      }
      expect(a['field'], isNot(a['beige']));
    });
    test('N=2: dark→paper interpolation holds under a darker accent too', () {
      final a = anchorsForN(['#003249', '#ccdbdc']);
      expect(a['field'], hslMix('#003249', '#ccdbdc', 1 / 3));
      expect(a['beige'], hslMix('#003249', '#ccdbdc', 2 / 3));
    });
    test('N=3: dark/accent/paper ranked, field/beige interpolate accent→paper',
        () {
      final a = anchorsForN(['#0b2545', '#8da9c4', '#eef4ed']);
      expect(a['dark'], '#0b2545');
      expect(a['accent'], '#8da9c4');
      expect(a['paper'], '#eef4ed');
      expect(a['field'], hslMix('#8da9c4', '#eef4ed', 1 / 3));
      expect(a['beige'], hslMix('#8da9c4', '#eef4ed', 2 / 3));
    });
    test('N=4: dark/accent/field/paper ranked, beige interpolates field→paper',
        () {
      final a = anchorsForN(['#101418', '#3e5c76', '#748cab', '#f0ebd8']);
      expect(a['dark'], '#101418');
      expect(a['accent'], '#3e5c76');
      expect(a['field'], '#748cab');
      expect(a['paper'], '#f0ebd8');
      expect(a['beige'], hslMix('#748cab', '#f0ebd8', 1 / 2));
    });
    test('N=5 delegates to the verified anchorsFor, byte-identical', () {
      expect(anchorsForN(_coolors5), anchorsFor(_coolors5));
      final a = anchorsForN(_coolors5);
      expect(a['dark'], '#6f58c9');
      expect(a['accent'], '#7e78d2');
      expect(a['field'], '#b6b8d6');
      expect(a['beige'], '#bbdbd1');
      expect(a['paper'], '#bdede0');
    });
    test('N=6: ranks 0,1,2,3,5 — the 5th-lightest is decimated out', () {
      final a = anchorsForN(
          ['#000000', '#202020', '#606060', '#a0a0a0', '#d0d0d0', '#ffffff']);
      expect(a['dark'], '#000000');
      expect(a['accent'], '#202020');
      expect(a['field'], '#606060');
      expect(a['beige'], '#a0a0a0');
      expect(a['paper'], '#ffffff');
      expect(a.values, isNot(contains('#d0d0d0')));
    });
    test('N=7: ranks 0,1,3,4,6 (floor(i*(N-1)/4))', () {
      final a = anchorsForN([
        '#000000',
        '#181818',
        '#303030',
        '#606060',
        '#909090',
        '#c8c8c8',
        '#ffffff'
      ]);
      expect(a['dark'], '#000000');
      expect(a['accent'], '#181818');
      expect(a['field'], '#606060');
      expect(a['beige'], '#909090');
      expect(a['paper'], '#ffffff');
    });
    test('normalizes case and missing # to canonical form', () {
      expect(anchorsForN(['#CCDBDC', '9ad1d4', '#80CED7', '007ea7', '#003249']),
          anchorsForN(_marine));
    });
    test('rejects 0, 8+, and malformed hexes', () {
      expect(() => anchorsForN([]), throwsArgumentError);
      expect(
          () => anchorsForN([
                '#101010',
                '#202020',
                '#303030',
                '#404040',
                '#505050',
                '#606060',
                '#707070',
                '#808080'
              ]),
          throwsArgumentError);
      expect(() => anchorsForN(['#aabbcc', 'not-a-color', '#ddeeff']),
          throwsFormatException);
    });
  });

  group('anchorsForN — role hints (Q6)', () {
    test('a pin beats the lightness rank', () {
      final a = anchorsForN(_marine,
          roleHints: [(role: 'accent', hex: '#003249')]);
      expect(a['accent'], '#003249', reason: 'the darkest hex pins to accent');
      // The remaining four rank-fill over the remaining pool by the N=4 law.
      expect(a['dark'], '#007ea7');
      expect(a['field'], '#9ad1d4');
      expect(a['beige'], hslMix('#9ad1d4', '#ccdbdc', 1 / 2));
      expect(a['paper'], '#ccdbdc');
    });
    test('two claims on one role are first-wins, never a refusal', () {
      final a = anchorsForN(_marine,
          roleHints: [
            (role: 'accent', hex: '#003249'),
            (role: 'accent', hex: '#007ea7'),
          ]);
      expect(a['accent'], '#003249', reason: 'statement order is client priority');
    });
    test('a hint naming an absent hex is ignored', () {
      final a = anchorsForN(_marine,
          roleHints: [(role: 'accent', hex: '#112233')]);
      expect(a, anchorsFor(_marine));
    });
    test('a pinned hex survives N=6 decimation', () {
      final a = anchorsForN(
          ['#000000', '#202020', '#606060', '#a0a0a0', '#d0d0d0', '#ffffff'],
          roleHints: [(role: 'paper', hex: '#a0a0a0')]);
      expect(a['paper'], '#a0a0a0',
          reason: 'pin first — decimation can never drop a pinned hex');
      expect(a['dark'], '#000000');
      expect(a['accent'], '#202020');
      expect(a['field'], '#606060');
      expect(a['beige'], '#d0d0d0');
    });
    test('pins never strand a role, even with an empty pool', () {
      final a = anchorsForN(['#0b2545', '#8da9c4', '#eef4ed'],
          roleHints: [
            (role: 'dark', hex: '#0b2545'),
            (role: 'accent', hex: '#8da9c4'),
            (role: 'paper', hex: '#eef4ed'),
          ]);
      // Pool exhausted: the mid-roles ride the first pin's tonal ramp.
      expect(a['field'], tonalRamp('#0b2545')[50]);
      expect(a['beige'], tonalRamp('#0b2545')[90]);
      expect(a.length, 5);
    });
  });

  group('selectSalient', () {
    test('refuses empty input', () {
      expect(() => selectSalient(const []), throwsArgumentError);
    });
    test('merges within RGB euclidean ≤ 12, keeping the heavier count', () {
      // Nine grays (step 20, no merges) plus a near-duplicate of the
      // lightest gray. Keep-heavier leaves the merged bucket at count 7,
      // so the top-8 cut drops it; a summing merge (13) would drop #8c8c8c.
      final picked = selectSalient([
        ColorCluster(0, 0, 0, 100),
        ColorCluster(20, 20, 20, 50),
        ColorCluster(40, 40, 40, 40),
        ColorCluster(60, 60, 60, 30),
        ColorCluster(80, 80, 80, 20),
        ColorCluster(100, 100, 100, 10),
        ColorCluster(120, 120, 120, 9),
        ColorCluster(140, 140, 140, 8),
        ColorCluster(160, 160, 160, 7),
        ColorCluster(163, 163, 163, 6), // d=3 from the 160 bucket
      ]);
      expect(picked,
          ['#8c8c8c', '#646464', '#3c3c3c', '#141414', '#000000']);
      expect(picked, isNot(contains('#a0a0a0')),
          reason: 'the merged bucket keeps the heavier count (7), never sums');
    });
    test('the merge boundary is inclusive at euclidean 12', () {
      final picked = selectSalient([
        ColorCluster(0, 0, 0, 50),
        ColorCluster(12, 0, 0, 40), // d == 12 → merged
        ColorCluster(40, 40, 40, 30),
        ColorCluster(90, 90, 90, 20),
        ColorCluster(140, 140, 140, 10),
        ColorCluster(190, 190, 190, 5),
      ]);
      expect(picked,
          ['#bebebe', '#8c8c8c', '#5a5a5a', '#282828', '#000000']);
    });
    test('a cluster just past 12 survives (thin input pads by repetition)', () {
      final picked = selectSalient([
        ColorCluster(0, 0, 0, 10),
        ColorCluster(13, 0, 0, 9), // d == 13 → survives
        ColorCluster(255, 255, 255, 8),
      ]);
      expect(picked,
          ['#ffffff', '#0d0000', '#0d0000', '#000000', '#000000']);
    });
    test('ranks by count desc, keeps the top 8, decimates to five light→dark',
        () {
      // Ten grays (step 28); the two darkest carry the lowest counts.
      final picked = selectSalient([
        for (var i = 0; i < 10; i++)
          ColorCluster(i * 28, i * 28, i * 28,
              [10, 20, 30, 40, 50, 60, 70, 80, 100, 90][i]),
      ]);
      expect(picked,
          ['#fcfcfc', '#c4c4c4', '#8c8c8c', '#545454', '#383838']);
    });
  });

  group('derive', () {
    test('coolors: the slug is the palette, passthrough to the rank law', () async {
      const input = 'https://coolors.co/bdede0-bbdbd1-b6b8d6-7e78d2-6f58c9';
      final p = await derive(DeriveKind.coolors, input);
      expect(p.swatch, _coolors5);
      expect(p.anchors, anchorsFor(_coolors5));
      expect(p.suggestedName, 'Palette 6F58C9');
      expect(p.evidence['source'], 'DeriveKind.coolors:$input');
      expect(p.toJson().keys,
          orderedEquals(['swatch', 'anchors', 'suggestedName', 'evidence']));
    });
    test('coolors: rejects non-slugs', () {
      expect(() => derive(DeriveKind.coolors, 'not a link'),
          throwsArgumentError);
    });
    test('hexes: carried verbatim in order, normalized to canonical form', () async {
      final p = await _hexes('bdede0, BBDBD1 b6b8d6,#7E78D2,6f58c9');
      expect(p.swatch, _coolors5);
      expect(p.anchors, anchorsFor(_coolors5));
    });
    test('hexes N=1: the swatch becomes the five anchors (3-floor law)', () async {
      final p = await _hexes('1b6ca8');
      expect(p.anchors['accent'], '#1b6ca8');
      expect(p.swatch, [
        p.anchors['dark'],
        p.anchors['accent'],
        p.anchors['field'],
        p.anchors['beige'],
        p.anchors['paper'],
      ]);
      expect(p.swatch.length, 5);
      expect((p.evidence['notes'] as List).join('\n'),
          contains('N<3, the 3-floor law'));
    });
    test('hexes N=2: swatch is the five anchors, dark→paper mid-roles', () async {
      final p = await _hexes('003249, ccdbdc');
      expect(p.anchors['dark'], '#003249');
      expect(p.anchors['accent'], '#003249');
      expect(p.anchors['paper'], '#ccdbdc');
      expect(p.anchors['field'], hslMix('#003249', '#ccdbdc', 1 / 3));
      expect(p.swatch.length, 5);
    });
    test('hexes: rejects >7, empty, and malformed tokens', () {
      expect(
          () => _hexes('101010,202020,303030,404040,505050,606060,707070,808080'),
          throwsArgumentError);
      expect(() => _hexes(''), throwsArgumentError);
      expect(() => _hexes('aabbcc, zzzzzz, ddeeff'), throwsFormatException);
    });
    test('url: rides the injected ClusterSource, trail recorded', () async {
      final fake = _FakeClusters({
        DeriveKind.url: [
          for (var i = 0; i < 10; i++)
            ColorCluster(i * 28, i * 28, i * 28,
                [10, 20, 30, 40, 50, 60, 70, 80, 100, 90][i]),
        ],
      });
      final p = await derive(DeriveKind.url, 'https://example.com',
          clusters: fake);
      expect(fake.calls, [(DeriveKind.url, 'https://example.com')]);
      expect(p.swatch,
          ['#fcfcfc', '#c4c4c4', '#8c8c8c', '#545454', '#383838']);
      expect(p.anchors['dark'], '#383838');
      expect(p.anchors['paper'], '#fcfcfc');
      expect((p.evidence['clusters'] as List).length, 10);
      expect(p.evidence['selected'], p.swatch);
    });
    test('image: the kind passes through the seam', () async {
      final fake = _FakeClusters({
        DeriveKind.image: [
          ColorCluster(16, 16, 16, 50),
          ColorCluster(64, 64, 64, 40),
          ColorCluster(112, 112, 112, 30),
          ColorCluster(176, 176, 176, 20),
          ColorCluster(240, 240, 240, 10),
        ],
      });
      final p = await derive(DeriveKind.image, '/tmp/shot.png', clusters: fake);
      expect(fake.calls, [(DeriveKind.image, '/tmp/shot.png')]);
      expect(p.swatch,
          ['#f0f0f0', '#b0b0b0', '#707070', '#404040', '#101010']);
    });
    test('url/image refuse without a ClusterSource', () {
      expect(() => derive(DeriveKind.url, 'https://example.com'),
          throwsArgumentError);
      expect(() => derive(DeriveKind.image, '/tmp/shot.png'),
          throwsArgumentError);
    });
    test('role hints pin and the pinnings + arbitration hit the evidence',
        () async {
      final p = await _hexes(_marine.join(','), roleHints: [
        (role: 'accent', hex: '#003249'),
        (role: 'accent', hex: '#007ea7'),
      ]);
      expect(p.anchors['accent'], '#003249');
      final notes = (p.evidence['notes'] as List).join('\n');
      expect(notes, contains('pinned accent = #003249 (client hint, Q6)'));
      expect(notes,
          contains('first-wins kept #003249, ignored #007ea7 (arbitration, Q6)'));
    });
  });

  group('planReseed — the Q7 slot-fill law', () {
    late DerivedPalette brand, winner, declined, reference;
    setUp(() async {
      brand = await _hexes('101010, 303030, 606060, a0a0a0, f0f0f0');
      winner = await _hexes('1b3a4b, 3e5c76, 748cab, b8c9d9, f0ebd8');
      declined = await _hexes('3c1642, 6a3937, 9c6644, d4a373, faedcd');
      reference = await _hexes('0d3b66, 14508c, 247ba0, 70c1b3, f4fffd');
    });

    test('brand → suitors → references → fallback, default = first candidate',
        () {
      final plan = planReseed(
        fallback: _fallback(),
        brand: [brand],
        suitors: [winner, declined],
        references: [reference],
      );
      expect(plan.entries.length, 5);
      expect([for (final e in plan.entries) e.id],
          ['c-101010', 'c-1b3a4b', 'c-3c1642', 'c-0d3b66', 'marine']);
      expect(plan.defaultId, 'c-101010');
      expect(plan.notes, [
        'slot 1: Palette 101010 (client brandColors (Q6 priority))',
        'slot 2: Palette 1B3A4B (winning suitor, remix applied)',
        'slot 3: Palette 3C1642 (declined suitor B)',
        'slot 4: Palette 0D3B66 (selected reference by score)',
        'slot 5: Marine Blue (fallback five backfill)',
      ]);
      expect(plan.entries.every((e) => e.seeded), isTrue);
      expect(plan.entries.first.themeColor, '#303030',
          reason: 'themeColor follows the accent anchor');
    });

    test('the default carries no sheet; the other four do', () {
      final plan = planReseed(
        fallback: _fallback(),
        brand: [brand],
        suitors: [winner, declined],
        references: [reference],
      );
      expect(plan.entries[0].sheet, isNull,
          reason: 'the default is the base corpus');
      for (var i = 1; i < 4; i++) {
        expect(plan.entries[i].sheet,
            '/assets/styles/palettes/palette-${plan.entries[i].id}.css');
      }
      expect(plan.entries[4].sheet,
          '/assets/styles/palettes/palette-marine.css',
          reason: 'a backfill slot is not the base corpus — it gets a sheet');
    });

    test('fallback keeps its ids and its sheets in the backfill slots', () {
      final plan = planReseed(fallback: _fallback(), brand: [brand]);
      expect([for (final e in plan.entries) e.id],
          ['c-101010', 'marine', 'c-6f58c9', 'c-2e1f27', 'c-8e518d']);
      expect(plan.entries[2].sheet,
          '/assets/styles/palettes/palette-c-6f58c9.css',
          reason: 'a fallback sheet rides verbatim');
      expect(plan.entries[4].sheet,
          '/assets/styles/palettes/palette-c-8e518d.css',
          reason: 'a sheet-less fallback entry gets the generated path');
    });

    test('never-derived projects get the fallback five, its default first', () {
      final plan = planReseed(fallback: _fallback());
      expect([for (final e in plan.entries) e.id],
          ['marine', 'c-6f58c9', 'c-2e1f27', 'c-8e518d', 'c-293f14']);
      expect(plan.defaultId, 'marine');
      expect(plan.entries[0].sheet, isNull);
    });

    test('dedup is by swatch set, first wins — order-insensitive', () async {
      final dupe = await _hexes('f0f0f0, a0a0a0, 606060, 303030, 101010');
      final plan = planReseed(
        fallback: _fallback(),
        brand: [brand],
        suitors: [dupe, winner],
      );
      expect([for (final e in plan.entries) e.id].take(2),
          ['c-101010', 'c-1b3a4b'],
          reason: 'the reordered duplicate never takes a slot');
      expect(plan.entries.length, 5);
    });

    test('a candidate matching the fallback default evicts it (first wins)',
        () async {
      final marineRemix = await _hexes('003249, 007ea7, 80ced7, 9ad1d4, ccdbdc');
      final plan = planReseed(fallback: _fallback(), references: [marineRemix]);
      expect(plan.entries[0].id, 'c-003249');
      expect([for (final e in plan.entries) e.id], isNot(contains('marine')),
          reason: 'the first claim on a swatch set holds it');
      expect(plan.entries.length, 5);
    });

    test('fresh ids mint c-<darkhex> with -n disambiguation', () async {
      final a = await _hexes('112233, 334455, 556677, 99aabb, eefff8');
      final b = await _hexes('112233, 553311, 886644, bb9977, ffeedd');
      final plan = planReseed(fallback: _fallback(), brand: [a, b]);
      expect(plan.entries[0].id, 'c-112233');
      expect(plan.entries[1].id, 'c-112233-2');
    });

    test('fallback ids are reserved — a mint never claims one', () async {
      final lavender = await _hexes('6f58c9, 8a76d8, a594e2, bdb3e9, d7d2f2');
      final plan = planReseed(fallback: _fallback(), brand: [lavender]);
      expect(plan.entries[0].id, 'c-6f58c9-2',
          reason: 'c-6f58c9 belongs to the fallback five');
      expect([for (final e in plan.entries) e.id], contains('c-6f58c9'),
          reason: 'the fallback entry keeps its id and its slot');
    });
  });
}
