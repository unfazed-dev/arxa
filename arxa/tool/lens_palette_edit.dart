// Palette-edit route E2E (operator, 2026-09-10, the universal-plane pilot):
// drives POST /__dial/palettes/update against a running design server and
// asserts the Q4/Q5 law — in-place edit with atomic re-derive, default-edit
// FORK into the one custom slot, duplicate-swatch refusal naming the
// conflict, and the 3..7 variable-width declaration law. Snapshots every
// file it may mutate and restores them byte-identical at the end; never
// touches the published pick. Usage:
//   dart run tool/lens_palette_edit.dart <base-url> <artifact-dir>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:arxa/design_palettes.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_palette_edit.dart <base-url> <artifact-dir>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  final dir = argv[1];
  // manifest-driven: the default id and the tokens-file layout come from
  // the artifact, not from arxa-site's shape (the two-layout law).
  final manifest = (jsonDecode(File(dir + '/palettes.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final defaultId = manifest['default'] as String;
  var failures = 0;
  void check(bool ok, String label) {
    stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
    if (!ok) failures++;
  }

  final http = HttpClient();
  Future<(int, Map<String, dynamic>)> post(String sub, Map<String, dynamic> body) async {
    final req = await http.postUrl(Uri.parse(base + sub));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final text = await utf8.decoder.bind(res).join();
    Map<String, dynamic> json = {};
    try { json = (jsonDecode(text) as Map).cast<String, dynamic>(); } catch (_) {}
    return (res.statusCode, json);
  }
  Future<String> get(String path) async {
    final req = await http.getUrl(Uri.parse(base + path));
    final res = await req.close().timeout(const Duration(seconds: 15));
    return utf8.decoder.bind(res).join();
  }

  // hygiene: snapshot every file the route may mutate
  final manifestFile = File(dir + '/palettes.json');
  var tokensFile = File(dir + '/ui/styles/common/tokens.css');
  if (!tokensFile.existsSync()) tokensFile = File(dir + '/assets/css/tokens.css');
  final sheetDir = Directory(dir + '/assets/styles/palettes');
  final snapshot = <String, String>{};
  snapshot[manifestFile.path] = manifestFile.readAsStringSync();
  snapshot[tokensFile.path] = tokensFile.readAsStringSync();
  for (final f in sheetDir.listSync().whereType<File>()) {
    snapshot[f.path] = f.readAsStringSync();
  }
  void restore() {
    for (final e in snapshot.entries) { File(e.key).writeAsStringSync(e.value); }
    for (final f in sheetDir.listSync().whereType<File>()) {
      if (!snapshot.containsKey(f.path)) f.deleteSync();
    }
  }

  const lavender = ['#6f58c9', '#9f8fdd', '#c9bff0', '#e6e0fa', '#3d2a86'];
  const forkSet = ['#0f3057', '#00587a', '#008891', '#a7d7c5', '#f6f6f6'];
  const three = ['#1d3557', '#e63946', '#f1faee'];
  const seven = ['#03071e', '#370617', '#6a040f', '#9d0208', '#dc2f02', '#e85d04', '#ffba08'];

  try {
    // 1. in-place edit of a seeded non-default palette
    var r = await post('/__dial/palettes/update', {'id': 'c-6f58c9', 'hexes': lavender});
    check(r.$1 == 200, 'update seeded non-default: 200 (got ' + r.$1.toString() + ')');
    var entry = (r.$2['palette'] as Map?)?.cast<String, dynamic>();
    check(entry != null && entry['id'] == 'c-6f58c9', 'in-place edit keeps the stable id');
    check(entry != null && (entry['swatch'] as List).length == 5, 'swatch carries the five new hexes');
    final anchors = anchorsFor(lavender);
    check(entry != null && entry['themeColor'] == anchors['accent'],
        'themeColor re-derived to the new accent ' + anchors['accent'].toString());
    final tokensCss = tokensFile.readAsStringSync().toLowerCase();
    check(tokensCss.contains(anchors['field']!.substring(1)),
        'tokens.css carries the re-derived field ' + anchors['field'].toString());
    check(tokensFile.readAsStringSync().contains('[data-palette="c-6f58c9"]'),
        'tokens.css block intact after edit');
    final html = await get('/?palette=c-6f58c9');
    check(html.contains('data-palette="c-6f58c9"'), 'serve-time attribute stamps the edited palette');

    // 2. editing the default FORKS into the one custom slot
    r = await post('/__dial/palettes/update', {'id': defaultId, 'hexes': forkSet});
    check(r.$1 == 200, 'default edit: 200 (got ' + r.$1.toString() + ')');
    check(r.$2['forked'] == true, 'default edit reports forked: true');
    entry = (r.$2['palette'] as Map?)?.cast<String, dynamic>();
    check(entry != null && entry['id'] != defaultId, 'fork lands a fresh id, never the default');
    final palettes = (r.$2['palettes'] as List).length;
    check(palettes == 6, 'still exactly 5 seeded + 1 custom after fork (got ' + palettes.toString() + ')');
    check((r.$2['palettes'] as List).whereType<Map>().where((p) => p['seeded'] != true).length == 1,
        'exactly one custom slot survives the sweep');

    // 3. duplicate swatch refuses, naming the conflict
    r = await post('/__dial/palettes/update', {'id': 'c-8e518d', 'hexes': forkSet});
    check(r.$1 == 409, 'duplicate swatch: 409 (got ' + r.$1.toString() + ')');
    check((r.$2['conflictsWith'] ?? '').toString().isNotEmpty,
        'refusal names the conflicting palette: ' + (r.$2['conflictsWith'] ?? r.$2['error']).toString());

    // 4. variable width: N=3 interpolates, N=7 decimates, N=2/N=8 refuse
    r = await post('/__dial/palettes/update', {'id': 'c-2e1f27', 'hexes': three});
    check(r.$1 == 200, 'N=3 accepted (got ' + r.$1.toString() + ')');
    entry = (r.$2['palette'] as Map?)?.cast<String, dynamic>();
    check(entry != null && (entry['swatch'] as List).length == 3, 'N=3 swatch stays three-wide');
    check(tokensFile.readAsStringSync().contains('[data-palette="c-2e1f27"]'),
        'N=3 tokens block written (interpolated roles inside)');

    r = await post('/__dial/palettes/update', {'id': 'c-2e1f27', 'hexes': seven});
    check(r.$1 == 200, 'N=7 accepted (got ' + r.$1.toString() + ')');
    entry = (r.$2['palette'] as Map?)?.cast<String, dynamic>();
    check(entry != null && (entry['swatch'] as List).length == 7, 'N=7 swatch stays seven-wide');

    r = await post('/__dial/palettes/update', {'id': 'c-2e1f27', 'hexes': three.sublist(0, 2)});
    check(r.$1 == 400, 'N=2 refuses: 400 (got ' + r.$1.toString() + ')');
    r = await post('/__dial/palettes/update', {'id': 'c-2e1f27', 'hexes': [...seven, '#ffffff']});
    check(r.$1 == 400, 'N=8 refuses: 400 (got ' + r.$1.toString() + ')');

    // 5. live repaint + console cleanliness through the lens
    final client = await CdpClient.launch();
    try {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(1280, 832);
      await tab.navigateAndSettle(base + '/?palette=c-6f58c9', settleMs: 3000);
      final accent = await tab.evaluate(
          "getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()");
      stdout.writeln('live --accent under edited c-6f58c9: ' + accent.toString());
      final rgb = anchors['accent']!.substring(1);
      final rr = int.parse(rgb.substring(0, 2), radix: 16);
      final gg = int.parse(rgb.substring(2, 4), radix: 16);
      final bb = int.parse(rgb.substring(4, 6), radix: 16);
      final want = 'rgb(' + rr.toString() + ', ' + gg.toString() + ', ' + bb.toString() + ')';
      final wantHex = anchors['accent']!.toLowerCase();
      check(accent.toString() == want || accent.toString().toLowerCase() == wantHex,
          'live --accent token repaints to ' + want + ' (got ' + accent.toString() + ')');
      final errs = [...tab.consoleErrors, ...tab.pageErrors];
      check(errs.isEmpty, 'zero console/page errors under the edited palette');
      for (final e in errs) { stdout.writeln('  err: ' + e); }
    } finally {
      await client.close();
    }
  } finally {
    restore();
    var clean = true;
    for (final e in snapshot.entries) {
      if (File(e.key).readAsStringSync() != e.value) { clean = false; stdout.writeln('RESTORE-MISS ' + e.key); }
    }
    check(clean, 'artifact tree restored byte-identical');
    http.close();
  }
  if (failures > 0) exit(1);
  stdout.writeln('lens palette-edit: ALL PASS');
}
