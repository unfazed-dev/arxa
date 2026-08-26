// Comment-flow probe (operator bug report 2026-08-25: 'comments feature
// does not work'). Reproduces the FULL author comment path in real Chrome:
// reveal -> dock -> Comment verb -> click a real element -> composer ->
// Add pin -> pin badge renders -> server stores it. Console/page errors
// fail the probe; the suspected root cause IS a console TypeError
// (verbEls.pin is undefined in arm()).
import 'dart:async';
import 'dart:io';

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}

Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/',
      settleMs: 2500);

  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  await js(tab, "$sr.querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));

  final verb = await js(tab, "$sr.querySelector('[data-verb=comment]') != null");
  check(verb == true, 'comment verb present');
  await js(tab, "$sr.querySelector('[data-verb=comment]').click()");
  await Future.delayed(const Duration(milliseconds: 600));

  final typeErrs = tab.consoleErrors
      .where((e) => e.contains('TypeError') || e.contains('verbEls'))
      .toList();
  check(typeErrs.isEmpty,
      'comment verb arms without TypeError${typeErrs.isEmpty ? '' : ' -- ${typeErrs.first}'}');

  final pt = await js(tab, '''(() => {
    const els = [...document.querySelectorAll('[data-arxa-id]')];
    for (const el of els) {
      const r = el.getBoundingClientRect();
      if (r.width > 40 && r.height > 12 && r.x >= 0 && r.y >= 0 &&
          r.x + r.width <= innerWidth && r.y + r.height <= innerHeight) {
        return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2)};
      }
    }
    return null;
  })()''');
  if (pt is Map) {
    final x = (pt['x'] as num).toInt(), y = (pt['y'] as num).toInt();
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
    await Future.delayed(const Duration(milliseconds: 600));
    final composerOpen = await js(tab,
        "$sr.querySelector('#composer').classList.contains('open')");
    check(composerOpen == true, 'composer opens on element click');

    if (composerOpen == true) {
      await js(tab,
          "$sr.querySelector('#composer textarea').value = 'probe: pin the hero'");
      await js(tab,
          "$sr.querySelector('#composer button.btn:not(.ghost)').click()");
      await Future.delayed(const Duration(milliseconds: 1200));
      final pins = await js(tab, "$sr.querySelectorAll('#pins .pin').length");
      check((pins is num) && pins > 0, 'pin badge rendered ($pins)');
      final stored = await js(tab, '''(async () => {
        const r = await fetch('/__dial/pins');
        const j = await r.json();
        return (j.pins || []).filter(p => (p.body||'').includes('probe: pin the hero')).length;
      })()''');
      check((stored as num? ?? 0) > 0, 'server stores the pin');
    }
  } else {
    check(false, 'selectable element in view');
  }
  check(tab.pageErrors.isEmpty,
      'page errors none (${tab.pageErrors.length})');
  check(tab.consoleErrors.isEmpty,
      'console clean (${tab.consoleErrors.length})');

  stdout.writeln(fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await client.close();
  exit(fails == 0 ? 0 : 1);
}
