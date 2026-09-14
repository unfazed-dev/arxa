// Route tests for POST /__dial/palettes/update (the universal palette
// plane, grilled Q4): in-dial editing — in-place re-derive for non-default
// palettes, FORK into the one custom slot when the default is edited, 409
// naming the conflicting palette, 400 on bad shape/count/hex and unknown
// ids, 503 with no artifact dir, 403 for guests. Derivation correctness
// lives in design_palettes_test.dart; this file pins the route shapes.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/arxa_dial.dart';
import 'package:arxa/design_palettes.dart';
import 'package:test/test.dart';

void main() {
  group('POST /__dial/palettes/update', () {
    late Directory dir;
    late DialApi api;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('arxa-dial-update-test');
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
            '{"name":"--accent","base":"#007ea7","family":"accent","form":"hex"}],'
            '"rules":[{"at":[],'
            '"sel":"[data-palette=\\"{id}\\"] .thing",'
            '"tpl":"background: {0};",'
            '"slots":[{"base":"#80ced7","family":"field","form":"hex"}]}]}');
      File('${dir.path}/ui/styles/common/tokens.css')
        ..createSync(recursive: true)
        ..writeAsStringSync(':root {\n  --accent: #007ea7;\n}\n');
      api = DialApi(
          store: MemoryDialStore(), artifact: 'demo', artifactDir: dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    const forkBody = <String, Object>{
      'id': 'marine',
      'hexes': ['#2e1f27', '#854d27', '#dd7230', '#f4c95d', '#e7e393'],
    };

    test('200 — editing the default FORKS (palette, palettes, forked)',
        () async {
      final r =
          await api.handle('POST', '/palettes/update', {}, forkBody, null);
      expect(r.status, 200, reason: jsonEncode(r.json));
      final j = (r.json as Map).cast<String, dynamic>();
      expect(j['forked'], isTrue);
      final palette = (j['palette'] as Map).cast<String, dynamic>();
      expect(palette['id'], 'c-2e1f27');
      expect(palette['name'], 'Custom 2E1F27');
      expect(palette['source'], 'dial-edit:fork-of-marine');
      expect(palette['themeColor'], '#854d27');
      expect((j['palettes'] as List).length, 3,
          reason: 'the island resyncs from the full list, never blind-push');
      expect(PaletteManifest.load(dir.path)!.declares('c-2e1f27'), isTrue);
    });

    test('200 — a non-default palette edits IN PLACE', () async {
      final r = await api.handle('POST', '/palettes/update', {}, {
        'id': 'c-6f58c9',
        'hexes': ['#0f2027', '#203a43', '#2c5364'],
        'name': 'Renamed Iris',
      }, null);
      expect(r.status, 200, reason: jsonEncode(r.json));
      final j = (r.json as Map).cast<String, dynamic>();
      expect(j['forked'], isFalse);
      final palette = (j['palette'] as Map).cast<String, dynamic>();
      expect(palette['id'], 'c-6f58c9', reason: 'the id is stable');
      expect(palette['name'], 'Renamed Iris');
      expect(palette['seeded'], isTrue, reason: 'seeded untouched');
      expect(palette['themeColor'], '#203a43');
    });

    test('400 — bad shape, bad count, bad hex, unknown id', () async {
      for (final body in <Map<String, Object>>[
        {'hexes': const ['#111111', '#222222', '#333333']},
        {'id': 'marine', 'hexes': 'nope'},
        {'id': 'marine', 'hexes': const ['#111111', '#222222']},
        {
          'id': 'marine',
          'hexes': const [
            '#111111', '#222222', '#333333', '#444444',
            '#555555', '#666666', '#777777', '#888888',
          ],
        },
        {
          'id': 'marine',
          'hexes': const ['#zz0000', '#111111', '#222222'],
        },
        {
          'id': 'marine',
          'hexes': const ['#111111', '#222222', '#333333'],
          'name': 7,
        },
        {
          'id': 'nope',
          'hexes': const ['#111111', '#222222', '#333333'],
        },
      ]) {
        final r = await api.handle('POST', '/palettes/update', {}, body, null);
        expect(r.status, 400,
            reason: '${jsonEncode(body)} -> ${jsonEncode(r.json)}');
      }
    });

    test('409 — a duplicate swatch set names the conflicting palette',
        () async {
      final r = await api.handle('POST', '/palettes/update', {}, {
        'id': 'marine',
        'hexes': ['#bdede0', '#bbdbd1', '#b6b8d6', '#7e78d2', '#6f58c9'],
      }, null);
      expect(r.status, 409, reason: jsonEncode(r.json));
      final j = (r.json as Map).cast<String, dynamic>();
      expect(j['conflictsWith'], 'c-6f58c9');
      expect('${j['error']}', contains('c-6f58c9'));
    });

    test('503 — no artifact dir (the same refusal as ingest)', () async {
      final bare = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final r =
          await bare.handle('POST', '/palettes/update', {}, forkBody, null);
      expect(r.status, 503);
      expect((r.json as Map)['error'], 'palettes unavailable');
    });

    test('403 — guests never edit (author-only like its siblings)', () async {
      final token =
          await api.store.mintShareLink('demo', const Duration(days: 1));
      final grant = await api.store.resolveShareLink(token);
      final r = await api.handle(
          'POST', '/palettes/update', {'dial': token}, forkBody, grant);
      expect(r.status, 403);
      expect((r.json as Map)['error'], 'author only');
    });
  });
}
