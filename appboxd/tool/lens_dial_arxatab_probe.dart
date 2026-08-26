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
//   8. one-focus law: while an element is selected NO other element
//      can be selected — clicks/double-clicks on other elements are
//      absorbed; only a full deselect (or the element dying in a swap)
//      re-opens selection; re-clicking the SAME element re-opens the
//      card
//   9. zero console AND page errors on BOTH tabs
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
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
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:4319$path'));
    final res = await req.close();
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

// The agent's patch path: read the draft, hand it back mutated. UTF-8
// body — artifact text carries non-Latin-1 characters and a plain
// write() Latin-1-encodes them into a crash.
Future<Map?> httpCall(String method, String path, Map? body) async {
  final client = HttpClient();
  try {
    final req =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:4319$path'));
    if (body != null) {
      req.headers.contentType =
          ContentType.parse('application/json; charset=utf-8');
      req.add(utf8.encode(jsonEncode(body)));
    }
    final res = await req.close();
    final txt = await res.transform(utf8.decoder).join();
    return txt.isEmpty ? null : jsonDecode(txt) as Map;
  } finally {
    client.close();
  }
}

// The floating card, tab-law view.
const cardSt = '''  JSON.stringify((() => {
    const root = $sr;
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
    jsonDecode((await js(tab, cardSt)) as String) as Map;

Future<void> clickAt(CdpSession tab, num x, num y) async {
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseMoved', 'x': x, 'y': y});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
}

// A real double-click: press/release clickCount 1 then press/release
// clickCount 2 — Chrome synthesizes the dblclick event from the
// clickCount:2 pair (a hand-built MouseEvent('dblclick') carries
// clientX/Y 0,0 and the island's point picker would read the page
// corner instead of the element).
Future<void> dblClickAt(CdpSession tab, num x, num y) async {
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseMoved', 'x': x, 'y': y});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 2});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 2});
}

// The one-focus protocol (operator law, 2026-08-26): while an element
// holds the focus NO other element can be selected — the law's only
// door to a new selection is a full deselect (Esc closes the card and
// keeps the selection; a second Esc disarms Edit Mode and clears it),
// then a fresh re-arm. Every beat that legitimately moves the
// selection from one element to another walks this door.
Future<void> deselectAndRearm(CdpSession tab) async {
  await js(tab,
      "document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape'}))");
  await Future.delayed(const Duration(milliseconds: 300));
  await js(tab,
      "document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape'}))");
  await Future.delayed(const Duration(milliseconds: 300));
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await poll(tab,
      "getComputedStyle($sr.getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 6));
  await js(tab, "$sr.querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$sr.querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 400));
}

// Clean hit-test pick (block 41 law): the topmost arxa element at the
// candidate's center must BE the leaf. Scans upward from [skip] for the
// first leaf passing the gate. ALWAYS re-queries (the page's split-text
// animation restructures the DOM — rects and hit regions move).
Future<Map?> pickLeaf(CdpSession tab, int skip, [String? excludeId]) async {
  final raw = await js(tab, '''    (() => {
      const exclude = ${excludeId == null ? 'null' : "'$excludeId'"};
      const els = [...document.querySelectorAll('[data-arxa-id]')];
      const leaves = els.filter((el) => {
        if (exclude && el.getAttribute('data-arxa-id') === exclude) return false;
        const t = (el.textContent || '').trim();
        if (!t || t.length < 3 || el.querySelector('[data-arxa-id]')) return false;
        const r = el.getBoundingClientRect();
        return r.width > 40 && r.height > 12 && r.x >= 0 && r.y >= 0 &&
          r.x + r.width <= innerWidth && r.y + r.height <= innerHeight;
      });
      for (let i = $skip; i < leaves.length; i++) {
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
  final raw = await js(tab, '''    (() => {
      const el = document.querySelector('[data-arxa-id="$id"]');
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
      "getComputedStyle($sr.getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 4));
  await js(tab, "$sr.querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$sr.querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 300));

  await Future.delayed(const Duration(milliseconds: 2500)); // split-text settle
  final elA = await pickLeaf(tab, 0);
  if (elA == null) {
    check(false, 'selectable element in view');
    await browser.close();
    exit(1);
  }
  stdout.writeln('element A: ${elA['id'] as String}');
  await clickAt(tab, elA['x'], elA['y']);
  await Future.delayed(const Duration(milliseconds: 500));

  // 1. header is the tab bar; sparkle retired; identity row present.
  var st = await cardst(tab);
  check(st['open'] == true, 'card opens on a real element');
  final tabs = (st['tabs'] as List).cast<Map>();
  check(tabs.length == 2 &&
      tabs[0]['id'] == 'customise' && tabs[1]['id'] == 'arxa',
      'header is the tab bar: ${tabs.map((t) => t['text']).join('|')}');
  check(st['sparkle'] == false, 'the ✨ arxa header button retired');
  check(st['hasIdrow'] == true && st['idrowHasLabel'] == true,
      'identity row carries label + chip');

  // 2. Customise default; footer holds Apply CSS.
  stdout.writeln('customise body: ${st['body'] as String}');
  check(tabs.isNotEmpty && tabs[0]['on'] == true, 'Customise is the default tab');
  check((st['body'] as String).contains('Facets'),
      'customise pane shows the facets');
  check((st['foot'] as List).contains('Apply CSS'),
      'footer holds Apply CSS: ${(st['foot'] as List).join('|')}');

  // 3. Arxa tab: unsent state; viewing sends NOTHING.
  await js(tab, "$sr.querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  st = await cardst(tab);
  stdout.writeln('arxa body: ${st['body'] as String}');
  check((st['body'] as String).contains('Send this element'),
      'Arxa unsent state explains the send');
  check((st['foot'] as List).contains('Send to arxa studio'),
      'unsent footer holds Send: ${(st['foot'] as List).join('|')}');

  // 4. Send: pane shows the real id; footer switches; server has a PNG.
  await js(tab, '''    (() => { const b = [...$sr.querySelectorAll('#cfoot button')]
      .find((x) => (x.textContent || '').trim() === 'Send to arxa studio');
      if (b) b.click(); return !!b; })()
  ''');
  final sent = await poll(tab, '''    (() => { const m = ($sr.querySelector('.tabpane.on .arxaid') || {}).textContent || '';
      return m.indexOf('design selection s') >= 0; })()
  ''', const Duration(seconds: 10));
  check(sent, 'send flips the pane to the sent state with the real id');
  st = await cardst(tab);
  check((st['foot'] as List).contains('→ composer') &&
      (st['foot'] as List).contains('copy line') &&
      (st['foot'] as List).contains('send again'),
      'sent footer: ${(st['foot'] as List).join('|')}');
  final sentId = await js(tab, '''    ($sr.querySelector('.tabpane.on .arxaid') || {}).textContent
      .replace(/^.*design selection\\s*/, '').trim()
  ''');
  final entry = selIdFrom(sentId);
  var pngLen = 0;
  if (entry != null) {
    final body = await httpGet('/__dial/selection/$entry');
    if (body != null) {
      final m = jsonDecode(body) as Map;
      final png = m['png'];
      pngLen = png is String ? png.length : 0;
    }
  }
  check(pngLen > 100,
      'server entry for ${entry ?? '?'} carries a real PNG ($pngLen chars)');
  check((st['body'] as String).contains('snapshot captured'),
      'sent pane shows the snapshot line');

  // 5. tab memory: close + reopen SAME element -> Arxa restored.
  await js(tab, "$sr.querySelector('#chead .tab[data-tab=customise]').click()");
  await Future.delayed(const Duration(milliseconds: 200));
  await js(tab, "$sr.querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 200));
  await js(tab, "$sr.querySelector('#chead .cclose').click()");
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
        "($sr.querySelector('#cidrow .idline') || {}).textContent || ''");
    check(t2.length == 2 && t2[1]['on'] == true &&
        (idlineNow as String).contains(elA['id'] as String),
        'same element restores the Arxa tab after close/reopen (idline: ${idlineNow as String})');
  }

  // 5b. a DIFFERENT element starts on Customise (no cross-element memory).
  // A DIFFERENT element — sibling line-instances share the id ("Spaces
  // for living" splits into two e8 leaves), so exclude A's id outright.
  final elB = await pickLeaf(tab, 0, elA['id'] as String);
  if (elB != null) {
    stdout.writeln('element B: ${elB['id'] as String} @${elB['x']},${elB['y']}');
    // one-focus law (2026-08-26): A still holds the focus — a direct
    // click on B is absorbed. The beat walks the law's door instead:
    // deselect fully, re-arm, then pick.
    await deselectAndRearm(tab);
    await clickAt(tab, elB['x'], elB['y']);
    await Future.delayed(const Duration(milliseconds: 500));
    st = await cardst(tab);
    final t3 = (st['tabs'] as List).cast<Map>();
    final bline = await js(tab,
        "($sr.querySelector('#cidrow .idline') || {}).textContent || '(no idline)'");
    stdout.writeln('B card: open=${st['open']} tabs=${t3.map((t) => t['id'].toString() + (t['on'] == true ? '*' : '')).join(',')} idline=${bline as String}');
    check(t3.length == 2 && t3[0]['on'] == true &&
        !(bline as String).contains(elA['id'] as String),
        'a different element starts on Customise');
  } else {
    stdout.writeln('NOTE  no second clean element; cross-element memory check skipped');
  }

  // 6. a tab click never drags the card.
  final before = await cardst(tab);
  await js(tab, "$sr.querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 200));
  await js(tab, "$sr.querySelector('#chead .tab[data-tab=customise]').click()");
  await Future.delayed(const Duration(milliseconds: 200));
  final after = await cardst(tab);
  check(after['left'] == before['left'] && after['top'] == before['top'],
      'tab clicks never drag the card');

  // Back to element A for the compose flow (its Arxa state is sent).
  final back = await hitFor(tab, elA['id'] as String);
  if (back == null) {
    check(false, 'element A re-hit for the compose flow');
  } else {
    // one-focus law (2026-08-26): B holds the focus here — deselect,
    // re-arm, then return to A through the same door.
    await deselectAndRearm(tab);
    await clickAt(tab, back['x'], back['y']);
  }
  await Future.delayed(const Duration(milliseconds: 500));
  await js(tab, "$sr.querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 300));

  // 7. → composer: island asks, studio inserts (panel dock CLOSED),
  //    chip flashes at the destination, the ack flips the status.
  // DECoy law (2026-08-26 live failure): the operator's studio page
  // carries textareas ABOVE the composer (commit banner in the dock,
  // gen-ui cards) and the insert used to land in the FIRST one — the
  // card said ✓ while the composer stayed empty. A visible decoy,
  // first in DOM order, replicates that page exactly; the insert must
  // land in the real composer (the data-phase SessionInput), never in
  // the decoy.
  await js(gui, '''
    (() => { const d = document.createElement('textarea');
      d.id = 'decoy-ta'; d.placeholder = 'decoy';
      d.style.cssText = 'position:fixed;top:8px;left:8px;width:140px;' +
        'height:32px;z-index:2147483000';
      document.body.prepend(d); return true; })()
  ''');
  await js(tab, '''    (() => { const b = [...$sr.querySelectorAll('#cfoot button')]
      .find((x) => (x.textContent || '').trim() === '→ composer');
      if (b) b.click(); return !!b; })()
  ''');
  final lineOk = await poll(gui, '''
    (() => { const ta = [...document.querySelectorAll('textarea')]
        .find((t) => t.hasAttribute('data-phase'));
      const decoy = document.getElementById('decoy-ta');
      const decoyClean = !decoy || (decoy.value || '').indexOf('design selection') < 0;
      return !!(ta && (ta.value || '').indexOf('design selection') >= 0 && decoyClean); })()
  ''', const Duration(seconds: 12));
  check(lineOk,
      'pointer line inserted in the REAL composer (data-phase), decoy untouched');
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
  final ackOk = await poll(tab, '''    (() => { const s = ($sr.querySelector('.tabpane.on .arxastatus') || {}).textContent || '';
      return s.indexOf('inserted into the composer') >= 0; })()
  ''', const Duration(seconds: 6));
  check(ackOk, 'the ack loop flips the Arxa tab to a VERIFIED ✓');

  // 7b. Fixed dimensions law (operator, 2026-08-26): the card is a
  //     CONSTANT size — min(440px, 62vh) tall — no matter which tab or
  //     how much content; the body alone scrolls inside it.
  Future<Map> cardDims() async {
    final raw = await js(tab, '''      (() => { const c = $sr.getElementById('card');
        const b = c.querySelector('.cbody');
        return JSON.stringify({ h: Math.round(c.getBoundingClientRect().height),
          expect: Math.min(440, Math.round(window.innerHeight * 0.62)),
          scrolls: b.scrollHeight > b.clientHeight + 4 }); })()
    ''');
    return jsonDecode(raw as String) as Map;
  }
  final dmA = await cardDims();
  check(dmA['h'] == dmA['expect'],
      'card height is FIXED at min(440px,62vh) on the Arxa tab (got ${dmA['h']}, want ${dmA['expect']})');
  await js(tab, "$sr.querySelector('#chead .tab[data-tab=customise]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  final dmC = await cardDims();
  check(dmC['h'] == dmA['h'], 'card height is constant across tabs');
  check(dmC['scrolls'] == true,
      'the card body scrolls (Customise content exceeds the fixed body)');
  await js(tab, "$sr.querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 300));

  // Evidence: the Arxa tab sent state at 2x, plus the studio composer.
  Future<List<int>> clipCard() async {
    final rect = await js(tab, '''      (() => { const r = $sr.getElementById('card').getBoundingClientRect();
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
  File('$evDir/arxa-tab-sent-2x.png').writeAsBytesSync(await clipCard());
  File('$evDir/arxa-tab-studio-insert-1280.png').writeAsBytesSync(await gui.screenshot());
  stdout.writeln('evidence: $evDir');

  // 7c. Legacy bridge (version-skew law): an island bundle older than
  //     the tabbed card — a stale design tab — asks by POSTing
  //     /selection WITHOUT the v:2 marker. The new panel must still
  //     deliver line + snapshot to the composer directly (the green
  //     card that used to confirm it is retired).
  final legacyId = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/selection', { method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key: 'el:legacy-probe',
          label: 'legacy probe element', route: '/',
          png: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' }) });
      const j = await r.json(); return j.id || null; })()
  ''');
  check(legacyId is String && (legacyId as String).isNotEmpty,
      'legacy selection registered (no v marker)');
  final lid = legacyId is String ? legacyId as String : 'zzz';
  final legacyLine = await poll(gui, '''
    (() => { const ta = [...document.querySelectorAll('textarea')]
        .find((t) => t.hasAttribute('data-phase'));
      const decoy = document.getElementById('decoy-ta');
      const decoyClean = !decoy || (decoy.value || '').indexOf('LID') < 0;
      return !!(ta && (ta.value || '').indexOf('LID') >= 0 && decoyClean); })()
  '''.replaceAll('LID', lid), const Duration(seconds: 8));
  check(legacyLine,
      'legacy (v-less) selection still lands in the studio composer');

  // 7d. Honest failure: with NO composer mounted in the studio page,
  //     that page's ack carries inserted:false and its chip SAYS so.
  //     Multi-page truth law: every connected studio page acks its own
  //     result — if another open page DID take the insert, the card's
  //     ✓ is true. The strict assertion is therefore on THIS page's
  //     chip (never a fake ✓ from the page that inserted nothing) plus
  //     the card reaching SOME honest terminal state.
  await js(gui, "(() => { [...document.querySelectorAll('textarea')]" '.forEach((t) => t.remove()); return true; })()');
  await js(tab, '''    (() => { const b = [...$sr.querySelectorAll('#cfoot button')]
      .find((x) => (x.textContent || '').trim() === '→ composer');
      if (b) b.click(); return !!b; })()
  ''');
  final chipWarn = await poll(gui, '''
    (() => { const c = document.getElementById('arxa-compose-chip');
      return !!(c && (c.textContent || '').indexOf('no studio composer') >= 0); })()
  ''', const Duration(seconds: 8));
  check(chipWarn,
      'no composer in that studio page → the HONEST warning chip, never a fake ✓ chip');
  final term = await poll(tab, '''    (() => { const s = ($sr.querySelector('.tabpane.on .arxastatus') || {}).textContent || '';
      return s.indexOf('inserted into the composer') >= 0 ||
        s.indexOf('no open composer') >= 0; })()
  ''', const Duration(seconds: 10));
  check(term,
      'the card reaches an honest terminal state (✓ if another studio '
      'page took it, no-composer truth otherwise)');

  // 7e. Reactivity law (operator, 2026-08-26): everything in an OPEN
  //     card tracks the page. An external draft patch (the agent's
  //     path) re-syncs the facets live; an external frame while the
  //     author is mid-edit in the CSS escape hatch may NOT wipe their
  //     unapplied text or steal focus (skip that beat); the next frame
  //     after blur catches the card up.
  await js(tab, "$sr.querySelector('#chead .tab[data-tab=customise]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  Future<String?> swatchOf() async {
    return await js(tab, '''      (() => { const row = [...$sr.querySelectorAll('#card .facet')]
          .find((r) => (r.querySelector('label') || {textContent:''}).textContent === 'background');
        const sw = row && row.querySelector('input[type="color"]');
        return sw ? sw.value : null; })()
    ''') as String?;
  }
  final keyRaw = await js(tab,
      "((($sr.querySelector('#cidrow .idline') || {textContent:''}).textContent || '').split(' → ').pop())");
  final dkey = (keyRaw as String).trim();
  Map? draftDoc;
  Future<bool> patchBackground(String cssColor) async {
    draftDoc = await httpCall('GET', '/__dial/draft', null);
    final draft = ((draftDoc?['draft']) as Map?) ?? {};
    final patches = Map<String, dynamic>.from((draft['patches'] as Map?) ?? {});
    final p = Map<String, dynamic>.from((patches[dkey] as Map?) ?? {});
    final style = Map<String, dynamic>.from((p['style'] as Map?) ?? {});
    style['background'] = cssColor;
    p['style'] = style;
    patches[dkey] = p;
    final put = await httpCall('PUT', '/__dial/draft', {
      'tokens': (draft['tokens'] as Map?) ?? {},
      'patches': patches,
    });
    return put != null && put['ok'] == true;
  }
  check(await patchBackground('rgb(192, 57, 43)'),
      'external draft patch accepted (agent path)');
  // diagnostics for the beat: did the pane re-render at all?
  await js(tab, '''    (() => { window.__rc = 1; window.__rerenders = 0;
      const mo = new MutationObserver(() => { window.__rerenders++; });
      mo.observe($sr.querySelector('.cbody'), { childList: true, subtree: true });
      return true; })()
  ''');
  var sw = await poll(tab, '''    (() => { const row = [...$sr.querySelectorAll('#card .facet')]
        .find((r) => (r.querySelector('label') || {textContent:''}).textContent === 'background');
        const sw = row && row.querySelector('input[type="color"]');
        return !!(sw && sw.value === '#c0392b'); })()
  ''', const Duration(seconds: 8));
  check(sw, 'external restyle: the background swatch re-syncs live');
  if (!sw) {
    final diagInfo = await js(tab, '''      (() => { const row = [...$sr.querySelectorAll('#card .facet')]
          .find((r) => (r.querySelector('label') || {textContent:''}).textContent === 'background');
        const swx = row && row.querySelector('input[type="color"]');
        return JSON.stringify({ canary: window.__rc === 1 ? 'no-reload' : 'RELOADED',
          rerenders: window.__rerenders, swatch: swx ? swx.value : 'no-row',
          cardOpen: $sr.getElementById('card').classList.contains('open') }); })()
    ''');
    stdout.writeln('NOTE  swatch FAIL diagnostics: ${diagInfo ?? 'n/a'}');
  }

  // mid-edit beat: focus the CSS ESCAPE HATCH (the textarea whose
  // placeholder starts 'prop:') with UNAPPLIED text. NEVER the first
  // textarea in the card — that one is the CONTENT editor and its
  // input listener live-writes the element's text into the draft
  // (a probe typing there corrupts the design's text signature).
  final cssTa = "[...$sr.querySelectorAll('#card textarea')].find((t) => (t.placeholder || '').indexOf('prop:') === 0)";
  await js(tab, '''    (() => { const t = $cssTa;
      t.focus(); t.value = 'opacity: .9;'; return !!t; })()
  ''');
  check(await patchBackground('rgb(41, 128, 185)'),
      'second external patch accepted while editing');
  await Future.delayed(const Duration(milliseconds: 1200));
  final guard = await js(tab, '''    (() => { const t = $cssTa;
      const ae = document.getElementById('arxa-dial-host').shadowRoot.activeElement;
      return !!(t && (t.value || '').indexOf('opacity: .9;') >= 0 &&
        ae && ae === t); })()
  ''');
  check(guard == true,
      'mid-edit: unapplied CSS text AND focus survive the external frame');
  if (guard != true) {
    final gdiag = await js(tab, '''      (() => { const t = $cssTa;
        const ae = document.getElementById('arxa-dial-host').shadowRoot.activeElement;
        return JSON.stringify({ text: t ? t.value : null,
          aeTag: ae ? ae.tagName : null }); })()
    ''');
    stdout.writeln('NOTE  guard FAIL diagnostics: ${gdiag ?? 'n/a'}');
  }

  // catch-up beat: blur, one more external frame, the card follows
  await js(tab, "document.activeElement && document.activeElement.blur()");
  check(await patchBackground('rgb(39, 174, 96)'),
      'third external patch accepted after blur');
  sw = await poll(tab, '''    (() => { const row = [...$sr.querySelectorAll('#card .facet')]
        .find((r) => (r.querySelector('label') || {textContent:''}).textContent === 'background');
        const sw = row && row.querySelector('input[type="color"]');
        return !!(sw && sw.value === '#27ae60'); })()
  ''', const Duration(seconds: 8));
  check(sw, 'after blur the next frame catches the card up');

  // 7g. The chip-follows-field law (operator, 2026-08-25 report:
  //     "i changed the background color to green, it changed in the
  //     design but in the floating card background color swatch does
  //     not react and is not in sync"). A color TYPED into the hex
  //     field is the same edit as one picked in the chip: the page
  //     turns green, the field carries the hex — and the CHIP must
  //     follow it, not freeze at its open-time value. Plus the
  //     catch-up half of the reactivity law: a frame skipped because
  //     the author is focused in the card is made up when focus
  //     LEAVES — a suppressed beat may not be dropped forever.
  final bgRow = "[...$sr.querySelectorAll('#card .facet')].find((r) => (r.querySelector('label') || {textContent:''}).textContent === 'background')";
  await js(tab, '''    (() => { const row = $bgRow;
      const f = row && row.querySelector('input[type="text"]');
      if (!f) return false;
      f.focus(); f.value = '#18cd45';
      f.dispatchEvent(new Event('input', { bubbles: true }));
      return true; })()
  ''');
  final kJs = jsonEncode(dkey);
  var chipSync = await poll(tab, '''    (() => { const row = $bgRow;
      const sw = row && row.querySelector('input[type="color"]');
      const f = row && row.querySelector('input[type="text"]');
      const k = $kJs;
      const el = k.indexOf('el:') === 0
        ? document.querySelector('[data-el="' + k.slice(3) + '"]')
        : document.querySelector('[data-arxa-id="' + k + '"]');
      const live = el && getComputedStyle(el).backgroundColor === 'rgb(24, 205, 69)';
      const ae = document.getElementById('arxa-dial-host').shadowRoot.activeElement;
      return !!(live && f && f.value === '#18cd45' && sw && sw.value === '#18cd45'
        && ae === f); })()
  ''', const Duration(seconds: 8));
  check(chipSync,
      'typed green: page turns, field keeps the hex AND focus, the CHIP follows');
  if (!chipSync) {
    final d7g = await js(tab, '''      (() => { const row = $bgRow;
        const sw = row && row.querySelector('input[type="color"]');
        const f = row && row.querySelector('input[type="text"]');
        const ae = document.getElementById('arxa-dial-host').shadowRoot.activeElement;
        return JSON.stringify({ field: f ? f.value : null,
          chip: sw ? sw.value : null, focus: ae ? ae.type : null }); })()
    ''');
    stdout.writeln('NOTE  chip-sync FAIL diagnostics: ${d7g ?? 'n/a'}');
  }

  // catch-up half: an external frame arriving while the author is in
  // the hex field is skipped (the guard); BLUR must make it up.
  await patchBackground('rgb(142, 68, 173)');
  await Future.delayed(const Duration(milliseconds: 1200));
  final guardField = await js(tab, '''    (() => { const row = $bgRow;
      const f = row && row.querySelector('input[type="text"]');
      return !!(f && f.value === '#18cd45'); })()
  ''');
  check(guardField == true,
      'mid-edit in the hex field: the external frame does not wipe it');
  await js(tab, '''
    (() => { const s = document.getElementById('arxa-dial-host').shadowRoot;
      if (s.activeElement) s.activeElement.blur(); return true; })()
  ''');
  final caughtUp = await poll(tab, '''    (() => { const row = $bgRow;
      const sw = row && row.querySelector('input[type="color"]');
      return !!(sw && sw.value === '#8e44ad'); })()
  ''', const Duration(seconds: 8));
  check(caughtUp,
      'after blur the SKIPPED frame catches the chip up (#8e44ad)');

  // 7h. The picker-persistence law (operator, 2026-08-25 23:21
  //     screenshots: red picked in the NATIVE picker — chip red while
  //     the picker is open, page red — "as soon as the color picker
  //     disappears the swatch becomes black again"). The picker writes
  //     a HEX string into the patch; closing it blurs the chip, the
  //     focusout catch-up re-renders, and the re-render MUST still
  //     show the picked color. (Pixel-evidence: chip (255,0,17) open
  //     → (0,0,0) closed.) The input[type=color] contract (MDN): an
  //     invalid or empty value renders as #000000 — so feeding it an
  //     unparsed value is indistinguishable from black.
  await js(tab, '''    (() => { const row = $bgRow;
      const sw = row && row.querySelector('input[type="color"]');
      if (!sw) return false;
      sw.focus(); sw.value = '#ff0000';
      sw.dispatchEvent(new Event('input', { bubbles: true }));
      return true; })()
  ''');
  var pickLive = await poll(tab, '''    (() => { const row = $bgRow;
      const sw = row && row.querySelector('input[type="color"]');
      const f = row && row.querySelector('input[type="text"]');
      const k = $kJs;
      const el = k.indexOf('el:') === 0
        ? document.querySelector('[data-el="' + k.slice(3) + '"]')
        : document.querySelector('[data-arxa-id="' + k + '"]');
      return !!(sw && sw.value === '#ff0000' && f && f.value === '#ff0000' &&
        el && getComputedStyle(el).backgroundColor === 'rgb(255, 0, 0)'); })()
  ''', const Duration(seconds: 8));
  check(pickLive,
      'picker pick: chip + field + page all red while the pick is live');
  // the picker close, REAL path: closing the picker ends the edit,
  // the 700ms save debounce PUTs the draft, the SSE echo is swallowed
  // by the own-save window and its DEFERRED recheck runs syncRemoteDraft
  // ~1.6s later → refreshOpenCard re-renders the facets. THAT re-render
  // is where the operator's chip went black — bare blur alone re-renders
  // nothing (no pending beat), so the beat must ride the save echo.
  await js(tab, '''    (() => { const row = $bgRow;
      const sw = row && row.querySelector('input[type="color"]');
      if (sw) sw.blur(); return true; })()
  ''');
  var storeHex = false;
  {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      final doc = await httpCall('GET', '/__dial/draft', null);
      final v = ((((doc?['draft']) as Map?)?['patches'] as Map?)?[dkey]
          as Map?)?['style'];
      if (v is Map && v['background'] == '#ff0000') { storeHex = true; break; }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }
  check(storeHex,
      'the picked HEX reached the draft store (the echo path is armed)');
  // let the deferred recheck fire and re-render; the chip must STILL
  // be the picked red afterwards
  await Future.delayed(const Duration(milliseconds: 3500));
  final pickStays = await poll(tab, '''    (() => { const row = $bgRow;
      const sw = row && row.querySelector('input[type="color"]');
      return !!(sw && sw.value === '#ff0000'); })()
  ''', const Duration(seconds: 6));
  check(pickStays,
      'picker closed: the chip KEEPS the picked color through the save-echo re-render');
  if (!pickStays) {
    final d7h = await js(tab, '''      (() => { const row = $bgRow;
        const sw = row && row.querySelector('input[type="color"]');
        const f = row && row.querySelector('input[type="text"]');
        return JSON.stringify({ chip: sw ? sw.value : null,
          field: f ? f.value : null }); })()
    ''');
    stdout.writeln('NOTE  picker-persist FAIL diagnostics: ${d7h ?? 'n/a'}');
  }
  // 7i. The hunt-freeze law (operator, 2026-08-25): in Edit Mode, the
  //     cursor's selection hunting STOPS once an element is selected —
  //     focus belongs to the selected element (amber outline + card);
  //     a second highlight chasing the cursor is noise. Deselected →
  //     hunting resumes. (MDN pointer-events: hover feedback is the
  //     app's own overlay on its own pointermove listener — nothing
  //     platform-side forces it.)
  final hoverJs = "$sr.querySelector('#hover')";
  Future<String?> hoverState() async {
    return await js(tab, '''      (() => { const hv = $hoverJs;
        if (!hv) return 'no-el';
        const cs = getComputedStyle(hv);
        return cs.display + '|' + ((hv.firstChild || {}).textContent || ''); })()
    ''') as String?;
  }
  // a DIFFERENT visible stamped element to sweep the cursor over
  final sweepPt = await js(tab, '''    (() => { const selKey = $kJs;
      const els = [...document.querySelectorAll('[data-arxa-id]')];
      for (const el of els) {
        const id = el.getAttribute('data-arxa-id');
        const me = selKey.indexOf('el:') === 0
          ? el.getAttribute('data-el') === selKey.slice(3)
          : id === selKey;
        if (me) continue;
        const r = el.getBoundingClientRect();
        if (r.width > 40 && r.height > 20 && r.top > 10 &&
            r.bottom < innerHeight - 10 && r.left > 10 && r.right < innerWidth - 10) {
          const cx = Math.round(r.left + r.width / 2), cy = Math.round(r.top + r.height / 2);
          const top = document.elementsFromPoint(cx, cy)[0];
          if (top && (top === el || el.contains(top))) {
            return JSON.stringify({ x: cx, y: cy }); } } }
      return null; })()
  ''');
  Map? sweep;
  try { sweep = sweepPt is String ? jsonDecode(sweepPt as String) as Map : null; } catch (_) {}
  check(sweep != null, 'a second stamped element is visible for the hunt-freeze sweep');
  if (sweep != null) {
    await js(tab, "document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape'}))"); // card closed, selection STAYS
    await Future.delayed(const Duration(milliseconds: 400));
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': sweep!['x'] as num, 'y': sweep!['y'] as num});
    await Future.delayed(const Duration(milliseconds: 300));
    final st = (await hoverState()) ?? '?';
    check(st.split('|')[0] == 'none',
        'selected (card closed): cursor sweep does NOT hunt — hover stays hidden (got $st)');
    // deselect fully: second Escape disarms Edit Mode; re-arm it fresh
    await js(tab, "document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape'}))");
    await Future.delayed(const Duration(milliseconds: 400));
    for (var i = 0; i < 5; i++) {
      await tab.send('Input.dispatchMouseEvent',
          {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
      await Future.delayed(const Duration(milliseconds: 80));
    }
    await js(tab, "$sr.querySelector('#dockbtn').click()");
    await Future.delayed(const Duration(milliseconds: 400));
    await js(tab, "$sr.querySelector('[data-verb=edit]').click()");
    await Future.delayed(const Duration(milliseconds: 400));
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': sweep!['x'] as num, 'y': sweep!['y'] as num});
    await Future.delayed(const Duration(milliseconds: 300));
    final st2 = (await hoverState()) ?? '?';
    final parts2 = st2.split('|');
    check(parts2[0] == 'block' &&
        parts2.length > 1 && parts2[1].trim().isNotEmpty,
        'deselected + re-armed: hunting resumes (hover labels the swept element, got $st2)');
  }

  // 7j. The track-back law (operator, 2026-08-26): "i need a icon
  //     button in the floating card top bar to track back to the
  //     selected element even if scrolled or navigated between
  //     pages". Two beats: (a) same page — the element is scrolled
  //     out of view, the button brings it back (both axes: this
  //     design scrolls horizontally); (b) cross-page — a boosted
  //     link swap (hx-boost wipes body children; the island is
  //     off-body and survives) kills the selected ELEMENT while the
  //     card floats on — the button navigates back to the element's
  //     route and restores the selection, centered.
  final cgoJs = "$sr.querySelector('#chead .cgo')";
  // ORACLE LAW (learned the hard way): the inline amber outline is
  // CLOBBERED by the hero animator (node styles churn continuously),
  // so beats read the island's own truth — the card's idline KEY —
  // and resolve the element through targetsForKey semantics.
  if (sweep != null) {
    await clickAt(tab, sweep!['x'] as num, sweep!['y'] as num);
    await Future.delayed(const Duration(milliseconds: 800));
  }
  final keyRaw2 = await js(tab, '''    (() => ((($sr.querySelector('#cidrow .idline') ||
      {textContent:''}).textContent || '').split(' → ').pop()) || null)()
  ''');
  final skey = ((keyRaw2 as String?) ?? '').trim();
  final keyJs = jsonEncode(skey);
  final cardSel = await poll(tab, '''    (() => { const c = $sr.getElementById('card');
      const t = ((c && c.classList.contains('open')
        ? $sr.querySelector('#cidrow .idline') : null) || {textContent:''}).textContent || '';
      return !!(c && c.classList.contains('open') && t && $cgoJs); })()
  ''', const Duration(seconds: 6));
  check(cardSel,
      'element selected by a real click; the card carries the track-back button (.cgo) [key $skey]');
  if (cardSel && skey.isNotEmpty) {
    // (a) same page: scroll the element off-screen — through the
    // PAGE'S OWN SCROLLER (a Lenis-style lerp owns the wheel here and
    // fights bare scrollTop writes; real wheel events are its native
    // path). Then the button must bring the element back.
    for (var wi = 0; wi < 8; wi++) {
      await tab.send('Input.dispatchMouseEvent', {
        'type': 'mouseWheel', 'x': 640, 'y': 400,
        'deltaX': 0, 'deltaY': 2500});
      await Future.delayed(const Duration(milliseconds: 220));
    }
    final awayState = await js(tab, '''      (() => { const k = $keyJs;
        const insts = k.indexOf('el:') === 0
          ? document.querySelectorAll('[data-el="' + k.slice(3) + '"]')
          : document.querySelectorAll('[data-arxa-id="' + k + '"]');
        const el = insts[0]; if (!el) return JSON.stringify({ err: 'no-el' });
        const r = el.getBoundingClientRect();
        // the visibility band: the element overlaps the middle 60% of
        // the viewport (a strict midpoint == center loses to layout
        // drift of a few px)
        const vis = r.top <= innerHeight * 0.7 && r.bottom >= innerHeight * 0.3;
        return JSON.stringify({ off: !vis, top: Math.round(r.top),
          st: Math.round((document.scrollingElement || {}).scrollTop || 0) }); })()
    ''') as String?;
    Map? away;
    try { away = awayState != null ? jsonDecode(awayState) as Map : null; } catch (_) {}
    check(away != null && away!['off'] == true,
        'same page: the selected element is scrolled OUT of view');
    if (away != null && away!['off'] != true) {
      stdout.writeln('NOTE  away diag: $awayState');
    }
    if (away != null && away!['off'] == true) {
      await js(tab, "$cgoJs.click()");
      final backIn = await poll(tab, '''        (() => { const k = $keyJs;
          const insts = k.indexOf('el:') === 0
            ? document.querySelectorAll('[data-el="' + k.slice(3) + '"]')
            : document.querySelectorAll('[data-arxa-id="' + k + '"]');
          const el = insts[0]; if (!el) return false;
          const r = el.getBoundingClientRect();
          return r.top <= innerHeight * 0.7 && r.bottom >= innerHeight * 0.3; })()
      ''', const Duration(seconds: 10));
      check(backIn, 'track-back (same page): the button returns the element to view');
    }
    // (b) cross-page, the REAL operator flow: Edit Mode's capture-phase
    // click handler EATS link clicks while armed (a link click selects
    // the link) — so navigation means DISARM first (the card closes;
    // the live stash keeps the selection), roam to /about, then come
    // BACK: boot or htmx afterSwap restores the selection, centered.
    await js(tab, "$sr.querySelector('#dockbtn').click()");
    await Future.delayed(const Duration(milliseconds: 400));
    await js(tab, "$sr.querySelector('[data-verb=edit]').click()"); // disarm
    await Future.delayed(const Duration(milliseconds: 400));
    await js(tab, '''
      (() => { const link = document.querySelector('a[href="/about"]');
        if (link) link.click(); return !!link; })()
    ''');
    final onAbout = await poll(tab, "location.pathname === '/about'",
        const Duration(seconds: 10));
    check(onAbout, 'cross-page: disarmed and navigated to /about (the disarm closed the card)');
    if (onAbout) {
      // the stash must NOT have restored anything on the wrong route
      final quiet = await js(tab, '''        (() => { const c = $sr.getElementById('card');
          return !!(c && !c.classList.contains('open')); })()
      ''');
      check(quiet == true, 'on the other route nothing chases the author (card stays closed)');
      // the only a[href="/"] on /about is display:none (hover-reveal
      // menu) — navigate home deterministically; the full load rides
      // the BOOT restore path (afterSwap covers the swap path)
      await js(tab, "location.assign('/')");
      // staged poll: names the failing condition instead of a bare
      // false (poll's try/catch once masked a ReferenceError here —
      // hostEl vs host — for a whole debugging round)
      var restored = false;
      var lastStage = 'never';
      {
        final deadline = DateTime.now().add(const Duration(seconds: 14));
        while (DateTime.now().isBefore(deadline)) {
          final stage = await js(tab, '''            (() => { if (location.pathname !== '/') return 'path';
              const hostEl = document.getElementById('arxa-dial-host');
              if (!hostEl || !hostEl.shadowRoot) return 'host';
              const c = hostEl.shadowRoot.getElementById('card');
              if (!c || !c.classList.contains('open')) return 'card';
              const t = ((hostEl.shadowRoot.querySelector('#cidrow .idline') ||
                {textContent:''}).textContent || '').split(' → ').pop();
              if (t !== $keyJs) return 'key:' + t;
              const insts = t.indexOf('el:') === 0
                ? document.querySelectorAll('[data-el="' + t.slice(3) + '"]')
                : document.querySelectorAll('[data-arxa-id="' + t + '"]');
              const el = insts[0]; if (!el) return 'el';
              const r = el.getBoundingClientRect();
              if (!(r.top <= innerHeight * 0.7 && r.bottom >= innerHeight * 0.3))
                return 'band:' + Math.round(r.top) + '/' + Math.round(r.bottom);
              return true; })()
          ''');
          if (stage == true) { restored = true; break; }
          lastStage = (stage ?? 'null').toString();
          await Future.delayed(const Duration(milliseconds: 250));
        }
      }
      if (!restored) stdout.writeln('NOTE  restore poll stuck at: $lastStage');
      check(restored,
          'track-back (cross-page): back home the selection is restored and centered');
      if (!restored) {
        final rdiag = await js(tab, '''          (() => { const hostEl = document.getElementById('arxa-dial-host');
            const sr = hostEl ? hostEl.shadowRoot : null;
            const card = sr ? sr.getElementById('card') : null;
            const idl = sr ? ((sr.querySelector('#cidrow .idline') ||
              {textContent:''}).textContent || '') : '';
            const k = $keyJs;
            const insts = k.indexOf('el:') === 0
              ? document.querySelectorAll('[data-el="' + k.slice(3) + '"]')
              : document.querySelectorAll('[data-arxa-id="' + k + '"]');
            const r = insts[0] ? insts[0].getBoundingClientRect() : null;
            return JSON.stringify({ path: location.pathname,
              stash: sessionStorage.getItem('arxa-dial-trackback'),
              cardOpen: !!(card && card.classList.contains('open')),
              idline: idl.slice(0, 60), n: insts.length,
              rect: r ? { top: Math.round(r.top), h: Math.round(r.height) } : null }); })()
        ''');
        stdout.writeln('NOTE  restore diag: ${rdiag ?? 'n/a'}');
      }
    }
  }

  // 7k. The one-focus law (operator, 2026-08-26): "when selected an
  //     element in edit mode no other element can be selected". The
  //     hunt-freeze law (7i) stopped the cursor's HIGHLIGHT; this
  //     closes the bigger hole the operator still felt — a click (or
  //     double-click) on a different element SWITCHED the selection
  //     outright. While an element holds the focus, gestures on other
  //     elements are absorbed; the only doors to a new selection are a
  //     full deselect (Esc ×2 / tray close) or the element dying in a
  //     swap. Re-clicking the SAME element stays legal — the recovery
  //     path that re-opens a ×-closed card (selection kept, 7i's law).
  {
    // The SELECTED instance's truth is the handles layer: it tracks
    // S.selected.el every frame, and sibling instances share ids, so
    // rects-by-id cannot tell the selected element from its twins (the
    // outline itself is clobbered by the hero animator — 7j's oracle
    // law). The handles' bounding box marks exactly the selected one.
    Future<Map?> handlesCtr() async {
      final raw = await js(tab, '''        (() => { const hs = [...$sr.querySelectorAll('#handles .hnd')];
          if (hs.length < 8) return null;
          const xs = hs.map((x) => parseFloat(x.style.left) || 0);
          const ys = hs.map((y) => parseFloat(y.style.top) || 0);
          return JSON.stringify({
            x: Math.round((Math.min.apply(null, xs) + Math.max.apply(null, xs)) / 2),
            y: Math.round((Math.min.apply(null, ys) + Math.max.apply(null, ys)) / 2) }); })()
      ''');
      if (raw is! String) return null;
      try {
        return jsonDecode(raw) as Map;
      } catch (_) {
        return null;
      }
    }
    Future<String?> curKey() async => ((await js(tab,
            "((($sr.querySelector('#cidrow .idline') || {textContent:''}).textContent || '').split(' → ').pop() || '').trim() || null"))
        as String?);
    Future<bool> cardOpen() async => await js(tab,
            "!!($sr.getElementById('card') || {classList:{contains:function(){return false;}}}).classList.contains('open')") ==
        true;

    final aidRaw = await js(tab, '''      (() => { const k = $keyJs;
        const insts = k.indexOf('el:') === 0
          ? document.querySelectorAll('[data-el="' + k.slice(3) + '"]')
          : document.querySelectorAll('[data-arxa-id="' + k + '"]');
        const el = [...insts].find((x) => x.isConnected);
        return el ? (el.getAttribute('data-arxa-id') || '') : ''; })()
    ''');
    final aid = (aidRaw as String?) ?? '';
    final lockB = aid.isNotEmpty ? await pickLeaf(tab, 0, aid) : null;
    final actr = await handlesCtr();
    if (lockB == null || actr == null) {
      stdout.writeln('NOTE  one-focus preconditions (B=${lockB != null}, handles=${actr != null}); beats skipped');
    } else {
      final bId = lockB!['id'] as String;
      stdout.writeln('one-focus: A=$skey  B=$bId');

      // (1) absorbed switch: A holds the focus, a real click lands on B.
      await clickAt(tab, lockB!['x'] as num, lockB!['y'] as num);
      await Future.delayed(const Duration(milliseconds: 600));
      final k1 = await curKey();
      final open1 = await cardOpen();
      final path1 = await js(tab, 'location.pathname');
      check(k1 == skey && open1 && path1 == '/',
          'one-focus: a click on another element does NOT steal the selection (idline: ${k1 ?? 'none'}, card open=$open1)');

      // (2) a real double-click on B is absorbed the same way — and
      // must NOT start on-canvas typing inside the unselected element.
      await dblClickAt(tab, lockB!['x'] as num, lockB!['y'] as num);
      await Future.delayed(const Duration(milliseconds: 600));
      final k2 = await curKey();
      final bEditing = await js(tab, '''        (() => { const els = document.querySelectorAll('[data-arxa-id="$bId"]');
          for (var i = 0; i < els.length; i++) {
            if (els[i].getAttribute('contenteditable')) return true; }
          return false; })()
      ''');
      check(k2 == skey && bEditing != true,
          'one-focus: a double-click on another element is absorbed — no reselect, no inline typing (idline: ${k2 ?? 'none'}, B editable=$bEditing)');

      // (3) the SAME element stays clickable: × keeps the selection;
      // re-clicking the element is the card's way back.
      final stillOpen3 = await cardOpen();
      if (stillOpen3) {
        await js(tab, "$sr.querySelector('#chead .cclose').click()");
        await Future.delayed(const Duration(milliseconds: 400));
      }
      final handles3 = await js(tab,
          "(() => $sr.querySelectorAll('#handles .hnd').length)()");
      check(handles3 == 8,
          'card closed by ×: the selection (and its 8 handles) STAY');
      final hctr = await handlesCtr();
      if (hctr == null) {
        check(false, 'handles re-readable for the same-element re-click');
      } else {
        await clickAt(tab, hctr!['x'] as num, hctr!['y'] as num);
        await Future.delayed(const Duration(milliseconds: 600));
        final k3 = await curKey();
        final open3 = await cardOpen();
        check(open3 && k3 == skey,
            'one-focus: re-clicking the SAME element re-opens its card (idline: ${k3 ?? 'none'})');
      }

      // (4) the door: full deselect releases the lock — B selects.
      await deselectAndRearm(tab);
      await clickAt(tab, lockB!['x'] as num, lockB!['y'] as num);
      await Future.delayed(const Duration(milliseconds: 600));
      final k4 = await curKey();
      final open4 = await cardOpen();
      check(open4 && k4 != null && k4 != skey,
          'deselected first: B selects freely through the law\'s door (idline: ${k4 ?? 'none'})');

      // hygiene (holds in GREEN and RED worlds alike): end any inline
      // edit, close any card, disarm, and clear the track-back stash —
      // B's selection rewrote it, and a leftover stash would auto-
      // restore on the cleanup reload and break the media beat's
      // fresh-page assumption.
      Map? hst;
      for (var hi = 0; hi < 4; hi++) {
        final st = await js(tab, '''          (() => { const sr = $sr;
            const editing = !!document.querySelector('[data-arxa-id][contenteditable]');
            const card = sr.getElementById('card');
            const open = !!(card && card.classList.contains('open'));
            const verb = sr.querySelector('[data-verb=edit]');
            const armed = !!(verb && verb.classList.contains('on'));
            return JSON.stringify({ editing: editing, open: open, armed: armed }); })()
        ''');
        try {
          hst = st is String ? jsonDecode(st) as Map : null;
        } catch (_) {
          hst = null;
        }
        if (hst == null) break;
        if (hst!['editing'] == true || hst!['open'] == true || hst!['armed'] == true) {
          await js(tab,
              "document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape'}))");
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }
        break;
      }
      await js(tab,
          "try { sessionStorage.removeItem('arxa-dial-trackback'); } catch (e) {} true");
      final stashGone = await js(tab,
          "sessionStorage.getItem('arxa-dial-trackback') === null");
      check(hst != null && hst!['armed'] != true && hst!['open'] != true &&
          hst!['editing'] != true && stashGone == true,
          'one-focus hygiene: disarmed, card closed, stash cleared');
    }
  }
  // cleanup the reactivity beats' patches (probe hygiene law). A
  // shrinking draft converges the live page by RELOAD (the island's
  // law) — wait it out and re-arm the dial for the media beat.
  // __preCleanup canary: survives iff the page NEVER reloaded (the
  // media beat's dock/verb clicks assume a FRESH disarmed page).
  await js(tab, "window.__preCleanup = 1; true");
  await httpCall('GET', '/__dial/draft', null).then((doc) async {
    final draft = ((doc?['draft']) as Map?) ?? {};
    final patches = Map<String, dynamic>.from((draft['patches'] as Map?) ?? {});
    if (patches.remove(dkey) != null) {
      await httpCall('PUT', '/__dial/draft', {
        'tokens': (draft['tokens'] as Map?) ?? {},
        'patches': patches,
      });
    }
  });
  await Future.delayed(const Duration(milliseconds: 2500));
  // re-arm on a possibly-RELOADED page: the island boots async, and the
  // dock button only REVEALS on pointer proximity — wiggle the corner
  // exactly like boot, then wait for it, then click (a click on a null
  // selector arms nothing and the media tap lands on a dead surface).
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  final dockReady = await poll(tab,
      "getComputedStyle($sr.getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 10));
  check(dockReady, 'dial re-armed after the cleanup reload');
  await js(tab, "$sr.querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$sr.querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 2000)); // split-text settle
  String? mediaPick;

  // 7f. One-pick law (operator, 2026-08-26): changing ONE image via the
  //     Media section rewrites exactly THAT image — an anchor whose
  //     instances diverge on src (22 distinct data-el="media-source"
  //     images) is not a homogeneous row. The patch records the picked
  //     instance (attrsNth.src), live apply touches one image, and the
  //     serve-time overlay reproduces the same ONE image after reload.
  await js(tab, '''
    (() => {
      const cands = [...document.querySelectorAll('img[data-el="media-source"]')]
        .filter((m) => { const r = m.getBoundingClientRect();
          return r.width > 30 && r.height > 30; });
      if (!cands.length) return 'none';
      // bring the first candidate fully into view, then hit-test it
      // this design is a HORIZONTAL scroll layout — center on BOTH axes
      cands[0].scrollIntoView({ block: 'center', inline: 'center' });
      return 'scrolled'; })()
  ''');
  await Future.delayed(const Duration(milliseconds: 2200));
  // Pick the click point with the DISPATCH-TARGET law: a synthetic
  // MouseEvent carries clientX/Y 0,0 and the island's picker would
  // select whatever sits at the page corner — the point must hit-test
  // to the IMG itself. A real CDP click at that point does the rest.
  final mediaHit = await js(tab, '''
    (() => { const cands = [...document.querySelectorAll('img[data-el="media-source"]')]
        .filter((m) => { const r = m.getBoundingClientRect();
          return r.width > 30 && r.height > 30 && r.bottom > 60 && r.top < innerHeight - 60; });
      const inVp = (x, y) => x > 10 && x < innerWidth - 10 && y > 10 && y < innerHeight - 10;
      for (const m of cands) {
        const r = m.getBoundingClientRect();
        // sample a GRID across the rect clamped into the viewport —
        // this layout is a horizontal track whose elements straddle the
        // right edge, so the center is often off-screen while the left
        // part is fully visible.
        const xs = [r.x + r.width * 0.25, r.x + r.width * 0.5, r.x + r.width * 0.75];
        const ys = [r.top + r.height * 0.25, r.top + r.height * 0.5, Math.max(r.top, 0) + 60];
        for (const sx of xs) for (const sy of ys) {
          const cx = Math.round(sx), cy = Math.round(sy);
          if (!inVp(cx, cy)) continue;
          if (cx < r.x + 5 || cx > r.right - 5 || cy < r.top + 5 || cy > r.bottom - 5) continue;
          const stack = document.elementsFromPoint(cx, cy);
          const top = stack && stack[0];
          if (top && (top === m || m.contains(top) ||
              (top.closest && top.closest('[data-arxa-id]') === m))) {
            const all = [...document.querySelectorAll('[data-el="media-source"]')];
            return JSON.stringify({ x: cx, y: cy, idx: all.indexOf(m),
              src: m.getAttribute('src') || '' }); } } }
      if (window.__mediaTopDebug === undefined) {
        window.__mediaTopDebug = {
          iw: innerWidth, ih: innerHeight,
          cands: cands.slice(0, 4).map((m) => {
            const r = m.getBoundingClientRect();
            const cx = Math.round(r.x + r.width / 2);
            const cy = Math.round(Math.max(Math.min(r.top + (r.bottom - r.top) * 0.5, innerHeight - 20), 20));
            return { rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
              pt: [cx, cy],
              stack: document.elementsFromPoint(cx, cy).slice(0, 3).map((el) =>
                el.tagName + '[' + (el.getAttribute('data-el') || '') + ']') };
          }) };
      }
      return 'none'; })()
  ''');
  Map? mhit;
  try { mhit = mediaHit is String ? jsonDecode(mediaHit as String) as Map : null; } catch (_) {}
  if (mhit == null) {
    final stackInfo = await js(tab, 'JSON.stringify(window.__mediaTopDebug || [])');
    stdout.writeln('NOTE  media stack tops: ${stackInfo ?? 'n/a'}');
    check(false, 'a visible media-source image was tapped for the one-pick law');
  } else {
    await clickAt(tab, mhit!['x'] as num, mhit!['y'] as num);
    mediaPick = jsonEncode({'idx': mhit!['idx'], 'src': mhit!['src']});
  }
  await Future.delayed(const Duration(milliseconds: 800));
  Map? mpick;
  try { mpick = jsonDecode(mediaPick as String) as Map; } catch (_) {}
  if (mpick == null) {
    check(false, 'a visible media-source image was tapped for the one-pick law');
  } else {
    final midx = mpick!['idx'] as int;
    // card should be open on the media element; From assets → first
    // asset whose path differs from this image's current src
    await js(tab, '''      (() => { const b = [...$sr.querySelectorAll('#card button')]
          .find((x) => (x.textContent || '').trim() === 'From assets');
        if (b) b.click(); return !!b; })()
    ''');
    final assetsReady = await poll(tab, '''      (() => [...$sr.querySelectorAll('#card button')]
          .some((b) => (b.title || '').indexOf('assets/') === 0))()
    ''', const Duration(seconds: 6));
    check(assetsReady, 'From assets listed the artifact assets');
    if (!assetsReady) {
      final mediaDiag = await js(tab, '''        (() => { const d = $sr;
          const card = d.getElementById('card');
          const btns = [...d.querySelectorAll('#card button')]
            .map((b) => (b.textContent || '').trim()).slice(0, 10);
          const dockBtn = d.getElementById('dockbtn');
          return JSON.stringify({ cardOpen: card.classList.contains('open'),
            idline: ((card.querySelector('#cidrow .idline') || {textContent:''}).textContent || '').slice(0, 60),
            kchip: ((card.querySelector('#cidrow .kchip') || {textContent:''}).textContent || '').trim(),
            buttons: btns,
            credit: ((card.querySelector('.idline:not(#cidrow .idline)') || {textContent:''}).textContent || '').slice(0, 60),
            dockMode: dockBtn ? (dockBtn.getAttribute('data-mode') || '') : 'no-dockbtn',
            page: window.__preCleanup === 1 ? 'same-page' : 'reloaded' }); })()
      ''');
      stdout.writeln('NOTE  media section diagnostics: ${mediaDiag ?? 'n/a'}');
    }
    final pickedPath = await js(tab, '''      (() => { const btns = [...$sr.querySelectorAll('#card button')]
          .filter((b) => (b.title || '').indexOf('assets/') === 0);
        const cur = document.querySelectorAll('[data-el="media-source"]')[$midx].getAttribute('src');
        const b = btns.find((x) => x.title !== cur) || btns[0];
        if (b) b.click(); return b ? b.title : null; })()
    ''');
    check(pickedPath is String && (pickedPath as String).isNotEmpty,
        'an asset was picked for one image');
    await Future.delayed(const Duration(milliseconds: 900));
    final wantJs = "const want = '${pickedPath is String ? pickedPath as String : 'zz'}';";
    final counts = await js(tab, '''      (() => { const all = [...document.querySelectorAll('[data-el="media-source"]')];
        $wantJs        return JSON.stringify({ withNew: all.filter((m) => m.getAttribute('src') === want).length,
          total: all.length }); })()
    ''').then((raw) => raw is String ? jsonDecode(raw) as Map : null);
    if (counts == null) {
      check(false, 'one-pick counts readable');
    } else {
      check(counts!['withNew'] == 1,
          'ONE image changed (got ${counts!['withNew']} of ${counts!['total']})');
    }
    // draft carries the instance scoping
    final ddoc = await httpCall('GET', '/__dial/draft', null);
    final patch = (((ddoc?['draft']) as Map?)?['patches'] as Map?)?['el:media-source'];
    Map? attrsNthMap;
    if (patch is Map) {
      final rawNth = (patch as Map)['attrsNth'];
      if (rawNth is Map) attrsNthMap = rawNth;
    }
    final nth = attrsNthMap?['src'];
    check(nth == midx,
        'the patch records the picked instance (attrsNth.src=$nth, want $midx)');
    // reload parity: the overlay must reproduce the SAME one image
    await tab.navigateAndSettleForCapture(dialUrl, settleMs: 3000);
    final counts2 = await js(tab, '''      (() => { const all = [...document.querySelectorAll('[data-el="media-source"]')];
        $wantJs        return all.filter((m) => m.getAttribute('src') === want).length; })()
    ''');
    check(counts2 == 1,
        'after reload the overlay still changes exactly ONE image (got $counts2)');
    // cleanup: the probe never leaves media patches behind
    final ddoc2 = await httpCall('GET', '/__dial/draft', null);
    final draft2 = ((ddoc2?['draft']) as Map?) ?? {};
    final patches2 = Map<String, dynamic>.from((draft2['patches'] as Map?) ?? {});
    if (patches2.remove('el:media-source') != null) {
      await httpCall('PUT', '/__dial/draft', {
        'tokens': (draft2['tokens'] as Map?) ?? {},
        'patches': patches2,
      });
    }
  }

  // 8. both error channels clean, both tabs.
  check(tab.pageErrors.isEmpty && tab.consoleErrors.isEmpty &&
      gui.pageErrors.isEmpty && gui.consoleErrors.isEmpty,
      'zero page + console errors, both tabs (A ${tab.pageErrors.length + tab.consoleErrors.length}, B ${gui.pageErrors.length + gui.consoleErrors.length})');
  for (final e in tab.pageErrors) {
    stdout.writeln('PAGE-A: $e');
  }
  for (final e in gui.pageErrors) {
    stdout.writeln('PAGE-B: $e');
  }
  for (final e in gui.consoleErrors) {
    stdout.writeln('CONSOLE-B: $e');
  }

  await browser.close();
  stdout.writeln(fails == 0 ? 'ALL PASS' : 'FAILURES: $fails');
  exit(fails == 0 ? 0 : 1);
}

// 'design selection sXXXX · ...' -> sXXXX (or null)
String? selIdFrom(Object? raw) {
  if (raw is! String) return null;
  final m = RegExp(r's[0-9a-z]{3,20}').firstMatch(raw);
  return m?.group(0);
}
