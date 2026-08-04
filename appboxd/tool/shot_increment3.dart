// Throwaway verification driver for Increment 3 (edit arming + resize handles).
// Drives the REAL UI in Chrome — clicks the arm chip and a card the way a user
// would — rather than poking the HTTP endpoints, so the screenshots are
// evidence that the interaction works, not just that the routes respond.
import 'dart:convert';
import 'dart:io';
import 'package:appboxd/cdp.dart';

const base = 'http://127.0.0.1:8899';
final outDir = Directory('/tmp/inc3-shots')..createSync(recursive: true);

Future<void> shot(CdpSession s, String name) async {
  final png = await s.screenshot();
  final f = File('${outDir.path}/$name.png')..writeAsBytesSync(png);
  print('  shot: ${f.path} (${png.length} bytes)');
}

void check(String label, bool ok) =>
    print('${ok ? "PASS" : "FAIL"}  $label');

/// JSON-quote a value for embedding in a page expression.
String _js(Object? v) => jsonEncode(v);

Future<void> main() async {
  final client = await CdpClient.launch();
  final page = await client.newTab();
  await page.enable();
  await page.setViewport(1600, 1000);

  await page.navigateAndSettle('$base/design', settleMs: 2500);
  print('loaded /design');

  // --- baseline: nothing armed ---
  final armed0 = await page.evaluate(
      "!!document.querySelector('[data-wedit-armed=\"1\"]')");
  check('baseline is DISARMED', armed0 == false);
  await shot(page, '1-baseline');

  // --- click the arm chip the way a user does ---
  final chip = await page.evaluate("""
    (() => {
      const b = document.querySelector('.dv-arm-chip');
      if (!b) return null;
      const r = b.getBoundingClientRect();
      return {x: Math.round(r.left + r.width/2), y: Math.round(r.top + r.height/2)};
    })()
  """);
  if (chip == null) {
    print('FAIL  arm chip not found in DOM');
    await client.close();
    exit(1);
  }
  await page.click(chip['x'] as int, chip['y'] as int);
  final armedOk = await page.waitForFunction(
      "!!document.querySelector('[data-wedit-armed=\"1\"]')");
  check('clicking the chip ARMS the canvas', armedOk);
  // The arm response morphs the viewer. Measuring click coords mid-morph
  // yields rects that are stale by the time the click dispatches, so the
  // click silently lands on nothing — let the swap settle first.
  await Future.delayed(const Duration(milliseconds: 1200));
  await shot(page, '2-armed');

  // Stamp the live frame so "preserved" means THIS iframe survived. drag.js's
  // _cw/_cz guards are set once and never cleared, so they read true even for
  // a freshly swapped-in frame — they cannot evidence preservation.
  await page.evaluate("""
    (() => {
      const f = document.querySelector('iframe[data-screen="portalo.home"]');
      f.contentWindow.__stamp = 'inc3-' + Math.random();
      window.__stamp = f.contentWindow.__stamp;
    })()
  """);

  // --- click a real widget inside a tile iframe ---
  // Tiles are CSS-scaled, so content coords must be scaled into viewport space.
  final target = await page.evaluate("""
    (() => {
      const f = document.querySelector('iframe[data-screen="portalo.home"]');
      if (!f) return {err: 'no home iframe'};
      // The canvas is a long scrollable surface: without this the tile sits
      // thousands of px below the fold and the synthetic click lands on
      // nothing (which looks exactly like a broken handler).
      f.scrollIntoView({block: 'center', inline: 'center'});
      const fr = f.getBoundingClientRect();
      const d = f.contentDocument;
      if (!d) return {err: 'no contentDocument'};
      // [data-el] is the selection identity canvas.js keys on — clicking
      // anything else is correctly a no-op, so the test must click one.
      const el = d.querySelector('[data-el]');
      if (!el) return {err: 'no [data-el] widget inside frame'};
      const scale = fr.width / d.documentElement.clientWidth;
      const er = el.getBoundingClientRect();
      return {
        x: Math.round(fr.left + (er.left + er.width/2) * scale),
        y: Math.round(fr.top  + (er.top  + er.height/2) * scale),
        tag: el.tagName + '[' + el.getAttribute('data-el') + ']'
      };
    })()
  """);
  if (target is Map && target['err'] != null) {
    print('FAIL  ${target['err']}');
    await client.close();
    exit(1);
  }
  final tx = target['x'] as int, ty = target['y'] as int;
  print('  clicking widget: ${target['tag']} at $tx,$ty');
  if (tx < 0 || ty < 0 || tx > 1600 || ty > 1000) {
    print('FAIL  target is outside the viewport — harness bug, not app bug');
    await client.close();
    exit(1);
  }
  await page.click(tx, ty);

  final selOk = await page.waitForFunction(
      "!!document.querySelector('[data-wedit-sel]')");
  check('clicking a widget SELECTS it (server-side)', selOk);

  // Handles are hung by drag.js off the server-derived selection.
  // drag.js names these `.dv-wedit-handles` (the box) and `.dv-wh` (the grips).
  final handles = await page.evaluate(
      "document.querySelectorAll('.dv-wedit-handles .dv-wh').length");
  check('resize handles are hung on the selection (found $handles)',
      (handles as int) > 0);

  // The sizing-mode chips must render for the selected widget.
  final chips = await page.evaluate("""
    Array.from(document.querySelectorAll('.dv-wedit-mode'))
         .map(e => e.textContent.trim()).join(',')
  """);
  print('  sizing-mode chips: $chips');
  final c = '$chips'.toLowerCase(); // labels are title-cased ("Hug")
  check('hug/fill/fixed chips render',
      c.contains('hug') && c.contains('fill') && c.contains('fixed'));

  // Tiles must survive the selection morph — a swap that reloaded every
  // iframe would be a regression even with handles working.
  final preserved = await page.evaluate("""
    (() => {
      const f = document.querySelector('iframe[data-screen="portalo.home"]');
      return !!(f && f.contentWindow && f.contentWindow.__stamp === window.__stamp);
    })()
  """);
  check('tiles preserved across the selection morph (same frame, not reloaded)',
      preserved == true);

  await shot(page, '3-armed-selected-handles');

  // --- second entry point: the explode row. It posts the same route with a
  // DIFFERENT name argument (label(name), not the raw data-el suffix), and
  // now that select returns a full stageContext a mismatch would fail
  // silently — a viewer with no editor bound rather than an error.
  final selBefore = await page.evaluate(
      "document.querySelector('[data-wedit-sel]').getAttribute('data-wedit-sel')");
  // Dispatched on the element, not by coordinate: explode.js binds its own
  // click listener, so this exercises the real wire while staying immune to
  // the mid-morph rect race that already bit the canvas phase once.
  final row = await page.evaluate("""
    (() => {
      window.__posted = null;
      document.body.addEventListener('htmx:beforeRequest', (e) => {
        window.__posted = e.detail.pathInfo?.requestPath || '?';
      }, {once: true});
      const rows = Array.from(document.querySelectorAll('.dv-explode-el'));
      if (!rows.length) return {err: 'no explode rows rendered'};
      const r = rows.find(x => !/Ceramics/.test(x.textContent)) || rows[0];
      const panel = r.closest('.dv-explode');
      r.click();
      return {label: r.textContent.trim().slice(0, 24),
              explodeFor: panel ? panel.dataset.explodeFor : null};
    })()
  """);
  if (row is Map && row['err'] != null) {
    print('FAIL  ${row['err']}');
  } else {
    print('  clicked explode row: ${row['label']} (panel: ${row['explodeFor']})');
    final changed = await page.waitForFunction(
        "document.querySelector('[data-wedit-sel]') && "
        "document.querySelector('[data-wedit-sel]').getAttribute('data-wedit-sel') !== ${_js(selBefore)}");
    print('  row posted to: ${await page.evaluate("window.__posted")}');
    check('explode row click RE-SELECTS via the same route', changed);
    final h2 = await page.evaluate(
        "document.querySelectorAll('.dv-wedit-handles .dv-wh').length");
    check('handles follow the row selection (found $h2)', (h2 as int) > 0);
    final c2 = await page.evaluate(
        "document.querySelectorAll('.dv-wedit-mode').length");
    check('editor is bound after a row click (found $c2 chips)', (c2 as int) > 0);
    await shot(page, '4-explode-row-selected');
  }

  await client.close();
  print('done');
}
