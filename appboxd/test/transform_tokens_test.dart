// transform_tokens test — ports the Python self-test's discriminating cases.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/transform_tokens.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('transform-tokens-test-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // ──────────── 1. parseColor — every accepted + rejected form ────────────

  test('parseColor: hex forms, rgb(), rgba() alpha is CSS-spec 0-1', () {
    // #rgb (3-digit doubled, opaque)
    expect(parseColor('#abc'), [0xaa, 0xbb, 0xcc, 255]);
    // #rrggbb (prepended FF alpha)
    expect(parseColor('#1a2b3c'), [0x1a, 0x2b, 0x3c, 255]);
    // #aarrggbb (alpha FIRST)
    expect(parseColor('#801a2b3c'), [0x1a, 0x2b, 0x3c, 0x80]);
    // uppercase hex
    expect(parseColor('#ABC'), [0xaa, 0xbb, 0xcc, 255]);

    // rgb()
    expect(parseColor('rgb(10,20,30)'), [10, 20, 30, 255]);
    expect(parseColor('rgb( 10 , 20 , 30 )'), [10, 20, 30, 255]);

    // rgba() alpha is 0-1, clamped before ×255
    expect(parseColor('rgba(10,20,30,0.5)'), [10, 20, 30, 128]);
    expect(parseColor('rgba(10,20,30,1.0)'), [10, 20, 30, 255]);
    // stray 0-255 alpha clamps to opaque (not 255×255=65025)
    expect(parseColor('rgba(10,20,30,255)'), [10, 20, 30, 255]);
    expect(parseColor('rgba(10,20,30,-1)'), [10, 20, 30, 0]);

    // channel clamping
    expect(parseColor('rgb(300,0,0)'), [255, 0, 0, 255]);
    expect(parseColor('rgb(-10,0,0)'), [0, 0, 0, 255]);
  });

  test('parseColor: rejected forms return null', () {
    for (final bad in [
      '#abcd', '#12345', '#1234567', 'red', 'blue',
      'hsl(0,100%,50%)', '', '#zzzzzz', 'rgb(10,20)',
      'rgb(a,b,c)', 'rgb(10,20,30,)', 'transparent'
    ]) {
      expect(parseColor(bad), isNull, reason: 'parseColor($bad) should be null');
    }
  });

  // ──────────── 2. parseNum — unit conversion ────────────

  test('parseNum: rem/em ×16, pt ×4/3, % → null, bare passthrough', () {
    expect(parseNum('12'), 12.0);
    expect(parseNum('-1.5'), -1.5);
    expect(parseNum('12px'), 12.0);
    expect(parseNum('1rem'), 16.0);
    expect(parseNum('2em'), 32.0);
    expect(parseNum('0rem'), 0.0);
    expect(parseNum('12pt'), 16.0); // 12 × 4/3 = 16
    expect(parseNum('  12px  '), 12.0); // whitespace stripped
    expect(parseNum('50%'), isNull, reason: '% is not a static length');
  });

  test('parseNum: rejected forms return null', () {
    for (final bad in ['.5', '12.', '12mm', '12vw', '1e3', '+12', '0x10']) {
      expect(parseNum(bad), isNull, reason: 'parseNum($bad) should be null');
    }
  });

  // ──────────── 3. emitDart output format ────────────

  test('emitDart: color/dimension/fontFamily/cubicBezier/shadow lines', () {
    final tree = <String, dynamic>{
      'color': <String, dynamic>{
        'accent': <String, dynamic>{
          r'$type': 'color',
          r'$value': '#0E7C66',
        },
      },
      'size': <String, dynamic>{
        'radius': <String, dynamic>{
          r'$type': 'dimension',
          r'$value': '1rem',
        },
      },
      'font': <String, dynamic>{
        'sans': <String, dynamic>{
          r'$type': 'fontFamily',
          r'$value': 'Sora',
        },
      },
      'motion': <String, dynamic>{
        'rise': <String, dynamic>{
          r'$type': 'cubicBezier',
          r'$value': 'cubic-bezier(0.25,0.9,0.3,1)',
        },
      },
      'shadow': <String, dynamic>{
        'card': <String, dynamic>{
          r'$type': 'shadow',
          r'$value': '0 2px 4px rgba(0,0,0,0.1)',
        },
      },
    };
    final dart = emitDart(tree);

    // header
    expect(dart.contains('abstract final class AppTokens {'), isTrue);
    expect(dart.contains("import 'package:flutter/material.dart';"), isTrue);

    // color — AARRGGBB from #rrggbb (FF alpha prepended)
    expect(
      dart.contains('static const Color accent = Color(0xFF0E7C66);'),
      isTrue,
      reason: 'color line format',
    );

    // dimension — 1rem → 16 (g-format strips trailing zeros)
    expect(
      dart.contains('static const double radius = 16;'),
      isTrue,
      reason: 'dimension: 1rem → 16',
    );

    // fontFamily — json-encoded string binding
    expect(
      dart.contains('static const String sansFamily = "Sora";'),
      isTrue,
      reason: 'fontFamily line format',
    );

    // cubicBezier — List<double> with trailing-zero-preserving fmt
    expect(
      dart.contains('static const List<double> rise = [0.25, 0.9, 0.3, 1.0];'),
      isTrue,
      reason: 'cubicBezier line format (1.0 not 1)',
    );

    // shadow — ponytail comment
    expect(
      dart.contains('// ponytail: shadow token card (apply via BoxDecoration)'),
      isTrue,
    );

    // baseline appended (accent is defined so it's excluded; others present)
    expect(dart.contains('// appbox.baseline'), isTrue);
    expect(dart.contains('static const Color accent2'), isTrue);
    // accent is in existing → must NOT be duplicated by baseline
    final accentCount = 'static const Color accent '
        .allMatches(dart).length;
    expect(accentCount, 1, reason: 'no duplicate const for accent');
  });

  test('emitDart: nested DTCG — numeric leaves namespaced, alpha leaves alone', () {
    final tree = <String, dynamic>{
      'color': <String, dynamic>{
        'brand': <String, dynamic>{
          '0': <String, dynamic>{r'$type': 'color', r'$value': '#0E7C66'},
          '500': <String, dynamic>{r'$type': 'color', r'$value': '#0E7C66'},
        },
        'bg': <String, dynamic>{
          'surface': <String, dynamic>{r'$type': 'color', r'$value': '#FBFCFC'},
        },
        'fg': <String, dynamic>{
          'on-accent': <String, dynamic>{r'$type': 'color', r'$value': '#FFFFFF'},
        },
      },
    };
    final dart = emitDart(tree);
    expect(dart.contains('brand0'), isTrue, reason: 'numeric leaf → brand0');
    expect(dart.contains('brand500'), isTrue, reason: 'numeric leaf → brand500');
    expect(dart.contains('surface'), isTrue,
        reason: 'alpha leaf stays leaf-only');
    expect(dart.contains('onAccent'), isTrue,
        reason: 'hyphenated leaf camelCased');
    // no group-prefix regression
    expect(dart.contains('colorAccent'), isFalse);
    expect(dart.contains('colorSurface'), isFalse);
  });

  // ──────────── 4. aliasHexMap — the reverse map contract ────────────

  test('aliasHexMapFromTree: semantic leaves + aliases, alias wins', () {
    final tree = <String, dynamic>{
      'color': <String, dynamic>{
        'fg': <String, dynamic>{
          'ink': <String, dynamic>{r'$type': 'color', r'$value': '#1A1714'},
        },
        'brand': <String, dynamic>{
          '0': <String, dynamic>{r'$type': 'color', r'$value': '#D2522B'},
        },
      },
      r'$extensions': <String, dynamic>{
        'com.fluttercrew.aliases': <String, dynamic>{
          '_description': <String, dynamic>{r'$value': '#000000'},
          'ink': <String, dynamic>{r'$ref': 'color.fg.ink'},
          'accent': <String, dynamic>{r'$ref': 'color.brand.0'},
          'bone': <String, dynamic>{r'$value': '#F5F0E8'},
          'ink2': <String, dynamic>{r'$value': '#3a3530'},
          'short': <String, dynamic>{r'$value': '#abc'},
        },
      },
    };
    final m = aliasHexMapFromTree(tree);

    // alias $ref wins over semantic leaf
    expect(m['#D2522B'], 'AppTokens.accent');
    // alias $value
    expect(m['#F5F0E8'], 'AppTokens.bone');
    // lowercase normalized to UPPER
    expect(m['#3A3530'], 'AppTokens.ink2');
    // #rgb expanded
    expect(m['#AABBCC'], 'AppTokens.short');
    // semantic leaf when no alias collides
    expect(m['#1A1714'], 'AppTokens.ink');
    // underscore-prefixed alias skipped
    expect(m.containsKey('#000000'), isFalse);
  });

  test('aliasHexMapFromTree: no alias block → semantic leaves only', () {
    final m = aliasHexMapFromTree(<String, dynamic>{
      'color': <String, dynamic>{
        'x': <String, dynamic>{r'$type': 'color', r'$value': '#000000'},
      },
    });
    expect(m['#000000'], 'AppTokens.x');
    expect(aliasHexMapFromTree(<String, dynamic>{}), isEmpty);
  });

  // ──────────── 5. round-trip: emit dart → alias map resolves ────────────

  test('round-trip: every emitted color hex resolves via aliasHexMap', () {
    final tree = <String, dynamic>{
      'color': <String, dynamic>{
        'accent': <String, dynamic>{r'$type': 'color', r'$value': '#D2522B'},
        'bone': <String, dynamic>{r'$type': 'color', r'$value': '#EAE3D6'},
        'ink': <String, dynamic>{r'$type': 'color', r'$value': '#1A1714'},
      },
    };
    final dart = emitDart(tree);
    final hexMap = aliasHexMapFromTree(tree);

    // every token's hex must resolve to its AppTokens.name
    expect(hexMap['#D2522B'], 'AppTokens.accent');
    expect(hexMap['#EAE3D6'], 'AppTokens.bone');
    expect(hexMap['#1A1714'], 'AppTokens.ink');

    // and the emitted dart references each name
    for (final name in ['accent', 'bone', 'ink']) {
      expect(dart.contains('static const Color $name'), isTrue,
          reason: 'dart emits const for $name');
    }
  });

  // ──────────── 6. bezierVals ────────────

  test('bezierVals: string form, list form, ease-in-out fallback', () {
    expect(bezierVals('cubic-bezier(0.4, 0.0, 0.2, 1.0)'), [0.4, 0.0, 0.2, 1.0]);
    expect(bezierVals('cubic-bezier(0.4,0.0,0.2,1.0)'), [0.4, 0.0, 0.2, 1.0]);
    expect(bezierVals([0.2, 0.85, 0.2, 1.0]), [0.2, 0.85, 0.2, 1.0]);
    // embedded in larger string → null
    expect(bezierVals('foo cubic-bezier(0.4,0,0.2,1) bar'), isNull);
    // named easing not mapped here
    expect(bezierVals('ease-in-out'), isNull);
    // malformed list (wrong length)
    expect(bezierVals([0.4, 0.0]), isNull);

    // ease-in-out fallback in emitDart
    final dart = emitDart(<String, dynamic>{
      'motion': <String, dynamic>{
        'ease': <String, dynamic>{
          r'$type': 'cubicBezier',
          r'$value': 'ease-in-out',
        },
      },
    });
    expect(dart.contains('[0.4, 0.0, 0.2, 1.0]'), isTrue,
        reason: 'ease-in-out fallback resolves to hardcoded curve');
  });

  // ──────────── 7. transformTokens — file I/O ────────────

  test('transformTokens: writes 3 platform files, returns 0', () {
    final inPath = '${tmp.path}/tokens.json';
    final outDir = '${tmp.path}/out';
    File(inPath).writeAsStringSync(jsonEncode(<String, dynamic>{
      'color': <String, dynamic>{
        'accent': <String, dynamic>{
          r'$type': 'color',
          r'$value': '#0E7C66',
        },
      },
    }));

    final rc = transformTokens(inPath, outDir);
    expect(rc, 0, reason: 'success');

    expect(File('$outDir/dart/app_tokens.dart').existsSync(), isTrue);
    expect(File('$outDir/ios/AppTokens.swift').existsSync(), isTrue);
    expect(File('$outDir/android/tokens.xml').existsSync(), isTrue);

    final dart = File('$outDir/dart/app_tokens.dart').readAsStringSync();
    expect(dart.contains('static const Color accent = Color(0xFF0E7C66);'),
        isTrue);

    final android = File('$outDir/android/tokens.xml').readAsStringSync();
    expect(android.contains('<color name="accent">#FF0E7C66</color>'), isTrue);
  });

  test('transformTokens: returns 1 on missing file', () {
    expect(transformTokens('${tmp.path}/nope.json', '${tmp.path}/out'), 1);
  });

  // ──────────── 8. cross-platform parity ────────────

  test('parity: color/fontFamily/shadow on all 3 platforms', () {
    final tree = <String, dynamic>{
      'color': <String, dynamic>{
        'accent': <String, dynamic>{
          r'$type': 'color',
          r'$value': '#0E7C66',
        },
      },
      'font': <String, dynamic>{
        'sans': <String, dynamic>{
          r'$type': 'fontFamily',
          r'$value': 'Sora',
        },
      },
      'shadow': <String, dynamic>{
        'card': <String, dynamic>{
          r'$type': 'shadow',
          r'$value': '0 2px 4px rgba(0,0,0,0.1)',
        },
      },
    };
    final da = emitDart(tree);
    final sw = emitSwift(tree);
    final an = emitAndroid(tree);

    // color on all three
    expect(da.contains('accent'), isTrue);
    expect(sw.contains('accent'), isTrue);
    expect(an.contains('accent'), isTrue);

    // fontFamily binding on Dart + Swift; note on Android
    expect(da.contains('sansFamily'), isTrue);
    expect(sw.contains('sansFamily'), isTrue);
    expect(an.contains('fontFamily sans'), isTrue);

    // shadow ponytail comment on all three
    expect(da.contains('shadow token'), isTrue);
    expect(sw.contains('shadow token'), isTrue);
    expect(an.contains('shadow token'), isTrue);
  });

  test('camel: hyphenated → camelCased, preserves legacy contract', () {
    expect(camel('status-bar-bg'), 'statusBarBg');
    expect(camel('accent'), 'accent');
    expect(camel('on-accent'), 'onAccent');
    expect(camel(''), 'token');
    expect(camel('123abc'), 'abc');
  });
}
