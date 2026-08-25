// Arxa tab probe (2026-08-26).
//
// Operator spec: "when i tap on arxa the top card in green is arxa card
// - instead of being separate in a card on top, i need the arxa feature
// card to be in the floating card itself and have the floating card be
// with tabs in the top bar of the floating card: customise and arxa as
// tabs" + "add a bottom bar ... where all the CTA buttons can be
// located per tab".
//
// Grilled decisions (2026-08-26): the panel's green card RETIRES
// entirely (machinery stays, markup goes); no auto-send on tab view;
// Customise default tab, no cross-element memory, per-element restore
// on reopen; bottom CTAs — Customise: Apply CSS, Arxa unsent: Send,
// Arxa sent: → composer / copy line / send again; BOTH insert
// confirmations (destination highlight+chip AND a real ack loop the
// island waits on); tabs left, × right, label+chip to the identity row,
// the ✨ header button retires.
//
// Assertions:
//   1. the card header is a TAB BAR (Customise/Arxa/×), the ✨ button
//      retired, identity row carries label + chip + idline
//   2. Customise default; footer holds Apply CSS
//   3. Arxa tab: unsent state, footer holds Send; NO POST on tab view
//   4. Send: pane shows the real selection id + snapshot line; footer
//      switches to the sent CTA set; server entry carries a real PNG
//   5. tab memory: same element restores Arxa after close/reopen; a
//      different element starts on Customise
//   6. a tab click never drags the card
//   7. → composer (tab A footer) lands the pointer line + snapshot in
//      the STUDIO composer (tab B, panel dock CLOSED — the always-on
//      listener law), flashes the destination chip, and the island's
//      ack status flips to a VERIFIED ✓
//   8. zero console AND page errors on BOTH tabs
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const SR = "document.getElementById('arxa-dial-host').shadowRoot";
const dialUrl = 'http://127.0.0.1:4319/';
const guiUrl = 'http://arxa.studio.localhost:7891/';

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
    await Future.delayed(const Duration(milliseconds: 200));
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

// The floating card, tab-law view.
const CARDST = '''
  JSON.stringify((() => {
    const root = ''' + SR + ''';
    const card = root.getElementById('card');
    const tabs = [...card.querySelectorAll('#chead .tab')]
      .map((b) => ({ id: b.getAttribute('data-tab'), on: b.classList.contains('on'),
        text: (b.textContent || '').trim() }));
    const panes = [...card.querySelectorAll('.tabpane')];
    const openPane = panes.findIndex((p) => p.classList.contains('on'));
    const foot = [...card.querySelectorAll('#cfoot button')]
      .map((b) => (b.textContent || '').trim());
    const sparkle = !!card.querySelector('#chead button[title*=arxa]');
    const idrow = card.querySelector('#cidrow');
    const bodyText = (card.querySelector('.tabpane.on') || {}).textContent || '';
    const r = card.getBoundingClientRect();
    return {
      open: card.classList.contains('open'),
      tabs, openPane, foot, sparkle,
      hasIdrow: !!idrow,
      idrowHasLabel: !!idrow && idrow.querySelector('.kchip') != null,
      body: bodyText.replace(/\\s+/g, ' ').slice(0, 260),
      left: Math.round(r.x), top: Math.round(r.y),
    };
  })())
''';

Future<Map> cardst(CdpSession tab) async =>
    jsonDecode((await js(tab, CARDST)) as String) as Map;

Future<void> clickAt(CdpSession tab, num x, num y) async {
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseMoved', 'x': x, 'y': y});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
}

// Clean hit-test pick (block 41 law): the topmost arxa element at the
// candidate's center must BE the leaf. Scans upward from [skip] for the
// first leaf passing the gate. ALWAYS re-queries (the page's split-text
// animation restructures the DOM — rects and hit regions move).
Future<Map?> pickLeaf(CdpSession tab, int skip, [String? excludeId]) async {
  final raw = await js(tab, '''
    (() => {
      const exclude = ''' + (excludeId == null ? 'null' : "'" + excludeId + "'") + ''';
      const els = [...document.querySelectorAll('[data-arxa-id]')];
      const leaves = els.filter((el) => {
        if (exclude && el.getAttribute('data-arxa-id') === exclude) return false;
        const t = (el.textContent || '').trim();
        if (!t || t.length < 3 || el.querySelector('[data-arxa-id]')) return false;
        const r = el.getBoundingClientRect();
        return r.width > 40 && r.height > 12 && r.x >= 0 && r.y >= 0 &&
          r.x + r.width <= innerWidth && r.y + r.height <= innerHeight;
      });
      for (let i = ''' + skip.toString() + '''; i < leaves.length; i++) {
        const el = leaves[i];
        const r = el.getBoundingClientRect();
        const cx = r.x + r.width / 2, cy = r.y + r.height / 2;
        // The REAL dispatch target is elementsFromPoint's first entry —
        // the open card (shadow host, no data-arxa-id) or a full-bleed
        // wrapper both steal clicks; only the leaf itself or one of its
        // descendants is a clean pick (block 41 + 42 law).
        const stack = document.elementsFromPoint(cx, cy);
        if (stack.length && (stack[0] === el || el.contains(stack[0]))) {
          return JSON.stringify({x: Math.round(cx), y: Math.round(cy),
            id: el.getAttribute('data-arxa-id')});
        }
      }
      return 'null';
    })()
  ''');
  if (raw == 'null') return null;
  return jsonDecode(raw as String) as Map;
}

// Fresh hit-point for an element by id (post-split DOM — never reuse a
// stale rect across animation restructuring).
Future<Map?> hitFor(CdpSession tab, String id) async {
  final raw = await js(tab, '''
    (() => {
      const el = document.querySelector('[data-arxa-id="''' + id + '''"]');
      if (!el) return 'null';
      const r = el.getBoundingClientRect();
      if (r.width < 2 || r.height < 2) return 'null';
      const cx = Math.max(4, Math.min(innerWidth - 4, r.x + r.width / 2));
      const cy = Math.max(4, Math.min(innerHeight - 4, r.y + r.height / 2));
      return JSON.stringify({x: Math.round(cx), y: Math.round(cy)});
    })()
  ''');
  if (raw == 'null') return null;
  return jsonDecode(raw as String) as Map;
}

Future<void> main() async {
  final browser = await CdpClient.launch();

  // ---- tab B first: the studio, panel dock CLOSED (the always-on
  // listener law: the insert must land without the dock expanded).
  final gui = await browser.newTab();
  await gui.setViewport(1280, 800);
  await gui.navigateAndSettleForCapture(guiUrl, settleMs: 4000);
  check(await js(gui,
          "!!document.querySelector(\"button[title='arxa design panel']\")") == true,
      'studio panel plugin mounted (dock closed, tab B)');

  // ---- tab A: the real dial interaction.
  final tab = await browser.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture(dialUrl, settleMs: 2500);
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await poll(tab,
      "getComputedStyle(" + SR + ".getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 4));
  await js(tab, SR + ".querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, SR + ".querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 300));

  await Future.delayed(const Duration(milliseconds: 2500)); // split-text settle
  final elA = await pickLeaf(tab, 0);
  if (elA == null) {
    check(false, 'selectable element in view');
    await browser.close();
    exit(1);
  }
  stdout.writeln('element A: ' + (elA['id'] as String));
  await clickAt(tab, elA['x'], elA['y']);
  await Future.delayed(const Duration(milliseconds: 500));

  // 1. header is the tab bar; sparkle retired; identity row present.
  var st = await cardst(tab);
  check(st['open'] == true, 'card opens on a real element');
  final tabs = (st['tabs'] as List).cast<Map>();
  check(tabs.length == 2 &&
      tabs[0]['id'] == 'customise' && tabs[1]['id'] == 'arxa',
      'header is the tab bar: ' +
          tabs.map((t) => t['text']).join('|'));
  check(st['sparkle'] == false, 'the ✨ arxa header button retired');
  check(st['hasIdrow'] == true && st['idrowHasLabel'] == true,
      'identity row carries label + chip');

  // 2. Customise default; footer holds Apply CSS.
  stdout.writeln('customise body: ' + (st['body'] as String));
  check(tabs.isNotEmpty && tabs[0]['on'] == true, 'Customise is the default tab');
  check((st['body'] as String).contains('Facets'),
      'customise pane shows the facets');
  check((st['foot'] as List).contains('Apply CSS'),
      'footer holds Apply CSS: ' + (st['foot'] as List).join('|'));

  // 3. Arxa tab: unsent state; viewing sends NOTHING.
  await js(tab, SR + ".querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  st = await cardst(tab);
  stdout.writeln('arxa body: ' + (st['body'] as String));
  check((st['body'] as String).contains('Send this element'),
      'Arxa unsent state explains the send');
  check((st['foot'] as List).contains('Send to arxa studio'),
      'unsent footer holds Send: ' + (st['foot'] as List).join('|'));

  // 4. Send: pane shows the real id; footer switches; server has a PNG.
  await js(tab, '''
    (() => { const b = [...''' + SR + '''.querySelectorAll('#cfoot button')]
      .find((x) => (x.textContent || '').trim() === 'Send to arxa studio');
      if (b) b.click(); return !!b; })()
  ''');
  final sent = await poll(tab, '''
    (() => { const m = (''' + SR + '''.querySelector('.tabpane.on .arxaid') || {}).textContent || '';
      return m.indexOf('design selection s') >= 0; })()
  ''', const Duration(seconds: 10));
  check(sent, 'send flips the pane to the sent state with the real id');
  st = await cardst(tab);
  check((st['foot'] as List).contains('→ composer') &&
      (st['foot'] as List).contains('copy line') &&
      (st['foot'] as List).contains('send again'),
      'sent footer: ' + (st['foot'] as List).join('|'));
  final sentId = await js(tab, '''
    (''' + SR + '''.querySelector('.tabpane.on .arxaid') || {}).textContent
      .replace(/^.*design selection\\s*/, '').trim()
  ''');
  final entry = selIdFrom(sentId);
  var pngLen = 0;
  if (entry != null) {
    final body = await httpGet('/__dial/selection/' + entry);
    if (body != null) {
      final m = jsonDecode(body) as Map;
      final png = m['png'];
      pngLen = png is String ? png.length : 0;
    }
  }
  check(pngLen > 100,
      'server entry for ' + (entry ?? '?') + ' carries a real PNG (' +
          pngLen.toString() + ' chars)');
  check((st['body'] as String).contains('snapshot captured'),
      'sent pane shows the snapshot line');

  // 5. tab memory: close + reopen SAME element -> Arxa restored.
  await js(tab, SR + ".querySelector('#chead .tab[data-tab=customise]').click()");
  await Future.delayed(const Duration(milliseconds: 200));
  await js(tab, SR + ".querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 200));
  await js(tab, SR + ".querySelector('#chead .cclose').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  final again = await hitFor(tab, elA['id'] as String);
  if (again == null) {
    check(false, 'element A re-hit after close');
  } else {
    await clickAt(tab, again['x'], again['y']);
    await Future.delayed(const Duration(milliseconds: 500));
    st = await cardst(tab);
    final t2 = (st['tabs'] as List).cast<Map>();
    // The reopen MUST select the same element — the idline is the proof
    // (a different element means the hit region shifted, not memory).
    final idlineNow = await js(tab,
        "(" + SR + ".querySelector('#cidrow .idline') || {}).textContent || ''");
    check(t2.length == 2 && t2[1]['on'] == true &&
        (idlineNow as String).contains(elA['id'] as String),
        'same element restores the Arxa tab after close/reopen (idline: ' +
            (idlineNow as String) + ')');
  }

  // 5b. a DIFFERENT element starts on Customise (no cross-element memory).
  // A DIFFERENT element — sibling line-instances share the id ("Spaces
  // for living" splits into two e8 leaves), so exclude A's id outright.
  final elB = await pickLeaf(tab, 0, elA['id'] as String);
  if (elB != null) {
    stdout.writeln('element B: ' + (elB['id'] as String) + ' @' + elB['x'].toString() + ',' + elB['y'].toString());
    await clickAt(tab, elB['x'], elB['y']);
    await Future.delayed(const Duration(milliseconds: 500));
    st = await cardst(tab);
    final t3 = (st['tabs'] as List).cast<Map>();
    final bline = await js(tab,
        "(" + SR + ".querySelector('#cidrow .idline') || {}).textContent || '(no idline)'");
    stdout.writeln('B card: open=' + st['open'].toString() +
        ' tabs=' + t3.map((t) => t['id'].toString() + (t['on'] == true ? '*' : '')).join(',') +
        ' idline=' + (bline as String));
    check(t3.length == 2 && t3[0]['on'] == true &&
        !(bline as String).contains(elA['id'] as String),
        'a different element starts on Customise');
  } else {
    stdout.writeln('NOTE  no second clean element; cross-element memory check skipped');
  }

  // 6. a tab click never drags the card.
  final before = await cardst(tab);
  await js(tab, SR + ".querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 200));
  await js(tab, SR + ".querySelector('#chead .tab[data-tab=customise]').click()");
  await Future.delayed(const Duration(milliseconds: 200));
  final after = await cardst(tab);
  check(after['left'] == before['left'] && after['top'] == before['top'],
      'tab clicks never drag the card');

  // Back to element A for the compose flow (its Arxa state is sent).
  final back = await hitFor(tab, elA['id'] as String);
  if (back == null) {
    check(false, 'element A re-hit for the compose flow');
  } else {
    await clickAt(tab, back['x'], back['y']);
  }
  await Future.delayed(const Duration(milliseconds: 500));
  await js(tab, SR + ".querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 300));

  // 7. → composer: island asks, studio inserts (panel dock CLOSED),
  //    chip flashes at the destination, the ack flips the status.
  await js(tab, '''
    (() => { const b = [...''' + SR + '''.querySelectorAll('#cfoot button')]
      .find((x) => (x.textContent || '').trim() === '→ composer');
      if (b) b.click(); return !!b; })()
  ''');
  final lineOk = await poll(gui, '''
    (() => { const tas = [...document.querySelectorAll('textarea')];
      const ta = tas[tas.length - 1];
      return !!(ta && (ta.value || '').indexOf('design selection') >= 0); })()
  ''', const Duration(seconds: 12));
  check(lineOk, 'pointer line inserted in the studio composer (dock closed)');
  final rail = await js(gui, '''
    (() => {
      const fresh = [...document.querySelectorAll('img')]
        .filter((im) => (im.src || '').startsWith('blob:') || (im.src || '').startsWith('data:'));
      return fresh.length;
    })()
  ''');
  check((rail as num? ?? 0) >= 1, 'snapshot attached in the composer image rail');
  final chipOk = await js(gui, "!!document.getElementById('arxa-compose-chip')");
  check(chipOk == true, 'destination confirmation chip flashed (tab B)');
  final ackOk = await poll(tab, '''
    (() => { const s = (''' + SR + '''.querySelector('.tabpane.on .arxastatus') || {}).textContent || '';
      return s.indexOf('inserted into the composer') >= 0; })()
  ''', const Duration(seconds: 6));
  check(ackOk, 'the ack loop flips the Arxa tab to a VERIFIED ✓');

  // Evidence: the Arxa tab sent state at 2x, plus the studio composer.
  Future<List<int>> clipCard() async {
    final rect = await js(tab, '''
      (() => { const r = ''' + SR + '''.getElementById('card').getBoundingClientRect();
        return JSON.stringify({x: r.x, y: r.y, w: r.width, h: r.height}); })()
    ''');
    final rc = jsonDecode(rect as String) as Map;
    final shot = await tab.send('Page.captureScreenshot', {
      'format': 'png',
      'clip': {
        'x': (rc['x'] as num).toDouble() - 8,
        'y': (rc['y'] as num).toDouble() - 8,
        'width': (rc['w'] as num).toDouble() + 16,
        'height': (rc['h'] as num).toDouble() + 16,
        'scale': 2,
      },
    });
    return base64Decode(shot['result']['data'] as String);
  }
  final evDir = '/Volumes/developer_ssd/Developer/totem_labs/'
      'clients/architect-gallore/design/suczka-studio/evidence/dial-card';
  Directory(evDir).createSync(recursive: true);
  File(evDir + '/arxa-tab-sent-2x.png').writeAsBytesSync(await clipCard());
  File(evDir + '/arxa-tab-studio-insert-1280.png').writeAsBytesSync(await gui.screenshot());
  stdout.writeln('evidence: ' + evDir);

  // 8. both error channels clean, both tabs.
  check(tab.pageErrors.isEmpty && tab.consoleErrors.isEmpty &&
      gui.pageErrors.isEmpty && gui.consoleErrors.isEmpty,
      'zero page + console errors, both tabs (A ' +
          (tab.pageErrors.length + tab.consoleErrors.length).toString() +
          ', B ' + (gui.pageErrors.length + gui.consoleErrors.length).toString() + ')');
  for (final e in tab.pageErrors) stdout.writeln('PAGE-A: ' + e);
  for (final e in gui.pageErrors) stdout.writeln('PAGE-B: ' + e);
  for (final e in gui.consoleErrors) stdout.writeln('CONSOLE-B: ' + e);

  await browser.close();
  stdout.writeln(fails == 0 ? 'ALL PASS' : 'FAILURES: ' + fails.toString());
  exit(fails == 0 ? 0 : 1);
}

// 'design selection sXXXX · ...' -> sXXXX (or null)
String? selIdFrom(Object? raw) {
  if (raw is! String) return null;
  final m = RegExp(r's[0-9a-z]{3,20}').firstMatch(raw);
  return m == null ? null : m.group(0);
}
