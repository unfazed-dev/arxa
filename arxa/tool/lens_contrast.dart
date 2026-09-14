// lens_contrast — the contrast engine's LIVE verdict (2026-09-11):
// boots a page (local or deployed), waits past the intro, then measures
// the REAL computed foreground/background of the elements the contract's
// keyed selectors name — DOM truth, not sheet math. Fails listing every
// pair under its WCAG 2.2 AA target. Usage:
//   dart run tool/lens_contrast.dart <url> [--wait-ms N]
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('usage: dart run tool/lens_contrast.dart <url> [--wait-ms N]');
    exit(2);
  }
  final url = argv[0];
  final waitMs = argv.contains('--wait-ms')
      ? int.parse(argv[argv.indexOf('--wait-ms') + 1])
      : 9000;

  final client = await CdpClient.launch();
  var failures = 0;
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(url, settleMs: waitMs);

    // The measured probes: selector, fg property, and the surface
    // selector+property behind it — the composite surfaces the contract
    // named, verified as the browser actually painted them.
    const probes = [
      ('.arxa-intro-headline', 'color', '.arxa-intro', 'backgroundColor', 4.5),
      ('.arxa-intro-sub', 'color', '.arxa-intro', 'backgroundColor', 4.5),
      ('.hero-title', 'color', '.hero', 'backgroundColor', 3.0),
      ('.hero-subline', 'color', '.hero', 'backgroundColor', 4.5),
      ('.site-nav-link', 'color', 'body', 'backgroundColor', 4.5),
    ];
    final probesJs = '[' +
        probes
            .map((p0) => "[ '" + p0.$1 + "', '" + p0.$2 + "', '" + p0.$3 + "', '" + p0.$4 + "', " + p0.$5.toString() + " ]")
            .join(',') +
        ']';
    final expr ='''
      (() => {
        const probes = __PROBES__;
        function parse(v) {
          const m = /rgba?\\(([^)]+)\\)/.exec(v || '');
          if (!m) return null;
          let body = m[1], alpha = 1;
          const slash = body.indexOf('/');
          if (slash >= 0) { alpha = parseFloat(body.slice(slash + 1)); body = body.slice(0, slash); }
          const p = body.split(/[\\s,]+/).filter((x) => x.length > 0).map(Number);
          if (p.length < 3 || p.some(isNaN)) return null;
          // alpha rides the 4th comma component in legacy serialization
          // (Chrome emits rgba(0, 0, 0, 0), not rgb(0 0 0 / 0)) — 2026-09-11
          const a = p.length >= 4 ? p[3] : alpha;
          return [p[0], p[1], p[2], isFinite(a) ? a : 1];
        }
        function eff(el, prop) {
          let n = el;
          while (n && n !== document.documentElement) {
            const cs0 = getComputedStyle(n);
            const c = parse(prop === 'color' ? cs0.color : cs0.backgroundColor);
            if (c && c[3] > 0.85) return c;
            n = n.parentElement;
          }
          const root0 = getComputedStyle(document.documentElement);
          return parse(prop === 'color' ? root0.backgroundColor : root0.backgroundColor) || [255,255,255,1];
        }
        return probes.map(([sel, fgp, bgsel, bgp, target]) => {
          const el = document.querySelector(sel);
          if (!el) return { sel, skip: true };
          const cs = getComputedStyle(el);
          const fg = parse(fgp === 'color' ? cs.color : cs.backgroundColor) || eff(el, 'color');
          const bg = eff(document.querySelector(bgsel) || el, bgp === 'backgroundColor' ? 'backgroundColor' : 'color');
          const mix = (a, b) => [0,1,2].map(i => Math.round(a[i]*a[3] + b[i]*(1-a[3])));
          const f = fg[3] < 1 ? mix(fg, bg) : fg;
          function ch(v) { v /= 255; return v <= 0.04045 ? v/12.92 : Math.pow((v+0.055)/1.055, 2.4); }
          const lum = (c) => 0.2126*ch(c[0]) + 0.7152*ch(c[1]) + 0.0722*ch(c[2]);
          const la = lum(f), lb = lum(bg);
          const ratio = (Math.max(la,lb)+0.05)/(Math.min(la,lb)+0.05);
          return { sel, fg: 'rgb(' + f.join(',') + ')', bg: 'rgb(' + bg.slice(0,3).join(',') + ')', ratio: Math.round(ratio*100)/100, target };
        });
      })()
    '''.replaceAll('__PROBES__', probesJs);
    final rows = await tab.evaluate(expr);
    for (final r0 in (rows as List).cast<Map>()) {
      if (r0['skip'] == true) {
        stdout.writeln('SKIP ' + (r0['sel'] as String) + ' (not on this page)');
        continue;
      }
      final ratio = (r0['ratio'] as num).toDouble();
      final target = (r0['target'] as num).toDouble();
      final ok = ratio >= target;
      if (!ok) failures++;
      stdout.writeln((ok ? 'PASS ' : 'FAIL ') +
          (r0['sel'] as String) + '  ' +
          (r0['fg'] as String) + ' on ' + (r0['bg'] as String) + '  ' +
          ratio.toStringAsFixed(2) + ':1 (target ' + target.toString() + ':1)');
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
      ? 'lens contrast: ALL PASS'
      : 'lens contrast: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
