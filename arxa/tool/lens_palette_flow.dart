// Dial palette-flow E2E (operator, 2026-09-09): verifies the two fixes —
// the native cursor over the open tray (custom-cursor stacking bug) and the
// one-custom-slot replace flow through the REAL dial UI (paste A, paste B
// replaces A, x deletes, seeded five remain). Restores the published pick
// at the end. Usage: dart run tool/lens_palette_flow.dart <url> <restoreId>
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_palette_flow.dart <url> <restorePaletteId>');
    exit(2);
  }
  final url = argv[0];
  final restoreId = argv[1];
  final client = await CdpClient.launch();
  var failures = 0;
  void check(bool ok, String label) {
    stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
    if (!ok) failures++;
  }

  Future<dynamic> ev(dynamic tab, String js) => tab.evaluate(js);

  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(url, settleMs: 3500);
    const sr = "document.querySelector('#arxa-dial-host').shadowRoot";
    // open the tray
    await ev(tab, "(() => { const r = $sr; r.querySelector('#dockbtn').click(); "
        "const v = [...r.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent)); "
        "v[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 900));

    // ── fix 1: cursor over the tray chrome ─────────────────────────────
    final cursors = await ev(tab,
        "(() => { const r = $sr; const cs = (sel) => getComputedStyle(r.querySelector(sel)).cursor; "
        "return { title: cs('#ttitle'), slide: cs('.slide'), card: cs('.palcard'), "
        "stripe: cs('.palstripe'), close: cs('#tclose') }; })()") as Map;
    stdout.writeln('cursors: ' + cursors.toString());
    check(cursors['title'] == 'auto', 'tray chrome cursor is native (auto), was ' + cursors['title'].toString());
    check(cursors['slide'] == 'auto', 'slide body cursor is native (auto), was ' + cursors['slide'].toString());
    check(cursors['card'] == 'pointer', 'palette card keeps pointer, got ' + cursors['card'].toString());
    check(cursors['stripe'] == 'copy', 'stripe keeps copy, got ' + cursors['stripe'].toString());

    // ── fix 2: replace flow through the real input ─────────────────────
    Future<List<dynamic>> cardNames() async => (await ev(tab,
        "(() => [...$sr.querySelectorAll('.palcard')].map(c => { "
        "const n = c.querySelector('.palname').textContent; "
        "const chips = [...c.querySelectorAll('.palchip')].filter(x => getComputedStyle(x).display !== 'none').map(x => x.textContent); "
        "return n + (chips.length ? ' [' + chips.join(',') + ']' : ''); }))()")) as List;
    Future<void> paste(String link) async {
      await ev(tab,
          "(() => { const r = $sr; const i = r.querySelector('.facet input'); "
          "i.value = '" + link + "'; "
          "i.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); return 1; })()");
      await Future<void>.delayed(const Duration(milliseconds: 1600));
    }

    await paste('https://coolors.co/606c38-283618-fefae0-dda15e-bc6c25');
    var names = await cardNames();
    stdout.writeln('after paste A: ' + names.toString());
    check(names.length == 6, 'six cards after first paste (5 seeded + 1 custom)');
    check(names.any((n) => n.contains('283618') && n.contains('Custom')),
        'custom card shows the Custom chip');

    await paste('https://coolors.co/ef476f-ffd166-06d6a0-118ab2-073b4c');
    names = await cardNames();
    stdout.writeln('after paste B: ' + names.toString());
    check(names.length == 6, 'STILL six cards after second paste (replace, not accumulate)');
    check(!names.any((n) => n.contains('283618')), 'previous custom card is gone');
    check(names.any((n) => n.contains('073B4C') && n.contains('Custom')),
        'new custom took the slot');

    // delete the custom via its x — normal operations resume
    await ev(tab,
        "(() => { const r = $sr; const d = r.querySelector('.paldel'); "
        "if (!d) return 'no-del'; d.click(); return 'ok'; })()");
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    names = await cardNames();
    stdout.writeln('after delete: ' + names.toString());
    check(names.length == 5, 'back to the five seeded after delete');

    // restore the operator's published pick
    await ev(tab,
        "(() => { const r = $sr; const cards = [...r.querySelectorAll('.palcard')]; "
        "const c = cards.find(x => x.querySelector('.palname').textContent.includes('Forest')); "
        "if (c) c.click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final active = await ev(tab, "document.documentElement.getAttribute('data-palette')");
    check(active == restoreId, 'published pick restored to ' + restoreId + ' (active=' + active.toString() + ')');

    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    check(errs.isEmpty, 'zero console/page errors');
    for (final e in errs) { stdout.writeln('  err: ' + e); }
  } finally {
    await client.close();
  }
  if (failures > 0) exit(1);
  stdout.writeln('lens palette-flow: ALL PASS');
}
