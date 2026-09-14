// Suitor palette OBJECTS (the palette plane, Q7/Q9 of
// docs/plans/arxa-palette-plane-universal.md): a suitor's tokens.palette
// recorded as the derived object must validate whole — swatch exactly 5
// valid hexes, anchors complete, paletteSource in the SELECTED set,
// provenance measured|judged with judged legal only when the credited
// reference has neither url nor shot, and palette evidence resolving on
// disk. A prose palette string is the pre-plane shape and stays green —
// the grandfather pin below protects records made between the audition
// landing and the palette plane.
//
// Every assertion is written to FAIL if the behaviour it names is removed,
// in the house style of moodboard_suitors_test.dart.

import 'dart:io';

import 'package:arxa/moodboard_check.dart';
import 'package:test/test.dart';

Map<String, dynamic> _ref(String name,
        {bool selected = true, String? url, bool shot = false}) =>
    <String, dynamic>{
      'name': name,
      'url': ?url,
      if (shot)
        'shot': <String, dynamic>{
          'file': 'polestar.png',
          'id': 'main--polestar',
          'src': '/assets/images/moodboard/main/polestar.png',
        },
      'provenance': 'inferred',
      'scores': {'premium': 4},
      'total': 4.0,
      if (selected) 'selected': true,
    };

Map<String, dynamic> _validPalette(
        {String provenance = 'measured', Object? source = 'main/Polestar'}) =>
    <String, dynamic>{
      'name': 'polestar night',
      'swatch': ['#0a0a0a', '#1b3a4b', '#5b7a8c', '#c9d4d9', '#f2f4f5'],
      'anchors': <String, dynamic>{
        'dark': '#0a0a0a',
        'accent': '#1b3a4b',
        'field': '#5b7a8c',
        'beige': '#c9d4d9',
        'paper': '#f2f4f5',
      },
      'paletteSource': source,
      'provenance': provenance,
      'evidence': [
        {'kind': 'palette', 'file': 'evidence/polestar__palette.json'},
      ],
    };

Map<String, dynamic> _suitor(String id, {Object? palette, bool tokensOnly = false}) =>
    <String, dynamic>{
      'id': id,
      'name': 'direction $id',
      'spread': 'owns the register the others do not',
      'leads': const ['main/Polestar'],
      'tokens': <String, dynamic>{
        'palette': ?palette,
        if (!tokensOnly) 'motion': 'scroll-scrubbed canvas',
      },
      'provenance': 'judged',
    };

/// An approved, selected record with three suitors whose palettes are the
/// derived object. The credited reference carries a url by default —
/// measured palettes derive from it; judged-palette tests drop it.
Map<String, dynamic> _record(
        {Object? paletteA,
        Object? paletteB,
        Object? paletteC,
        String? refUrl = 'https://example.com/',
        bool refShot = false,
        bool refSelected = true,
        bool tokensOnly = false}) =>
    <String, dynamic>{
      'criteria': [
        {'id': 'premium', 'weight': 1},
      ],
      'selectionStatus': 'approved',
      'boards': [
        {
          'id': 'main',
          'references': [
            _ref('Polestar',
                url: refUrl, shot: refShot, selected: refSelected),
          ],
        },
      ],
      'suitors': [
        _suitor('A', palette: paletteA ?? _validPalette(), tokensOnly: tokensOnly),
        _suitor('B', palette: paletteB ?? _validPalette(), tokensOnly: tokensOnly),
        _suitor('C', palette: paletteC ?? _validPalette(), tokensOnly: tokensOnly),
      ],
    };

void main() {
  late Directory tmp;
  late String moodboardDir;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('suitor_palette_');
    moodboardDir = '${tmp.path}/moodboard';
    Directory('$moodboardDir/evidence').createSync(recursive: true);
    File('$moodboardDir/evidence/polestar__palette.json')
        .writeAsStringSync('{}');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('happy paths', () {
    test('three valid derived palettes are green with evidence on disk', () {
      expect(checkMoodboardRecord(_record(), moodboardDir: moodboardDir),
          isEmpty);
    });

    test('a prose palette string stays green — the pre-plane shape', () {
      final rec = _record(
          paletteA: 'warm white / deep green',
          paletteB: 'cold blue / bare metal',
          paletteC: 'paper white / ink black');
      expect(checkMoodboardRecord(rec, moodboardDir: moodboardDir), isEmpty);
    });

    test('a palette object alone satisfies the token requirement', () {
      expect(
          checkMoodboardRecord(_record(tokensOnly: true),
              moodboardDir: moodboardDir),
          isEmpty);
    });

    test('a judged palette is green when the reference has neither url nor '
        'shot', () {
      final judged = _validPalette(provenance: 'judged')..remove('evidence');
      final rec =
          _record(refUrl: null, paletteA: judged, paletteB: judged, paletteC: judged);
      expect(checkMoodboardRecord(rec, moodboardDir: moodboardDir), isEmpty);
    });

    test('shape-only validation skips disk resolution', () {
      // No moodboardDir: the palette cites evidence, nothing is on disk,
      // and shape-only mode has no resolution to fail.
      expect(checkMoodboardRecord(_record()), isEmpty);
    });
  });

  group('shape failures', () {
    test('a palette that is neither object nor string fails', () {
      final failures = checkMoodboardRecord(_record(paletteA: 42));
      expect(failures.any((f) => f.contains('suitor A: tokens.palette must '
          'be the derived palette object')), isTrue);
    });

    test('a swatch of 4 fails — exactly 5', () {
      final p = _validPalette()
        ..['swatch'] = ['#0a0a0a', '#1b3a4b', '#5b7a8c', '#c9d4d9'];
      final failures = checkMoodboardRecord(_record(paletteA: p));
      expect(failures.any((f) => f.contains('suitor A: palette swatch must '
          'be exactly 5 hexes, got 4')), isTrue);
    });

    test('a swatch of 6 fails — the plane width never reaches the moodboard',
        () {
      final p = _validPalette()
        ..['swatch'] = [
          '#0a0a0a', '#1b3a4b', '#2e4a5a', '#5b7a8c', '#c9d4d9', '#f2f4f5',
        ];
      final failures = checkMoodboardRecord(_record(paletteA: p));
      expect(failures.any((f) => f.contains('got 6')), isTrue);
    });

    test('a non-hex swatch entry fails', () {
      final p = _validPalette()
        ..['swatch'] = ['#0a0a0a', '#1b3a4b', '#5b7a8c', '#c9d4d9', '#zzzzzz'];
      final failures = checkMoodboardRecord(_record(paletteA: p));
      expect(failures.any((f) => f.contains('suitor A: palette swatch '
          '"#zzzzzz" is not a valid hex')), isTrue);
    });

    test('anchors missing a role fail', () {
      final p = _validPalette()
        ..['anchors'] = <String, dynamic>{
          'dark': '#0a0a0a',
          'accent': '#1b3a4b',
          'field': '#5b7a8c',
          'paper': '#f2f4f5',
        };
      final failures = checkMoodboardRecord(_record(paletteA: p));
      expect(failures.any((f) => f.contains('suitor A: palette anchors '
          'missing or not valid hexes: beige')), isTrue);
    });

    test('an anchor that is not a hex fails', () {
      final p = _validPalette()
        ..['anchors'] = <String, dynamic>{
          'dark': '#0a0a0a',
          'accent': '#1b3a4b',
          'field': '#5b7a8c',
          'beige': '#c9d4d9',
          'paper': 'white',
        };
      final failures = checkMoodboardRecord(_record(paletteA: p));
      expect(failures.any((f) => f.contains('missing or not valid hexes: '
          'paper')), isTrue);
    });

    test('anchors that are not a map fail', () {
      final p = _validPalette()..['anchors'] = 'nope';
      final failures = checkMoodboardRecord(_record(paletteA: p));
      expect(failures.any((f) => f.contains('suitor A: palette anchors must '
          'carry the five template-family roles')), isTrue);
    });
  });

  group('paletteSource', () {
    test('a source resolving to no reference fails', () {
      final p = _validPalette(source: 'main/Nobody');
      final failures = checkMoodboardRecord(_record(paletteA: p));
      expect(failures.any((f) => f.contains('suitor A: paletteSource '
          '"main/Nobody" is not a selected reference')), isTrue);
    });

    test('a source resolving to an UNSELECTED reference fails', () {
      // The lead-resolution failure text overlaps this one, so pin the
      // paletteSource wording itself — a lead-only failure must not satisfy
      // this assertion.
      final failures = checkMoodboardRecord(_record(refSelected: false));
      expect(
          failures.any((f) => f.contains('paletteSource "main/Polestar" is '
              'not a selected reference')),
          isTrue);
    });

    test('a source that is not a string fails', () {
      final p = _validPalette(source: 7);
      final failures = checkMoodboardRecord(_record(paletteA: p));
      expect(
          failures.any((f) => f.contains('suitor A: paletteSource "7" is '
              'not a selected reference')),
          isTrue);
    });
  });

  group('provenance', () {
    test('provenance outside measured|judged fails', () {
      final p = _validPalette(provenance: 'remembered');
      final failures = checkMoodboardRecord(_record(paletteA: p));
      expect(failures.any((f) => f.contains('suitor A: palette provenance '
          'must be measured|judged')), isTrue);
    });

    test('a judged palette fails when the credited reference has a url', () {
      final p = _validPalette(provenance: 'judged')..remove('evidence');
      final failures = checkMoodboardRecord(_record(paletteB: p));
      expect(failures.any((f) => f.contains('suitor B: palette judged but '
          '"main/Polestar" has a url — derivation was possible')), isTrue);
    });

    test('a judged palette fails when the credited reference has a shot', () {
      final p = _validPalette(provenance: 'judged')..remove('evidence');
      final failures =
          checkMoodboardRecord(_record(refUrl: null, refShot: true, paletteB: p));
      expect(failures.any((f) => f.contains('suitor B: palette judged but '
          '"main/Polestar" has a shot — derivation was possible')), isTrue);
    });

    test('a measured palette with no evidence fails — measured cites the '
        'engine JSON', () {
      // Absent key and explicit empty list are the same lie: derivation IS
      // measurement, and the citation is the proof. Judged stays
      // evidence-optional (its weakness is flagged by the url/shot check).
      final absent = _validPalette()..remove('evidence');
      final empty = _validPalette()..['evidence'] = <Map<String, dynamic>>[];
      for (final p in [absent, empty]) {
        final failures = checkMoodboardRecord(_record(paletteA: p),
            moodboardDir: moodboardDir);
        expect(
            failures.any((f) => f.contains('suitor A: palette provenance '
                'measured but no evidence')),
            isTrue);
      }
    });
  });

  group('evidence', () {
    test('palette evidence that does not resolve on disk fails', () {
      final p = _validPalette()
        ..['evidence'] = [
          {'kind': 'palette', 'file': 'evidence/never-written.json'},
        ];
      final failures =
          checkMoodboardRecord(_record(paletteA: p), moodboardDir: moodboardDir);
      expect(failures.any((f) => f.contains('suitor A palette: evidence '
          'file "evidence/never-written.json" does not resolve')), isTrue);
    });
  });
}
