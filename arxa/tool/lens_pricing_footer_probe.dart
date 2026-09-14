// lens_pricing_footer_probe — reproduction probe for the operator's two
// live reports (2026-09-12): (1) on the pricing tier cards the cursor orb
// hides by law (data-cursor-dot -> native dual-tone dot cursor) and the
// complaint is that the dot's OUTLINE vanishes on the white cards; (2) the
// footer LINKS/COMPANY column hovers reportedly do nothing. This probe
// measures, per point: the law's belief (document.__arxaCursor), the
// native-dot tone ratios against the RENDERED surface (hide-layer,
// screenshot, median pixel), the tier hover computed colors under REAL
// CDP input (synthetic events never set :hover), and the footer link
// hover truth: elementFromPoint before/after, matches(':hover'),
// computed color before/after, and a pixel-diff of the link rect.
// Usage:
//   dart run tool/lens_pricing_footer_probe.dart <url> [--width N]
import 'dart:io';
import 'dart:math' as math;

import 'package:arxa/cdp.dart';
import 'package:arxa/lens/pixels.dart' show decodePng;

List<int> parseHex(String h) {
  final b = h.replaceAll('#', '');
  return [int.parse(b.substring(0, 2), radix: 16), int.parse(b.substring(2, 4), radix: 16), int.parse(b.substring(4, 6), radix: 16)];
}

double srgb(int v) {
  final d = v / 255;
  return d <= 0.04045 ? d / 12.92 : math.pow((d + 0.055) / 1.055, 2.4).toDouble();
}

double luminance(List<int> c) => 0.2126 * srgb(c[0]) + 0.7152 * srgb(c[1]) + 0.0722 * srgb(c[2]);

double contrast(List<int> a, List<int> b) {
  final la = luminance(a);
  final lb = luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la < lb ? la : lb;
  return (hi + 0.05) / (lo + 0.05);
}

List<int>? parseColorStr(String? s) {
  if (s == null) return null;
  final hex = RegExp(r'#[0-9a-fA-F]{6}').firstMatch(s);
  if (hex != null) return parseHex(hex.group(0)!);
  final rgb = RegExp(r'rgba?\(([^)]+)\)').firstMatch(s);
  if (rgb != null) {
    final parts = rgb.group(1)!.split(RegExp(r'[\s,/]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 3) {
      return [double.parse(parts[0]).round(), double.parse(parts[1]).round(), double.parse(parts[2]).round()];
    }
  }
  return null;
}

List<int> median5(List<List<int>> s) {
  final r = s.map((c) => c[0]).toList()..sort();
  final g = s.map((c) => c[1]).toList()..sort();
  final b = s.map((c) => c[2]).toList()..sort();
  return [r[2], g[2], b[2]];
}

String hex(List<int> c) => '#' + c.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

Future<void> main(List<String> argv) async {
  var url = argv[0];
  final width = argv.contains('--width') ? int.parse(argv[argv.indexOf('--width') + 1]) : 1280;
  const vh = 832;
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, vh);
    await tab.navigateAndSettle(url, settleMs: 9000);

    final env = await tab.evaluate(r'''
      (() => {
        const root = document.documentElement;
        const cs = getComputedStyle(root);
        return {
          palette: root.getAttribute('data-palette'),
          accent: cs.getPropertyValue('--accent').trim(),
          ink: cs.getPropertyValue('--ink').trim(),
          paper: cs.getPropertyValue('--paper').trim(),
          cursorOn: root.classList.contains('arxa-cursor-on')
        };
      })()
    ''', awaitPromise: false);
    stdout.writeln('ENV palette=' + env['palette'].toString() + ' accent=' + env['accent'].toString() + ' ink=' + env['ink'].toString() + ' paper=' + env['paper'].toString() + ' cursorOn=' + env['cursorOn'].toString());

    String beliefJs(int x, int y) => r'''
      (async () => {
        const x = ''' + x.toString() + r'''; const y = ''' + y.toString() + r''';
        document.dispatchEvent(new MouseEvent('mousemove', { clientX: x, clientY: y }));
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        await new Promise((r) => setTimeout(r, 60));
        const canvas = document.getElementById('cursor-canvas');
        const dot = document.getElementById('cursor-dot');
        const b = document.__arxaCursor || null;
        return {
          surface: b ? b.surface : null,
          state: b ? b.state : null,
          hidden: canvas ? canvas.style.opacity === '0' : null,
          dotOpacity: dot ? dot.style.opacity : null
        };
      })()
''';
    const hideJs = r'''
      (async () => {
        const dot = document.getElementById('cursor-dot');
        const canvas = document.getElementById('cursor-canvas');
        if (dot) dot.style.display = 'none';
        if (canvas) canvas.style.display = 'none';
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        return true;
      })()
''';
    const showJs = r'''
      (async () => {
        const dot = document.getElementById('cursor-dot');
        const canvas = document.getElementById('cursor-canvas');
        if (dot) dot.style.display = '';
        if (canvas) canvas.style.display = '';
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        return true;
      })()
''';

    List<int> surfaceAt(dynamic image, int x, int y) {
      final offs = <List<int>>[
        [x, y],
        [((x + 24) as num).clamp(0, image.width - 1).toInt(), y],
        [((x - 24) as num).clamp(0, image.width - 1).toInt(), y],
        [x, ((y + 24) as num).clamp(0, image.height - 1).toInt()],
        [x, ((y - 24) as num).clamp(0, image.height - 1).toInt()]
      ];
      final samples = offs.map((o) {
        final p = image.getPixel(o[0], o[1]);
        return <int>[p.r.toInt(), p.g.toInt(), p.b.toInt()];
      }).toList();
      return median5(samples);
    }

    // ============ PART A - pricing tier cards ============
    await tab.evaluate(r'''
      (async () => {
        const sec = document.getElementById('pricing');
        if (sec) sec.scrollIntoView({ block: 'center' });
        await new Promise((r) => setTimeout(r, 600));
      })()
''', awaitPromise: true);
    final cards = await tab.evaluate(r'''
      (() => {
        const out = [];
        document.querySelectorAll('.tier-card').forEach((card, i) => {
          const grab = (sel) => {
            const el = card.querySelector(sel);
            if (!el) return null;
            const r = el.getBoundingClientRect();
            return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
          };
          const price = card.querySelector('.tier-price');
          const cta = card.querySelector('.tier-cta');
          out.push({
            i,
            desc: grab('.tier-description'),
            media: grab('.tier-media'),
            cta: grab('.tier-cta'),
            cursor: getComputedStyle(card).cursor.slice(0, 90),
            priceColor: price ? getComputedStyle(price).color : null,
            ctaBg: cta ? getComputedStyle(cta).backgroundColor : null,
            ctaColor: cta ? getComputedStyle(cta).color : null
          });
        });
        return out;
      })()
''', awaitPromise: false);
    final white = [255, 255, 255];
    final coreTone = parseHex('0a0d12');
    for (final entry in (cards as List? ?? [])) {
      final ci = entry as Map;
      stdout.writeln('--- tier #' + ci['i'].toString() + ' computed-cursor="' + ci['cursor'].toString() + '"');
      stdout.writeln('    rest: price=' + ci['priceColor'].toString() + ' ctaBg=' + ci['ctaBg'].toString() + ' ctaColor=' + ci['ctaColor'].toString());
      final pts = <String, Map?>{'desc': ci['desc'] as Map?, 'media': ci['media'] as Map?, 'cta': ci['cta'] as Map?};
      for (final label in ['desc', 'media', 'cta']) {
        final pt = pts[label];
        if (pt == null) continue;
        final x = (pt['x'] as num).toInt();
        final y = (pt['y'] as num).toInt();
        final belief = await tab.evaluate(beliefJs(x, y), awaitPromise: true) as Map?;
        await tab.evaluate(hideJs, awaitPromise: true);
        final png = await tab.screenshot();
        await tab.evaluate(showJs, awaitPromise: true);
        final image = decodePng(png);
        final surf = surfaceAt(image, x, y);
        final ringR = contrast(white, surf);
        final coreR = contrast(coreTone, surf);
        final lawStr = belief == null ? 'null' : (belief['state'] ?? 'null').toString() + '@' + (belief['surface'] ?? 'null').toString() + ' hidden=' + belief['hidden'].toString();
        // OUTLINE gate: the orb reads as an outlined orb iff some tone in
        // the outer band (white ring / dark stroke) clears 3.0 vs the
        // surface. Pre-fix (dual-tone) the outer band is the white ring
        // alone — fails on white/light surfaces (the operator's report).
        final outlineR = ringR > coreR ? ringR : coreR;
        stdout.writeln('    ' + label.padRight(5) + ' @' + x.toString() + ',' + y.toString() + ' pixel=' + hex(surf) + ' law=' + lawStr + ' | WHITE-ring ' + ringR.toStringAsFixed(2) + (ringR >= 3.0 ? ' PASS' : ' FAIL') + '  DARK-tone ' + coreR.toStringAsFixed(2) + (coreR >= 3.0 ? ' PASS' : ' FAIL') + '  OUTLINE-BAND ' + outlineR.toStringAsFixed(2) + (outlineR >= 3.0 ? ' PASS' : ' FAIL'));
      }
      final d = ci['desc'] as Map?;
      if (d != null) {
        final hx = (d['x'] as num).toInt();
        final hy = (d['y'] as num).toInt();
        await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': hx, 'y': hy});
        await Future.delayed(const Duration(milliseconds: 450));
        final hv = await tab.evaluate(r'''
          (() => {
            const el = document.elementFromPoint(''' + hx.toString() + r''', ''' + hy.toString() + r''');
            const card = el ? el.closest('.tier-card') : null;
            const price = card ? card.querySelector('.tier-price') : null;
            const cta = card ? card.querySelector('.tier-cta') : null;
            return {
              hit: el ? el.tagName.toLowerCase() + '.' + (typeof el.className === 'string' ? el.className.split(' ')[0] : '') : null,
              cardHover: card ? card.matches(':hover') : null,
              priceColor: price ? getComputedStyle(price).color : null,
              ctaBg: cta ? getComputedStyle(cta).backgroundColor : null,
              ctaColor: cta ? getComputedStyle(cta).color : null
            };
          })()
''', awaitPromise: false) as Map?;
        final pc = parseColorStr(hv == null ? null : hv['priceColor']?.toString());
        final cb = parseColorStr(hv == null ? null : hv['ctaBg']?.toString());
        final cc = parseColorStr(hv == null ? null : hv['ctaColor']?.toString());
        final priceR = pc != null ? contrast(pc, white) : -1.0;
        final ctaR = cb != null && cc != null ? contrast(cc, cb) : -1.0;
        stdout.writeln('    hover: hit=' + (hv == null ? '?' : hv['hit'].toString()) + ' :hover=' + (hv == null ? '?' : hv['cardHover'].toString()) + ' price=' + (hv == null ? '?' : hv['priceColor'].toString()) + ' vs-white ' + priceR.toStringAsFixed(2) + (priceR >= 4.5 ? ' PASS(4.5)' : ' FAIL(4.5)') + ' | cta ' + (hv == null ? '?' : hv['ctaBg'].toString()) + '/' + (hv == null ? '?' : hv['ctaColor'].toString()) + ' ' + ctaR.toStringAsFixed(2) + (ctaR >= 4.5 ? ' PASS(4.5)' : ' FAIL(4.5)'));
        final shot = await tab.screenshot();
        File('/tmp/pf-tier' + ci['i'].toString() + '-hover.png').writeAsBytesSync(shot);
      }
    }

    // ============ PART B - footer link hover ============
    final fs = await tab.evaluate(r'''
      (async () => {
        window.scrollTo(0, document.documentElement.scrollHeight);
        await new Promise((r) => setTimeout(r, 800));
        const footer = document.querySelector('.site-footer');
        const r = footer.getBoundingClientRect();
        return { top: Math.round(r.top), bottom: Math.round(r.bottom), vh: window.innerHeight, y: Math.round(window.scrollY), docH: document.documentElement.scrollHeight };
      })()
''', awaitPromise: true) as Map? ?? <dynamic, dynamic>{};
    stdout.writeln('FOOTER rect top=' + fs['top'].toString() + ' bottom=' + fs['bottom'].toString() + ' vh=' + fs['vh'].toString() + ' scrollY=' + fs['y'].toString() + '/' + fs['docH'].toString());
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': (width / 2).round(), 'y': 80});
    await Future.delayed(const Duration(milliseconds: 400));
    final beforePng = await tab.screenshot();
    final before = decodePng(beforePng);
    final links = await tab.evaluate(r'''
      (() => {
        const out = [];
        document.querySelectorAll('.site-footer-link').forEach((a) => {
          const r = a.getBoundingClientRect();
          out.push({
            id: a.getAttribute('data-el'),
            x: Math.round(r.left + r.width / 2),
            y: Math.round(r.top + r.height / 2),
            w: Math.round(r.width),
            h: Math.round(r.height),
            color: getComputedStyle(a).color
          });
        });
        const first = document.querySelector('.site-footer-link');
        if (first) {
          const fr = first.getBoundingClientRect();
          const fx = Math.round(fr.left + fr.width / 2);
          const fy = Math.round(fr.top + fr.height / 2);
          out.push({
            id: '__stack',
            stack: document.elementsFromPoint(fx, fy).slice(0, 6).map((e) => e.tagName.toLowerCase() + (typeof e.className === 'string' && e.className ? '.' + e.className.split(' ')[0] : '') + '[pe=' + getComputedStyle(e).pointerEvents + ' z=' + getComputedStyle(e).zIndex + ']').join(' ;; ')
          });
        }
        return out;
      })()
''', awaitPromise: false);
    int diffCount(dynamic a, dynamic b, int x, int y, int w, int h) {
      var n = 0;
      final x0 = ((x - w / 2 - 4) as num).clamp(0, a.width - 1).toInt();
      final x1 = ((x + w / 2 + 4) as num).clamp(0, a.width).toInt();
      final y0 = ((y - h / 2 - 4) as num).clamp(0, a.height - 1).toInt();
      final y1 = ((y + h / 2 + 4) as num).clamp(0, a.height).toInt();
      for (var yy = y0; yy < y1; yy += 2) {
        for (var xx = x0; xx < x1; xx += 2) {
          final pa = a.getPixel(xx, yy);
          final pb = b.getPixel(xx, yy);
          if ((pa.r - pb.r).abs() > 10 || (pa.g - pb.g).abs() > 10 || (pa.b - pb.b).abs() > 10) n++;
        }
      }
      return n;
    }

    final white2 = [255, 255, 255];
    for (final l in (links as List? ?? [])) {
      final m = l as Map;
      if (m['id'] == '__stack') {
        stdout.writeln('FOOTER stack@first-link: ' + m['stack'].toString());
        continue;
      }
      final x = (m['x'] as num).toInt();
      final y = (m['y'] as num).toInt();
      final w = (m['w'] as num).toInt();
      final h = (m['h'] as num).toInt();
      await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
      await Future.delayed(const Duration(milliseconds: 450));
      final hv = await tab.evaluate(r'''
        (() => {
          const el = document.elementFromPoint(''' + x.toString() + r''', ''' + y.toString() + r''');
          const link = el ? el.closest('.site-footer-link') : null;
          return {
            hit: el ? el.tagName.toLowerCase() + '.' + (typeof el.className === 'string' ? el.className.split(' ')[0] : '') : null,
            hover: link ? link.matches(':hover') : false,
            color: link ? getComputedStyle(link).color : null,
            underline: link ? getComputedStyle(link).textDecorationLine : null
          };
        })()
''', awaitPromise: false) as Map?;
      final afterPng = await tab.screenshot();
      final after = decodePng(afterPng);
      final diffs = diffCount(before, after, x, y, w, h);
      final restC = parseColorStr(m['color']?.toString());
      final hovC = parseColorStr(hv == null ? null : hv['color']?.toString());
      // the card surface under the link, measured from the BEFORE shot
      // (palettes may invert light/dark — a hardcoded white basis lies)
      final bgSamples = <List<int>>[
        [x - 14, y - 8], [x + 14, y - 8], [x - 14, y + 8], [x + 14, y + 8], [x, y - 12]
      ].map((o) {
        final px = before.getPixel(o[0].clamp(0, before.width - 1), o[1].clamp(0, before.height - 1));
        return <int>[px.r.toInt(), px.g.toInt(), px.b.toInt()];
      }).toList();
      final surfC = median5(bgSamples);
      final hovR = hovC != null ? contrast(hovC, surfC) : -1.0;
      final changed = restC != null && hovC != null && (restC[0] != hovC[0] || restC[1] != hovC[1] || restC[2] != hovC[2]);
      // AFFORDANCE gate: a hover that leans on color alone must move the
      // rest state by >= 3.0 — accent-~-ink palettes render the color cue
      // invisible (1.14-1.30:1 measured), so the underline carries it.
      final deltaR = restC != null && hovC != null ? contrast(hovC, restC) : -1.0;
      // the affordance passes if the color cue moves >= 3.0 OR a non-color
      // cue (underline) is present on hover (WCAG 1.4.1)
      final underlined = hv != null && hv['underline'] != null && hv['underline'].toString() != 'none';
      final afford = deltaR >= 3.0 || underlined;
      stdout.writeln('LINK ' + m['id'].toString() + ' hit=' + (hv == null ? '?' : hv['hit'].toString()) + ' :hover=' + (hv == null ? '?' : hv['hover'].toString()) + ' rest=' + m['color'].toString() + ' hoverColor=' + (hv == null ? '?' : hv['color'].toString()) + ' changed=' + changed.toString() + ' pixelDiff=' + diffs.toString() + ' hover-vs-surface=' + hex(surfC) + ' ' + hovR.toStringAsFixed(2) + (hovR >= 4.5 ? ' PASS(4.5)' : ' FAIL(4.5)') + ' rest-to-hover ' + deltaR.toStringAsFixed(2) + ' AFFORD ' + (afford ? 'PASS' : 'FAIL') + ' underline=' + (hv == null ? '?' : hv['underline'].toString()));
      if (m['id'].toString().contains('HowItWorks')) {
        File('/tmp/pf-footer-hover.png').writeAsBytesSync(afterPng);
      }
      await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': (width / 2).round(), 'y': 80});
      await Future.delayed(const Duration(milliseconds: 250));
    }
    stdout.writeln('DONE');
  } finally {
    await client.close();
  }
}
