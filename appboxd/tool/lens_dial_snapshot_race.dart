// Race test for the snapshot attach (2026-08-25 night, systematic-debugging
// Phase 4 failing-test-first).
//
// Defect under test: the panel's insertIntoComposer read selReq.png at CLICK
// time. The context fetch (fetch-on-arrival) resolves AFTER the card paints,
// so a click in that window attaches NO snapshot - text-only handoff, exactly
// the operator-visible symptom, even on the fixed bytes.
//
// Deterministic exercise: window.fetch on the studio tab is patched to delay
// any /__dial/selection GET by 1200ms; the composer button is clicked the
// INSTANT the card text appears (before any context can have arrived). The
// fixed panel awaits the in-flight context promise inside the click, so the
// image rail still fills ~1.2s later; the unfixed one never fills.
//
//   dart run tool/lens_dial_snapshot_race.dart
import 'dart:io';

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
const guiUrl = 'http://arxa.studio.localhost:7891/';
const dialUrl = 'http://127.0.0.1:4319/';

int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}

Future<bool> poll(CdpSession tab, String expr, Duration limit) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await js(tab, expr) == true) return true;
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 150));
  }
  return false;
}

Future<void> main() async {
  final browser = await CdpClient.launch();

  // ---- tab B: studio; slow the context fetch BEFORE any selection exists.
  final gui = await browser.newTab();
  await gui.setViewport(1280, 800);
  await gui.navigateAndSettleForCapture(guiUrl, settleMs: 4000);
  check(await js(gui,
          "(() => { const b = document.querySelector(\"button[title='arxa design panel']\"); if (!b) return false; b.click(); return true; })()") ==
      true, 'design panel opened (tab B)');
  await poll(gui,
      "!![...document.querySelectorAll('button')].some(b => /(mobile|tablet|desktop)/.test(b.textContent||''))",
      const Duration(seconds: 10));
  check(await js(gui, '''
    (() => {
      if (window.__slowSel) return true;
      window.__slowSel = true;
      const orig = window.fetch.bind(window);
      window.fetch = (u, ...a) => {
        if (String(u).includes('/__dial/selection')) {
          return new Promise((res) => setTimeout(() => res(orig(u, ...a)), 1200));
        }
        return orig(u, ...a);
      };
      return true;
    })()
  ''') == true, 'context fetch slowed to 1200ms (tab B)');

  // ---- tab A: real dial flow.
  final dial = await browser.newTab();
  await dial.setViewport(1280, 800);
  await dial.navigateAndSettleForCapture(dialUrl, settleMs: 2500);
  for (var i = 0; i < 5; i++) {
    await dial.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  await js(dial, "$sr.querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  await js(dial, "$sr.querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  final pt = await js(dial, '''
    (() => {
      const els = [...document.querySelectorAll('[data-arxa-id]')];
      for (const el of els) {
        const t = (el.textContent || '').trim();
        if (!t || t.length < 3 || el.querySelector('[data-arxa-id]')) continue;
        const r = el.getBoundingClientRect();
        if (r.width > 40 && r.height > 12 && r.x >= 0 && r.y >= 0 &&
            r.x + r.width <= innerWidth && r.y + r.height <= innerHeight) {
          return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2)};
        }
      }
      return null;
    })()
  ''');
  if (pt is! Map) {
    check(false, 'selectable element in view (tab A)');
    await browser.close();
    exit(1);
  }
  final x = (pt['x'] as num).toInt(), y = (pt['y'] as num).toInt();
  await dial.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
  await dial.send('Input.dispatchMouseEvent',
      {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await dial.send('Input.dispatchMouseEvent',
      {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await Future.delayed(const Duration(milliseconds: 500));
  await js(dial, '''    (() => {
      const ask = $sr.querySelector('#chead button[title*=arxa]');
      if (ask) ask.click();
      return true;
    })()
  ''');
  await Future.delayed(const Duration(milliseconds: 1500));

  // ---- the race: click the composer button the instant the card exists.
  final cardUp = await poll(gui,
      "document.body.textContent.includes('design selection')",
      const Duration(seconds: 15));
  check(cardUp, 'card rendered (tab B)');
  check(await js(gui, '''
    (() => {
      const b = [...document.querySelectorAll('button')]
        .find((x2) => (x2.textContent || '').trim() === '\u2192 composer');
      if (!b) return false;
      b.click();
      return true;
    })()
  ''') == true, 'composer button clicked IMMEDIATELY (context still in flight)');

  // Text lands right away...
  await Future.delayed(const Duration(milliseconds: 500));
  final line = await js(gui,
      "(() => { const tas = [...document.querySelectorAll('textarea')]; const ta = tas[tas.length - 1]; return ta ? (ta.value || '') : ''; })()");
  check((line as String? ?? '').contains('design selection'),
      'pointer line landed immediately');

  // ...and the snapshot must STILL arrive once the delayed context resolves.
  final railFilled = await poll(gui, '''
    (() => {
      const imgs = [...document.querySelectorAll('img')];
      return imgs.some((im) => (im.src || '').startsWith('blob:') ||
                                (im.src || '').startsWith('data:'));
    })()
  ''', const Duration(seconds: 8));
  check(railFilled,
      'SNAPSHOT attached despite the click racing the context fetch');

  stdout.writeln('tab A console errors: ${dial.consoleErrors.length}; tab B console errors: ${gui.consoleErrors.length}');
  if (dial.consoleErrors.isNotEmpty || gui.consoleErrors.isNotEmpty) fails++;
  await browser.close();
  stdout.writeln(fails == 0 ? '\nRACE VERDICT: PASS' : '\nRACE VERDICT: FAIL');
  exit(fails == 0 ? 0 : 1);
}
