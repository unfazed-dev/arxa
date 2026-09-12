// lens_cursor_truth — PIXEL ground-truth audit of the animated cursor
// (2026-09-12, after the operator's screenshots caught two live misses the
// DOM-truth audits structurally could not see): same grid as
// lens_cursor_probe, but at every point the cursor layer is HIDDEN, the
// viewport is screenshotted, the PNG is decoded, and the surface is the
// MEDIAN of five sampled pixels around the point (center + 4 offsets at
// 24px, clamped) — the rendered truth, not the DOM's opinion. The law's
// own belief rides document.__arxaCursor (surface/state/alpha, and
// since cursor law v3 .sampled — true when the surface was read from
// LIVE PIXELS via the media/bg-image sampler) so each row can show
// law-vs-pixels side by side; the element paint stack is dumped at every
// failure so the blind spot is diagnosable, not just countable. A
// SAMPLED media surface is pixel truth — misses there FAIL (the
// NOTE(media) veil excuse only covers media the law could NOT sample).
// Floors are the locked ones vs the PIXEL surface: dot >= 3.0,
// stuck-mix at the reported alpha >= 3.0, idle-mix >= 2.0. Usage:
//   dart run tool/lens_cursor_truth.dart <url> [--palette name] [--width N]
//                                          [--wait-ms N]
import 'dart:io';
import 'dart:math' as math;

import 'package:arxa/cdp.dart';
import 'package:arxa/lens/pixels.dart' show decodePng;

String pad(String s, int n) => s.length >= n ? s.substring(0, n) : s + ' ' * (n - s.length);

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

// law parity (cursor.js mixAt): t is the fraction of the FIRST argument
// (the stroke color) — the stuck blend is the exact paint, not a proxy.
List<int> mixAt(List<int> a, List<int> b, double t) => [
  (a[0] * t + b[0] * (1 - t)).round(),
  (a[1] * t + b[1] * (1 - t)).round(),
  (a[2] * t + b[2] * (1 - t)).round(),
];

List<int>? parseColorStr(String s) {
  final hex = RegExp(r'#[0-9a-fA-F]{6}').firstMatch(s);
  if (hex != null) return parseHex(hex.group(0)!);
  final rgb = RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)').firstMatch(s);
  if (rgb != null) return [int.parse(rgb.group(1)!), int.parse(rgb.group(2)!), int.parse(rgb.group(3)!)];
  return null;
}

List<int> median5(List<List<int>> s) {
  final r = s.map((c) => c[0]).toList()..sort();
  final g = s.map((c) => c[1]).toList()..sort();
  final b = s.map((c) => c[2]).toList()..sort();
  return [r[2], g[2], b[2]];
}

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('usage: dart run tool/lens_cursor_truth.dart <url> [--palette name] [--width N] [--wait-ms N]');
    exit(2);
  }
  var url = argv[0];
  final palette = argv.contains('--palette') ? argv[argv.indexOf('--palette') + 1] : null;
  final width = argv.contains('--width') ? int.parse(argv[argv.indexOf('--width') + 1]) : 1280;
  final waitMs = argv.contains('--wait-ms') ? int.parse(argv[argv.indexOf('--wait-ms') + 1]) : 9000;
  if (palette != null) {
    final sep = url.contains('?') ? '&' : '?';
    url = url + sep + 'palette=' + palette;
  }

  final client = await CdpClient.launch();
  var failures = 0;
  var total = 0;
  try {
    final tab = await client.newTab();
    await tab.enable();
    final vh = width < 500 ? 844 : 832;
    await tab.setViewport(width, vh);
    await tab.navigateAndSettle(url, settleMs: waitMs);

    String moveJs(int x, int y) => r'''
      (async () => {
        const x = ''' + x.toString() + r'''; const y = ''' + y.toString() + r''';
        document.dispatchEvent(new MouseEvent('mousemove', { clientX: x, clientY: y }));
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        await new Promise((r) => setTimeout(r, 60));
        const dot = document.getElementById('cursor-dot');
        const canvas = document.getElementById('cursor-canvas');
        if (!dot || !canvas) return null;
        function parse(v) {
          if (!v) return null;
          let m = /rgba?\(([^)]+)\)/.exec(v);
          if (m) {
            let body = m[1], alpha = 1;
            const slash = body.indexOf('/');
            if (slash >= 0) { alpha = parseFloat(body.slice(slash + 1)); body = body.slice(0, slash); }
            const p = body.split(/[\s,]+/).filter((s) => s.length > 0).map(Number);
            if (p.length < 3 || p.some(isNaN)) return null;
            const a = p.length >= 4 ? p[3] : alpha;
            return [Math.round(p[0]), Math.round(p[1]), Math.round(p[2]), isFinite(a) ? a : 1];
          }
          m = /color\(\s*srgb\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s*(?:\/\s*([0-9.]+))?\s*\)/.exec(v);
          if (m) {
            const f = [parseFloat(m[1]), parseFloat(m[2]), parseFloat(m[3])];
            const ca = m[4] !== undefined ? parseFloat(m[4]) : 1;
            return [Math.round(Math.min(1, Math.max(0, f[0])) * 255), Math.round(Math.min(1, Math.max(0, f[1])) * 255), Math.round(Math.min(1, Math.max(0, f[2])) * 255), isFinite(ca) ? ca : 1];
          }
          return null;
        }
        function hx(c) { return '#' + c.map((v) => Math.round(v).toString(16).padStart(2, '0')).join(''); }
        const state = parse(dot.style.background) || parse(dot.style.backgroundColor);
        const belief = document.__arxaCursor || null;
        // LOCK LAW v3.1: while sticking the law samples (and the ring is
        // drawn) at the target's center — audit THAT position, not the
        // pointer's, or a lock over a big button reads as a mismatch.
        const lawX = belief && typeof belief.lawX === 'number' ? Math.max(0, Math.min(window.innerWidth - 1, Math.round(belief.lawX))) : x;
        const lawY = belief && typeof belief.lawY === 'number' ? Math.max(0, Math.min(window.innerHeight - 1, Math.round(belief.lawY))) : y;
        const stackAll = document.elementsFromPoint(lawX, lawY).filter((e) => !(e.id && e.id.indexOf('cursor-') === 0));
        // media veil: a video/img/canvas/SVG painting ABOVE the DOM surface
        // makes the rendered pixel CONTENT (footage/imagery/vector art —
        // the hiw zoom bloom is an SVG petal), not a paintable surface —
        // the locked contract audits that as NOTE, not FAIL — BUT ONLY
        // when the law did not sample it: cursor law v3 drawImages the
        // img/video at the pointer and keys the actual pixels
        // (belief.sampled), so a SAMPLED media surface is held to the
        // floors like any paint.
        const sampled = !!(belief && belief.sampled);
        const veil = !sampled && stackAll.slice(0, 8).some((e) => ['VIDEO', 'IMG', 'CANVAS', 'PICTURE', 'SVG', 'PATH'].indexOf(e.tagName.toUpperCase()) >= 0);
        const stack = stackAll.slice(0, 6);
        const dump = stack.map((e) => {
          const s = getComputedStyle(e);
          const tag = e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') + (typeof e.className === 'string' && e.className ? '.' + e.className.split(' ').slice(0, 2).join('.') : '');
          return tag + '|bg=' + s.backgroundColor + '|img=' + s.backgroundImage.slice(0, 40) + '|pe=' + s.pointerEvents + '|pos=' + s.position;
        }).join(' ;; ');
        return {
          state: state ? hx(state.slice(0, 3)) : null,
          alpha: parseFloat(dot.dataset.arxaStuckAlpha || '0.55'),
          hidden: canvas.style.opacity === '0' || dot.style.opacity === '0',
          lawSurface: belief ? belief.surface : null,
          lawState: belief ? belief.state : null,
          lawX,
          lawY,
          sampled,
          veil,
          dump,
        };
      })()
''';

    const hideJs = r'''
      (async () => {
        const dot = document.getElementById('cursor-dot');
        const canvas = document.getElementById('cursor-canvas');
        dot.style.display = 'none';
        canvas.style.display = 'none';
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        return true;
      })()
''';
    const showJs = r'''
      (async () => {
        const dot = document.getElementById('cursor-dot');
        const canvas = document.getElementById('cursor-canvas');
        dot.style.display = '';
        canvas.style.display = '';
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        return true;
      })()
''';

    final sections = await tab.evaluate(r'''
      [...document.querySelectorAll('section, footer')].filter((e) => e.getBoundingClientRect().height > 120).slice(0, 16).map((e) => e.id || (typeof e.className === 'string' ? e.className.split(' ')[0] : e.tagName))
    ''', awaitPromise: false);
    final sectionIds = (sections as List? ?? []).map((e) => e.toString()).toList();
    stdout.writeln('sections: ' + sectionIds.join(', '));

    const chr = "'"; // quote constant: keeps the raw script blocks quote-clean
    final xs = [0.2, 0.35, 0.5, 0.65, 0.8];
    final ys = [0.35, 0.5, 0.72];
    var shotOk = 0;
    var shotBad = 0;
    // pinned stages (the 500vh hiw pin, the 250vh stories pin) need
    // PROGRESS sampling: center-scroll only audits the middle of the pin,
    // which is how the final-fifth zoom bloom (the operator's screenshot)
    // stayed unaudited. Steps = (label, id, mode): mode center | progress.
    final steps = <List<String>>[];
    for (final id in sectionIds) {
      steps.add([id, id, 'center']);
      if (id == 'how-it-works') {
        steps.add([id + '@p0.9', id, '0.9']);
        steps.add([id + '@p0.97', id, '0.97']);
      }
      if (id == 'clientstories') {
        steps.add([id + '@p0.15', id, '0.15']);
        steps.add([id + '@p0.85', id, '0.85']);
      }
    }
    for (final step in steps) {
      final id = step[1];
      final mode = step[2];
      await tab.evaluate(r'''
        (async () => {
          const id = ''' + chr + id.replaceAll(chr, '') + chr + r''';
          const mode = ''' + chr + mode + chr + r''';
          const el = document.getElementById(id) || document.querySelector('.' + id) || document.querySelector(id);
          if (el) {
            if (mode === 'center') {
              el.scrollIntoView({ block: 'center' });
            } else {
              const p = parseFloat(mode);
              const rect = el.getBoundingClientRect();
              const top = rect.top + window.scrollY;
              window.scrollTo(0, top + p * Math.max(1, el.offsetHeight - window.innerHeight));
            }
          }
          await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
          await new Promise((r) => setTimeout(r, mode === 'center' ? 280 : 480));
        })()
''', awaitPromise: true);
      for (final fx in xs) {
        for (final fy in ys) {
          final x = (width * fx).round();
          final y = (vh * fy).round();
          total++;
          final info = await tab.evaluate(moveJs(x, y), awaitPromise: true);
          if (info == null || info['state'] == null) continue;
          // LOCK LAW v3.1: decode at the LAW position (lock target center
          // while sticking) — the ring is drawn there, so that is the
          // backdrop the floors must clear against.
          final lx = ((info['lawX'] as num?) ?? x).toInt().clamp(0, width - 1);
          final ly = ((info['lawY'] as num?) ?? y).toInt().clamp(0, vh - 1);
          final hidden = info['hidden'] == true;
          await tab.evaluate(hideJs, awaitPromise: true);
          final png = await tab.screenshot();
          await tab.evaluate(showJs, awaitPromise: true);
          final image = decodePng(png);
          if (image.width < x + 1 || image.height < y + 1) { shotBad++; continue; }
          shotOk++;
          final offs = <List<int>>[
            [lx, ly],
            [(lx + 24).clamp(0, image.width - 1), ly],
            [(lx - 24).clamp(0, image.width - 1), ly],
            [lx, (ly + 24).clamp(0, image.height - 1)],
            [lx, (ly - 24).clamp(0, image.height - 1)],
          ];
          final ring = <List<int>>[
            [(lx + 48).clamp(0, image.width - 1), ly],
            [(lx - 48).clamp(0, image.width - 1), ly],
            [lx, (ly + 48).clamp(0, image.height - 1)],
            [lx, (ly - 48).clamp(0, image.height - 1)],
            [(lx + 34).clamp(0, image.width - 1), (ly + 34).clamp(0, image.height - 1)],
            [(lx - 34).clamp(0, image.width - 1), (ly + 34).clamp(0, image.height - 1)],
            [(lx + 34).clamp(0, image.width - 1), (ly - 34).clamp(0, image.height - 1)],
            [(lx - 34).clamp(0, image.width - 1), (ly - 34).clamp(0, image.height - 1)],
          ];
          final samples = offs.map((o) {
            final p = image.getPixel(o[0], o[1]);
            return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
          }).toList();
          final ringSamples = ring.map((o) {
            final p = image.getPixel(o[0], o[1]);
            return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
          }).toList();
          final pixel = median5(samples);
          final stateC = parseHex(info['state'].toString());
          final alpha = double.parse(info['alpha'].toString());
          final dotR = contrast(stateC, pixel);
          final idleR = contrast(mixAt(stateC, pixel, 0.5), pixel);
          final stuckR = contrast(mixAt(stateC, pixel, alpha), pixel);
          final ok = dotR >= 3.0 && stuckR >= 3.0 && idleR >= 2.0;
          // grain tolerance: the fixed grain overlay shifts rendered pixels
          // ~1-2%, worth about +-0.1 ratio on knife-edge floors. The DOM
          // audit gate stays strict; the PIXEL probe tolerates the shift.
          final okTol = dotR >= 2.9 && stuckR >= 2.9 && idleR >= 1.9;
          var surfaceNote = '';
          final lawSurface = info['lawSurface']?.toString();
          final lawSurfaceC = lawSurface == null ? null : parseColorStr(lawSurface);
          var surfaceAgrees = false;
          var surfaceInRing = false;
          if (lawSurfaceC != null) {
            final agree = contrast(lawSurfaceC, pixel);
            surfaceAgrees = agree < 1.35;
            surfaceInRing = ringSamples.any((s) => contrast(lawSurfaceC, s) < 1.35);
            if (agree < 2.5) surfaceNote = '  SURFACE-MISMATCH(law ' + (lawSurface ?? 'null') + ' vs pixel ' + pixel.join(',') + ' r' + agree.toStringAsFixed(2) + ')';
          }
          final veil = info['veil'] == true;
          // content-overlap: the pixel disagrees with the law's surface only
          // because CONTENT (glyphs, footage) paints over it — the state
          // still clears the floors vs the surface the law actually keyed,
          // AND that surface is still visible in the surrounding ring.
          // That is the reference's own behavior over text/media: NOTE, not
          // FAIL. A phantom-surface miss (paint the walk cannot see — the
          // class the color-mix fix removed) has NO believed-surface color
          // anywhere near the point: that stays FAIL.
          var contentOverlap = veil;
          if (!contentOverlap && lawSurfaceC != null) {
            final ls = lawSurfaceC;
            final stateVsSurface = contrast(stateC, ls) >= 3.0 &&
                contrast(mixAt(stateC, ls, 0.5), ls) >= 2.0 &&
                contrast(mixAt(stateC, ls, alpha), ls) >= 3.0;
            contentOverlap = stateVsSurface && surfaceInRing;
          }
          if (!ok && !hidden) {
            var flag = veil ? 'NOTE(media)' : (contentOverlap ? 'NOTE(content)' : (okTol && surfaceAgrees ? 'NOTE(grain)' : 'FAIL'));
            var dotRs = dotR;
            var idleRs = idleR;
            var stuckRs = stuckR;
            var pixelS = pixel;
            var stateS = info['state'].toString();
            var alphaS = alpha.toStringAsFixed(2);
            var surfaceNoteS = surfaceNote;
            var stackS = info['dump'].toString();
            // settle-and-recheck (DOM-probe parity): a raw FAIL is
            // re-parked once after a settle + 1px jiggle — Lenis eases
            // and hover filter transitions strand stale states at the
            // parked instant; only a FAIL that survives the settle counts.
            if (flag == 'FAIL') {
              await tab.evaluate('(async () => { await new Promise((r) => setTimeout(r, 300)); document.dispatchEvent(new MouseEvent("mousemove", { clientX: ' + (x + 1).toString() + ', clientY: y })); await new Promise((r) => setTimeout(r, 250)); return true; })()', awaitPromise: true);
              final info2 = await tab.evaluate(moveJs(x, y), awaitPromise: true);
              if (info2 != null && info2['state'] != null) {
                await tab.evaluate(hideJs, awaitPromise: true);
                final png2 = await tab.screenshot();
                await tab.evaluate(showJs, awaitPromise: true);
                final image2 = decodePng(png2);
                final lx2 = ((info2['lawX'] as num?) ?? x).toInt().clamp(0, width - 1);
                final ly2 = ((info2['lawY'] as num?) ?? y).toInt().clamp(0, vh - 1);
                final samples2 = offs.map((o) {
                  final px = image2.getPixel(o[0].clamp(0, image2.width - 1) == lx2 ? lx2 : o[0], ly2);
                  return [px.r.toInt(), px.g.toInt(), px.b.toInt()];
                }).toList();
                // re-sample the median at the settled law position
                final mid2 = image2.getPixel(lx2, ly2);
                samples2[0] = [mid2.r.toInt(), mid2.g.toInt(), mid2.b.toInt()];
                final pixel2 = median5(samples2);
                final stateC2 = parseHex(info2['state'].toString());
                final alpha2 = double.parse(info2['alpha'].toString());
                final dotR2 = contrast(stateC2, pixel2);
                final idleR2 = contrast(mixAt(stateC2, pixel2, 0.5), pixel2);
                final stuckR2 = contrast(mixAt(stateC2, pixel2, alpha2), pixel2);
                if (dotR2 >= 3.0 && stuckR2 >= 3.0 && idleR2 >= 2.0) {
                  flag = 'NOTE(settled)';
                }
                dotRs = dotR2;
                idleRs = idleR2;
                stuckRs = stuckR2;
                pixelS = pixel2;
                stateS = info2['state'].toString();
                alphaS = alpha2.toStringAsFixed(2);
                stackS = info2['dump'].toString();
              }
            }
            final isFail = flag == 'FAIL';
            if (isFail) failures++;
            stdout.writeln(
              pad(step[0] + ' @' + fx.toString() + ',' + fy.toString(), 40) + ' state ' + stateS + ' a' + alphaS + '  pixel [' + pixelS.join(',') + ']' +
              '  dot ' + dotRs.toStringAsFixed(2) + ' idle ' + idleRs.toStringAsFixed(2) + ' stuck ' + stuckRs.toStringAsFixed(2) + surfaceNoteS + '  ' + flag);
            stdout.writeln('    stack: ' + stackS);
          }
        }
      }
    }
    stdout.writeln((failures == 0 ? 'ALL PIXEL CHECKS PASS' : 'PIXEL FAILURES: ' + failures.toString()) + '  (' + total.toString() + ' points, shots ok ' + shotOk.toString() + ' bad ' + shotBad.toString() + ')');
    await client.close();
    exit(failures == 0 ? 0 : 1);
  } catch (e) {
    stderr.writeln('truth probe error: ' + e.toString());
    await client.close();
    exit(1);
  }
}
