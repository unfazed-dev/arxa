// arxa lens style-probe driver: extract a computed-style fingerprint of a URL.
// Navigates, settles, then evaluates one extraction pass over the DOM:
//   meta (scroll metrics), palette buckets, big color blocks with rects/radii,
//   the big-text typographic scale (size/weight/tracking/color per element),
//   fixed chrome, and large media treatment. Prints JSON to stdout.
// Usage:
//   dart run tool/lens_probe_styles.dart <url> [width] [height] [settleMs] [outJson]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:arxa/lens/daemon.dart';

String _js() {
  return r'''
(() => {
  const out = {};
  out.meta = {
    w: window.innerWidth, h: window.innerHeight,
    scrollHeight: document.documentElement.scrollHeight,
    bodyFont: getComputedStyle(document.body).fontFamily,
    bodyBg: getComputedStyle(document.body).backgroundColor,
    bodyColor: getComputedStyle(document.body).color
  };
  const px = (r) => ({ x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) });
  const all = document.querySelectorAll('*');
  const buckets = new Map();
  for (const el of all) {
    const cs = getComputedStyle(el);
    const bg = cs.backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') continue;
    buckets.set(bg, (buckets.get(bg) || 0) + 1);
  }
  out.palette = [...buckets.entries()].sort((a, b) => b[1] - a[1]).slice(0, 14)
    .map(([color, count]) => ({ color, count }));
  const blocks = [];
  const seenKey = new Set();
  for (const el of all) {
    const r = el.getBoundingClientRect();
    if (r.width < 200 || r.height < 140) continue;
    const cs = getComputedStyle(el);
    const bg = cs.backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') continue;
    if (cs.backgroundImage && cs.backgroundImage !== 'none') continue;
    let p = el.parentElement, dup = false;
    while (p && p !== document.body) {
      const pr = p.getBoundingClientRect();
      const pcs = getComputedStyle(p);
      if (pcs.backgroundColor === bg && pr.width >= r.width - 2 && pr.height >= r.height - 2) { dup = true; break; }
      p = p.parentElement;
    }
    if (dup) continue;
    const key = bg + '|' + Math.round(r.width) + 'x' + Math.round(r.height);
    if (seenKey.has(key)) continue;
    seenKey.add(key);
    blocks.push({ tag: el.tagName.toLowerCase(), cls: (el.className || '').toString().slice(0, 40),
      rect: px(r), bg: bg, radius: cs.borderRadius, pad: cs.padding });
  }
  blocks.sort((a, b) => (a.rect.y + a.rect.w * 0.1) - (b.rect.y + b.rect.w * 0.1));
  out.bigBlocks = blocks.slice(0, 44);
  const texts = [];
  for (const el of all) {
    let hasText = false;
    for (const n of el.childNodes) { if (n.nodeType === 3 && n.textContent.trim().length > 1) { hasText = true; break; } }
    if (!hasText) continue;
    const cs = getComputedStyle(el);
    const fs = parseFloat(cs.fontSize);
    if (fs < 18) continue;
    const r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) continue;
    texts.push({ text: el.textContent.trim().slice(0, 42), rect: px(r),
      family: cs.fontFamily.split(',')[0].slice(0, 28), size: Math.round(fs * 10) / 10,
      weight: cs.fontWeight, tracking: cs.letterSpacing, lineH: Math.round(parseFloat(cs.lineHeight) || 0),
      color: cs.color, transform: cs.textTransform, align: cs.textAlign });
  }
  texts.sort((a, b) => (a.rect.y + a.rect.x * 0.05) - (b.rect.y + b.rect.x * 0.05));
  out.bigText = texts.slice(0, 170);
  const fixed = [];
  for (const el of all) {
    const cs = getComputedStyle(el);
    if (cs.position !== 'fixed' && cs.position !== 'sticky') continue;
    const r = el.getBoundingClientRect();
    if (r.width < 60 || r.height < 24 || r.top > 260) continue;
    fixed.push({ tag: el.tagName.toLowerCase(), cls: (el.className || '').toString().slice(0, 40),
      pos: cs.position, rect: px(r), bg: cs.backgroundColor, radius: cs.borderRadius,
      border: cs.border, shadow: cs.boxShadow.slice(0, 60) });
  }
  out.fixedChrome = fixed.slice(0, 10);
  const imgs = [];
  for (const el of document.querySelectorAll('img, video')) {
    const r = el.getBoundingClientRect();
    if (r.width < 160 || r.height < 120) continue;
    const cs = getComputedStyle(el);
    imgs.push({ tag: el.tagName.toLowerCase(), src: (el.currentSrc || el.src || '').slice(0, 70),
      rect: px(r), fit: cs.objectFit, radius: cs.borderRadius, filter: cs.filter.slice(0, 50) });
  }
  imgs.sort((a, b) => a.rect.y - b.rect.y);
  out.media = imgs.slice(0, 22);
  return out;
})()
''';
}

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/lens_probe_styles.dart <url> [width] [height] '
        '[settleMs] [outJson]');
    exit(2);
  }
  final url = argv[0];
  final width = argv.length > 1 ? int.parse(argv[1]) : 1280;
  final height = argv.length > 2 ? int.parse(argv[2]) : 832;
  final settleMs = argv.length > 3 ? int.parse(argv[3]) : 7500;
  final outPath = argv.length > 4 ? argv[4] : '';

  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);
    try {
      await tab.evaluate(
          '(() => { for (const sel of ["#onetrust-accept-btn-handler",'
          " \"button[class*='consent' i]\", \"button[class*='cookie' i]\","
          " \"a[class*='cookie' i]\", \"[class*='accept' i]\"]) {"
          ' const b = document.querySelector(sel); if (b) { b.click(); break; } }'
          ' return true; })()');
      await Future.delayed(const Duration(milliseconds: 600));
    } on CdpException {
      // best effort
    }
    final result = await tab.evaluate(_js());
    final encoder = const JsonEncoder.withIndent('  ');
    final text = encoder.convert(result);
    if (outPath.isNotEmpty) {
      File(outPath).writeAsStringSync(text);
      stdout.writeln('probe -> ' + outPath);
    } else {
      stdout.writeln(text);
    }
  } finally {
    await client.close();
  }
}
