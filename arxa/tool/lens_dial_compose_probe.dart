// Two-tab composer-write probe (rework slice 7 + operator ask, 2026-08-25).
//
// The missing live-GUI proof: the full selection handoff chain in real
// Chrome across TWO tabs of one browser -
//   tab A (dial): 4319 design page, corner reveal -> Edit Mode -> click a
//                  real element -> card opens -> Ask-arxa tapped
//   tab B (GUI):  arxa studio (DSH web) with the design panel open ->
//                  SSE selection frame -> rail-twin card renders ->
//                  composer clicked -> the GUI composer textarea holds
//                  the pointer line.
// Evidence: screenshot of tab B under the client repo evidence dir.
// Console/page errors on either tab fail the probe.
//
//   dart run tool/lens_dial_compose_probe.dart
import 'dart:async';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
const guiUrl = 'http://arxa.studio.localhost:7891/';
const dialUrl = 'http://127.0.0.1:4319/';
const evidenceDir = '/Volumes/developer_ssd/Developer/totem_labs/'
    'clients/architect-gallore/design/suczka-studio/evidence/composer-write';

int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}

Future<bool> poll(CdpSession tab, String expr, Duration limit) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final v = await js(tab, expr);
      if (v == true) return true;
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

Future<void> main() async {
  Directory(evidenceDir).createSync(recursive: true);
  final client = await CdpClient.launch();

  // ---- tab B first: GUI panel open, subscribing BEFORE the tap.
  final gui = await client.newTab();
  await gui.setViewport(1280, 800);
  await gui.navigateAndSettleForCapture(guiUrl, settleMs: 4000);
  final opened = await js(gui,
      '(() => { const b = document.querySelector(' '"button[title=\'arxa design panel\']");' ' if (!b) return false; b.click(); return true; })()');
  check(opened == true, 'design panel button present and clicked');
  final dockUp = await poll(gui,
      "!![...document.querySelectorAll('button')].some(b => /(mobile|tablet|desktop)/.test(b.textContent||''))",
      const Duration(seconds: 10));
  check(dockUp, 'panel dock mounted (rung buttons render)');

  // ---- tab A: the real dial interaction, exactly as the author does it.
  final dial = await client.newTab();
  await dial.setViewport(1280, 800);
  await dial.navigateAndSettleForCapture(dialUrl, settleMs: 2500);
  // Same-origin witness: catch the broadcast frame on the dial tab itself,
  // so a missing GUI card can be blamed on the right half of the chain.
  await js(dial, '''
    window.__probeFrames = [];
    (() => {
      const es = new EventSource('/__dial/events');
      es.addEventListener('dial', (ev) => { window.__probeFrames.push(ev.data); });
    })()
  ''');
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
    check(false, 'selectable text element in view (tab A)');
    await client.close();
    exit(1);
  }
  final x = (pt['x'] as num).toInt(), y = (pt['y'] as num).toInt();
  await dial.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
  await dial.send('Input.dispatchMouseEvent',
      {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await dial.send('Input.dispatchMouseEvent',
      {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await Future.delayed(const Duration(milliseconds: 500));
  check(await js(dial, "$sr.querySelector('#card').classList.contains('open')") == true,
      'card opens on a real element (tab A)');
  final tapped = await js(dial, '''    (() => {
      const ask = $sr.querySelector('#chead button[title*=arxa]');
      if (!ask) return false;
      ask.click();
      return true;
    })()
  ''');
  check(tapped == true, 'Ask-arxa tapped (tab A)');
  await Future.delayed(const Duration(milliseconds: 2500));
  final sawFrame = await js(dial,
      "(() => (window.__probeFrames || []).some(f => f.includes('selection')))()");
  check(sawFrame == true, 'selection frame broadcast on /__dial/events');

  // ---- tab B: the SSE frame should have painted the rail-twin card.
  final cardUp = await poll(gui,
      "document.body.textContent.includes('design selection')",
      const Duration(seconds: 20));
  check(cardUp, 'rail-twin selection card rendered (SSE frame received)');
  final composed = await js(gui, '''
    (() => {
      const btns = [...document.querySelectorAll('button')];
      const b = btns.find(x => (x.textContent || '').trim() === '\u2192 composer');
      if (!b) return {clicked: false};
      b.click();
      return {clicked: true};
    })()
  ''');
  check((composed as Map?)?['clicked'] == true, 'composer button clicked (tab B)');
  await Future.delayed(const Duration(milliseconds: 700));
  final line = await js(gui, '''
    (() => {
      const tas = [...document.querySelectorAll('textarea')];
      const ta = tas.find(t => (t.value || '').includes('design selection'));
      return ta ? ta.value : null;
    })()
  ''');
  check(line is String && line.contains('design selection'),
      'composer textarea holds the pointer line');
  if (line is String) {
    stdout.writeln('     line: ${line.length > 160 ? '${line.substring(0, 160)}...' : line}');
  }

  // ---- evidence + cleanliness.
  try {
    File('$evidenceDir/gui-composer-1280.png')
        .writeAsBytesSync(await gui.screenshot());
    stdout.writeln('     evidence: $evidenceDir/gui-composer-1280.png');
  } catch (e) {
    stdout.writeln('     evidence: screenshot failed - $e');
  }
  check(gui.consoleErrors.isEmpty, 'GUI console clean');
  check(dial.consoleErrors.isEmpty, 'dial console clean');

  stdout.writeln(fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await client.close();
  exit(fails == 0 ? 0 : 1);
}
