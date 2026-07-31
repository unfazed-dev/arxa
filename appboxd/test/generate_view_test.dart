// generate_view test — ports the Python self-test's discriminating cases.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/generate_view.dart';
import 'package:test/test.dart';

Node _node(Map<String, dynamic> m) => m;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('generate-view-test-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // ──────────── 1. pure leaf helpers ────────────

  test('px / numFmt / dartStr / pascal / snake formatting fidelity', () {
    expect(px('12px'), 12.0);
    expect(px('12'), 12.0);
    expect(px('-1.5px'), -1.5);
    expect(px('auto'), isNull);
    expect(px(''), isNull);
    expect(px(null), isNull);

    // integral floats drop ".0"; fractional keep it (mirrors Python str(float))
    expect(numFmt(5.0), '5');
    expect(numFmt(5.5), '5.5');
    expect(numFmt(0.0), '0');

    // dartStr: single-quote default; double-quote when only single-quotes present
    expect(dartStr('Hello'), "'Hello'");
    expect(dartStr("it's"), '"it\'s"'); // contains ' but not " → double quotes
    expect(dartStr('a\$b'), "'a\\\$b'"); // $ escaped

    expect(pascalCase('sign_in'), 'SignIn');
    expect(pascalCase('hello-world foo'), 'HelloWorldFoo');
    expect(snakeCase('SignInView'), 'signinview');
    expect(snakeCase('foo-bar baz'), 'foo_bar_baz');
  });

  test('svgId: SHA-1 content-hash parity with Python hashlib.sha1[:10]', () {
    // sha1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d → first 10 = a9993e3647
    expect(svgId('abc'), 'svg_a9993e3647');
    // sha1("") = da39a3ee5e6b4b0d3255bfef95601890afd80709
    expect(svgId(''), 'svg_da39a3ee5e');
  });

  test('wcagContrast: white/black = 21:1; runs < opaque black/cream', () {
    expect(wcagContrast('#FFFFFF', '#000000'), closeTo(21.0, 0.01));
    // a near-white on cream is a low ratio (the washed-out label case)
    expect(wcagContrast('#FFFFFF', '#FBF8F2'), lessThan(2.0));
  });

  // ──────────── 2. colorDart — token map / raw hex / rgba / var() ────────────

  test('colorDart: hex→token (alias map), raw hex→Color, rgba, var() resolution', () {
    final g = GenerateView();
    // defaults carry the atlet palette: #D2522B → AppTokens.accent
    expect(g.colorDart('#D2522B'), 'AppTokens.accent');
    expect(g.colorDart('#1A1714'), 'AppTokens.ink');
    expect(g.colorDart('#1a1714'), 'AppTokens.ink'); // case-insensitive
    // raw 6-digit hex → const Color (the 6-digit branch precedes the white set,
    // so '#FFFFFF' is const Color, matching Python; only '#fff'/'white' hit white)
    expect(g.colorDart('#0E7C66'), 'const Color(0xFF0E7C66)');
    expect(g.colorDart('#FFFFFF'), 'const Color(0xFFFFFFFF)');
    expect(g.colorDart('#fff'), 'Colors.white');
    expect(g.colorDart('white'), 'Colors.white');
    // rgba → Color.fromRGBO (NOT const)
    expect(g.colorDart('rgba(10,20,30,0.5)'), 'Color.fromRGBO(10, 20, 30, 0.5)');
    expect(g.colorDart('rgb(10,20,30)'), 'Color.fromRGBO(10, 20, 30, 1)');
    // unresolvable
    expect(g.colorDart('red'), isNull);
    expect(g.colorDart(null), isNull);

    // a foreign design's alias map augments + wins on collision
    final g2 = GenerateView();
    g2.hex2tok = {'#D2522B': 'AppTokens.brand', '#0E7C66': 'AppTokens.teal'};
    expect(g2.colorDart('#D2522B'), 'AppTokens.brand');
    expect(g2.colorDart('#0E7C66'), 'AppTokens.teal');

    // var() resolution against the token table
    final g3 = GenerateView();
    g3.tokens = {'--accent': '#D2522B'};
    expect(g3.colorDart('var(--accent)'), 'AppTokens.accent'); // resolves then maps
    g3.tokens = {'--brand': '#0E7C66'};
    expect(g3.colorDart('var(--brand, #000000)'), 'const Color(0xFF0E7C66)');
  });

  // ──────────── 3. emit — widget-tree dispatch ────────────

  test('emit: Column + gap + Text + Box(→Container) structure', () {
    final g = GenerateView();
    final node = _node({
      'prim': 'Column',
      'class': <String>['col'],
      'style': <String, dynamic>{'align-items': 'center', 'gap': '8px'},
      'children': <dynamic>[
        _node({
          'prim': 'Text',
          'class': <String>[],
          'style': <String, dynamic>{
            'font-size': '14px',
            'color': '#1A1714'
          },
          'text': 'Hello',
        }),
        _node({
          'prim': 'Box',
          'class': <String>['badge'],
          'style': <String, dynamic>{
            'background': '#FFFFFF',
            'border-radius': '24px',
            'width': '40px',
            'height': '40px'
          },
          'children': <dynamic>[],
        }),
      ],
    });
    final out = g.emit(node, false);
    // Column with centered cross-axis + min size
    expect(out.contains('Column(mainAxisSize: MainAxisSize.min, '
        'crossAxisAlignment: CrossAxisAlignment.center,'), isTrue);
    // gap interposed between children
    expect(out.contains('SizedBox(height: 8)'), isTrue);
    // text node: static text + tokenised colour
    expect(out.contains("Text('Hello', style: TextStyle(fontSize: 14, "
        'color: AppTokens.ink))'), isTrue);
    // decorative box → Container with size + fill (6-digit hex → const Color) + radius
    expect(out.contains('Container(width: 40, height: 40, decoration: '
        'BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: '
        'BorderRadius.circular(24)))'), isTrue);
  });

  test('emit: chart tag-driven dispatch (foreign design vocabulary)', () {
    final g = GenerateView();
    final donut = _node({
      'prim': 'chart:bars',
      'class': <String>['chart'],
      'style': <String, dynamic>{},
      'tag': 'DonutChart',
      'children': <dynamic>[],
    });
    // tag 'DonutChart' → widget DonutChart + k-prefixed data consts (not atlet's)
    expect(g.emit(donut, false),
        'DonutChart(values: kDonutChartValues, labels: kDonutChartLabels, max: 0)');
  });

  // ──────────── 4. seedToSessionLiterals — reconciliation ────────────

  test('seedToSessionLiterals: design keys → Session ctor fields', () {
    final seed = <dynamic>[
      {
        'id': 'w1',
        'name': 'Sunrise 5k',
        'type': 'distance',
        'target': 5,
        'unit': 'km',
        'notes': 'Steady aerobic',
        'last': '2d ago',
        'streak': 4
      },
      {
        'id': 'w2',
        'name': 'Push Day',
        'type': 'reps',
        'target': 60,
        'unit': 'reps',
        'last': 'Yesterday',
        'streak': 7
      },
    ];
    final lits = seedToSessionLiterals(seed);
    expect(lits.length, 2);
    expect(lits[0].contains("title: 'Sunrise 5k'"), isTrue);
    expect(lits[0].contains('metric: 5'), isTrue);
    expect(lits[0].contains("note: 'Steady aerobic'"), isTrue);
    expect(lits[0].contains("occurredOn: DateTime.parse('2025-04-16')"), isTrue);
    expect(lits[1].contains("occurredOn: DateTime.parse('2025-04-17')"), isTrue);
    expect(lits[1].contains('streak: 7'), isTrue);

    // partial row (no id+title source) is skipped
    expect(seedToSessionLiterals(<dynamic>[
      {'type': 'reps'}
    ]).length, 0);
  });

  test('seedToSessionLiterals: foreign field_map resolves to its own fields', () {
    final foreign = <dynamic>[
      {
        'id': 'r1',
        'title': 'Morning Ride',
        'value': 25,
        'unit': 'km',
        'type': 'distance',
        'streak': 3,
        'description': 'River loop',
        'when': '3d ago'
      },
    ];
    // seedFrom.map inverted: {title:title, value:metric, description:note, when:occurredOn}
    final fmap = <String, String>{
      'title': 'title',
      'value': 'metric',
      'description': 'note',
      'when': 'occurredOn',
    };
    final lits = seedToSessionLiterals(foreign, fieldMap: fmap);
    expect(lits.length, 1);
    expect(lits[0].contains("title: 'Morning Ride'"), isTrue);
    expect(lits[0].contains('metric: 25'), isTrue);
    expect(lits[0].contains("note: 'River loop'"), isTrue);
    expect(lits[0].contains("occurredOn: DateTime.parse('2025-04-15')"), isTrue);
    // without the field_map a foreign seed (no 'name' key) is skipped
    expect(seedToSessionLiterals(foreign).length, 0);
  });

  // ──────────── 5. buildView — home bespoke dashboard ────────────

  test('buildView home: StatsCarousel + tag-driven StatBars + s.title bind', () {
    final g = GenerateView();
    final spec = _node({
      'entry': 'Home',
      'tokens': <String, dynamic>{},
      'tree': <dynamic>[
        _node({
          'prim': 'Box',
          'class': <String>['root'],
          'style': <String, dynamic>{},
          'children': <dynamic>[
            _node({
              'prim': 'Text',
              'class': <String>['workouts-title'],
              'style': <String, dynamic>{},
              'text': 'Your workouts',
            }),
            _node({
              'prim': 'Box',
              'class': <String>['stat-card'],
              'style': <String, dynamic>{'background': '#FFFFFF'},
              'children': <dynamic>[
                _node({
                  'prim': 'Text',
                  'class': <String>['eyebrow'],
                  'style': <String, dynamic>{},
                  'text': 'THIS WEEK',
                }),
                _node({
                  'prim': 'chart:bars',
                  'class': <String>['chart'],
                  'style': <String, dynamic>{},
                  'tag': 'StatBars',
                  'children': <dynamic>[],
                }),
              ],
            }),
            _node({
              'prim': 'Box',
              'class': <String>['workout-card'],
              'style': <String, dynamic>{'background': '#FFFFFF'},
              'children': <dynamic>[
                _node({
                  'prim': 'Row',
                  'class': <String>['title'],
                  'style': <String, dynamic>{},
                  'children': <dynamic>[
                    _node({
                      'prim': 'Text',
                      'class': <String>['name'],
                      'style': <String, dynamic>{},
                      'bind': <String>['w.name'],
                      'text': '',
                    }),
                  ],
                }),
              ],
            }),
          ],
        }),
      ],
    });
    final out = g.buildView(spec);

    expect(out.contains('class HomeView extends StackedView<HomeViewModel>'), isTrue);
    expect(out.contains('StatsCarousel(cards:'), isTrue);
    // tag-driven chart dispatch: kStatBarsValues, NOT atlet's stale kWeekVolume
    expect(out.contains('StatBars(values: kStatBarsValues'), isTrue);
    expect(out.contains('kWeekVolume'), isFalse);
    // spec-driven static eyebrow text survives
    expect(out.contains('THIS WEEK'), isTrue);
    // the title text is read from the spec
    expect(out.contains('Your workouts'), isTrue);
    // the w.name bind resolves to the Session field via the BIND map
    expect(out.contains('s.title'), isTrue);
    expect(out.contains('Widget _sessionCard(Session s)'), isTrue);
    // balanced brackets (cheap syntax smoke)
    expect(out.split('(').length, out.split(')').length);
  });

  // ──────────── 6. buildView — generic screen translation ────────────

  test('buildView generic: SafeArea + CSS padding → EdgeInsets', () {
    final g = GenerateView();
    final spec = _node({
      'entry': 'SettingsView',
      'tokens': <String, dynamic>{},
      'tree': <dynamic>[
        _node({
          'prim': 'Box',
          'class': <String>['screen'],
          'style': <String, dynamic>{'padding': '26px 18px'},
          'children': <dynamic>[
            _node({
              'prim': 'Text',
              'class': <String>['title'],
              'style': <String, dynamic>{
                'font-size': '24px',
                'font-weight': 'bold',
                'color': '#1A1714'
              },
              'text': 'Settings',
            }),
          ],
        }),
      ],
    });
    final out = g.buildView(spec);
    expect(out.contains('class SettingsView extends StackedView<SettingsViewModel>'),
        isTrue);
    // CSS box-model survives: 26px 18px → symmetric EdgeInsets
    expect(out.contains('EdgeInsets.symmetric(vertical: 26, horizontal: 18)'),
        isTrue);
    // generic body fills viewport + scrolls (FLOW path: start-aligned, no flex)
    expect(out.contains('SingleChildScrollView'), isTrue);
    // static title + tokenised colour + bold weight
    expect(out.contains("Text('Settings', style: TextStyle(fontSize: 24, "
        'fontWeight: FontWeight.w700, color: AppTokens.ink))'), isTrue);
    // every generic screen declares a reactive status-bar AnnotatedRegion
    expect(out.contains('AnnotatedRegion<SystemUiOverlayStyle>'), isTrue);
  });

  // ──────────── 7. generateView — file I/O round-trip + error path ────────────

  test('generateView: writes a view file, returns 0; bad spec returns 1', () {
    final specPath = '${tmp.path}/spec.json';
    final outPath = '${tmp.path}/out/settings_view.dart';
    File(specPath).writeAsStringSync(jsonEncode(<String, dynamic>{
      'entry': 'SettingsView',
      'tokens': <String, dynamic>{},
      'tree': <dynamic>[
        <String, dynamic>{
          'prim': 'Box',
          'class': <String>['screen'],
          'style': <String, dynamic>{},
          'children': <dynamic>[
            <String, dynamic>{
              'prim': 'Text',
              'class': <String>['title'],
              'style': <String, dynamic>{},
              'text': 'Settings',
            },
          ],
        },
      ],
    }));

    final rc = generateView(specPath, outPath);
    expect(rc, 0, reason: 'success');
    expect(File(outPath).existsSync(), isTrue);
    final dart = File(outPath).readAsStringSync();
    expect(dart.contains('class SettingsView extends StackedView'), isTrue);

    // a malformed spec (not a JSON object) → 1
    final badPath = '${tmp.path}/bad.json';
    File(badPath).writeAsStringSync('[1, 2, 3]');
    expect(generateView(badPath, '${tmp.path}/out2.dart'), 1);
    // a missing file → 1
    expect(generateView('${tmp.path}/nope.json', '${tmp.path}/out3.dart'), 1);
  });

  test('generateView: tokensPath injects the alias hex→name map', () {
    // tokens.json declares an alias block: accent ← #D2522B
    final tokensPath = '${tmp.path}/tokens.json';
    File(tokensPath).writeAsStringSync(jsonEncode(<String, dynamic>{
      'color': <String, dynamic>{
        'brand': <String, dynamic>{
          '0': <String, dynamic>{r'$type': 'color', r'$value': '#D2522B'},
        },
      },
      r'$extensions': <String, dynamic>{
        'com.fluttercrew.aliases': <String, dynamic>{
          'accent': <String, dynamic>{r'$ref': 'color.brand.0'},
        },
      },
    }));
    final specPath = '${tmp.path}/spec.json';
    final outPath = '${tmp.path}/out/view.dart';
    File(specPath).writeAsStringSync(jsonEncode(<String, dynamic>{
      'entry': 'HeroView',
      'tokens': <String, dynamic>{},
      'tree': <dynamic>[
        <String, dynamic>{
          'prim': 'Box',
          'class': <String>['screen'],
          'style': <String, dynamic>{},
          'children': <dynamic>[
            <String, dynamic>{
              'prim': 'Text',
              'class': <String>['cta'],
              'style': <String, dynamic>{'color': '#D2522B'},
              'text': 'Go',
            },
          ],
        },
      ],
    }));
    expect(generateView(specPath, outPath, tokensPath: tokensPath), 0);
    final dart = File(outPath).readAsStringSync();
    // the design hex resolves to its OWN token name (AppTokens.accent), not a
    // bare Color(0xFF...) literal
    expect(dart.contains('color: AppTokens.accent'), isTrue);
    expect(dart.contains('const Color(0xFFD2522B)'), isFalse);
  });
}
