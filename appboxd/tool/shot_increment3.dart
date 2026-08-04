// Throwaway verification driver for Increment 3 (edit arming + resize handles).
// Drives the REAL UI in Chrome — clicks the arm chip and a card the way a user
// would — rather than poking the HTTP endpoints, so the screenshots are
// evidence that the interaction works, not just that the routes respond.
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
  final framesLive = await page.evaluate("""
    (() => {
      const f = document.querySelector('iframe[data-screen="portalo.home"]');
      return {wired: !!(f && f._cw), doc: !!(f && f.contentDocument && f.contentDocument._cz)};
    })()
  """);
  check('tiles preserved across the selection morph (not reloaded)',
      framesLive['wired'] == true && framesLive['doc'] == true);

  await shot(page, '3-armed-selected-handles');
  await client.close();
  print('done');
}
