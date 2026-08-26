// Four-improvement probe (research slice, 2026-08-25). One Chrome session
// proves all four behaviors on the live server:
//   1. SSE resume  - broadcasts carry id:; a Last-Event-ID reconnect gets
//                    the missed frames replayed + a resync frame (curl,
//                    Dart-side; plus the in-page witness sees ids).
//   2. Float track - the thread popover AND the design card re-derive
//                    their position while open as the page scrolls.
//   3. Keyboard    - the tray track is a focusable region; arrows move
//                    slides; dots are roving-tabindex with aria-current.
//   4. Pin context - the anchored element's text rides the pin: composer
//                    previews it, the thread quotes it, the wire carries it.
//
// PROBE ANCHOR INJECTION. The suczka artifact is scroll-jacked: after its
// intro animation every section is transform-pinned and NOTHING resolves
// to an element that natively scrolls (measured 2026-08-25 - even a
// frame-aware movement probe over a full-viewport grid found zero movers).
// So the tracking proofs pin an INJECTED plain-flow paragraph: normal
// document flow, scrolls with the window by construction, carries both
// data-el and data-arxa-id identity. That tests exactly the island's
// tracking behavior (anchorPoint -> position, rAF-coalesced) without
// depending on the artifact's own scroll exotica. Probe-only DOM; the
// page reloads clean.
//
// Console/page errors fail the probe. DOM asserts carry the verification
// burden (known lens-capture washout; screenshots are evidence, not gate).
//
//   dart run tool/lens_dial_improvements_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
const dialUrl = 'http://127.0.0.1:4319/';
int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}

Future<void> esc(CdpSession tab) async {
  await js(tab,
      "document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape'}))");
  await Future.delayed(const Duration(milliseconds: 250));
}

/// The injected probe anchor (plain flow - scrolls with the window).
const injectJs = '''
  (() => {
    const zone = document.createElement('div');
    zone.id = 'probe-zone';
    zone.setAttribute('data-el', 'probe-zone');
    zone.setAttribute('data-arxa-id', 'probe-zone');
    zone.style.cssText = 'height:2600px;padding:1200px 24px 0;';
    const p = document.createElement('p');
    p.id = 'probe-anchor';
    p.setAttribute('data-el', 'probe-anchor');
    p.setAttribute('data-arxa-id', 'probe-card-anchor');
    p.textContent = 'probe anchor paragraph for float tracking verification';
    p.style.cssText = 'font-size:22px;margin:0;';
    zone.appendChild(p);
    document.body.appendChild(zone);
    p.scrollIntoView({block: 'center'});
    const r = p.getBoundingClientRect();
    return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2),
            idx: [...document.querySelectorAll('[data-arxa-id]')].indexOf(p)};
  })()
''';

/// Thread position probe: popover style top, the anchor's rect top,
/// viewport height - before/after deltas prove tracking.
const threadPosJs = '''
  (() => ({
    t: parseFloat(SRMARK.querySelector('#thread').style.top) || 0,
    a: document.querySelector('[data-el="probe-anchor"]').getBoundingClientRect().top,
    ih: innerHeight,
  }))()
''';

/// Card position probe, against the injected anchor's data-arxa-id.
const cardPosJs = '''
  (() => ({
    t: parseFloat(SRMARK.querySelector('#card').style.top) || 0,
    h: SRMARK.querySelector('#card').offsetHeight,
    a: document.querySelector('[data-arxa-id="probe-card-anchor"]').getBoundingClientRect().top,
    ih: innerHeight,
  }))()
''';

/// Window-scroll delta helper for the tracking measurements.
const scrollJs = '''
  ((px) => {
    const b = scrollY;
    scrollBy(0, px);
    return Math.round(scrollY - b);
  })
''';
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture(dialUrl, settleMs: 2500);

  // In-page SSE witness: every dial frame with its id (improvement 1).
  await js(tab, '''
    window.__probeFrames = [];
    (() => {
      const es = new EventSource('/__dial/events');
      es.addEventListener('dial', (ev) => {
        window.__probeFrames.push((ev.lastEventId || '0') + '|' + ev.data);
      });
    })()
  ''');

  // ---- corner reveal -> dock, exactly as the author does it.
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  await js(tab, "$sr.querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));

  // ---- inject the probe anchor and bring it to center stage.
  final anchor = await js(tab, injectJs);
  await Future.delayed(const Duration(milliseconds: 400));
  if (anchor is! Map) {
    check(false, 'probe anchor injected');
  } else {
    final ax = (anchor['x'] as num).toInt(), ay = (anchor['y'] as num).toInt();

    // ============ improvement 4: context text rides the pin ==============
    await js(tab, "$sr.querySelector('[data-verb=comment]').click()");
    await Future.delayed(const Duration(milliseconds: 500));
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': ax, 'y': ay});
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mousePressed', 'x': ax, 'y': ay, 'button': 'left', 'clickCount': 1});
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseReleased', 'x': ax, 'y': ay, 'button': 'left', 'clickCount': 1});
    await Future.delayed(const Duration(milliseconds: 600));
    final composerOpen = await js(tab,
        "$sr.querySelector('#composer').classList.contains('open')");
    check(composerOpen == true, 'composer opens on the probe anchor');
    final sawCtx = await js(tab,
        "$sr.querySelector('#composer .ctx') != null");
    check(sawCtx == true, 'composer previews the anchored text');
    await js(tab,
        "$sr.querySelector('#composer textarea').value = 'probe: context rides the pin'");
    await js(tab,
        "$sr.querySelector('#composer button.btn:not(.ghost)').click()");
    await Future.delayed(const Duration(milliseconds: 1200));
    final pinInfo = await js(tab, '''
      (async () => {
        const r = await fetch('/__dial/pins');
        const j = await r.json();
        const p = (j.pins || []).filter(q => (q.body||'').includes('context rides the pin'));
        return p.length ? {text: (p[p.length-1].anchor && p[p.length-1].anchor.text) || '',
                           el: (p[p.length-1].anchor && p[p.length-1].anchor.el) || ''} : null;
      })()
    ''');
    check(pinInfo is Map && (pinInfo['text'] as String).length >= 8,
        'wire carries anchor.text (${pinInfo is Map ? (pinInfo['text'] as String).length : 0} chars)');

    // =============== improvement 2a: the thread tracks scroll ============
    await js(tab, "$sr.querySelector('#pins .pin:last-child').click()");
    await Future.delayed(const Duration(milliseconds: 400));
    final ctxInThread = await js(tab,
        "$sr.querySelector('#thread .ctx') != null");
    check(ctxInThread == true, 'thread quotes the anchored text');

    final tp = threadPosJs.replaceAll('SRMARK', sr);
    final before = await js(tab, tp);
    final moved = await js(tab, '$scrollJs(250)');
    await Future.delayed(const Duration(milliseconds: 500));
    final after = await js(tab, tp);
    if (before is Map && after is Map && moved is num) {
      final dt = (before['t'] as num) - (after['t'] as num);
      final da = (before['a'] as num) - (after['a'] as num);
      final exact = (dt - da).abs() <= 2;
      final clamped = dt >= 100 &&
          (after['t'] as num) <= (after['ih'] as num) - 300 &&
          (after['t'] as num) >= 8;
      check(moved > 100 && da.abs() > 100 && (exact || clamped),
          'thread tracks its anchor on scroll (scrolled ${moved}px, anchor ${da.toStringAsFixed(0)}px, thread ${dt.toStringAsFixed(0)}px${exact ? ', exact' : clamped ? ', clamped at edge' : ', BROKEN'})');
    } else {
      check(false, 'thread position readable before/after scroll');
    }
    await esc(tab);

    // =============== improvement 2b: the card tracks scroll ==============
    // Re-center the anchor first: the thread scroll moved it up 250px.
    await js(tab,
        "document.getElementById('probe-anchor').scrollIntoView({block: 'center'})");
    await Future.delayed(const Duration(milliseconds: 400));
    await js(tab, "$sr.querySelector('[data-verb=edit]').click()");
    await Future.delayed(const Duration(milliseconds: 400));
    final cpt = await js(tab, '''
      (() => {
        const p = document.getElementById('probe-anchor');
        const r = p.getBoundingClientRect();
        return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2)};
      })()
    ''');
    if (cpt is! Map) {
      check(false, 'probe anchor re-centered for the card');
    } else {
      final cx = (cpt['x'] as num).toInt(), cy = (cpt['y'] as num).toInt();
      await tab.send('Input.dispatchMouseEvent',
          {'type': 'mouseMoved', 'x': cx, 'y': cy});
      await tab.send('Input.dispatchMouseEvent',
          {'type': 'mousePressed', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1});
      await tab.send('Input.dispatchMouseEvent',
          {'type': 'mouseReleased', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1});
      await Future.delayed(const Duration(milliseconds: 500));
      final cardOpen = await js(tab,
          "$sr.querySelector('#card').classList.contains('open')");
      check(cardOpen == true, 'card opens on the probe anchor');
      if (cardOpen == true) {
        final cp = cardPosJs.replaceAll('SRMARK', sr);
        final cBefore = await js(tab, cp);
        final cmoved = await js(tab, '$scrollJs(250)');
        await Future.delayed(const Duration(milliseconds: 500));
        final cAfter = await js(tab, cp);
        if (cBefore is Map && cAfter is Map && cmoved is num) {
          final dt = (cBefore['t'] as num) - (cAfter['t'] as num);
          final da = (cBefore['a'] as num) - (cAfter['a'] as num);
          // The card is a DROPDOWN: flip/clamp placement, not pixel-lock.
          // The tracking contract is (a) it re-derives on scroll (the
          // position CHANGES - before this slice it sat frozen at its
          // open-time spot), and (b) it stays fully on screen. Direction
          // may invert when the flip branch trades sides as space opens.
          final rederived = dt.abs() >= 50;
          final onScreen = (cAfter['t'] as num) >= 8 &&
              (cAfter['t'] as num) + (cAfter['h'] as num) <=
                  (cAfter['ih'] as num) - 4;
          check(cmoved > 100 && da.abs() > 100 && rederived && onScreen,
              'card re-derives placement on scroll (scrolled ${cmoved}px, anchor ${da.toStringAsFixed(0)}px, card moved ${dt.toStringAsFixed(0)}px${rederived ? ', repositioned' : ', FROZEN'}${onScreen ? ', on screen' : ', OFF SCREEN'})');
        } else {
          check(false, 'card position readable before/after scroll');
        }
      }
    }
    await esc(tab);
    await esc(tab);
  }

  // ================= improvement 3: keyboard sheet navigation ===========
  await esc(tab);
  await js(tab, "$sr.querySelector('[data-verb=studio]').click()");
  await Future.delayed(const Duration(milliseconds: 700));
  final trackExpr = '''
    (() => {
      const sr = SRMARK;
      const t = sr.querySelector('#track');
      const d = sr.querySelectorAll('.dotbtn');
      return {
        tab: t.tabIndex, role: t.getAttribute('role'),
        label: t.getAttribute('aria-label') || '',
        d0: d.length ? d[0].tabIndex : null,
        d1: d.length > 1 ? d[1].tabIndex : null,
      };
    })()
  ''';
  final trackAttrs = await js(tab, trackExpr.replaceAll('SRMARK', sr));
  check(trackAttrs is Map && trackAttrs['tab'] == 0 && trackAttrs['role'] == 'region',
      'track is a focusable labelled region');
  check(trackAttrs is Map && trackAttrs['d0'] == 0 && trackAttrs['d1'] == -1,
      'dots use roving tabindex (active 0, others -1)');
  final keyRight =
      "SRMARK.querySelector('#track').dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowRight'}))";
  await js(tab, keyRight.replaceAll('SRMARK', sr));
  await Future.delayed(const Duration(milliseconds: 1000));
  final cur1 = await js(tab,
      "$sr.querySelector('.dotbtn[aria-current]') != null ? $sr.querySelector('.dotbtn[aria-current]').getAttribute('data-i') : null");
  check(cur1 == '1', 'ArrowRight moves to slide 2 (aria-current on dot 2)');
  final keyLeft =
      "SRMARK.querySelector('#track').dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowLeft'}))";
  await js(tab, keyLeft.replaceAll('SRMARK', sr));
  await Future.delayed(const Duration(milliseconds: 1000));
  final cur2 = await js(tab,
      "$sr.querySelector('.dotbtn[aria-current]') != null ? $sr.querySelector('.dotbtn[aria-current]').getAttribute('data-i') : null");
  check(cur2 == '0', 'ArrowLeft returns to slide 1');
  await js(tab, "$sr.querySelector('#tclose').click()");
  await Future.delayed(const Duration(milliseconds: 300));

  // ================= improvement 1: SSE ids + Last-Event-ID replay ======
  final framesSeen = await js(tab,
      '(window.__probeFrames || []).filter(f => /^\\d+\\|/.test(f)).length');
  check(framesSeen is num && framesSeen >= 1,
      'in-page EventSource sees numbered frames ($framesSeen)');

  // Dart-side: stream, two mutations, reconnect with Last-Event-ID.
  final sse = await Process.start('curl', ['-sN', '${dialUrl}__dial/events']);
  final lines = <String>[];
  sse.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(lines.add);
  await Future.delayed(const Duration(milliseconds: 800));
  Future<void> postPin(String body) async {
    await Process.run('curl', [
      '-s', '-X', 'POST', '${dialUrl}__dial/pins',
      '-H', 'Content-Type: application/json',
      '-d', jsonEncode({
        'route': '/',
        'viewport': {'w': 1280, 'h': 800},
        'anchor': {
          'el': null,
          'rect': {'x': 10, 'y': 10, 'w': 100, 'h': 20},
        },
        'body': body,
      }),
    ]);
  }

  await postPin('probe: sse replay one');
  await Future.delayed(const Duration(milliseconds: 400));
  await postPin('probe: sse replay two');
  await Future.delayed(const Duration(milliseconds: 600));
  sse.kill();
  final ids = lines
      .where((l) => l.startsWith('id: '))
      .map((l) => int.tryParse(l.substring(4)))
      .whereType<int>()
      .toList();
  check(ids.length >= 2,
      'live stream stamped ids on broadcasts (${ids.length})');
  var replayOk = false;
  var replayDetail = 'no ids';
  if (ids.length >= 2) {
    final first = ids[ids.length - 2];
    final second = ids.last;
    final replay = await Process.run('curl', [
      '-sN', '--max-time', '4',
      '-H', 'Last-Event-ID: $first',
      '${dialUrl}__dial/events',
    ]);
    final out = (replay.stdout as String?) ?? '';
    final replayedFrame = out.contains('id: $second');
    final resync = out.contains('resumed');
    replayOk = replayedFrame && resync;
    replayDetail = 'replayed id ${replayedFrame ? second.toString() : 'MISSING'}${resync ? ' + resync frame' : ', resync MISSING'}';
  }
  check(replayOk, 'Last-Event-ID reconnect replays missed frames ($replayDetail)');

  // ---- errors (the law: both channels asserted).
  check(tab.pageErrors.isEmpty,
      'page errors none (${tab.pageErrors.length})');
  check(tab.consoleErrors.isEmpty,
      'console clean (${tab.consoleErrors.length})');

  stdout.writeln(
      fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await client.close();
  exit(fails == 0 ? 0 : 1);
}
