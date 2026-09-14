// arxa lens nav-probe driver: numeric ground truth for the floating pill
// nav. Drives the SAME scripted scroll sequence on the reference and the
// build — hero-exit swap (links zone collapses 1fr->0fr, 500ms blackout,
// content swap, re-expand), how-it-works pin (links->progress dots, dot
// index from floor(past/span x 5)), return-to-top swap, scrollspy band —
// sampling at 60ms resolution: wrapper transform/opacity (must stay put),
// pill rect (width breathes), zone width + inner opacity, CTA label/bg,
// visible link set + weights/colors, dot widths, mobile menu state.
// Anchor screenshots at rest / mid-collapse / main mode / dots / dots-mid
// / back-hero / menu make the side-by-side pairs.
// Usage:
//   dart run tool/lens_probe_nav.dart <url> [width] [height] [outJson]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/daemon.dart';

// wait until the pill is revealed and no intro overlay/preloader remains
String _revealJs() {
  return r'''
(() => {
  const overlay = [...document.querySelectorAll('div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && (s.zIndex === '9999' || s.zIndex === '99999');
  });
  const wrap = [...document.querySelectorAll('div,header')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && s.top === '16px' && s.justifyContent === 'center';
  });
  if (!wrap || overlay) return false;
  return parseFloat(getComputedStyle(wrap).opacity) >= 0.9;
})()
''';
}

// one sampler pass — locators are style-signature based (the reference
// renders bare React nodes), so the same code reads both sites
String _sampleJs() {
  return r'''
(() => {
  const out = {};
  const px = v => parseFloat(v) || 0;
  const vis = el => !!el && el.offsetParent !== null;
  const wrap = [...document.querySelectorAll('div,header')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && s.top === '16px' && s.justifyContent === 'center' && s.pointerEvents === 'none';
  }) || null;
  if (!wrap) { out.wrap = null; return out; }
  const ws = getComputedStyle(wrap);
  const wm = ws.transform.match(/matrix\(([^)]+)\)/);
  out.wrap = { opacity: ws.opacity, ty: wm ? Math.round(px(wm[1].split(',')[5])) : null, z: ws.zIndex };
  const pill = [...wrap.querySelectorAll('*')].find(d => getComputedStyle(d).borderRadius === '55px') || null;
  if (!pill) { out.pill = null; out.zone = null; return out; }
  const pr = pill.getBoundingClientRect();
  out.pill = { x: Math.round(pr.x), y: Math.round(pr.y), w: Math.round(pr.width), h: Math.round(pr.height) };
  const zone = [...pill.querySelectorAll('div')].find(d => getComputedStyle(d).display === 'grid') || null;
  if (!zone) { out.zone = null; } else {
    const zr = zone.getBoundingClientRect();
    const inner = zone.firstElementChild;
    out.zone = {
      w: Math.round(zr.width),
      innerOpacity: inner ? getComputedStyle(inner).opacity : null,
      gridCols: getComputedStyle(zone).gridTemplateColumns
    };
  }
  out.links = [...pill.querySelectorAll('a')]
    .filter(a => vis(a) && getComputedStyle(a).borderRadius !== '43px')
    .map(a => { const s = getComputedStyle(a); return { t: a.textContent.trim(), w: s.fontWeight, c: s.color }; });
  const cta = [...pill.querySelectorAll('a')].find(a => vis(a) && getComputedStyle(a).borderRadius === '43px') || null;
  out.cta = cta === null ? null : (() => { const s = getComputedStyle(cta); return { t: cta.textContent.trim(), bg: s.backgroundColor }; })();
  out.dots = [...pill.querySelectorAll('*')]
    .filter(d => vis(d) && (getComputedStyle(d).height === '8px' || getComputedStyle(d).height === '7px') && getComputedStyle(d).borderRadius === '4px')
    .map(d => Math.round(d.getBoundingClientRect().width));
  const menu = [...document.querySelectorAll('div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && s.zIndex === '10001' && s.backgroundColor === 'rgb(0, 0, 0)';
  }) || null;
  if (menu === null) { out.menu = null; } else {
    const ms = getComputedStyle(menu);
    const link = menu.querySelector('a');
    out.menu = {
      opacity: ms.opacity,
      pe: ms.pointerEvents,
      linkSize: link ? getComputedStyle(link).fontSize : null,
      linkColor: link ? getComputedStyle(link).color : null,
      linkFont: link ? getComputedStyle(link).fontFamily.split(',')[0] : null
    };
  }
  return out;
})()
''';
}

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('usage: dart run tool/lens_probe_nav.dart <url> [width] [height] [outJson]');
    exit(2);
  }
  final url = argv[0];
  final width = argv.length > 1 ? int.parse(argv[1]) : 1280;
  final height = argv.length > 2 ? int.parse(argv[2]) : 900;
  final outPath = argv.length > 3 ? argv[3] : '';
  final mobile = width <= 480;
  final result = <String, dynamic>{
    'url': url,
    'viewport': width.toString() + 'x' + height.toString(),
  };
  final shots = <String, String>{};

  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: 700);
    final watch = Stopwatch()..start();

    Future<void> shot(String name) async {
      if (outPath.isEmpty) return;
      final png = await tab.screenshot();
      final name2 = outPath.replaceAll('.json', '-' + name + '.png');
      File(name2).writeAsBytesSync(png);
      shots[name] = name2;
    }

    int? tReveal;
    while (watch.elapsedMilliseconds < 25000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) {
        tReveal = watch.elapsedMilliseconds;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    result['tRevealMs'] = tReveal;
    if (tReveal == null) {
      result['error'] = 'nav never revealed within budget';
    } else {
      await Future.delayed(const Duration(milliseconds: 400));

      Future<Map<String, dynamic>> sample() async {
        final s = await tab.evaluate(_sampleJs());
        return s is Map<String, dynamic> ? s : <String, dynamic>{};
      }

      Future<List<Map<String, dynamic>>> runPhase(int ms, int tickMs,
          {Map<int, String>? shotAt}) async {
        final ticks = <Map<String, dynamic>>[];
        final start = watch.elapsedMilliseconds;
        final taken = <int>{};
        while (watch.elapsedMilliseconds - start < ms) {
          final rel = watch.elapsedMilliseconds - start;
          ticks.add({
            't': rel,
            's': await sample(),
          });
          if (shotAt != null) {
            for (final entry in shotAt.entries) {
              if (rel >= entry.key && !taken.contains(entry.key)) {
                taken.add(entry.key);
                await shot(entry.value);
              }
            }
          }
          await Future.delayed(Duration(milliseconds: tickMs));
        }
        return ticks;
      }

      // — rest state —
      final rest = await sample();
      await shot('rest');
      result['rest'] = rest;
      int restZoneW = 0;
      final restZone = rest['zone'] as Map<String, dynamic>?;
      if (restZone != null && restZone['w'] is num) {
        restZoneW = (restZone['w'] as num).toInt();
      }
      final restCta = rest['cta'] as Map<String, dynamic>?;
      final restCtaT = restCta == null ? '' : (restCta['t'] ?? '').toString();

      // — swap 1: hero -> main —
      await tab.evaluate(
          r'''window.scrollTo(0, (document.getElementById('hero-section') || document.body).offsetHeight + 300);''');
      final swap = await runPhase(1600, 60, shotAt: {220: 'swap-mid', 1400: 'main-mode'});
      result['swapHeroMain'] = {'ticks': swap};

      // — swap 2: main -> dots (how-it-works pin) —
      await tab.evaluate(r'''(() => { const hiw = document.getElementById('how-it-works'); const span = (hiw.offsetHeight - window.innerHeight) * 0.8; window.scrollTo(0, hiw.offsetTop + span * 0.15); })()''');
      final dots = await runPhase(1700, 60, shotAt: {1400: 'dots-mode'});
      result['dotsEnter'] = {'ticks': dots};

      // — dot index advance mid-pin —
      await tab.evaluate(r'''(() => { const hiw = document.getElementById('how-it-works'); const span = (hiw.offsetHeight - window.innerHeight) * 0.8; window.scrollTo(0, hiw.offsetTop + span * 0.5); })()''');
      final dotsMid = await runPhase(900, 60, shotAt: {700: 'dots-mid'});
      result['dotsMid'] = {'ticks': dotsMid};

      // — swap 3: back to top (dots -> hero) —
      await tab.evaluate(r'''window.scrollTo(0, 0);''');
      final back = await runPhase(1700, 60, shotAt: {1400: 'back-hero'});
      result['backToHero'] = {'ticks': back};

      // — scrollspy band on pricing —
      await tab.evaluate(r'''(() => { const p = document.getElementById('pricing'); window.scrollTo(0, p.offsetTop - window.innerHeight * 0.35); })()''');
      await Future.delayed(const Duration(milliseconds: 1300));
      result['spyPricing'] = await sample();

      if (mobile) {
        await tab.evaluate(r'''window.scrollTo(0, 0);''');
        await Future.delayed(const Duration(milliseconds: 900));
        await tab.evaluate(r'''(() => { const b = document.querySelector('[aria-label="Open menu"]'); if (b) b.click(); })()''');
        await Future.delayed(const Duration(milliseconds: 450));
        result['menuOpen'] = await sample();
        await shot('menu');
        await tab.evaluate(r'''(() => { const b = document.querySelector('[aria-label="Close menu"]'); if (b) b.click(); })()''');
      }

      // — derivations: staged-swap timeline per phase —
      Map<String, dynamic>? derive(List<Map<String, dynamic>> phase, int w0) {
        int? collapseOnset;
        int? minAt;
        int minW = 1 << 30;
        int? expandOnset;
        int? settledAt;
        for (final tick in phase) {
          final t = tick['t'] as int;
          final s = tick['s'] as Map<String, dynamic>;
          final zone = s['zone'] as Map<String, dynamic>?;
          final w = zone == null ? 0 : (zone['w'] is num ? (zone['w'] as num).toInt() : 0);
          if (collapseOnset == null && w < w0 - 8) collapseOnset = t;
          if (w < minW) {
            minW = w;
            minAt = t;
          }
          if (minAt != null && expandOnset == null && t > minAt && w > minW + 8) {
            expandOnset = t;
          }
          if (expandOnset != null && settledAt == null && w >= w0 - 8) {
            settledAt = t;
          }
        }
        return {
          'collapseOnset': collapseOnset,
          'minAt': minAt,
          'minW': minW == 1 << 30 ? null : minW,
          'expandOnset': expandOnset,
          'settledAt': settledAt,
        };
      }

      result['swapDerived'] = derive(swap, restZoneW);
      result['backDerived'] = derive(back, restZoneW);
      final lastDots = dotsMid.isNotEmpty ? dotsMid.last['s'] : (dots.isNotEmpty ? dots.last['s'] : null);
      if (lastDots is Map<String, dynamic>) result['dotsFinal'] = lastDots['dots'];
      result['shots'] = shots;
    }
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
