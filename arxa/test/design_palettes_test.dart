// Tests for the palette plane (lib/design_palettes.dart) — VERIFY ADDENDUM
// 17/18. The 18 regression: a pasted palette sheet generated but never wired
// into the served <head>, so its tokens flipped while the 57 override rules
// stayed base — the "mixed palette" report. These tests pin the wiring
// (serve-time injection + theme-color) and the ingest lifecycle (generate,
// dedup, repair-on-half-wipe, delete-without-residue).

import 'dart:io';

import 'package:arxa/design_palettes.dart';
import 'package:arxa/palette_derive.dart' show hslMix;
import 'package:test/test.dart';

PaletteManifest _manifest() => PaletteManifest(defaultId: 'marine', palettes: [
      const PaletteEntry(
        id: 'marine',
        name: 'Marine Blue',
        swatch: ['#ccdbdc', '#9ad1d4', '#80ced7', '#007ea7', '#003249'],
        themeColor: '#007EA7',
        seeded: true,
      ),
      const PaletteEntry(
        id: 'original',
        name: 'Original',
        swatch: ['#fafafa', '#ede7db', '#e7e8e6', '#ff692e', '#0a0d12'],
        themeColor: '#ff692e',
        seeded: true,
        sheet: '/assets/styles/palettes/palette-original.css',
      ),
      const PaletteEntry(
        id: 'c-6f58c9',
        name: 'Coolors 6F58C9',
        swatch: ['#bdede0', '#bbdbd1', '#b6b8d6', '#7e78d2', '#6f58c9'],
        themeColor: '#7e78d2',
        sheet: '/assets/styles/palettes/palette-c-6f58c9.css',
      ),
    ]);

const _html = '<!doctype html>'
    '<html lang="en"><head>'
    '<meta name="theme-color" content="#007EA7">'
    '<link rel="stylesheet" href="/ui/styles/common/styles.css">'
    '<link rel="stylesheet" href="/assets/styles/palettes/palette-original.css">'
    '</head><body><div id="app"></div></body></html>';

void main() {
  group('applyPaletteToServedHtml', () {
    test('stamps the attribute: override > stored > default', () {
      final m = _manifest();
      final over = applyPaletteToServedHtml(_html,
          query: {'palette': 'original'}, stored: 'c-6f58c9', manifest: m);
      expect(over.active, 'original');
      expect(over.html, contains('data-palette="original"'));
      final stored = applyPaletteToServedHtml(_html,
          query: const {}, stored: 'c-6f58c9', manifest: m);
      expect(stored.active, 'c-6f58c9');
      final def = applyPaletteToServedHtml(_html,
          query: const {}, stored: null, manifest: m);
      expect(def.active, 'marine');
      final unknown = applyPaletteToServedHtml(_html,
          query: {'palette': 'nope'}, stored: 'c-6f58c9', manifest: m);
      expect(unknown.active, 'c-6f58c9');
    });

    test('wires every declared sheet exactly once (ADDENDUM 18)', () {
      final m = _manifest();
      final r = applyPaletteToServedHtml(_html,
          query: const {}, stored: null, manifest: m);
      expect(RegExp(r'palette-original.css').allMatches(r.html).length, 1,
          reason: 'statically linked sheet must not be duplicated');
      expect(r.html,
          contains('href="/assets/styles/palettes/palette-c-6f58c9.css"'),
          reason: 'an unlinked declared sheet must be injected');
      expect(r.html, contains('data-palette-sheet="c-6f58c9"'));
      expect(r.html.indexOf('palette-c-6f58c9.css'),
          lessThan(r.html.indexOf('</head>')),
          reason: 'injected sheets land inside <head>');
    });

    test('stamps theme-color to the ACTIVE palette', () {
      final m = _manifest();
      final r = applyPaletteToServedHtml(_html,
          query: {'palette': 'c-6f58c9'}, stored: null, manifest: m);
      expect(r.html, contains('name="theme-color" content="#7e78d2"'));
    });
  });

  group('parseCoolorsSlug', () {
    test('accepts url, /palette/ path, and bare slug', () {
      for (final input in [
        'https://coolors.co/bdede0-bbdbd1-b6b8d6-7e78d2-6f58c9',
        'https://coolors.co/palette/bdede0-bbdbd1-b6b8d6-7e78d2-6f58c9',
        'bdede0-bbdbd1-b6b8d6-7e78d2-6f58c9',
      ]) {
        expect(parseCoolorsSlug(input),
            ['bdede0', 'bbdbd1', 'b6b8d6', '7e78d2', '6f58c9'],
            reason: input);
      }
    });
    test('rejects non-slugs', () {
      expect(parseCoolorsSlug('https://coolors.co/ffffff'), isNull);
      expect(parseCoolorsSlug('not a link'), isNull);
    });
  });

  group('transplant law', () {
    test('an anchor transplants onto the target anchor exactly', () {
      expect(transplant('#007ea7', '#007ea7', '#1a936f'), '#1a936f');
    });
    test('lightness rank assigns roles (darkest=dark, lightest=paper)', () {
      final a =
          anchorsFor(['#bdede0', '#bbdbd1', '#b6b8d6', '#7e78d2', '#6f58c9']);
      expect(a['dark'], '#6f58c9');
      expect(a['accent'], '#7e78d2');
      expect(a['field'], '#b6b8d6');
      expect(a['beige'], '#bbdbd1');
      expect(a['paper'], '#bdede0');
    });
  });

  group('PaletteIngestion', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('arxa-palette-test');
      File('${dir.path}/palettes.json').writeAsStringSync(
          '{"version":1,"default":"marine","palettes":['
          '{"id":"marine","name":"Marine Blue",'
          '"swatch":["#ccdbdc","#9ad1d4","#80ced7","#007ea7","#003249"],'
          '"themeColor":"#007EA7","seeded":true}]}');
      File('${dir.path}/assets/styles/palettes/_template.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{'
            '"anchors":{"accent":"#007ea7","dark":"#003249",'
            '"paper":"#ccdbdc","beige":"#9ad1d4","field":"#80ced7"},'
            '"tokens":['
            '{"name":"--accent","base":"#007ea7","family":"accent","form":"hex"},'
            '{"name":"--ink","base":"#003249","family":"dark","form":"hex"}],'
            '"rules":[{"at":[],'
            '"sel":"[data-palette=\\"{id}\\"] .thing",'
            '"tpl":"background: {0};",'
            '"slots":[{"base":"#80ced7","family":"field","form":"hex"}]}]}');
      File('${dir.path}/ui/styles/common/tokens.css')
        ..createSync(recursive: true)
        ..writeAsStringSync(':root {\n  --accent: #007ea7;\n}\n');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    const slug = 'https://coolors.co/2e1f27-854d27-dd7230-f4c95d-e7e393';

    test('ingest writes sheet + tokens block + manifest entry', () {
      final e = PaletteIngestion(artifactDir: dir.path).ingest(slug);
      expect(e.id, 'c-2e1f27');
      expect(e.themeColor, '#854d27');
      expect(
          File('${dir.path}/assets/styles/palettes/palette-c-2e1f27.css')
              .existsSync(),
          isTrue);
      final tokens =
          File('${dir.path}/ui/styles/common/tokens.css').readAsStringSync();
      expect(tokens, contains('[data-palette="c-2e1f27"]'));
      expect(PaletteManifest.load(dir.path)!.declares('c-2e1f27'), isTrue);
    });

    test('dedup returns the same id without a duplicate entry', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      final a = ing.ingest(slug);
      final b = ing.ingest(slug);
      expect(b.id, a.id);
      expect(PaletteManifest.load(dir.path)!.palettes.length, 2);
    });

    test('a half-wiped entry repairs on re-ingest (ADDENDUM 18)', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      final a = ing.ingest(slug);
      // simulate the crash/cleanup window: artifacts gone, manifest stays
      File('${dir.path}/assets/styles/palettes/palette-c-2e1f27.css')
          .deleteSync();
      final tokensFile = File('${dir.path}/ui/styles/common/tokens.css');
      tokensFile.writeAsStringSync(tokensFile.readAsStringSync().replaceAll(
          RegExp('\\n*/\\* pasted palette c-2e1f27[^\\n]*\\*/\\n'
              '\\[data-palette="c-2e1f27"\\] \\{[^}]*\\}\\n?'),
          '\n'));
      final b = ing.ingest(slug); // must NOT hollow-return
      expect(b.id, a.id);
      expect(
          File('${dir.path}/assets/styles/palettes/palette-c-2e1f27.css')
              .existsSync(),
          isTrue,
          reason: 're-ingest must regenerate the wiped sheet');
      expect(
          File('${dir.path}/ui/styles/common/tokens.css').readAsStringSync(),
          contains('[data-palette="c-2e1f27"]'));
      expect(PaletteManifest.load(dir.path)!.palettes.length, 2,
          reason: 'repair must not duplicate the manifest entry');
    });

    test('delete strips entry + sheet + tokens block, no residue', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      ing.ingest(slug);
      ing.delete('c-2e1f27');
      expect(PaletteManifest.load(dir.path)!.declares('c-2e1f27'), isFalse);
      expect(
          File('${dir.path}/assets/styles/palettes/palette-c-2e1f27.css')
              .existsSync(),
          isFalse);
      expect(File('${dir.path}/ui/styles/common/tokens.css').readAsStringSync(),
          isNot(contains('c-2e1f27')));
    });

    test('seeded entries and the default refuse deletion', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      expect(() => ing.delete('marine'), throwsArgumentError);
    });

    test('a new paste replaces the previous custom (one-slot law)', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      ing.ingest(slug); // c-2e1f27 takes the custom slot
      const slug2 = 'https://coolors.co/d7c0d0-f7c7db-f79ad3-c86fc9-8e518d';
      final b = ing.ingest(slug2);
      expect(b.id, 'c-8e518d');
      final m = PaletteManifest.load(dir.path)!;
      expect(m.declares('c-2e1f27'), isFalse,
          reason: 'the previous custom leaves the manifest');
      expect(m.declares('c-8e518d'), isTrue);
      expect(m.declares('marine'), isTrue,
          reason: 'seeded palettes survive the sweep');
      expect(
          File('${dir.path}/assets/styles/palettes/palette-c-2e1f27.css')
              .existsSync(),
          isFalse,
          reason: 'the replaced custom sheet is stripped');
      final tokens =
          File('${dir.path}/ui/styles/common/tokens.css').readAsStringSync();
      expect(tokens, isNot(contains('[data-palette="c-2e1f27"]')),
          reason: 'the replaced custom tokens block is stripped');
      expect(tokens, contains('[data-palette="c-8e518d"]'));
      expect(m.palettes.where((e) => !e.seeded).length, 1,
          reason: 'exactly one custom slot, always');
    });

    test('a dedup re-paste never sweeps the slot', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      final a = ing.ingest(slug);
      final b = ing.ingest(slug); // the same link again
      expect(b.id, a.id);
      expect(PaletteManifest.load(dir.path)!.declares('c-2e1f27'), isTrue);
    });
  });

  group('PaletteEntry.fromJson (the 3..7 law)', () {
    Map<String, Object?> json(int n) => {
          'id': 'c-123456',
          'name': 'X',
          'themeColor': '#123456',
          'swatch': [for (var i = 0; i < n; i++) '#12345$i'],
        };
    test('accepts 3..7 swatches, refuses 2 and 8', () {
      expect(PaletteEntry.fromJson(json(3)), isNotNull);
      expect(PaletteEntry.fromJson(json(5)), isNotNull);
      expect(PaletteEntry.fromJson(json(7)), isNotNull);
      expect(PaletteEntry.fromJson(json(2)), isNull);
      expect(PaletteEntry.fromJson(json(8)), isNull);
    });
  });

  group('tokensCssPath (the two-layout resolver)', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('arxa-tokens-path-test');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('site-layout wins when present, app-layout otherwise', () {
      expect(tokensCssPath(dir.path), endsWith('assets/css/tokens.css'));
      File('${dir.path}/ui/styles/common/tokens.css')
          .createSync(recursive: true);
      expect(
          tokensCssPath(dir.path), endsWith('ui/styles/common/tokens.css'));
    });
  });

  group('PaletteIngestion.update', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('arxa-palette-update-test');
      File('${dir.path}/palettes.json').writeAsStringSync(
          '{"version":1,"default":"marine","palettes":['
          '{"id":"marine","name":"Marine Blue",'
          '"swatch":["#ccdbdc","#9ad1d4","#80ced7","#007ea7","#003249"],'
          '"themeColor":"#007EA7","seeded":true},'
          '{"id":"c-6f58c9","name":"Lavender Iris",'
          '"swatch":["#bdede0","#bbdbd1","#b6b8d6","#7e78d2","#6f58c9"],'
          '"themeColor":"#7e78d2","seeded":true,'
          '"source":"https://coolors.co/bdede0-bbdbd1-b6b8d6-7e78d2-6f58c9",'
          '"sheet":"/assets/styles/palettes/palette-c-6f58c9.css"}]}');
      File('${dir.path}/assets/styles/palettes/_template.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{'
            '"anchors":{"accent":"#007ea7","dark":"#003249",'
            '"paper":"#ccdbdc","beige":"#9ad1d4","field":"#80ced7"},'
            '"tokens":['
            '{"name":"--accent","base":"#007ea7","family":"accent","form":"hex"},'
            '{"name":"--ink","base":"#003249","family":"dark","form":"hex"}],'
            '"rules":[{"at":[],'
            '"sel":"[data-palette=\\"{id}\\"] .thing",'
            '"tpl":"background: {0};",'
            '"slots":[{"base":"#80ced7","family":"field","form":"hex"}]}]}');
      File('${dir.path}/assets/styles/palettes/palette-c-6f58c9.css')
          .writeAsStringSync('/* stale */\n');
      File('${dir.path}/ui/styles/common/tokens.css')
        ..createSync(recursive: true)
        ..writeAsStringSync(
            ':root {\n  --accent: #007ea7;\n  --ink: #003249;\n}\n'
            '\n/* pasted palette c-6f58c9 (#bdede0-#bbdbd1-#b6b8d6-#7e78d2-#6f58c9)'
            ' — ingestion, do not hand-edit */\n'
            '[data-palette="c-6f58c9"] {\n'
            '  --accent: #7e78d2;\n  --ink: #6f58c9;\n}\n');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    const forkHexes = ['#2e1f27', '#854d27', '#dd7230', '#f4c95d', '#e7e393'];
    const trio = ['#0f2027', '#203a43', '#2c5364'];

    test('in-place: re-derives swatch/themeColor/sheet/tokens, id stable', () {
      final r =
          PaletteIngestion(artifactDir: dir.path).update('c-6f58c9', trio);
      expect(r.forked, isFalse);
      expect(r.entry.id, 'c-6f58c9', reason: 'the id is stable');
      expect(r.entry.seeded, isTrue, reason: 'seeded untouched');
      expect(r.entry.source,
          'https://coolors.co/bdede0-bbdbd1-b6b8d6-7e78d2-6f58c9',
          reason: 'source untouched');
      expect(r.entry.sheet, '/assets/styles/palettes/palette-c-6f58c9.css',
          reason: 'sheet untouched');
      expect(r.entry.swatch, trio);
      // N=3: dark=r0, accent=r1, paper=r2; field/beige interpolate.
      expect(r.entry.themeColor, '#203a43');
      final field = hslMix('#203a43', '#2c5364', 1 / 3);
      final sheet = File(
              '${dir.path}/assets/styles/palettes/palette-c-6f58c9.css')
          .readAsStringSync();
      expect(sheet, contains('[data-palette="c-6f58c9"] .thing'));
      expect(sheet, contains('background: $field;'));
      expect(sheet, isNot(contains('stale')),
          reason: 'the sheet is rewritten, not appended');
      final tokens =
          File('${dir.path}/ui/styles/common/tokens.css').readAsStringSync();
      expect('[data-palette="c-6f58c9"]'.allMatches(tokens).length, 1,
          reason: 'strip + append in ONE write leaves exactly one block');
      expect(tokens, contains('--accent: #203a43;'));
      expect(tokens, contains('--ink: #0f2027;'));
      expect(tokens, isNot(contains('#7e78d2')),
          reason: 'the old derivation is gone');
      expect(tokens, contains(':root'),
          reason: 'the base block is not the update\'s to touch');
      final m = PaletteManifest.load(dir.path)!;
      expect(m.palettes.length, 2, reason: 'no entries added in place');
      expect(m.palettes.singleWhere((e) => e.id == 'c-6f58c9').swatch, trio,
          reason: 'the manifest saves LAST with the new swatch');
      expect(
          Directory('${dir.path}/assets/styles/palettes')
              .listSync()
              .whereType<File>()
              .any((f) => f.path.endsWith('.tmp')),
          isFalse,
          reason: 'the atomic sheet write leaves no temp residue');
    });

    test('in-place renames only when a name is given', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      final r = ing.update('c-6f58c9', trio, name: 'Renamed Iris');
      expect(r.entry.name, 'Renamed Iris');
      final again = ing.update('c-6f58c9', trio);
      expect(again.entry.name, 'Renamed Iris',
          reason: 'no name given — the manifest name survives');
    });

    test('in-place accepts seven hexes (N>5 takes ranks 0,1,3,4,6)', () {
      const seven = [
        '#111111', '#333333', '#555555', '#777777',
        '#999999', '#bbbbbb', '#dddddd',
      ];
      final r =
          PaletteIngestion(artifactDir: dir.path).update('c-6f58c9', seven);
      expect(r.entry.swatch.length, 7);
      expect(r.entry.themeColor, '#333333',
          reason: 'accent = the 2nd by lightness');
    });

    test('editing the default FORKS into the one custom slot (Q4)', () {
      final r =
          PaletteIngestion(artifactDir: dir.path).update('marine', forkHexes);
      expect(r.forked, isTrue);
      final e = r.entry;
      expect(e.id, 'c-2e1f27');
      expect(e.name, 'Custom 2E1F27');
      expect(e.seeded, isFalse);
      expect(e.source, 'dial-edit:fork-of-marine');
      expect(e.themeColor, '#854d27');
      expect(e.sheet, '/assets/styles/palettes/palette-c-2e1f27.css');
      expect(
          File('${dir.path}/assets/styles/palettes/palette-c-2e1f27.css')
              .existsSync(),
          isTrue);
      expect(
          File('${dir.path}/ui/styles/common/tokens.css').readAsStringSync(),
          contains('[data-palette="c-2e1f27"]'));
      final m = PaletteManifest.load(dir.path)!;
      expect(m.defaultId, 'marine', reason: 'the fork never claims the default');
      expect(m.palettes.singleWhere((e) => e.id == 'marine').swatch,
          const ['#ccdbdc', '#9ad1d4', '#80ced7', '#007ea7', '#003249'],
          reason: 'the base corpus stays hand-owned');
      expect(r.palettes.length, 3);
    });

    test('a second fork sweeps the previous custom (one-slot law)', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      ing.update('marine', forkHexes);
      const other = ['#d7c0d0', '#f7c7db', '#f79ad3', '#c86fc9', '#8e518d'];
      final r = ing.update('marine', other);
      expect(r.entry.id, 'c-8e518d');
      final m = PaletteManifest.load(dir.path)!;
      expect(m.declares('c-2e1f27'), isFalse,
          reason: 'the previous custom leaves the manifest');
      expect(m.declares('c-8e518d'), isTrue);
      expect(m.palettes.where((e) => !e.seeded).length, 1,
          reason: 'exactly one custom slot, always');
      expect(
          File('${dir.path}/assets/styles/palettes/palette-c-2e1f27.css')
              .existsSync(),
          isFalse,
          reason: 'the swept custom sheet is stripped');
      final tokens =
          File('${dir.path}/ui/styles/common/tokens.css').readAsStringSync();
      expect(tokens, isNot(contains('[data-palette="c-2e1f27"]')));
      expect(tokens, contains('[data-palette="c-8e518d"]'));
    });

    test('a fork duplicating ANY palette refuses, naming the conflict', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      expect(
          () => ing.update('marine', const [
              '#bdede0', '#bbdbd1', '#b6b8d6', '#7e78d2', '#6f58c9']),
          throwsA(isA<PaletteConflictError>()
              .having((e) => e.conflictsWith, 'conflictsWith', 'c-6f58c9')));
      // … the default included: a no-op fork has nothing to add.
      expect(
          () => ing.update('marine', const [
              '#ccdbdc', '#9ad1d4', '#80ced7', '#007ea7', '#003249']),
          throwsA(isA<PaletteConflictError>()
              .having((e) => e.conflictsWith, 'conflictsWith', 'marine')));
    });

    test('an in-place edit duplicating another palette refuses, naming it', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      expect(
          () => ing.update('c-6f58c9', const [
              '#ccdbdc', '#9ad1d4', '#80ced7', '#007ea7', '#003249']),
          throwsA(isA<PaletteConflictError>()
              .having((e) => e.conflictsWith, 'conflictsWith', 'marine')));
      // The entry itself is excluded from the compare — a same-swatch save
      // re-derives without a conflict.
      final r = ing.update('c-6f58c9',
          const ['#bdede0', '#bbdbd1', '#b6b8d6', '#7e78d2', '#6f58c9']);
      expect(r.entry.id, 'c-6f58c9');
    });

    test('bounds, hex validity, and the no-such refusal', () {
      final ing = PaletteIngestion(artifactDir: dir.path);
      expect(() => ing.update('c-6f58c9', const ['#111111', '#222222']),
          throwsArgumentError);
      expect(
          () => ing.update('c-6f58c9', const [
              '#111111', '#222222', '#333333', '#444444',
              '#555555', '#666666', '#777777', '#888888']),
          throwsArgumentError);
      expect(
          () =>
              ing.update('c-6f58c9', const ['#zz0000', '#111111', '#222222']),
          throwsArgumentError);
      expect(
          () =>
              ing.update('nope', const ['#111111', '#222222', '#333333']),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message, 'message', 'no such palette: nope')));
    });

    test('app-layout: tokens blocks land in assets/css/tokens.css', () {
      final app = Directory.systemTemp.createTempSync('arxa-palette-app-test');
      addTearDown(() => app.deleteSync(recursive: true));
      File('${app.path}/palettes.json')
          .writeAsStringSync(File('${dir.path}/palettes.json').readAsStringSync());
      File('${app.path}/assets/styles/palettes/_template.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
            File('${dir.path}/assets/styles/palettes/_template.json')
                .readAsStringSync());
      // No ui/styles tree at all — the app layout (hello-hda).
      final r = PaletteIngestion(artifactDir: app.path)
          .update('marine', forkHexes);
      expect(r.forked, isTrue);
      final tokens = File('${app.path}/assets/css/tokens.css');
      expect(tokens.existsSync(), isTrue,
          reason: 'created on demand by the render path');
      expect(tokens.readAsStringSync(), contains('[data-palette="c-2e1f27"]'));
      expect(File('${app.path}/ui/styles/common/tokens.css').existsSync(),
          isFalse);
    });
  });
}
