// Dial palette-EDITOR E2E (operator, 2026-09-10, the universal-plane pilot):
// drives the real edit affordance in the shadow DOM — open the editor on a
// seeded card, hex-edit + save (in-place re-derive), edit the default card
// (fork banner + fork into the one custom slot with local preview), the
// duplicate-swatch refusal naming the conflict, and the add/remove stripe
// bounds (3..7). Snapshots the artifact's palette files and restores them
// byte-identical at the end; publishing stays untouched (the fork preview
// is local — a reload resets it). Usage:
//   dart run tool/lens_palette_edit_ui.dart <base-url> <artifact-dir>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_palette_edit_ui.dart <base-url> <artifact-dir>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  final dir = argv[1];
  var failures = 0;
  void check(bool ok, String label) {
    stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
    if (!ok) failures++;
  }

  // manifest-driven: the default card's name and the tokens-file layout
  // come from the artifact, not from arxa-site's shape.
  final manifest = (jsonDecode(File(dir + '/palettes.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final defaultName = ((manifest['palettes'] as List)
      .firstWhere((p) => (p as Map)['id'] == manifest['default']) as Map)['name'] as String;
  // hygiene: snapshot the palette files the route may mutate
  final tokensPath = File(dir + '/ui/styles/common/tokens.css').existsSync()
      ? dir + '/ui/styles/common/tokens.css'
      : dir + '/assets/css/tokens.css';
  final snapshot = <String, String>{
    dir + '/palettes.json': File(dir + '/palettes.json').readAsStringSync(),
    tokensPath: File(tokensPath).readAsStringSync(),
  };
  final sheetDir = Directory(dir + '/assets/styles/palettes');
  for (final f in sheetDir.listSync().whereType<File>()) {
    snapshot[f.path] = f.readAsStringSync();
  }
  void restore() {
    for (final e in snapshot.entries) { File(e.key).writeAsStringSync(e.value); }
    for (final f in sheetDir.listSync().whereType<File>()) {
      if (!snapshot.containsKey(f.path)) f.deleteSync();
    }
  }

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(base, settleMs: 3500);
    Future<dynamic> ev(String js) => tab.evaluate(js);
    const sr = "document.querySelector('#arxa-dial-host').shadowRoot";

    // open the tray to the Theme slide
    await ev("(() => { const r = " + sr + "; r.querySelector('#dockbtn').click(); "
        "const v = [...r.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent)); "
        "v[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 900));

    // 1. every card carries the edit affordance (author mode)
    final affordances = await ev("(() => [... " + sr + ".querySelectorAll('.palcard')]"
        ".map(c => ({ name: c.querySelector('.palname').textContent, "
        "edit: !!c.querySelector('.paledbtn') })))()") as List;
    stdout.writeln('cards: ' + affordances.toString());
    check(affordances.isNotEmpty && affordances.every((c) => (c as Map)['edit'] == true),
        'every palette card carries the edit affordance');

    // 2. open the editor on a seeded non-default card (Lavender Iris)
    await ev("(() => { const r = " + sr + "; const c = [...r.querySelectorAll('.palcard')]"
        ".find(x => x.querySelector('.palname').textContent.includes('Lavender')); "
        "c.querySelector('.paledbtn').click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 500));
    var state = await ev("(() => { const r = " + sr + "; const p = r.querySelector('.paledit'); "
        "if (!p) return { open: false }; "
        "return { open: true, rows: p.querySelectorAll('.edrow').length, "
        "banner: !!p.querySelector('.edbanner'), "
        "name: (p.querySelector('.edname') || {}).value }; })()") as Map;
    check(state['open'] == true, 'editor panel opens on a seeded card');
    check(state['rows'] == 5, 'five swatch rows for a 5-color palette (got ' + state['rows'].toString() + ')');
    check(state['banner'] != true, 'no fork banner on a non-default palette');

    // 3. hex-edit one row and save — in-place re-derive
    await ev("(() => { const r = " + sr + "; const row = r.querySelectorAll('.paledit .edrow')[1]; "
        "const hex = row.querySelector('input[type=text], input:not([type=color])'); "
        "hex.value = '#9f8fdd'; hex.dispatchEvent(new Event('input', { bubbles: true })); "
        "const btns = [...r.querySelectorAll('.paledit button')].filter(b => /save/i.test(b.textContent)); "
        "btns[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    state = await ev("(() => { const r = " + sr + "; return { "
        "err: (r.querySelector('.paledit .ederr') || { textContent: '' }).textContent.trim(), "
        "open: !!r.querySelector('.paledit') }; })()") as Map;
    check(state['err'] == '', 'in-place save shows no error (got: ' + state['err'].toString() + ')');
    check(state['open'] != true, 'editor closes after a successful save');

    // 4. edit the DEFAULT card — fork banner + fork into the custom slot
    await ev("(() => { const r = " + sr + "; const c = [...r.querySelectorAll('.palcard')]"
        ".find(x => x.querySelector('.palname').textContent.includes('" + defaultName + "'));"
        "c.querySelector('.paledbtn').click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 500));
    state = await ev("(() => { const r = " + sr + "; const p = r.querySelector('.paledit'); "
        "return { banner: p != null && !!p.querySelector('.edbanner'), "
        "bannerText: p == null || p.querySelector('.edbanner') == null ? '' : p.querySelector('.edbanner').textContent }; })()") as Map;
    check(state['banner'] == true, 'fork banner rides the default palette editor');
    stdout.writeln('banner: ' + state['bannerText'].toString());
    await ev("(() => { const r = " + sr + "; const row = r.querySelectorAll('.paledit .edrow')[0]; "
        "const hex = row.querySelector('input[type=text], input:not([type=color])'); "
        "hex.value = '#0f3057'; hex.dispatchEvent(new Event('input', { bubbles: true })); "
        "const btns = [...r.querySelectorAll('.paledit button')].filter(b => /save/i.test(b.textContent)); "
        "btns[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    state = await ev("(() => { const r = " + sr + "; return { "
        "cards: r.querySelectorAll('.palcard').length, "
        "custom: [...r.querySelectorAll('.palcard')].some(c => [...c.querySelectorAll('.palchip')]"
        ".some(x => /Custom/.test(x.textContent) && getComputedStyle(x).display !== 'none')) }; })()") as Map;
    check(state['cards'] == 6, 'fork lands the one custom slot (5 seeded + 1 custom, got ' + state['cards'].toString() + ')');
    check(state['custom'] == true, 'the forked palette carries the Custom chip');

    // 5. duplicate swatch refusal names the conflict inline
    await ev("(() => { const r = " + sr + "; const c = [...r.querySelectorAll('.palcard')]"
        ".find(x => x.querySelector('.palname').textContent.includes('Orchid')); "
        "c.querySelector('.paledbtn').click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await ev("(() => { const r = " + sr + "; const c = [...r.querySelectorAll('.palcard')]"
        ".find(x => [...x.querySelectorAll('.palchip')].some(y => /Custom/.test(y.textContent) && getComputedStyle(y).display !== 'none')); "
        "const hexes = [...c.querySelectorAll('.palstripe i')].map(s => s.textContent.trim()); "
        "const rows = [...r.querySelectorAll('.paledit .edrow')]; "
        "rows.forEach((row, i) => { const hex = row.querySelector('input[type=text], input:not([type=color])'); "
        "if (hexes[i]) { hex.value = hexes[i]; hex.dispatchEvent(new Event('input', { bubbles: true })); } }); "
        "const btns = [...r.querySelectorAll('.paledit button')].filter(b => /save/i.test(b.textContent)); "
        "btns[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    state = await ev("(() => { const r = " + sr + "; const e = r.querySelector('.paledit .ederr'); "
        "return { err: e == null ? '' : e.textContent.trim(), open: !!r.querySelector('.paledit') }; })()") as Map;
    check(state['open'] == true && state['err'] != '',
        'duplicate swatch keeps the editor open with an inline conflict (got: ' + state['err'].toString() + ')');
    stdout.writeln('conflict message: ' + state['err'].toString());
    // cancel out of the erroring editor
    await ev("(() => { const r = " + sr + "; const btns = [...r.querySelectorAll('.paledit button')]"
        ".filter(b => /cancel/i.test(b.textContent)); if (btns.length) btns[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // 6. add/remove stripe bounds (3..7)
    await ev("(() => { const r = " + sr + "; const c = [...r.querySelectorAll('.palcard')]"
        ".find(x => x.querySelector('.palname').textContent.includes('Sunset')); "
        "c.querySelector('.paledbtn').click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // The slide re-renders on every add/remove (renderTraySlide) — every
    // read and every click must re-query the live DOM, never hold a node.
    Future<int> rowCount() async => (await ev(
        "(() => { const p = " + sr + ".querySelector('.paledit'); "
        "return p ? p.querySelectorAll('.edrow').length : -1; })()")) as int;
    Future<bool> addDisabled() async => (await ev(
        "(() => { const p = " + sr + ".querySelector('.paledit'); "
        "const a = [...p.querySelectorAll('button')].find(b => b.classList.contains('edadd')); "
        "return a.disabled; })()")) as bool;
    Future<bool> remsDisabled() async => (await ev(
        "(() => { const p = " + sr + ".querySelector('.paledit'); "
        "return [...p.querySelectorAll('.edrow .edrem')].every(x => x.disabled); })()")) as bool;
    Future<void> clickAdd() async { await ev(
        "(() => { const p = " + sr + ".querySelector('.paledit'); "
        "[...p.querySelectorAll('button')].find(b => b.classList.contains('edadd')).click(); return 1; })()");
        await Future<void>.delayed(const Duration(milliseconds: 250)); }
    Future<void> clickRem() async { await ev(
        "(() => { const p = " + sr + ".querySelector('.paledit'); "
        "const rs = [...p.querySelectorAll('.edrow .edrem')]; rs[rs.length - 1].click(); return 1; })()");
        await Future<void>.delayed(const Duration(milliseconds: 250)); }
    final steps = <int>[];
    for (var i = 0; i < 4; i++) { await clickAdd(); steps.add(await rowCount()); }
    final capDisabled = await addDisabled();
    for (var i = 0; i < 4; i++) { await clickRem(); }
    final floored = await rowCount();
    final floorDisabled = await remsDisabled();
    stdout.writeln('bounds: steps=' + steps.toString() + ' floored=' + floored.toString()
        + ' capDisabled=' + capDisabled.toString() + ' floorDisabled=' + floorDisabled.toString());
    check(steps.isNotEmpty && steps.last == 7 && capDisabled,
        'add caps at 7 rows (steps ' + steps.toString() + ', disabled=' + capDisabled.toString() + ')');
    check(floored == 3 && floorDisabled,
        'remove floors at 3 rows (got ' + floored.toString() + ', disabled=' + floorDisabled.toString() + ')');

    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    check(errs.isEmpty, 'zero console/page errors through the editor flows');
    for (final e in errs) { stdout.writeln('  err: ' + e); }
  } finally {
    await client.close();
    restore();
    var clean = true;
    for (final e in snapshot.entries) {
      if (File(e.key).readAsStringSync() != e.value) { clean = false; stdout.writeln('RESTORE-MISS ' + e.key); }
    }
    check(clean, 'artifact tree restored byte-identical');
  }
  if (failures > 0) exit(1);
  stdout.writeln('lens palette-edit-ui: ALL PASS');
}
