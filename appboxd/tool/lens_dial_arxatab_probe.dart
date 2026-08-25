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

// The agent's patch path: read the draft, hand it back mutated. UTF-8
// body — artifact text carries non-Latin-1 characters and a plain
// write() Latin-1-encodes them into a crash.
Future<Map?> httpCall(String method, String path, Map? body) async {
  final client = HttpClient();
  try {
    final req =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:4319' + path));
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
  await js(tab, '''
    (() => { const b = [...''' + SR + '''.querySelectorAll('#cfoot button')]
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
  final ackOk = await poll(tab, '''
    (() => { const s = (''' + SR + '''.querySelector('.tabpane.on .arxastatus') || {}).textContent || '';
      return s.indexOf('inserted into the composer') >= 0; })()
  ''', const Duration(seconds: 6));
  check(ackOk, 'the ack loop flips the Arxa tab to a VERIFIED ✓');

  // 7b. Fixed dimensions law (operator, 2026-08-26): the card is a
  //     CONSTANT size — min(440px, 62vh) tall — no matter which tab or
  //     how much content; the body alone scrolls inside it.
  Future<Map> cardDims() async {
    final raw = await js(tab, '''
      (() => { const c = ''' + SR + '''.getElementById('card');
        const b = c.querySelector('.cbody');
        return JSON.stringify({ h: Math.round(c.getBoundingClientRect().height),
          expect: Math.min(440, Math.round(window.innerHeight * 0.62)),
          scrolls: b.scrollHeight > b.clientHeight + 4 }); })()
    ''');
    return jsonDecode(raw as String) as Map;
  }
  final dmA = await cardDims();
  check(dmA['h'] == dmA['expect'],
      'card height is FIXED at min(440px,62vh) on the Arxa tab (got ' +
          dmA['h'].toString() + ', want ' + dmA['expect'].toString() + ')');
  await js(tab, SR + ".querySelector('#chead .tab[data-tab=customise]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  final dmC = await cardDims();
  check(dmC['h'] == dmA['h'], 'card height is constant across tabs');
  check(dmC['scrolls'] == true,
      'the card body scrolls (Customise content exceeds the fixed body)');
  await js(tab, SR + ".querySelector('#chead .tab[data-tab=arxa]').click()");
  await Future.delayed(const Duration(milliseconds: 300));

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
  await js(gui, "(() => { [...document.querySelectorAll('textarea')]" +
      '.forEach((t) => t.remove()); return true; })()');
  await js(tab, '''
    (() => { const b = [...''' + SR + '''.querySelectorAll('#cfoot button')]
      .find((x) => (x.textContent || '').trim() === '→ composer');
      if (b) b.click(); return !!b; })()
  ''');
  final chipWarn = await poll(gui, '''
    (() => { const c = document.getElementById('arxa-compose-chip');
      return !!(c && (c.textContent || '').indexOf('no studio composer') >= 0); })()
  ''', const Duration(seconds: 8));
  check(chipWarn,
      'no composer in that studio page → the HONEST warning chip, never a fake ✓ chip');
  final term = await poll(tab, '''
    (() => { const s = (''' + SR + '''.querySelector('.tabpane.on .arxastatus') || {}).textContent || '';
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
  await js(tab, SR + ".querySelector('#chead .tab[data-tab=customise]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  Future<String?> swatchOf() async {
    return await js(tab, '''
      (() => { const row = [...''' + SR + '''.querySelectorAll('#card .facet')]
          .find((r) => (r.querySelector('label') || {textContent:''}).textContent === 'background');
        const sw = row && row.querySelector('input[type="color"]');
        return sw ? sw.value : null; })()
    ''') as String?;
  }
  final keyRaw = await js(tab,
      "(((" + SR + ".querySelector('#cidrow .idline') || {textContent:''}).textContent || '').split(' → ').pop())");
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
  await js(tab, '''
    (() => { window.__rc = 1; window.__rerenders = 0;
      const mo = new MutationObserver(() => { window.__rerenders++; });
      mo.observe(''' + SR + '''.querySelector('.cbody'), { childList: true, subtree: true });
      return true; })()
  ''');
  var sw = await poll(tab, '''
    (() => { const row = [...''' + SR + '''.querySelectorAll('#card .facet')]
        .find((r) => (r.querySelector('label') || {textContent:''}).textContent === 'background');
        const sw = row && row.querySelector('input[type="color"]');
        return !!(sw && sw.value === '#c0392b'); })()
  ''', const Duration(seconds: 8));
  check(sw, 'external restyle: the background swatch re-syncs live');
  if (!sw) {
    final diagInfo = await js(tab, '''
      (() => { const row = [...''' + SR + '''.querySelectorAll('#card .facet')]
          .find((r) => (r.querySelector('label') || {textContent:''}).textContent === 'background');
        const swx = row && row.querySelector('input[type="color"]');
        return JSON.stringify({ canary: window.__rc === 1 ? 'no-reload' : 'RELOADED',
          rerenders: window.__rerenders, swatch: swx ? swx.value : 'no-row',
          cardOpen: ''' + SR + '''.getElementById('card').classList.contains('open') }); })()
    ''');
    stdout.writeln('NOTE  swatch FAIL diagnostics: ' + (diagInfo ?? 'n/a'));
  }

  // mid-edit beat: focus the CSS ESCAPE HATCH (the textarea whose
  // placeholder starts 'prop:') with UNAPPLIED text. NEVER the first
  // textarea in the card — that one is the CONTENT editor and its
  // input listener live-writes the element's text into the draft
  // (a probe typing there corrupts the design's text signature).
  final CSSTA = "[..." + SR + ".querySelectorAll('#card textarea')]" +
      ".find((t) => (t.placeholder || '').indexOf('prop:') === 0)";
  await js(tab, '''
    (() => { const t = ''' + CSSTA + ''';
      t.focus(); t.value = 'opacity: .9;'; return !!t; })()
  ''');
  check(await patchBackground('rgb(41, 128, 185)'),
      'second external patch accepted while editing');
  await Future.delayed(const Duration(milliseconds: 1200));
  final guard = await js(tab, '''
    (() => { const t = ''' + CSSTA + ''';
      const ae = document.getElementById('arxa-dial-host').shadowRoot.activeElement;
      return !!(t && (t.value || '').indexOf('opacity: .9;') >= 0 &&
        ae && ae === t); })()
  ''');
  check(guard == true,
      'mid-edit: unapplied CSS text AND focus survive the external frame');
  if (guard != true) {
    final gdiag = await js(tab, '''
      (() => { const t = ''' + CSSTA + ''';
        const ae = document.getElementById('arxa-dial-host').shadowRoot.activeElement;
        return JSON.stringify({ text: t ? t.value : null,
          aeTag: ae ? ae.tagName : null }); })()
    ''');
    stdout.writeln('NOTE  guard FAIL diagnostics: ' + (gdiag ?? 'n/a'));
  }

  // catch-up beat: blur, one more external frame, the card follows
  await js(tab, "document.activeElement && document.activeElement.blur()");
  check(await patchBackground('rgb(39, 174, 96)'),
      'third external patch accepted after blur');
  sw = await poll(tab, '''
    (() => { const row = [...''' + SR + '''.querySelectorAll('#card .facet')]
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
  final BGROW = "[..." + SR + ".querySelectorAll('#card .facet')]" +
      ".find((r) => (r.querySelector('label') || {textContent:''}).textContent === 'background')";
  await js(tab, '''
    (() => { const row = ''' + BGROW + ''';
      const f = row && row.querySelector('input[type="text"]');
      if (!f) return false;
      f.focus(); f.value = '#18cd45';
      f.dispatchEvent(new Event('input', { bubbles: true }));
      return true; })()
  ''');
  final kJs = jsonEncode(dkey);
  var chipSync = await poll(tab, '''
    (() => { const row = ''' + BGROW + ''';
      const sw = row && row.querySelector('input[type="color"]');
      const f = row && row.querySelector('input[type="text"]');
      const k = ''' + kJs + ''';
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
    final d7g = await js(tab, '''
      (() => { const row = ''' + BGROW + ''';
        const sw = row && row.querySelector('input[type="color"]');
        const f = row && row.querySelector('input[type="text"]');
        const ae = document.getElementById('arxa-dial-host').shadowRoot.activeElement;
        return JSON.stringify({ field: f ? f.value : null,
          chip: sw ? sw.value : null, focus: ae ? ae.type : null }); })()
    ''');
    stdout.writeln('NOTE  chip-sync FAIL diagnostics: ' + (d7g ?? 'n/a'));
  }

  // catch-up half: an external frame arriving while the author is in
  // the hex field is skipped (the guard); BLUR must make it up.
  await patchBackground('rgb(142, 68, 173)');
  await Future.delayed(const Duration(milliseconds: 1200));
  final guardField = await js(tab, '''
    (() => { const row = ''' + BGROW + ''';
      const f = row && row.querySelector('input[type="text"]');
      return !!(f && f.value === '#18cd45'); })()
  ''');
  check(guardField == true,
      'mid-edit in the hex field: the external frame does not wipe it');
  await js(tab, '''
    (() => { const s = document.getElementById('arxa-dial-host').shadowRoot;
      if (s.activeElement) s.activeElement.blur(); return true; })()
  ''');
  final caughtUp = await poll(tab, '''
    (() => { const row = ''' + BGROW + ''';
      const sw = row && row.querySelector('input[type="color"]');
      return !!(sw && sw.value === '#8e44ad'); })()
  ''', const Duration(seconds: 8));
  check(caughtUp,
      'after blur the SKIPPED frame catches the chip up (#8e44ad)');
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
      "getComputedStyle(" + SR + ".getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 10));
  check(dockReady, 'dial re-armed after the cleanup reload');
  await js(tab, SR + ".querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, SR + ".querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 2000)); // split-text settle
  var mediaPick;

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
    stdout.writeln('NOTE  media stack tops: ' + (stackInfo ?? 'n/a'));
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
    await js(tab, '''
      (() => { const b = [...''' + SR + '''.querySelectorAll('#card button')]
          .find((x) => (x.textContent || '').trim() === 'From assets');
        if (b) b.click(); return !!b; })()
    ''');
    final assetsReady = await poll(tab, '''
      (() => [...''' + SR + '''.querySelectorAll('#card button')]
          .some((b) => (b.title || '').indexOf('assets/') === 0))()
    ''', const Duration(seconds: 6));
    check(assetsReady, 'From assets listed the artifact assets');
    if (!assetsReady) {
      final mediaDiag = await js(tab, '''
        (() => { const d = ''' + SR + ''';
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
      stdout.writeln('NOTE  media section diagnostics: ' + (mediaDiag ?? 'n/a'));
    }
    final pickedPath = await js(tab, '''
      (() => { const btns = [...''' + SR + '''.querySelectorAll('#card button')]
          .filter((b) => (b.title || '').indexOf('assets/') === 0);
        const cur = document.querySelectorAll('[data-el="media-source"]')[''' +
        midx.toString() + '''].getAttribute('src');
        const b = btns.find((x) => x.title !== cur) || btns[0];
        if (b) b.click(); return b ? b.title : null; })()
    ''');
    check(pickedPath is String && (pickedPath as String).isNotEmpty,
        'an asset was picked for one image');
    await Future.delayed(const Duration(milliseconds: 900));
    final wantJs = "const want = '" + (pickedPath is String ? pickedPath as String : 'zz') + "';";
    final counts = await js(tab, '''
      (() => { const all = [...document.querySelectorAll('[data-el="media-source"]')];
        ''' + wantJs + '''
        return JSON.stringify({ withNew: all.filter((m) => m.getAttribute('src') === want).length,
          total: all.length }); })()
    ''').then((raw) => raw is String ? jsonDecode(raw) as Map : null);
    if (counts == null) {
      check(false, 'one-pick counts readable');
    } else {
      check(counts!['withNew'] == 1,
          'ONE image changed (got ' + counts!['withNew'].toString() + ' of ' +
          counts!['total'].toString() + ')');
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
        'the patch records the picked instance (attrsNth.src=' +
        nth.toString() + ', want ' + midx.toString() + ')');
    // reload parity: the overlay must reproduce the SAME one image
    await tab.navigateAndSettleForCapture(dialUrl, settleMs: 3000);
    final counts2 = await js(tab, '''
      (() => { const all = [...document.querySelectorAll('[data-el="media-source"]')];
        ''' + wantJs + '''
        return all.filter((m) => m.getAttribute('src') === want).length; })()
    ''');
    check(counts2 == 1,
        'after reload the overlay still changes exactly ONE image (got ' +
        counts2.toString() + ')');
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
