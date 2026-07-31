// theme_map test — ports the Python self-test's discriminating cases.

import 'package:appboxd/theme_map.dart';
import 'package:test/test.dart';

void main() {
  // ──────────── hex forms ────────────

  test('6-digit hex #RRGGBB → alpha FF prefixed → 0xFF1A1714', () {
    final tree = {
      'color': {
        'fg': {'ink': {r'$value': '#1A1714', r'$type': 'color'}},
      }
    };
    final out = themeMap(tree);
    expect(out, contains('ThemeData'));
    expect(out, contains('0xFF1A1714'));
  });

  test('8-digit hex #AARRGGBB (alpha FF) → 0xFFDDD3C0, NOT double-alpha', () {
    // #FFDDD3C0 must NOT become 0xFFFFDDD3C0 (no prefixing onto an 8-digit value).
    final tree = {
      'color': {
        'bg': {'paper': {r'$value': '#FFDDD3C0', r'$type': 'color'}},
      }
    };
    final out = themeMap(tree);
    expect(out, contains('0xFFDDD3C0'));
    expect(out, isNot(contains('0xFFFFDDD3C0')));
  });

  test('8-digit non-FF alpha #80D2522B → 0x80D2522B (alpha first)', () {
    // Pins the alpha-first convention: CSS alpha-last would give 0xFF80D2522B.
    final tree = {
      'color': {
        'accent': {'soft': {r'$value': '#80D2522B', r'$type': 'color'}},
      }
    };
    final out = themeMap(tree);
    expect(out, contains('0x80D2522B'));
    expect(out, isNot(contains('0xFF80D2522B')));
  });

  test('combined fixture: all three hex forms in one tree', () {
    // The minimal W3C DTCG tree from the Python _self_test.
    final tree = {
      'color': {
        'fg': {'ink': {r'$value': '#1A1714', r'$type': 'color'}},
        'bg': {'paper': {r'$value': '#FFDDD3C0', r'$type': 'color'}},
        'accent': {'soft': {r'$value': '#80D2522B', r'$type': 'color'}},
      }
    };
    final out = themeMap(tree);
    expect(out, contains('0xFF1A1714'));
    expect(out, contains('0xFFDDD3C0'));
    expect(out, isNot(contains('0xFFFFDDD3C0')));
    expect(out, contains('0x80D2522B'));
    expect(out, isNot(contains('0xFF80D2522B')));
  });

  // ──────────── negatives ────────────

  test('empty tree → empty string', () {
    expect(themeMap({}), '');
  });

  test('non-color \$type (dimension) → skipped', () {
    final tree = {
      'color': {
        'size': {'lg': {r'$value': '24px', r'$type': 'dimension'}},
      }
    };
    expect(themeMap(tree), '');
  });

  test('non-hex \$value (rgb()) and garbage hex (#ZZZZZZ) → skipped, empty', () {
    final tree = {
      'color': {
        'weird': {'x': {r'$value': 'rgb(1,2,3)', r'$type': 'color'}},
        'bad': {'y': {r'$value': '#ZZZZZZ', r'$type': 'color'}},
      }
    };
    expect(themeMap(tree), '');
  });
}
