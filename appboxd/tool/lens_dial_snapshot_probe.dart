// Snapshot-to-composer verification probe (2026-08-25 night; reworked
// 2026-08-26 for the Arxa tab: the green studio card retired, the send
// lives in the floating card's Arxa tab, and → composer runs ISLAND-SIDE
// — the always-on panel listener inserts, flashes the destination chip,
// and acks back over the same dial event stream).
//
// Verified chain:
//   1. the island's captureElement produces a real PNG on suczka (the
//      selection entry server-side carries it)
//   2. the SSE 'selection' broadcast is a thin pointer {id, fetch}
//   3. the floating card's Arxa tab shows the sent state (the retired
//      studio card's content now lives here)
//   4. the Arxa footer's "→ composer" writes the pointer line AND
//      attaches the snapshot into the composer's draft image rail —
//      with the panel dock CLOSED (always-on listener law), the chip
//      flashing at the destination, and the ack ✓ back in the card
// Evidence screenshot lands under the client repo evidence dir (tracked).
// Console/page errors on either tab fail the probe. Nothing is sent.
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const SR = "document.getElementById('arxa-dial-host').shadowRoot";
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
    await Future.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

Future<String?> httpGet(String path) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:4319' + path));
    final res = await req.close();
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<void> main() async {
  final browser = await CdpClient.launch();

  // ---- tab B: the studio, subscribed BEFORE the tap. The panel dock
  // stays CLOSED — the dial listener is always-on now (the Arxa tab
  // drives the composer from the design iframe, dock state aside).
  final gui = await browser.newTab();
  await gui.setViewport(1280, 800);
  await gui.navigateAndSettleForCapture(guiUrl, settleMs: 4000);
  check(await js(gui,
          "!!document.querySelector(\"button[title='arxa design panel']\")") == true,
      'studio panel plugin mounted (dock closed, tab B)');

  // ---- tab A: the real dial interaction.
  final dial = await browser.newTab();
  await dial.setViewport(1280, 800);
  await dial.navigateAndSettleForCapture(dialUrl, settleMs: 2500);
  await js(dial, '''
    window.__frames = [];
    (() => {
      const es = new EventSource('/__dial/events');
      es.addEventListener('dial', (ev) => { window.__frames.push(ev.data); });
    })()
  ''');
  for (var i = 0; i < 5; i++) {
    await dial.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  await js(dial, SR + ".querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  await js(dial, SR + ".querySelector('[data-verb=edit]').click()");
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
  check(await js(dial, SR + ".querySelector('#card').classList.contains('open')") == true,
      'card opens on a real element (tab A)');
  // The Arxa tab flow: open the tab, then the footer Send button.
  await js(dial, SR + ".querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  check(await js(dial, '''
    (() => {
      const b = [...''' + SR + '''.querySelectorAll('#cfoot button')]
        .find((x) => (x.textContent || '').trim() === 'Send to arxa studio');
      if (!b) return false;
      b.click();
      return true;
    })()
  ''') == true, 'Arxa tab Send tapped (tab A)');
  await Future.delayed(const Duration(milliseconds: 4000));
  check(await js(dial, '''
    (() => { const m = (''' + SR + '''.querySelector('.tabpane.on .arxaid') || {}).textContent || '';
      return m.indexOf('design selection s') >= 0; })()
  ''') == true, 'Arxa tab shows the sent state (tab A)');

  // ---- 1+2: the frame content, verbatim.
  final frames = await js(dial,
      "JSON.stringify((window.__frames || []).filter(f => f.includes('selection')))");
  stdout.writeln('SSE selection frames: ' + (frames is String ? frames : '(none)'));
  String? selId;
  if (frames is String && frames.length > 4) {
    final list = jsonDecode(frames) as List;
    if (list.isNotEmpty) {
      final data = (jsonDecode(list.last as String) as Map)['data'];
      stdout.writeln('frame data keys: ' + (data as Map).keys.toList().toString());
      selId = data['id'] as String?;
    }
  }
  check(selId != null, 'selection id captured from the broadcast');

  // ---- 1: server-side truth for THIS selection.
  var pngLen = 0;
  var label = '';
  if (selId != null) {
    final body = await httpGet('/__dial/selection/' + selId);
    if (body != null) {
      final m = jsonDecode(body) as Map;
      final png = m['png'];
      pngLen = png is String ? png.length : 0;
      label = (m['label'] ?? '').toString();
      stdout.writeln('server entry: label=' + label + ' png=' +
          (png is String ? (png.length.toString() + ' chars') : 'ABSENT') +
          ' text=' + ((m['text'] as String?) ?? '').length.toString() + 'ch' +
          ' styles=' + ((m['styles'] as Map?) ?? {}).length.toString());
    }
  }
  check(pngLen > 100, 'island captureElement produced a real PNG on suczka');

  // ---- 3: the card shows the sent state — the retired studio card's
  // content lives in the floating card's Arxa tab now.
  final sentBody = await js(dial, '''
    (() => { const p = ''' + SR + '''.querySelector('.tabpane.on');
      return p ? (p.textContent || '').replace(/\\s+/g, ' ').slice(0, 240) : ''; })()
  ''');
  stdout.writeln('arxa pane: ' + (sentBody ?? '').toString());
  final safeLabel = label.replaceAll("'", '');
  check(label.isEmpty || (sentBody as String).contains(safeLabel.split(' · ')[0].trim()),
      'arxa tab shows the real element label from the sent handoff');

  // ---- 4: the card's OWN footer button - pointer text AND snapshot.
  check(await js(dial, '''
    (() => {
      const b = [...''' + SR + '''.querySelectorAll('#cfoot button')]
        .find((x) => (x.textContent || '').trim() === '\u2192 composer');
      if (!b) return false;
      b.click();
      return true;
    })()
  ''') == true, '→ composer tapped in the card footer (tab A)');
  await Future.delayed(const Duration(milliseconds: 2500));
  final line = await js(gui,
      "(() => { const tas = [...document.querySelectorAll('textarea')]; const ta = tas[tas.length - 1]; return ta ? (ta.value || '') : ''; })()");
  check((line as String? ?? '').contains('design selection'),
      'pointer line in the composer textarea');
  final rail = await js(gui, '''
    (() => {
      const imgs = [...document.querySelectorAll('img')];
      const fresh = imgs.filter((im) => (im.src || '').startsWith('blob:') ||
                                         (im.src || '').startsWith('data:'));
      return {fresh: fresh.length, src0: fresh.length ? fresh[0].src.slice(0, 40) : ''};
    })()
  ''');
  stdout.writeln('composer image rail: ' + (rail ?? '').toString());
  check((rail is Map ? (rail['fresh'] as num? ?? 0) : 0) >= 1,
      'SNAPSHOT attached in the composer draft image rail');
  // the destination chip flashed (tab B) and the ack verified back in
  // the card (tab A) — both confirmations (operator, 2026-08-26).
  check(await js(gui, "!!document.getElementById('arxa-compose-chip')") == true,
      'destination confirmation chip flashed (tab B)');
  check(await poll(dial, '''
    (() => { const s = (''' + SR + '''.querySelector('.tabpane.on .arxastatus') || {}).textContent || '';
      return s.indexOf('inserted into the composer') >= 0; })()
  ''', const Duration(seconds: 6)), 'ack ✓ verified in the card (tab A)');

  // Evidence: the GUI with line + thumbnail.
  final shot = await gui.screenshot();
  final evDir = '/Volumes/developer_ssd/Developer/totem_labs/'
      'clients/architect-gallore/design/suczka-studio/evidence/snapshot-to-composer';
  Directory(evDir).createSync(recursive: true);
  File(evDir + '/studio-gui-1280.png').writeAsBytesSync(shot);
  stdout.writeln('evidence: ' + evDir + '/studio-gui-1280.png');

  stdout.writeln('tab A console errors: ' + dial.consoleErrors.length.toString() +
      '; tab B console errors: ' + gui.consoleErrors.length.toString());
  if (dial.consoleErrors.isNotEmpty || gui.consoleErrors.isNotEmpty) fails++;
  await browser.close();
  stdout.writeln(fails == 0 ? '\nPROBE VERDICT: PASS' : '\nPROBE VERDICT: FAIL');
  exit(fails == 0 ? 0 : 1);
}
