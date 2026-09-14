// arxa lens cursor-probe driver: numeric ground truth for the custom
// cursor. Drives synthetic mousemoves through the page, then reads back
// the dot div's computed style, the ring canvas's z/opacity, and CANVAS
// PIXELS around each probe point (center fill alpha, ring radius, ring
// color) — the same fingerprint for reference and build.
// Tests: consent-button stick, nav-link stick (ink band), hero free air,
// accent free air, follow-lag after a 400px jump, tier-card dot mode,
// footer-pill no-stick. Prints one JSON document to stdout.
// Usage:
//   dart run tool/lens_probe_cursor.dart <url> [width] [height] [settleMs] [outJson]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:arxa/lens/daemon.dart';

// move to a rect center found by a JS element expression
String _moveToExprJs(String expr) {
  return "(() => { const el = (" + expr + "); if (!el) return null; "
      "const r = el.getBoundingClientRect(); "
      "const x = Math.round(r.left + r.width / 2), y = Math.round(r.top + r.height / 2); "
      "window.__ct = [x, y]; "
      "document.dispatchEvent(new MouseEvent('mousemove', { clientX: x, clientY: y, bubbles: true })); "
      "return { x: x, y: y, w: Math.round(r.width), h: Math.round(r.height) }; })()";
}

String _moveToJs() {
  return "(() => { const t = window.__ct; if (!t) return false; "
      "document.dispatchEvent(new MouseEvent('mousemove', { clientX: t[0], clientY: t[1], bubbles: true })); return true; })()";
}

// sample the two cursor visuals around window.__ct
String _sampleJs() {
  return r'''
(() => {
  // the reference renders bare React nodes (no ids); locate both sides by
  // style signature: fixed canvas at z 99997 + fixed 8px round dot at z 99998
  const cv = document.getElementById('cursor-canvas') ||
    [...document.querySelectorAll('canvas')].find(c => {
      const s = getComputedStyle(c);
      return s.position === 'fixed' && s.zIndex === '99997';
    }) || null;
  const dot = document.getElementById('cursor-dot') ||
    [...document.querySelectorAll('div')].find(d => {
      const s = getComputedStyle(d);
      return s.position === 'fixed' && s.zIndex === '99998' && s.width === '8px' && s.borderRadius === '50%';
    }) || null;
  if (!cv || !dot) return { missing: true, canvasFound: !!cv, dotFound: !!dot };
  const t = window.__ct || [0, 0];
  const out = {};
  const dcs = getComputedStyle(dot);
  out.dot = {
    w: dcs.width, h: dcs.height, radius: dcs.borderRadius, z: dcs.zIndex,
    bg: dcs.backgroundColor, opacity: dcs.opacity, transform: dcs.transform,
    transition: dcs.transition.slice(0, 90)
  };
  const ccs = getComputedStyle(cv);
  out.canvas = { z: ccs.zIndex, opacity: ccs.opacity, w: cv.width, h: cv.height };
  out.cursorUnderlying = getComputedStyle(document.body).cursor;
  const scale = cv.width / window.innerWidth || 1;
  const cx = Math.round(t[0] * scale), cy = Math.round(t[1] * scale);
  const R = Math.ceil(120 * scale);
  if (cx - R < 0 || cy - R < 0 || cx + R > cv.width || cy + R > cv.height) {
    out.sample = { clipped: true };
    return out;
  }
  const img = cv.getContext('2d').getImageData(cx - R, cy - R, R * 2, R * 2).data;
  let minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9, count = 0, sumA = 0;
  let centerA = 0, ringA = 0, ringR = -1, ringColor = null, sx = 0, sy = 0;
  for (let y = 0; y < R * 2; y++) {
    for (let x = 0; x < R * 2; x++) {
      const i = (y * R * 2 + x) * 4;
      const a = img[i + 3];
      if (a <= 12) continue;
      count++;
      const dx = x - R, dy = y - R;
      if (dx < minX) minX = dx; if (dx > maxX) maxX = dx;
      if (dy < minY) minY = dy; if (dy > maxY) maxY = dy;
      sumA += a; sx += dx; sy += dy;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < 5 * scale) { if (a > centerA) centerA = a; }
      if (dist > ringR) { ringR = dist; ringA = a; ringColor = [img[i], img[i + 1], img[i + 2]]; }
    }
  }
  out.sample = count === 0 ? { empty: true } : {
    centerFillAlpha: centerA,
    ringOuterRadiusPx: Math.round(((maxX - minX) / 2) / scale * 10) / 10,
    ringEdgeAlpha: ringA,
    ringColor: ringColor,
    paintedPixels: count,
    avgAlpha: Math.round(sumA / count * 10) / 10,
    centroidOffsetPx: Math.round(Math.sqrt((sx / count) * (sx / count) + (sy / count) * (sy / count)) / scale * 10) / 10
  };
  return out;
})()
''';
}

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/lens_probe_cursor.dart <url> [width] [height] '
        '[settleMs] [outJson]');
    exit(2);
  }
  final url = argv[0];
  final width = argv.length > 1 ? int.parse(argv[1]) : 1280;
  final height = argv.length > 2 ? int.parse(argv[2]) : 832;
  final settleMs = argv.length > 3 ? int.parse(argv[3]) : 9500;
  final outPath = argv.length > 4 ? argv[4] : '';
  final result = <String, dynamic>{};

  Future<void> wait(int ms) async => Future.delayed(Duration(milliseconds: ms));

  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);

    // -- T1: consent Accept button (generic button -> sticky ring)
    result['consentAccept'] = await tab.evaluate(_moveToExprJs(
        "[...document.querySelectorAll('button')].find(b => b.textContent.trim().toLowerCase() === 'accept') || null"));
    await wait(1600);
    result['consentAcceptSample'] = await tab.evaluate(_sampleJs());
    // dismiss the banner so it cannot shade later probes
    try {
      await tab.evaluate(
          "(() => { const b = [...document.querySelectorAll('button')].find(b => b.textContent.trim().toLowerCase() === 'reject'); if (b) b.click(); return true; })()");
      await wait(700);
    } on CdpException {
      // best effort
    }

    // -- T2: nav link (inside hero band -> ink, sticks)
    result['navLink'] = await tab.evaluate(_moveToExprJs(
        "document.querySelector('.site-nav-links a') || document.querySelector('header a') || null"));
    await wait(1600);
    result['navLinkSample'] = await tab.evaluate(_sampleJs());

    // -- T3: hero free air (ink band, unstuck)
    await tab.evaluate("window.__ct = [300, 640]");
    await tab.evaluate(_moveToJs());
    await wait(1600);
    result['heroFreeSample'] = await tab.evaluate(_sampleJs());

    // -- T4: accent free air (below hero)
    await tab.evaluate('window.scrollTo(0, 1700)');
    await wait(1400);
    await tab.evaluate("window.__ct = [640, 400]");
    await tab.evaluate(_moveToJs());
    await wait(1600);
    result['accentFreeSample'] = await tab.evaluate(_sampleJs());

    // -- T5: follow lag after a 400px jump (ring centroid vs pointer)
    await tab.evaluate("window.__ct = [240, 400]");
    await tab.evaluate(_moveToJs());
    await wait(180);
    result['lag180ms'] = await tab.evaluate(_sampleJs());
    await wait(900);
    result['lagSettled'] = await tab.evaluate(_sampleJs());

    // -- T6: tier card dot mode (two-phase aim: land the card's true
    // center mid-viewport, clear of the fixed nav, THEN move onto it)
    await tab.evaluate(
        '(() => { const s = document.getElementById("pricing") || document.querySelector("section[id*=pricing i]"); window.scrollTo(0, (s ? s.offsetTop : 8000) + 400); return true; })()');
    await wait(1500);
    result['tierCardAim'] = await tab.evaluate(
        "(() => { const el = document.querySelector('#pricing a[data-cursor-dot], section[id*=pricing i] a[data-cursor-dot]'); if (!el) return null; const r = el.getBoundingClientRect(); const target = Math.round(window.scrollY + r.top + r.height / 2 - window.innerHeight / 2); window.scrollTo(0, target); return { from: Math.round(r.top), to: target }; })()");
    await wait(1600);
    result['tierCard'] = await tab.evaluate(_moveToExprJs(
        "document.querySelector('#pricing a[data-cursor-dot], section[id*=pricing i] a[data-cursor-dot]') || null"));
    await wait(1700);
    result['tierCardSample'] = await tab.evaluate(_sampleJs());
    result['tierCardComputedCursor'] = await tab.evaluate(
        "(() => { const el = document.querySelector('#pricing a[data-cursor-dot], section[id*=pricing i] a[data-cursor-dot]'); return el ? getComputedStyle(el).cursor.slice(0, 140) : null; })()");

    // -- T7: footer pill no-stick (plain ring, footer root is no-stick)
    await tab.evaluate('window.scrollTo(0, document.body.scrollHeight)');
    await wait(1500);
    result['footerPill'] = await tab.evaluate(_moveToExprJs(
        "[...document.querySelectorAll('footer a')].find(a => /book/i.test(a.textContent)) || document.querySelector('footer a') || null"));
    await wait(1700);
    result['footerPillSample'] = await tab.evaluate(_sampleJs());
  } finally {
    await client.close();
  }

  final encoder = const JsonEncoder.withIndent('  ');
  final text = encoder.convert(result);
  if (outPath.isNotEmpty) {
    File(outPath).writeAsStringSync(text);
    stdout.writeln('probe -> ' + outPath);
  } else {
    stdout.writeln(text);
  }
}
