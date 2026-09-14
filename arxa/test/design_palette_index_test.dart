// design_palette_index tests (the universal palette plane, Q9/Q10): a
// fixture artifact proves the template shape + the derivation law end to
// end — index, render, drift — hermetically (temp dirs, no Chrome).
import 'dart:convert';
import 'dart:io';

import 'package:arxa/design_palette_index.dart';
import 'package:test/test.dart';

Directory _fixture() {
  final d = Directory.systemTemp.createTempSync('palette-index-test');
  // the manifest (identity default + one seeded backfill)
  File(d.path + '/palettes.json').writeAsStringSync(jsonEncode({
    'default': 'fix-teal',
    'palettes': [
      {
        'id': 'fix-teal',
        'name': 'Fixture Teal',
        'swatch': ['#0d0e13', '#0fa3a3', '#67625e', '#e5e2dd', '#fbf8f3'],
        'themeColor': '#0fa3a3',
        'seeded': true,
      },
      {
        'id': 'fix-alt',
        'name': 'Fixture Alt',
        'swatch': ['#1a1a2e', '#16213e', '#0f3460', '#e94560', '#eaeaea'],
        'themeColor': '#0f3460',
        'seeded': true,
        'sheet': '/assets/styles/palettes/palette-fix-alt.css',
      },
    ],
  }));
  Directory(d.path + '/ui/styles/common').createSync(recursive: true);
  File(d.path + '/ui/styles/common/tokens.css').writeAsStringSync(':root {\n'
      '  --dark: #0d0e13;\n'
      '  --accent: #0fa3a3;\n'
      '  --field: #67625e;\n'
      '  --beige: #e5e2dd;\n'
      '  --paper: #fbf8f3;\n'
      '  --overlay: rgba(13, 14, 19, 0.55);\n'
      '  --shadow-pill: 0 12px 32px rgba(15, 163, 163, 0.12);\n'
      '}\n');
  File(d.path + '/ui/styles/common/app.css').writeAsStringSync(
      '.hero { background: #fbf8f3; color: #0d0e13; }\n'
      '.cta { background: rgb(15, 163, 163); }\n'
      '.overlay { background: rgba(13, 14, 19, 0.55); }\n'
      '.note { color: #c0007a; }\n'
      '@media (min-width: 840px) { .hero { color: #67625e; } }\n');
  return d;
}

void main() {
  late Directory d;
  setUp(() { d = _fixture(); });
  tearDown(() { d.deleteSync(recursive: true); });

  test('indexArtifact: anchors derive from the default palette', () {
    final index = indexArtifact(d.path)!;
    expect(index.anchors, {
      'dark': '#0d0e13',
      'accent': '#0fa3a3',
      'field': '#67625e',
      'beige': '#e5e2dd',
      'paper': '#fbf8f3',
    });
  });

  test('indexTokens: five roles incl. the low-saturation field (the anchor '
      'pass), the overlay takes rgba form, the shadow takes shadow form', () {
    final index = indexArtifact(d.path)!;
    final byName = {for (final t in index.tokens) t['name']: t};
    expect(byName.keys, containsAll(
        ['--dark', '--accent', '--field', '--beige', '--paper', '--overlay', '--shadow-pill']));
    expect(byName['--field']!['family'], 'field');
    expect(byName['--overlay']!['form'], 'rgba:0.55');
    expect(byName['--overlay']!['family'], 'dark');
    expect(byName['--shadow-pill']!['form'],
        'shadow:0 12px 32px rgba({t}, 0.12)');
    expect(byName['--shadow-pill']!['family'], 'accent');
  });

  test('indexRules: literals become slots, at-rules nest, the intentional '
      'chromatic is reported by check, neutrals pass through', () {
    final index = indexArtifact(d.path)!;
    final sels = [for (final r in index.rules) r['sel'].toString()];
    expect(sels.any((s) => s.contains('.hero')), isTrue);
    expect(sels.any((s) => s.contains('.cta')), isTrue);
    expect(sels.any((s) => s.contains('.overlay')), isTrue);
    final heroAt = index.rules.firstWhere(
        (r) => r['sel'].toString().contains('.hero') && (r['at'] as List).isNotEmpty);
    expect(heroAt['at'], ['@media (min-width: 840px)']);
    final drift = checkPaletteTemplate(d.path);
    expect(drift.length, 1); // the missing template alone short-circuits
    expect(drift.single, contains('_template.json missing'));
  });

  test('writeTemplate + renderSeeded + check: the loop closes, then a '
      'corpus edit drifts named', () {
    writeTemplate(d.path, indexArtifact(d.path)!);
    renderSeeded(d.path);
    final sheet =
        File(d.path + '/assets/styles/palettes/palette-fix-alt.css');
    expect(sheet.existsSync(), isTrue);
    expect(sheet.readAsStringSync(), contains('[data-palette="fix-alt"] .hero'));
    final tokensText =
        File(d.path + '/ui/styles/common/tokens.css').readAsStringSync();
    expect(tokensText.contains('[data-palette="fix-alt"]'), isTrue);
    // clean except the intentional chromatic (the gate allowlists it, not us)
    var drift = checkPaletteTemplate(d.path);
    expect(drift.length, 1);
    expect(drift.single, contains('.note'));
    expect(drift.single, contains('#c0007a'));
    // edit the corpus: a new family-colored rule must drift, named
    File(d.path + '/ui/styles/common/app.css').writeAsStringSync(
        File(d.path + '/ui/styles/common/app.css').readAsStringSync() +
            '\n.new-rule { border-color: #0fa3a3; }\n');
    drift = checkPaletteTemplate(d.path);
    expect(drift.any((l) => l.contains('missing template rule') && l.contains('.new-rule')),
        isTrue);
    // and repair: re-run, drift is the chromatic alone again
    writeTemplate(d.path, indexArtifact(d.path)!);
    renderSeeded(d.path);
    drift = checkPaletteTemplate(d.path);
    expect(drift.length, 1);
  });

  test('familyOf: the fitted gates — neutral far from anchors, the anchor '
      'itself passes, chromatic beyond 45° is unindexed', () {
    final anchors = {
      'dark': '#0d0e13',
      'accent': '#0fa3a3',
      'field': '#67625e',
      'beige': '#e5e2dd',
      'paper': '#fbf8f3',
    };
    expect(familyOf('#ffffff', anchors), isNull); // neutral, far from anchors
    expect(familyOf('#67625e', anchors), 'field'); // the anchor itself (s < 12)
    expect(familyOf('#0fa3a3', anchors), 'accent');
    // the gate is ANCHOR-RELATIVE: under these warm anchors #c0392b sits
    // 26° from the field/beige hue — inside the gate, assigned (on the
    // all-cool marine anchors the same red was unindexed + allowlisted).
    expect(familyOf('#c0392b', anchors), 'field');
    expect(familyOf('#c0007a', anchors), isNull); // beyond 45° from every anchor
    expect(familyOf('#0c8a8a', anchors), 'accent'); // a teal shade
  });
}
