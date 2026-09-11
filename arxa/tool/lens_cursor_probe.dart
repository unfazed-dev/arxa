// lens_cursor_probe — DOM-truth audit of the animated cursor (2026-09-12,
// v2.1 sweep same day): drives the real page, moves the pointer over a
// GRID of points spanning every major section (5 x-positions x 3 y-bands —
// v1 sampled only the section center and stayed green while a live sweep
// caught the footer brand card: a dark pure-color GRADIENT the
// backgroundColor-only walk skipped), and asserts the cursor COLOR LAW the
// contrast engine locked (WCAG 2.2 non-text 3.0 floor against the surface
// actually under the pointer):
//   1. DOT (8px solid, full alpha — the pointer indicator proper) must
//      clear 3.0 vs the surface,
//   2. STUCK RING (fill .12 + stroke while over a target — an interactive
//      affordance): the stroke's ACTUAL alpha (data-arxa-stuck-alpha on the
//      dot, adaptive 0.55–1.0 by cursor law v2) mixed against the surface
//      must clear 3.0,
//   3. IDLE RING (free trail stroke at globalAlpha .5 — ambient motion,
//      not an affordance): the 50% mix must clear 2.0 (washed-out guard;
//      2.0-2.99 prints SOFT),
//   4. DYNAMISM — the cursor must not be one static color across opposing
//      surfaces: the states used over the darkest and lightest surfaces
//      must differ by a ratio of at least 1.5,
//   5. STALENESS — scrolling with a still pointer must not leave the
//      cursor painted for a surface that scrolled away (checked by a 1px
//      jiggle after the scroll: if the state changes, it was stale).
// effBg parity with cursor law v2.1: solid backgroundColor >= .95 alpha OR
// a sampleable pure-color gradient (sampled AT the pointer, same rounded
// math as the law). Hidden states ([data-cursor-dot]/[data-cursor-hide]
// zones, where the native cursor takes over) are skipped. Usage:
//   dart run tool/lens_cursor_probe.dart <url> [--palette name] [--width N]
//                                       [--wait-ms N]
import 'dart:io';

import 'package:arxa/cdp.dart';

String pad(String s, int n) => s.length >= n ? s.substring(0, n) : s + ' ' * (n - s.length);

List<int> parseHex(String h) {
  final b = h.replaceAll('#', '');
  return [int.parse(b.substring(0, 2), radix: 16), int.parse(b.substring(2, 4), radix: 16), int.parse(b.substring(4, 6), radix: 16)];
}

double srgb(int v) {
  final d = v / 255;
  return d <= 0.04045 ? d / 12.92 : ((d + 0.055) / 1.055);
}

double luminance(List<int> c) => 0.2126 * srgb(c[0]) + 0.7152 * srgb(c[1]) + 0.0722 * srgb(c[2]);

double contrast(List<int> a, List<int> b) {
  final la = luminance(a);
  final lb = luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la < lb ? la : lb;
  return (hi + 0.05) / (lo + 0.05);
}

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('usage: dart run tool/lens_cursor_probe.dart <url> [--palette name] [--width N] [--wait-ms N]');
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
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, width < 500 ? 844 : 832);
    await tab.navigateAndSettle(url, settleMs: waitMs);

    final raw = await tab.evaluate(r'''
      (async () => {
        function parse(v) {
          if (!v) return null;
          const m = /rgba?\(([^)]+)\)/.exec(v);
          if (!m) {
            // parity with cursor law v2.1: resolved color(srgb ...) form
            const cm = /color\(\s*srgb\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s*(?:\/\s*([0-9.]+))?\s*\)/.exec(v);
            if (!cm) return null;
            const f = [parseFloat(cm[1]), parseFloat(cm[2]), parseFloat(cm[3])];
            const ca = cm[4] !== undefined ? parseFloat(cm[4]) : 1;
            return [Math.round(Math.min(1, Math.max(0, f[0])) * 255), Math.round(Math.min(1, Math.max(0, f[1])) * 255), Math.round(Math.min(1, Math.max(0, f[2])) * 255), isFinite(ca) ? ca : 1];
          }
          let body = m[1], alpha = 1;
          const slash = body.indexOf('/');
          if (slash >= 0) { alpha = parseFloat(body.slice(slash + 1)); body = body.slice(0, slash); }
          const p = body.split(/[\s,]+/).filter((x) => x.length > 0).map(Number);
          if (p.length < 3 || p.some(isNaN)) return null;
          const a = p.length >= 4 ? p[3] : alpha; // legacy comma-alpha serialization
          return [p[0], p[1], p[2], isFinite(a) ? a : 1];
        }
        const ch = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
        const lum = (c) => 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2]);
        const ratio = (a, b) => { const la = lum(a), lb = lum(b); return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05); };
        const mixHalf = (a, b) => [0, 1, 2].map((i) => Math.round((a[i] + b[i]) / 2));
        const mixAt = (a, b, t) => [0, 1, 2].map((i) => Math.round(a[i] * t + b[i] * (1 - t)));
        const hex = (c) => '#' + [0, 1, 2].map((i) => Math.round(c[i]).toString(16).padStart(2, '0')).join('');
        const raf = () => new Promise((r) => requestAnimationFrame(r));
        const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
        const cs = getComputedStyle(document.documentElement);
        function tok(n) {
          const raw = cs.getPropertyValue(n).trim();
          if (raw.charAt(0) === '#') return raw.length === 7 ? raw.toLowerCase() : null;
          const c = parse(raw);
          return c ? hex(c.slice(0, 3)) : null;
        }
        // v2.1 parity: sample a pure-color gradient AT the pointer — the
        // same math cursor.js runs (rounded channels), or null.
        function sampleGradient(image, rect, x, y) {
          const m = /^\s*(repeating-)?(linear|radial)-gradient\((.*)\)\s*$/i.exec(image);
          if (!m) return null;
          const kind = m[2].toLowerCase();
          const inner = m[3];
          const parts = [];
          let depth = 0, cur = '';
          for (let i = 0; i < inner.length; i++) {
            const c2 = inner.charAt(i);
            if (c2 === '(') depth++;
            if (c2 === ')') depth--;
            if (c2 === ',' && depth === 0) { parts.push(cur); cur = ''; } else cur += c2;
          }
          parts.push(cur);
          const stops = [], conf = [];
          for (let j = 0; j < parts.length; j++) {
            const p = parts[j].trim();
            // stop = 'color' | 'color pos' | 'color pos1 pos2' — colors may
            // contain spaces (rgb(55, 37, 73)), so strip TRAILING positions.
            let stop = null;
            const whole = parse(p);
            if (whole) {
              stop = { c: [whole[0], whole[1], whole[2]], at: null };
            } else {
              const t1 = /^(.*)\s+(-?[0-9.]+(?:%|deg|px|em|rem))$/.exec(p);
              if (t1) {
                const cA = parse(t1[1].trim());
                if (cA) stop = { c: [cA[0], cA[1], cA[2]], at: parseFloat(t1[2]) };
              }
              if (!stop) {
                const t2 = t1 ? /^(.*)\s+(-?[0-9.]+(?:%|deg|px|em|rem))$/.exec(t1[1].trim()) : null;
                if (t2) {
                  const cB = parse(t2[1].trim());
                  if (cB) stop = { c: [cB[0], cB[1], cB[2]], at: parseFloat(t1[2]) };
                }
              }
            }
            if (stop) { stops.push(stop); continue; }
            if (stops.length === 0) { conf.push(p); continue; }
            return null;
          }
          if (stops.length < 2) return null;
          for (let k = 0; k < stops.length; k++) {
            if (stops[k].at === null) stops[k].at = (k / (stops.length - 1)) * 100;
          }
          let t;
          const px = x - rect.left, py = y - rect.top;
          if (kind === 'linear') {
            let angle = 180;
            const dir = conf.length ? conf[0].toLowerCase().replace(/\s+/g, ' ') : '';
            const named = { 'to top': 0, 'to right': 90, 'to bottom': 180, 'to left': 270, 'to top right': 45, 'to right top': 45, 'to bottom right': 135, 'to right bottom': 135, 'to bottom left': 225, 'to left bottom': 225, 'to top left': 315, 'to left top': 315 };
            if (named[dir] !== undefined) angle = named[dir];
            else if (/[0-9.]+deg$/.test(dir)) angle = parseFloat(dir);
            else if (conf.length) return null;
            const rad = (angle - 90) * Math.PI / 180;
            const dx = Math.cos(rad), dy = Math.sin(rad);
            const cx = rect.width / 2, cy = rect.height / 2;
            const extent = rect.width * Math.abs(dx) + rect.height * Math.abs(dy);
            if (extent < 1) return null;
            t = 0.5 + ((px - cx) * dx + (py - cy) * dy) / extent;
          } else {
            const at = /at\s+([^ ]+)(?:\s+([^ ]+))?/.exec(conf.join(' ').toLowerCase());
            let gx = rect.width / 2, gy = rect.height / 2;
            if (at) {
              if (/%$/.test(at[1])) gx = (parseFloat(at[1]) / 100) * rect.width;
              else if (/px$/.test(at[1])) gx = parseFloat(at[1]);
              if (at[2]) {
                if (/%$/.test(at[2])) gy = (parseFloat(at[2]) / 100) * rect.height;
                else if (/px$/.test(at[2])) gy = parseFloat(at[2]);
              }
            }
            const reach = Math.sqrt(rect.width * rect.width + rect.height * rect.height) / 2;
            if (reach < 1) return null;
            t = Math.sqrt((px - gx) * (px - gx) + (py - gy) * (py - gy)) / reach;
          }
          if (!isFinite(t)) return null;
          if (t <= 0) return stops[0].c.slice();
          if (t >= 1) return stops[stops.length - 1].c.slice();
          const tp = t * 100;
          for (let s = 1; s < stops.length; s++) {
            if (tp <= stops[s].at) {
              const a = stops[s - 1], b = stops[s];
              const span = b.at - a.at;
              const f = span > 0 ? (tp - a.at) / span : 0;
              return mixAt(b.c, a.c, f);
            }
          }
          return stops[stops.length - 1].c.slice();
        }
        // top-level background-image layers (commas at paren depth 0 only)
        function bgLayers(image) {
          const layers = [];
          let depth = 0, cur = '';
          for (let i = 0; i < image.length; i++) {
            const ch2 = image.charAt(i);
            if (ch2 === '(') depth++;
            if (ch2 === ')') depth--;
            if (ch2 === ',' && depth === 0) { layers.push(cur); cur = ''; } else cur += ch2;
          }
          layers.push(cur);
          return layers;
        }
        // ---- v3 parity samplers (2026-09-13): mirror cursor.js
        // sampleMedia/sampleUrlLayer/applyFilter/fitToNatural — the DOM
        // audit must see exactly what the law sees, now including MEDIA
        // PIXELS (img/video/canvas at the pointer, object-fit mapped,
        // luminance filters replicated, tainted-canvas guarded) and url()
        // background layers, with translucent paints alpha-COMPOSITED
        // instead of skipped. ----
        const sCanvas = document.createElement('canvas');
        sCanvas.width = 1; sCanvas.height = 1;
        const sCtx = sCanvas.getContext('2d', { willReadFrequently: true });
        function drawOne(media, sx, sy) {
          sCtx.clearRect(0, 0, 1, 1);
          sCtx.drawImage(media, Math.floor(sx), Math.floor(sy), 1, 1, 0, 0, 1, 1);
          const d = sCtx.getImageData(0, 0, 1, 1).data;
          return [d[0], d[1], d[2], d[3] / 255];
        }
        // Chrome resolves the shorthand chain in LINEAR light: the tier
        // photo measured 139 under sRGB channel math where the rendered
        // pixel was 124 — linearize once, run the chain in linear,
        // delinearize once (truth probe 2026-09-13).
        function applyFilter(rgb, filter) {
          if (!filter || filter === 'none') return rgb;
          const names = filter.match(/[a-z-]+\(/g);
          if (!names) return null;
          for (let i = 0; i < names.length; i++) {
            const fn = names[i].slice(0, -1);
            if (fn !== 'grayscale' && fn !== 'contrast' && fn !== 'brightness' && fn !== 'opacity') return null;
          }
          const toLin = (chv) => { const d = chv / 255; return d <= 0.04045 ? d / 12.92 : Math.pow((d + 0.055) / 1.055, 2.4); };
          const toSrgb = (lv) => lv <= 0.0031308 ? lv * 12.92 : 1.055 * Math.pow(lv, 1 / 2.4) - 0.055;
          let lin = [toLin(rgb[0]), toLin(rgb[1]), toLin(rgb[2])];
          const re = /(grayscale|contrast|brightness|opacity)\(([0-9.]+)%?\)/g;
          let mm;
          while ((mm = re.exec(filter)) !== null) {
            const v = parseFloat(mm[2]);
            if (mm[1] === 'grayscale') {
              const gl = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
              lin = [0, 1, 2].map((i) => lin[i] + (gl - lin[i]) * v);
            } else if (mm[1] === 'contrast') {
              lin = [0, 1, 2].map((i) => Math.max(0, Math.min(1, (lin[i] - 0.5) * v + 0.5)));
            } else if (mm[1] === 'brightness') {
              lin = [0, 1, 2].map((i) => Math.max(0, Math.min(1, lin[i] * v)));
            }
          }
          return [0, 1, 2].map((i) => Math.round(Math.max(0, Math.min(255, toSrgb(lin[i]) * 255))));
        }
        function fitToNatural(px, py, rect, nw, nh, fit, position) {
          let scale;
          if (fit === 'fill') return [px / rect.width * nw, py / rect.height * nh];
          if (fit === 'none' || fit === 'scale-down') {
            scale = 1;
            if (fit === 'scale-down') scale = Math.min(1, Math.min(rect.width / nw, rect.height / nh));
          } else {
            const cover = Math.max(rect.width / nw, rect.height / nh);
            const contain = Math.min(rect.width / nw, rect.height / nh);
            scale = fit === 'contain' ? contain : cover;
          }
          const dw = nw * scale, dh = nh * scale;
          const pos = typeof position === 'string' ? position.trim() : '';
          const m = /^(-?[0-9.]+)(%|px)?\s+(-?[0-9.]+)(%|px)?$/.exec(pos);
          let fx = 0.5, fy = 0.5;
          if (m) {
            fx = m[2] === 'px' ? (parseFloat(m[1]) - (rect.width - dw) / 2) / Math.max(1, rect.width - dw) : parseFloat(m[1]) / 100;
            fy = m[4] === 'px' ? (parseFloat(m[3]) - (rect.height - dh) / 2) / Math.max(1, rect.height - dh) : parseFloat(m[3]) / 100;
          } else if (/^center|top|bottom|left|right/.test(pos)) {
            if (/left/.test(pos)) fx = 0; else if (/right/.test(pos)) fx = 1;
            if (/top/.test(pos)) fy = 0; else if (/bottom/.test(pos)) fy = 1;
          }
          const ox = (rect.width - dw) * (isFinite(fx) ? fx : 0.5);
          const oy = (rect.height - dh) * (isFinite(fy) ? fy : 0.5);
          const nx = (px - ox) / scale, ny = (py - oy) / scale;
          if (nx < 0 || ny < 0 || nx >= nw || ny >= nh) return null;
          return [nx, ny];
        }
        function sampleMedia(el, x, y) {
          const tag = el.tagName;
          let nw = 0, nh = 0;
          if (tag === 'IMG') {
            if (!el.complete || !el.naturalWidth) return null;
            nw = el.naturalWidth; nh = el.naturalHeight;
          } else if (tag === 'VIDEO') {
            if (el.readyState < 2 || !el.videoWidth) return null;
            nw = el.videoWidth; nh = el.videoHeight;
          } else if (tag === 'CANVAS') {
            nw = el.width; nh = el.height;
          } else return null;
          const rect = el.getBoundingClientRect();
          if (rect.width < 1 || rect.height < 1) return null;
          const px = x - rect.left, py = y - rect.top;
          if (px < 0 || py < 0 || px >= rect.width || py >= rect.height) return null;
          const s = getComputedStyle(el);
          const mapped = fitToNatural(px, py, rect, nw, nh, s.objectFit, s.objectPosition);
          if (!mapped) return null;
          const got = [];
          try {
            const offs = [[0, 0], [6, 0], [-6, 0], [0, 6], [0, -6]];
            for (let i = 0; i < offs.length; i++) {
              const sx = Math.min(nw - 1, Math.max(0, mapped[0] + offs[i][0]));
              const sy = Math.min(nh - 1, Math.max(0, mapped[1] + offs[i][1]));
              got.push(drawOne(el, sx, sy));
            }
          } catch (err) { return null; }
          const med = (ix) => { const col = got.map((g) => g[ix]).sort((p, q) => p - q); return col[2]; };
          const rgb = applyFilter([med(0), med(1), med(2)], s.filter);
          if (!rgb) return null;
          let a = med(3);
          const op = parseFloat(s.opacity);
          if (isFinite(op)) a *= op;
          return [rgb[0], rgb[1], rgb[2], a];
        }
        const bgImageCache = {};
        function sampleUrlLayer(s, key, rect, x, y) {
          let rec = bgImageCache[key];
          if (!rec) {
            const img = new Image();
            rec = bgImageCache[key] = { img: img, ok: false };
            img.onload = () => { rec.ok = true; };
            img.src = key;
            return null;
          }
          if (!rec.ok || !rec.img.naturalWidth) return null;
          const nw = rec.img.naturalWidth, nh = rec.img.naturalHeight;
          const rep = String(s.backgroundRepeat || '').split(',')[0].trim() || 'repeat';
          if (!/^no-repeat no-repeat$|^no-repeat$/.test(rep)) return null;
          const size = String(s.backgroundSize || '').split(',')[0].trim() || 'auto';
          const sm = /^([a-z-]+|auto|[-0-9.]+(?:px|%)?)\s+([a-z-]+|auto|[-0-9.]+(?:px|%)?)$/.exec(size) || [null, size, size];
          const resolveLength = (tok, full) => {
            tok = String(tok);
            if (tok === 'auto') return null;
            if (/%$/.test(tok)) return (parseFloat(tok) / 100) * full;
            if (/px$/.test(tok)) return parseFloat(tok);
            return null;
          };
          let dw, dh;
          const sx1 = resolveLength(sm[1], rect.width);
          const sy1 = resolveLength(sm[2], rect.height);
          const kw = size.toLowerCase();
          if (kw === 'cover' || kw === 'contain') {
            const sc = kw === 'cover' ? Math.max(rect.width / nw, rect.height / nh) : Math.min(rect.width / nw, rect.height / nh);
            dw = nw * sc; dh = nh * sc;
          } else if (sx1 != null && sy1 != null) { dw = sx1; dh = sy1; }
          else if (sx1 != null) { dw = sx1; dh = sx1 * nh / nw; }
          else if (sy1 != null) { dh = sy1; dw = sy1 * nw / nh; }
          else { dw = nw; dh = nh; }
          if (dw < 1 || dh < 1) return null;
          const pos = String(s.backgroundPosition || '').split(',')[0].trim() || '0% 0%';
          const pm = /^([a-z-]+|[-0-9.]+(?:px|%)?)\s+([a-z-]+|[-0-9.]+(?:px|%)?)$/.exec(pos) || [null, pos, pos];
          const resolvePos = (tok, full, d) => {
            tok = String(tok);
            if (tok === 'left' || tok === 'top') return 0;
            if (tok === 'right' || tok === 'bottom') return full - d;
            if (tok === 'center') return (full - d) / 2;
            if (/%$/.test(tok)) return (parseFloat(tok) / 100) * (full - d);
            if (/px$/.test(tok)) return parseFloat(tok);
            return 0;
          };
          const ox = resolvePos(pm[1], rect.width, dw);
          const oy = resolvePos(pm[2], rect.height, dh);
          const px = x - rect.left - ox, py = y - rect.top - oy;
          if (px < 0 || py < 0 || px >= dw || py >= dh) return null;
          const got = [];
          try {
            const offs = [[0, 0], [6, 0], [-6, 0], [0, 6], [0, -6]];
            for (let i = 0; i < offs.length; i++) {
              const ix = Math.min(nw - 1, Math.max(0, (px / dw) * nw + offs[i][0] * (nw / dw)));
              const iy = Math.min(nh - 1, Math.max(0, (py / dh) * nh + offs[i][1] * (nh / dh)));
              got.push(drawOne(rec.img, ix, iy));
            }
          } catch (err) { return null; }
          const med = (ix) => { const col = got.map((g) => g[ix]).sort((p, q) => p - q); return col[2]; };
          return [med(0), med(1), med(2), med(3)];
        }
        function overComposite(acc, paint) {
          const a = acc[3] + paint[3] * (1 - acc[3]);
          if (a <= 0) return [0, 0, 0, 0];
          return [
            (acc[0] * acc[3] + paint[0] * paint[3] * (1 - acc[3])) / a,
            (acc[1] * acc[3] + paint[1] * paint[3] * (1 - acc[3])) / a,
            (acc[2] * acc[3] + paint[2] * paint[3] * (1 - acc[3])) / a,
            a
          ];
        }
        function nodePaint(n, x, y) {
          const media = sampleMedia(n, x, y);
          if (media) return media;
          const s = getComputedStyle(n);
          const c = parse(s.backgroundColor);
          if (c && c[3] > 0) return [c[0], c[1], c[2], c[3]];
          const img = s.backgroundImage;
          if (img && img !== 'none') {
            const top = bgLayers(img)[0];
            const trimmed = top ? top.trim() : '';
            const g = trimmed ? sampleGradient(trimmed, n.getBoundingClientRect(), x, y) : null;
            if (g) return [g[0], g[1], g[2], 1];
            const url = /^url\((['"]?)([^)'"]+)\1\)$/.exec(trimmed);
            if (url) {
              const bgu = sampleUrlLayer(s, url[2], n.getBoundingClientRect(), x, y);
              if (bgu) return bgu;
            }
          }
          return null;
        }
        function effBg(x, y) {
          const stack = document.elementsFromPoint(x, y).filter((e) => !(e.id && e.id.indexOf('cursor-') === 0));
          const chain = stack.slice();
          const seen = new Set(stack);
          let n = stack.length ? stack[stack.length - 1] : document.body;
          while (n && n !== document.documentElement) {
            if (!seen.has(n)) { chain.push(n); seen.add(n); }
            n = n.parentElement;
          }
          let acc = null;
          for (const e of chain) {
            const paint = nodePaint(e, x, y);
            if (paint) {
              acc = acc ? overComposite(acc, paint) : paint.slice(0, 4);
              if (acc[3] >= 0.95) return [Math.round(acc[0]), Math.round(acc[1]), Math.round(acc[2])];
            }
          }
          if (acc && acc[3] > 0.02) return [Math.round(acc[0]), Math.round(acc[1]), Math.round(acc[2])];
          return [255, 255, 255];
        }
        const cursorOn = document.documentElement.classList.contains('arxa-cursor-on');
        const dot = document.getElementById('cursor-dot');
        const canvas = document.getElementById('cursor-canvas');
        if (!cursorOn || !dot || !canvas) return { booted: false, cursorOn, hasDot: !!dot, hasCanvas: !!canvas };
        const sections = [...document.querySelectorAll('section, footer')].filter((e) => e.getBoundingClientRect().height > 120);
        const xs = [0.2, 0.35, 0.5, 0.65, 0.8];
        const ys = [0.35, 0.5, 0.72];
        const samples = [];
        let cx = 0, cy = 0;
        for (const el of sections.slice(0, 16)) {
          el.scrollIntoView({ block: 'center' });
          await raf(); await raf(); await sleep(280);
          for (const fx of xs) {
            for (const fy of ys) {
              cx = Math.round(window.innerWidth * fx);
              cy = Math.round(window.innerHeight * fy);
              document.dispatchEvent(new MouseEvent('mousemove', { clientX: cx, clientY: cy }));
              await raf(); await raf(); await sleep(50);
              let state = parse(dot.style.background) || parse(dot.style.backgroundColor);
              if (!state) continue;
              let bg = effBg(cx, cy);
              let hidden = canvas.style.opacity === '0' || dot.style.opacity === '0';
              let sa = parseFloat(dot.dataset.arxaStuckAlpha || '0.55');
              // transition guard (2026-09-13): scroll-scrubbed stages (the
              // hiw pin under Lenis easing) keep moving media under a still
              // pointer — a floors miss measured mid-ease is a transition
              // artifact, not a contract miss (the pixel-synchronous truth
              // probe never flags them). Re-settle 300ms, jiggle the
              // pointer 1px to force an immediate re-key, and re-measure:
              // the SETTLED values are what the audit records.
              let floorsOk = ratio(state, bg) >= 3.0 && ratio(mixAt(state, bg, sa), bg) >= 3.0 && ratio(mixHalf(state, bg), bg) >= 2.0;
              if (!floorsOk) {
                await sleep(300);
                document.dispatchEvent(new MouseEvent('mousemove', { clientX: cx + 1, clientY: cy }));
                await raf(); await raf(); await sleep(90);
                const state2 = parse(dot.style.background) || parse(dot.style.backgroundColor);
                if (state2) {
                  state = state2;
                  bg = effBg(cx, cy);
                  hidden = canvas.style.opacity === '0' || dot.style.opacity === '0';
                  sa = parseFloat(dot.dataset.arxaStuckAlpha || '0.55');
                }
              }
              samples.push({
                label: ((el.id || (typeof el.className === 'string' ? el.className.split(' ')[0] : el.tagName)).slice(0, 28)) + ' @' + fx + ',' + fy,
                state: hex(state.slice(0, 3)),
                bg: hex(bg),
                bgLum: lum(bg),
                hidden,
                dotRatio: Math.round(ratio(state, bg) * 100) / 100,
                ringEff: Math.round(ratio(mixHalf(state, bg), bg) * 100) / 100,
                ringStuck: Math.round(ratio(mixAt(state, bg, sa), bg) * 100) / 100,
              });
            }
          }
        }
        if (sections.length > 1) {
          sections[0].scrollIntoView({ block: 'center' });
          await raf(); await raf(); await sleep(350);
          const staleState = parse(dot.style.background);
          document.dispatchEvent(new MouseEvent('mousemove', { clientX: cx + 1, clientY: cy }));
          await raf(); await raf(); await sleep(300);
          const state = parse(dot.style.background);
          const bg = effBg(cx, cy);
          const sa2 = parseFloat(dot.dataset.arxaStuckAlpha || '0.55');
          samples.push({
            label: 'STALENESS(last-point)',
            state: state ? hex(state.slice(0, 3)) : null,
            staleState: staleState ? hex(staleState.slice(0, 3)) : null,
            bg: hex(bg),
            bgLum: lum(bg),
            hidden: canvas.style.opacity === '0',
            dotRatio: state ? Math.round(ratio(state, bg) * 100) / 100 : null,
            ringEff: state ? Math.round(ratio(mixHalf(state, bg), bg) * 100) / 100 : null,
            ringStuck: state ? Math.round(ratio(mixAt(state, bg, sa2), bg) * 100) / 100 : null,
            probe: true,
          });
        }
        return {
          booted: true,
          palette: document.documentElement.getAttribute('data-palette'),
          tokens: { accent: tok('--accent'), ink: tok('--ink'), paper: tok('--paper'), white: tok('--white') },
          samples,
        };
      })()
    ''', awaitPromise: true);
    final data = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    if (data['booted'] != true) {
      stdout.writeln('CURSOR NOT BOOTED (cursorOn=' + (data['cursorOn'].toString()) + ') — nothing to audit');
      await client.close();
      exit(1);
    }
    stdout.writeln('palette=' + (data['palette']?.toString() ?? 'null') + '  tokens=' + (data['tokens']?.toString() ?? ''));
    final samples = (data['samples'] as List? ?? []).cast<Map>();
    Map? darkest;
    Map? lightest;
    var printed = 0;
    for (final s in samples) {
      final label = s['label'].toString();
      final hidden = s['hidden'] == true;
      final dotR = s['dotRatio'] == null ? null : double.parse(s['dotRatio'].toString());
      final ringR = s['ringEff'] == null ? null : double.parse(s['ringEff'].toString());
      final stuckR = s['ringStuck'] == null ? null : double.parse(s['ringStuck'].toString());
      final isProbe = s['probe'] == true;
      var flag = 'HIDDEN';
      if (!hidden) {
        final floorsOk = dotR != null && dotR >= 3.0 && stuckR != null && stuckR >= 3.0;
        final washed = ringR != null && ringR < 2.0;
        if (isProbe) {
          final staleState = s['staleState']?.toString();
          final wasStale = staleState != null && staleState != s['state']?.toString();
          flag = (floorsOk && !washed && !wasStale) ? 'PASS' : 'STALE';
        } else {
          flag = !floorsOk || washed ? 'FAIL' : (ringR != null && ringR < 3.0 ? 'SOFT' : 'PASS');
        }
      }
      if (flag == 'FAIL' || flag == 'STALE') failures++;
      // v2.1 sweep: print every FAIL/SOFT point in full; PASS points stay
      // in the rollup — 240 grid points must stay readable.
      if (flag == 'FAIL' || flag == 'STALE' || flag == 'SOFT') {
        printed++;
        stdout.writeln(pad(label, 40) + ' ' + pad(s['state']?.toString() ?? 'null', 9) + ' ' + pad('bg ' + (s['bg']?.toString() ?? ''), 12) + '  dot ' + (dotR?.toStringAsFixed(2) ?? 'n/a') + '  idle ' + (ringR?.toStringAsFixed(2) ?? 'n/a') + '  stuck ' + (stuckR?.toStringAsFixed(2) ?? 'n/a') + '  ' + flag);
      }
      if (!isProbe && s['bgLum'] != null) {
        final l = double.parse(s['bgLum'].toString());
        if (darkest == null || l < double.parse(darkest!['bgLum'].toString())) darkest = s;
        if (lightest == null || l > double.parse(lightest!['bgLum'].toString())) lightest = s;
      }
    }
    if (darkest != null && lightest != null) {
      final sa = darkest!['state']?.toString();
      final sb = lightest!['state']?.toString();
      if (sa != null && sb != null && sa != sb) {
        final r = contrast(parseHex(sa), parseHex(sb));
        final flag = r >= 1.5 ? 'PASS' : 'FAIL';
        if (flag == 'FAIL') failures++;
        stdout.writeln('DYNAMISM  darkest-bg state ' + sa + ' vs lightest-bg state ' + sb + '  ratio ' + r.toStringAsFixed(2) + '  ' + flag);
      } else {
        failures++;
        stdout.writeln('DYNAMISM  FAIL — one static state color across opposing surfaces');
      }
    } else {
      failures++;
      stdout.writeln('DYNAMISM  FAIL — could not sample opposing surfaces');
    }
    stdout.writeln((failures == 0 ? 'ALL CURSOR CHECKS PASS' : 'FAILURES: ' + failures.toString()) + '  (' + samples.length.toString() + ' grid points, ' + printed.toString() + ' flagged)');
    await client.close();
    exit(failures == 0 ? 0 : 1);
  } catch (e) {
    stderr.writeln('probe error: ' + e.toString());
    await client.close();
    exit(1);
  }
}
