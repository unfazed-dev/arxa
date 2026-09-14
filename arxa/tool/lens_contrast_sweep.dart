// lens_contrast_sweep — full-page DOM-truth contrast audit (2026-09-11):
// walks EVERY visible element carrying direct text, measures computed
// foreground against the nearest opaque background (WCAG 2.2 AA: 4.5 body /
// 3.0 large), and audits the caret the dial's inline editor would paint —
// simulating [data-arxa-inline-editing] and reading caret-color as the
// browser resolves it (3.0 non-text floor). Gradient-backed text is listed
// as NOTE (no single bg to assert). Usage:
//   dart run tool/lens_contrast_sweep.dart <url> [--wait-ms N] [--width N]
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('usage: dart run tool/lens_contrast_sweep.dart <url> [--wait-ms N] [--width N]');
    exit(2);
  }
  final url = argv[0];
  final waitMs = argv.contains('--wait-ms')
      ? int.parse(argv[argv.indexOf('--wait-ms') + 1])
      : 9000;
  final width = argv.contains('--width')
      ? int.parse(argv[argv.indexOf('--width') + 1])
      : 1280;
  // --allow sel1,sel2: reviewed exceptions (painted-mockup text, soft-level
  // captions) — printed as KNOWN so an audit ends green by decision
  final allow = argv.contains('--allow')
      ? argv[argv.indexOf('--allow') + 1].split(',').toSet()
      : <String>{};

  final client = await CdpClient.launch();
  var failures = 0;
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, width < 500 ? 844 : 832);
    await tab.navigateAndSettle(url, settleMs: waitMs);

    final expr = r'''
      (() => {
        function parse(v) {
          if (!v) return null;
          const m = /rgba?\(([^)]+)\)/.exec(v);
          if (!m) return null;
          let body = m[1], alpha = 1;
          const slash = body.indexOf('/');
          if (slash >= 0) { alpha = parseFloat(body.slice(slash + 1)); body = body.slice(0, slash); }
          const p = body.split(/[\s,]+/).filter((x) => x.length > 0).map(Number);
          if (p.length < 3 || p.some(isNaN)) return null;
          // alpha rides the 4th comma component in legacy serialization
          // (Chrome emits rgba(0, 0, 0, 0), not rgb(0 0 0 / 0)) — 2026-09-11
          const a = p.length >= 4 ? p[3] : alpha;
          return [p[0], p[1], p[2], isFinite(a) ? a : 1];
        }
        function ch(v) { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
        function lum(c) { return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2]); }
        function ratio(a, b) { const la = lum(a), lb = lum(b); return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05); }
        function mix(a, b) { return [0, 1, 2].map((i) => Math.round(a[i] * a[3] + b[i] * (1 - a[3]))); }
        function effBg(el) {
          let n = el, gradient = false, crossedFixed = false, anc = null;
          while (n && n !== document.documentElement) {
            const cs0 = getComputedStyle(n);
            if (cs0.position === 'fixed' || cs0.position === 'sticky') crossedFixed = true;
            const c = parse(cs0.backgroundColor);
            if (c && c[3] > 0.85) { anc = c; break; }
            if (cs0.backgroundImage && cs0.backgroundImage !== 'none') gradient = true;
            n = n.parentElement;
          }
          // overlays (fixed/sticky headers) paint over SIBLINGS — the
          // ancestor walk answers with whatever opaque ancestor lies below
          // (often the dark body), so the PAINT STACK takes priority there;
          // the ancestor answer remains the fallback (energize's
          // above-light-theme header over light sections reads dark-on-dark
          // to an ancestor walk but beige to the paint stack)
          if (crossedFixed) {
            const b = el.getBoundingClientRect();
            const onscreen = b.bottom > 0 && b.top < window.innerHeight && b.right > 0 && b.left < window.innerWidth;
            if (onscreen) {
              const sx = Math.max(1, Math.min(window.innerWidth - 2, Math.round(b.left + b.width / 2)));
              const sy = Math.max(1, Math.min(window.innerHeight - 2, Math.round(b.top + b.height / 2)));
              let grad2 = false;
              for (const s of document.elementsFromPoint(sx, sy)) {
                if (s === el || el.contains(s)) continue;
                const cs2 = getComputedStyle(s);
                const c2 = parse(cs2.backgroundColor);
                if (c2 && c2[3] > 0.85) return { rgb: c2, gradient: grad2 };
                if (cs2.backgroundImage && cs2.backgroundImage !== 'none') grad2 = true;
              }
            }
          }
          if (anc) return { rgb: anc, gradient: gradient };
          const rb = parse(getComputedStyle(document.documentElement).backgroundColor);
          return { rgb: rb || [255, 255, 255, 1], gradient: gradient };
        }
        function label(el) {
          const cn = typeof el.className === 'string' ? el.className : (el.className && el.className.baseVal) || '';
          return el.tagName.toLowerCase() + (cn ? '.' + cn.trim().split(/\s+/).join('.') : '');
        }
        function visible(el) {
          const cs0 = getComputedStyle(el);
          if (cs0.display === 'none' || cs0.visibility === 'hidden') return false;
          // EFFECTIVE opacity: an element inside an opacity-0 ancestor is
          // not painted (intro-animator letters, closed overlays) — the
          // element's own computed opacity stays 1 (opacity does not
          // inherit), so multiply up the chain (suczka's DOM proved it)
          let effOp = parseFloat(cs0.opacity);
          let p0 = el.parentElement;
          while (p0 && p0 !== document.documentElement && effOp >= 0.05) {
            effOp *= parseFloat(getComputedStyle(p0).opacity);
            p0 = p0.parentElement;
          }
          if (effOp < 0.05) return false;
          const r = el.getBoundingClientRect();
          return r.width >= 2 && r.height >= 2;
        }
        function directText(el) {
          for (const n of el.childNodes) if (n.nodeType === 3 && n.textContent.trim().length > 0) return true;
          return false;
        }
        const out = { scanned: 0, textEls: 0, text: [], caret: [], gradient: [], ghost: [], outlineProbe: null };
        const seen = new Set();
        const els = Array.from(document.querySelectorAll('body *')).filter(visible);
        out.scanned = els.length;
        for (const el of els) {
          if (!directText(el)) continue;
          out.textEls++;
          const cs = getComputedStyle(el);
          const fg = parse(cs.color);
          if (!fg) continue;
          const bgInfo = effBg(el);
          const f = fg[3] < 1 ? mix(fg, bgInfo.rgb) : fg;
          const bg = bgInfo.rgb[3] < 1 ? mix(bgInfo.rgb, [255, 255, 255, 1]) : bgInfo.rgb;
          const px = parseFloat(cs.fontSize);
          const bold = parseInt(cs.fontWeight) >= 600;
          const large = px >= 24 || (px >= 18.66 && bold);
          const target = large ? 3.0 : 4.5;
          const ra = ratio(f, bg);
          const entry = { el: label(el), fg: 'rgb(' + f.join(',') + ')', bg: 'rgb(' + bg.slice(0, 3).join(',') + ')', ratio: Math.round(ra * 100) / 100, target: target, px: Math.round(px * 10) / 10 };
          if (bgInfo.gradient) {
            if (!out.gradient.some((e) => e.el === entry.el && e.ratio === entry.ratio)) out.gradient.push(entry);
            continue;
          }
          // ghost law: decorative watermarks (fg alpha < 0.3) are exempt, and
          // so are display-scale ornaments — glyphs within 1.6:1 of their
          // surface at >= 64px, or PUNCTUATION-ONLY separators at >= 64px
          // (energize's big-type marquee slashes ride every palette at
          // 1.2-2.1:1 by design — no one reads a 132px '/')
          const ornament = px >= 64 && (/^[\\/|\u2022\u00b7\u2014\u2013\-,.;:\s]+$/.test((el.textContent || '').trim()) || ra < 1.6);
          if (fg[3] < 0.3 || ornament) {
            if (!out.ghost.some((e) => e.el === entry.el && e.ratio === entry.ratio)) out.ghost.push(entry);
            continue;
          }
          if (ra < target) {
            const sig = entry.fg + '|' + entry.bg + '|' + entry.target;
            if (!seen.has(sig)) { seen.add(sig); out.text.push(entry); }
          }
        }
        const cseen = new Set();
        const pickFn = typeof document._arxaCaretPick === 'function' ? document._arxaCaretPick : null;
        out.caretMode = pickFn ? 'dial' : 'no-dial';
        if (pickFn) {
          for (const el of els) {
            if (!directText(el)) continue;
            el.setAttribute('data-arxa-inline-editing', '');
            const c2 = getComputedStyle(el);
            if (out.outlineProbe === null) {
              out.outlineProbe = { el: label(el), outlineStyle: c2.outlineStyle, outlineColor: c2.outlineColor, caretColor: c2.caretColor };
            }
            el.removeAttribute('data-arxa-inline-editing');
            // gradient-backed and ghost elements route through the text pass's
            // NOTE lists — the caret rides the same surface truth
            if (effBg(el).gradient) continue;
            const bgInfo = effBg(el);
            // normalize the bg exactly like the text pass: a transparent
            // html-fallback composites over the white canvas — computing
            // against alpha-zero black produced phantom 1:1 carets (hello-hda)
            const bg = bgInfo.rgb[3] < 1 ? mix(bgInfo.rgb, [255, 255, 255, 1]) : bgInfo.rgb;
            const picked = pickFn(el);
            const tx = parse(getComputedStyle(el).color);
            if (!picked) {
              // no candidate cleared BOTH floors — the dial falls back to
              // currentColor, which blends into the text by construction
              const sig = label(el) + '|nopick';
              if (!cseen.has(sig)) {
                cseen.add(sig);
                out.caret.push({ el: label(el), caret: '(no compliant pick — currentColor fallback)', bg: 'rgb(' + bg.slice(0, 3).join(',') + ')', vsBg: 0, vsText: 1 });
              }
              continue;
            }
            const rb = ratio(picked, bg);
            const rt = tx ? ratio(picked, tx) : 99;
            if (rb < 3.0 || rt < 1.5) {
              const sig = label(el) + '|' + picked.join(',');
              if (!cseen.has(sig)) {
                cseen.add(sig);
                out.caret.push({ el: label(el), caret: 'rgb(' + picked.join(',') + ')', bg: 'rgb(' + bg.slice(0, 3).join(',') + ')', vsBg: Math.round(rb * 100) / 100, vsText: Math.round(rt * 100) / 100 });
              }
            }
          }
        }
        return out;
      })()
    ''';
    final out = await tab.evaluate(expr) as Map;
    stdout.writeln('walked ${out['scanned']} visible elements, ${out['textEls']} with direct text (width $width)');
    if (out['caretMode'] == 'no-dial') {
      stdout.writeln('caret pass skipped (dial not booted — the caret is an author-side affordance)');
    }
    final probe = out['outlineProbe'] as Map?;
    if (probe != null) {
      stdout.writeln('INFO inline-edit rule probe on ' + probe['el'].toString() +
          ': outline=' + probe['outlineStyle'].toString() +
          ' caret=' + probe['caretColor'].toString() +
          (probe['outlineStyle'] == 'none' ? '  <- dial rule did NOT reach the page' : ''));
    }
    for (final e in (out['text'] as List).cast<Map>()) {
      if (allow.contains(e['el'])) {
        stdout.writeln('KNOWN (allowlisted) ' + e['el'].toString() +
            '  ' + e['ratio'].toString() + ':1 — reviewed exception');
        continue;
      }
      failures++;
      stdout.writeln('FAIL ' + e['el'].toString() +
          '  ' + e['fg'].toString() + ' on ' + e['bg'].toString() +
          '  ' + e['ratio'].toString() + ':1 (target ' + e['target'].toString() + ':1, ' + e['px'].toString() + 'px)');
    }
    for (final e in (out['caret'] as List).cast<Map>()) {
      if (allow.contains(e['el'])) {
        stdout.writeln('KNOWN (allowlisted caret) ' + e['el'].toString() +
            '  vsBg ' + e['vsBg'].toString() + ' vsText ' + e['vsText'].toString() + ' — reviewed exception');
        continue;
      }
      failures++;
      stdout.writeln('CARET-FAIL ' + e['el'].toString() +
          '  caret ' + e['caret'].toString() + ' on ' + e['bg'].toString() +
          '  vsBg ' + e['vsBg'].toString() + ':1 (floor 3.0) vsText ' + e['vsText'].toString() + ':1 (floor 1.5)');
    }
    for (final e in (out['ghost'] as List).cast<Map>()) {
      stdout.writeln('GHOST-NOTE decorative (alpha<0.3) ' + e['el'].toString() +
          '  ' + e['fg'].toString() + ' on ' + e['bg'].toString() + '  exempt');
    }
    for (final e in (out['gradient'] as List).cast<Map>()) {
      stdout.writeln('NOTE gradient-backed ' + e['el'].toString() +
          '  ' + e['fg'].toString() + '  ' + e['ratio'].toString() + ':1 vs deepest opaque — eyeball');
    }
    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    if (errs.isNotEmpty) {
      failures++;
      for (final e in errs) {
        stdout.writeln('ERR  ' + e);
      }
    }
  } finally {
    await client.close();
  }
  stdout.writeln(failures == 0
      ? 'lens contrast sweep: ALL PASS'
      : 'lens contrast sweep: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
