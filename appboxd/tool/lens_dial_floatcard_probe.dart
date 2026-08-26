// Arxa floating smart-card probe (2026-08-26).
//
// Operator spec: "the floating card anchored to its element must also be
// draggable and have the same color gradient as the new arxa studio
// palette (moss green that the dial just won) + remove scrollbar track
// and have the scrollbar thumb blend in the new color scheme"
//
// The floating smart card is Edit Mode's inspector (#card, anchored next
// to the selected element by positionCard + float tracking). This probe
// drives the REAL surfaces only: corner reveal -> fan -> Edit verb ->
// CDP mouse click on a real [data-arxa-id] element.
//
// Assertions:
//   1. clicking a real element opens the floating card
//   2. the card paints the arxa moss gradient (the same ramp the dock
//      card won: 139,165,101 -> 106,133,74 -> 64,80,44)
//   3. the header is a grab handle (cursor law) and a REAL CDP drag
//      moves the card by the dragged delta (clamped), card stays open
//   4. drag overrides the anchor law: a synthetic scroll event (which
//      fires the float tracker) does NOT snap the card back
//   5. reopening on a fresh selection re-anchors (drag pin reset): the
//      position matches the dropdown-anchor math again
//   6. scrollbar law on the card body: track transparent, thumb in the
//      moss family (computed scrollbar-color + sheet webkit rules)
//   7. zero console AND page errors
// Evidence: 2x-clipped dragged card + full page into the client repo.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
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
    await Future.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

const cardSt = '''  JSON.stringify((() => {
    const root = $sr;
    const card = root.getElementById('card');
    const head = root.getElementById('chead');
    const cs = getComputedStyle(card);
    const body = root.querySelector('#card .cbody');
    const bs = body ? getComputedStyle(body) : null;
    const r = card.getBoundingClientRect();
    const hr = head.getBoundingClientRect();
    return {
      open: card.classList.contains('open'),
      grad: (cs.backgroundImage || '').replace(/s+/g, ' '),
      left: Math.round(r.x), top: Math.round(r.y),
      w: Math.round(r.width), h: Math.round(r.height),
      headCursor: getComputedStyle(head).cursor,
      headX: Math.round(hr.x), headY: Math.round(hr.y),
      headW: Math.round(hr.width), headH: Math.round(hr.height),
      scrollColor: bs ? bs.scrollbarColor : '',
      scrollWidth: bs ? bs.scrollbarWidth : '',
      sheetHasCardTrack: root.querySelector('style').textContent
        .includes('#card ::-webkit-scrollbar-track'),
      sheetHasCardThumb: root.querySelector('style').textContent
        .includes('#card ::-webkit-scrollbar-thumb'),
    };
  })())
''';

Future<Map> cardst(CdpSession tab) async =>
    jsonDecode((await js(tab, cardSt)) as String) as Map;

// The selectable-element finder from the snapshot probe: leaf elements
// with real text, fully in view. [skip] drops the first N (to pick a
// second, disjoint element for the re-anchor step).
Future<List<Map>> candidates(CdpSession tab) async {
  final raw = await js(tab, '''
    (() => {
      const els = [...document.querySelectorAll('[data-arxa-id]')];
      const out = [];
      for (const el of els) {
        const t = (el.textContent || '').trim();
        if (!t || t.length < 3 || el.querySelector('[data-arxa-id]')) continue;
        const r = el.getBoundingClientRect();
        if (r.width > 40 && r.height > 12 && r.x >= 0 && r.y >= 0 &&
            r.x + r.width <= innerWidth && r.y + r.height <= innerHeight) {
          out.push({x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2),
            l: r.x, t: r.y, rt: r.right, b: r.bottom, w: r.width, h: r.height});
        }
      }
      return JSON.stringify(out);
    })()
  ''');
  return (jsonDecode(raw as String) as List).cast<Map>();
}

Future<void> clickAt(CdpSession tab, num x, num y) async {
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseMoved', 'x': x, 'y': y});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
}

// Mirror of positionCard's anchor math (the no-pin branch) so the probe
// can prove a reopened card is truly re-anchored, not just "somewhere".
Map anchorExpect(Map el, num cardH, num innerW, num innerH) {
  const W = 300.0, gap = 12.0;
  final ch = cardH.toDouble();
  var x = (el['rt'] as num).toDouble() + gap;
  if (x + W > innerW - 8) x = (el['l'] as num).toDouble() - W - gap;
  if (x < 8) {
    x = math.min(
        math.max(8.0, (el['l'] as num).toDouble()), math.max(8.0, innerW - W - 8));
  }
  var y = (el['t'] as num).toDouble();
  if (y + ch > innerH - 8) y = (el['t'] as num) + (el['h'] as num) - ch;
  y = math.min(math.max(8.0, y), math.max(8.0, innerH - ch - 8));
  return {'x': x, 'y': y};
}

Future<void> main() async {
  final browser = await CdpClient.launch();
  final tab = await browser.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture(dialUrl, settleMs: 2500);

  // Reveal the dial, open the fan, arm Edit.
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

  // 1. open the card on a real element.
  final cands = await candidates(tab);
  if (cands.isEmpty) {
    check(false, 'selectable element in view');
    await browser.close();
    exit(1);
  }
  final elA = cands.first;
  await clickAt(tab, elA['x'], elA['y']);
  await Future.delayed(const Duration(milliseconds: 500));
  var st = await cardst(tab);
  check(st['open'] == true, 'card opens on a real element');

  // 2. the arxa moss gradient (same ramp as the dock card).
  final grad = st['grad'] as String;
  check(grad.contains('linear-gradient') &&
      (grad.contains('139, 165, 101') || grad.contains('139,165,101')) &&
      (grad.contains('106, 133, 74') || grad.contains('106,133,74')) &&
      (grad.contains('64, 80, 44') || grad.contains('64,80,44')),
      'card paints the arxa moss gradient: $grad');

  // 3. drag by the header with the real mouse pipeline.
  check((st['headCursor'] as String).contains('grab'),
      'header is a grab handle: cursor=${st['headCursor'] as String}');
  final before = await cardst(tab);
  // The header is a TAB BAR now (2026-08-26): buttons never start a
  // drag, so the grab point is the free space BETWEEN the tab pair and
  // the × button — computed live, never a magic offset.
  final grabPt = await js(tab, '''    (() => {
      const root = $sr;
      const arxa = root.querySelector('#chead .tab[data-tab=arxa]');
      const close = root.querySelector('#chead .cclose');
      const head = root.getElementById('chead').getBoundingClientRect();
      const tabR = arxa ? arxa.getBoundingClientRect().right : head.x + 26;
      const closeL = close ? close.getBoundingClientRect().left : head.right - 30;
      return JSON.stringify({x: Math.round((tabR + closeL) / 2),
        y: Math.round(head.y + head.height / 2)});
    })()
  ''');
  final gp = jsonDecode(grabPt as String) as Map;
  final gx = (gp['x'] as num), gy = (gp['y'] as num);
  // choose a direction with room so clamping never eats the delta
  final dx = (before['left'] as num) + 140 + (before['w'] as num) + 8 <= 1280 ? 140 : -140;
  final dy = (before['top'] as num) + 90 + (before['h'] as num) + 8 <= 800 ? 90 : -90;
  await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': gx, 'y': gy});
  await Future.delayed(const Duration(milliseconds: 60));
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mousePressed', 'x': gx, 'y': gy, 'button': 'left', 'clickCount': 1});
  // Held-button moves MUST carry button state: a CDP mouseMoved without
  // button/buttons while the mouse is pressed is treated as a hover and
  // never reaches the page as a drag pointermove (found live, 2026-08-26).
  for (var i = 1; i <= 3; i++) {
    await tab.send('Input.dispatchMouseEvent', {
      'type': 'mouseMoved',
      'x': gx + dx * i / 3,
      'y': gy * 1.0 + dy * i / 3,
      'button': 'left',
      'buttons': 1,
    });
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseReleased', 'x': gx + dx, 'y': gy + dy, 'button': 'left', 'clickCount': 1});
  await Future.delayed(const Duration(milliseconds: 350));
  final dragged = await cardst(tab);
  final mdx = (dragged['left'] as num) - (before['left'] as num);
  final mdy = (dragged['top'] as num) - (before['top'] as num);
  check(dragged['open'] == true, 'card stays open through the drag');
  check((mdx - dx).abs() <= 8 && (mdy - dy).abs() <= 8,
      'header drag moves the card by the delta: d=($mdx,$mdy) want=($dx,$dy)');

  // 4. drag overrides the anchor law: fire the float tracker directly.
  await js(tab, 'window.dispatchEvent(new Event("scroll"))');
  await Future.delayed(const Duration(milliseconds: 300));
  final afterScroll = await cardst(tab);
  check(((afterScroll['left'] as num) - (dragged['left'] as num)).abs() <= 2 &&
      ((afterScroll['top'] as num) - (dragged['top'] as num)).abs() <= 2,
      'dropped card does not snap back to its anchor on scroll');

  // 5. a fresh selection re-anchors (pin reset).
  // The click must LAND on the candidate leaf: the TOPMOST arxa
  // element at its center has to BE the candidate — a full-bleed
  // wrapper painting over the center steals the click (its closest()
  // wins) and the card would (correctly) anchor to the wrapper
  // instead. Found live against primitives-e2 (2026-08-26).
  final bRaw = await js(tab, '''
    (() => {
      const els = [...document.querySelectorAll('[data-arxa-id]')];
      const leaves = els.filter((el) => {
        const t = (el.textContent || '').trim();
        if (!t || t.length < 3 || el.querySelector('[data-arxa-id]')) return false;
        const r = el.getBoundingClientRect();
        return r.width > 40 && r.height > 12 && r.x >= 0 && r.y >= 0 &&
          r.x + r.width <= innerWidth && r.y + r.height <= innerHeight;
      });
      for (const el of leaves.slice(1)) {
        const r = el.getBoundingClientRect();
        const cx = r.x + r.width / 2, cy = r.y + r.height / 2;
        const top = document.elementsFromPoint(cx, cy)
          .find((e) => e.hasAttribute && e.hasAttribute('data-arxa-id'));
        if (top === el) {
          return JSON.stringify({x: Math.round(cx), y: Math.round(cy),
            l: r.x, t: r.y, rt: r.right, b: r.bottom, w: r.width, h: r.height,
            id: el.getAttribute('data-arxa-id')});
        }
      }
      return 'null';
    })()
  ''');
  Map? elB;
  if (bRaw == 'null') {
    stdout.writeln('NOTE  no clean second element; re-anchor check skipped');
  } else {
    elB = jsonDecode(bRaw as String) as Map;
  }
  if (elB == null) {
    stdout.writeln('NOTE  no disjoint second element; re-anchor check skipped');
  } else {
    // one-focus law (2026-08-26): elA still holds the focus — a direct
    // click on elB is absorbed. Walk the law's door: deselect fully
    // (Esc closes the card and keeps the selection; a second Esc
    // disarms and clears it), re-arm, then make the fresh selection.
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
    // ALWAYS re-query (7j law): the door added ~2s between the rect
    // capture and this click, and the hero animator translates
    // elements while it runs — the card anchors where the element is
    // AT CLICK TIME, so the expectation must read the LIVE rect.
    final elBRaw = await js(tab, '''      (() => { const el = document.querySelector('[data-arxa-id="${elB['id'] as String}"]');
        if (!el) return 'null';
        const r = el.getBoundingClientRect();
        const cx = r.x + r.width / 2, cy = r.y + r.height / 2;
        const top = document.elementsFromPoint(cx, cy)
          .find((e) => e.hasAttribute && e.hasAttribute('data-arxa-id'));
        if (top !== el) return 'null';
        return JSON.stringify({x: Math.round(cx), y: Math.round(cy),
          l: r.x, t: r.y, rt: r.right, b: r.bottom, w: r.width, h: r.height}); })()
    ''');
    if (elBRaw == 'null') {
      stdout.writeln('NOTE  elB moved under the animator; re-anchor check skipped');
    } else {
      elB = jsonDecode(elBRaw as String) as Map;
      await clickAt(tab, elB['x'], elB['y']);
      await Future.delayed(const Duration(milliseconds: 500));
      final reopened = await cardst(tab);
      final exp = anchorExpect(elB, (reopened['h'] as num) + 2, 1280, 800);
      final okX = ((reopened['left'] as num) - exp['x']).abs() <= 3;
      final okY = ((reopened['top'] as num) - exp['y']).abs() <= 3;
      check(okX && okY,
          'reopening on a fresh selection re-anchors: pos=(${reopened['left']},${reopened['top']}) want=(${exp['x']},${exp['y']})');
    }
  }

  // 6. scrollbar law: no track, moss thumb (computed + sheet).
  final sc = (st['scrollColor'] as String? ?? '');
  final trackGone = sc.endsWith('rgba(0, 0, 0, 0)');
  final thumb = sc.replaceAll(' rgba(0, 0, 0, 0)', '');
  check(trackGone, 'scrollbar track is transparent: $sc');
  check(thumb.contains('43, 54, 29') || thumb.contains('110, 136, 76'),
      'scrollbar thumb blends into the moss scheme: $thumb');
  check(st['scrollWidth'] == 'thin', 'scrollbar-width thin');
  check(st['sheetHasCardTrack'] == true, 'sheet carries the card track rule');
  check(st['sheetHasCardThumb'] == true, 'sheet carries the card thumb rule');

  // Evidence: the dragged card at 2x, plus the full page.
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
  File('$evDir/float-card-dragged-2x.png').writeAsBytesSync(await clipCard());
  File('$evDir/page-with-float-card-1280.png').writeAsBytesSync(await tab.screenshot());
  stdout.writeln('evidence: $evDir');

  // 7. both error channels clean.
  check(tab.pageErrors.isEmpty && tab.consoleErrors.isEmpty,
      'zero page + console errors (${tab.pageErrors.length}+${tab.consoleErrors.length})');

  await browser.close();
  stdout.writeln(fails == 0 ? 'ALL PASS' : 'FAILURES: $fails');
  exit(fails == 0 ? 0 : 1);
}
