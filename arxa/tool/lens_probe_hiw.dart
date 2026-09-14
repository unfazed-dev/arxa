// arxa lens hiw-probe driver: numeric ground truth for the pinned
// "How it works" stage. Drives the SAME scripted scroll sequence on the
// reference and the build — rest (first two cards revealed, track at
// startX), 25/50/100% of the pin span (one new card reveal per stop,
// velocity parallax decay on the cells), the final-fifth zoom at
// 25/50/75/100% (stage scale from origin 50vw/(112+zoomH/2), last media
// box cream→#0a0d12 color-mix, petal logo bloom width 45%), and the
// post-pin release (logo fades over half a viewport) — sampling at 60ms
// resolution. Anchor screenshots at rest / track-25 / track-50 /
// track-100 / zoom-mid / zoom-end / zoom-release make the side-by-side
// pairs. The physics card's chip positions are random by design on BOTH
// sites (Math.random spawn), so only structural facts are sampled there.
// Usage:
//   dart run tool/lens_probe_hiw.dart <url> [width] [height] [outJson]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/daemon.dart';

// wait until no intro overlay/preloader remains (fixed z 9999/99999)
String _revealJs() {
  return r'''
(() => {
  const overlay = [...document.querySelectorAll('div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && (s.zIndex === '9999' || s.zIndex === '99999');
  });
  return !overlay;
})()
''';
}

// one sampler pass — locators are structure/style-signature based (the
// reference renders bare React nodes), so the same code reads both sites
String _sampleJs() {
  return r'''
(() => {
  const out = {};
  const px = v => parseFloat(v) || 0;
  const vis = el => !!el && el.offsetParent !== null;
  const section = document.getElementById('how-it-works');
  if (!section) { out.err = 'no section'; return out; }
  const srect = section.getBoundingClientRect();
  out.geometry = {
    offsetHeight: section.offsetHeight,
    top: Math.round(srect.top),
    vh: window.innerHeight,
    vw: window.innerWidth
  };
  const sticky = [...section.children].find(d => getComputedStyle(d).position === 'sticky') || null;
  const zoom = sticky ? sticky.firstElementChild : null;
  if (zoom) {
    const zs = getComputedStyle(zoom);
    const zm = zs.transform.match(/matrix\(([^)]+)\)/);
    out.zoom = {
      scale: zm ? parseFloat(zm[1].split(',')[0]) : 1,
      origin: zs.transformOrigin
    };
  }
  const viewport = sticky ? [...sticky.querySelectorAll('div')].find(d => getComputedStyle(d).perspective === '1400px') : null;
  const track = viewport ? viewport.firstElementChild : null;
  if (track) {
    const ts = getComputedStyle(track);
    const tm = ts.transform.match(/matrix\(([^)]+)\)/);
    out.track = {
      tx: tm ? parseFloat(tm[1].split(',')[4]) : 0,
      gap: ts.gap,
      padL: ts.paddingLeft,
      padR: ts.paddingRight
    };
    out.cells = [...track.children].map(c => {
      const cm = getComputedStyle(c).transform.match(/matrix\(([^)]+)\)/);
      return cm ? parseFloat(cm[1].split(',')[4]) : 0;
    });
    out.reveals = [...track.children].map(c => {
      const inner = c.firstElementChild;
      if (!inner) return null;
      const s = getComputedStyle(inner);
      const m = s.transform.match(/matrix\(([^)]+)\)/);
      return { opacity: s.opacity, ty: m ? Math.round(parseFloat(m[1].split(',')[5])) : null };
    });
    out.cards = [...track.children].map(c => {
      const card = c.firstElementChild ? c.firstElementChild.firstElementChild : null;
      if (!card) return null;
      const media = card.firstElementChild;
      const cr = card.getBoundingClientRect();
      return {
        left: Math.round(cr.left),
        w: Math.round(cr.width),
        radius: media ? getComputedStyle(media).borderRadius : null,
        bg: media ? getComputedStyle(media).backgroundColor : null,
        cursorRadius: card.getAttribute('data-cursor-radius')
      };
    });
    const cardAt = i => (track.children[i] && track.children[i].firstElementChild) ? track.children[i].firstElementChild.firstElementChild : null;
    const lastCard = cardAt(4);
    if (lastCard) {
      const media = lastCard.firstElementChild;
      if (media) {
        const logo = [...media.querySelectorAll('svg')].find(s => (s.getAttribute('viewBox') || '') === '0 0 221 261' && getComputedStyle(s).position === 'absolute') || null;
        if (logo) {
          const ls = getComputedStyle(logo);
          out.logo = { w: Math.round(px(ls.width)), h: Math.round(px(ls.height)), opacity: ls.opacity };
        }
        const clouds = [...media.querySelectorAll('img,svg')].filter(el => {
          const s = getComputedStyle(el);
          return s.position === 'absolute' && (s.willChange || '').indexOf('transform') !== -1 && s.left !== '50%' && s.pointerEvents === 'none';
        });
        out.clouds = clouds.slice(0, 2).map(el => {
          const s = getComputedStyle(el);
          const m = s.transform.match(/matrix\(([^)]+)\)/);
          return { tx: m ? Math.round(parseFloat(m[1].split(',')[4])) : 0, ty: m ? Math.round(parseFloat(m[1].split(',')[5])) : 0 };
        });
      }
    }
    const gridCard = cardAt(2);
    if (gridCard) {
      const svg = gridCard.firstElementChild ? gridCard.firstElementChild.querySelector('svg') : null;
      if (svg) {
        out.grid = {
          dots: svg.querySelectorAll('circle').length,
          petals: [...svg.querySelectorAll('g')].filter(g => g.style.opacity !== '').length,
          filled: [...svg.querySelectorAll('circle')].filter(c => (c.getAttribute('fill') || '') === '#ff692e').length,
          petalsOn: [...svg.querySelectorAll('g')].filter(g => g.style.opacity !== '' && g.style.opacity === '1').length
        };
      }
    }
    const physCard = cardAt(3);
    if (physCard) {
      const cv = physCard.querySelector('canvas');
      out.canvas = cv ? { w: cv.width, h: cv.height } : null;
    }
    const firstCard = cardAt(0);
    if (firstCard) {
      const v0 = firstCard.querySelector('video');
      if (v0) {
        const vs = getComputedStyle(v0);
        const vm = vs.transform.match(/matrix\(([^)]+)\)/);
        out.video0 = { scale: vm ? parseFloat(vm[1].split(',')[0]) : null, paused: v0.paused };
      }
      const p0 = firstCard.querySelector('p');
      if (p0) {
        const s = getComputedStyle(p0);
        out.caption = { size: s.fontSize, weight: s.fontWeight, color: s.color, ls: s.letterSpacing };
      }
    }
  }
  const pillWrap = [...document.querySelectorAll('div,header')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && s.top === '16px' && s.justifyContent === 'center' && s.pointerEvents === 'none';
  }) || null;
  if (pillWrap) {
    const cta = [...pillWrap.querySelectorAll('a')].find(a => {
      const s = getComputedStyle(a);
      return vis(a) && (s.borderRadius === '43px' || parseFloat(s.borderRadius) >= 40) && s.position !== 'fixed';
    }) || null;
    out.nav = {
      mode: document.querySelector('[data-nav-mode]') ? document.querySelector('[data-nav-mode]').getAttribute('data-nav-mode') : null,
      cta: cta ? { t: cta.textContent.trim(), bg: getComputedStyle(cta).backgroundColor } : null
    };
  }
  return out;
})()
''';
}

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('usage: dart run tool/lens_probe_hiw.dart <url> [width] [height] [outJson]');
    exit(2);
  }
  final url = argv[0];
  final width = argv.length > 1 ? int.parse(argv[1]) : 1280;
  final height = argv.length > 2 ? int.parse(argv[2]) : 832;
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
    while (watch.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) {
        tReveal = watch.elapsedMilliseconds;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    result['tRevealMs'] = tReveal;
    if (tReveal == null) {
      result['error'] = 'intro overlay never cleared within budget';
    } else {
      await Future.delayed(const Duration(milliseconds: 800));

      // dismiss the cookie banner if present (both sites render one)
      await tab.evaluate(r'''
(() => {
  const btn = [...document.querySelectorAll('button')].find(b => /^accept$/i.test((b.textContent || '').trim()));
  if (btn) btn.click();
  return !!btn;
})()
''');
      await Future.delayed(const Duration(milliseconds: 300));

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

      final scrollToSpan =
          r'''(() => { const hiw = document.getElementById('how-it-works'); const span = (hiw.offsetHeight - window.innerHeight) * 0.8; window.scrollTo(0, hiw.offsetTop + ARG); })()'''
              .replaceAll('ARG', 'FRACTION');

      // — rest —
      await tab.evaluate(r'''window.scrollTo(0, 0);''');
      await Future.delayed(const Duration(milliseconds: 900));
      result['rest'] = await sample();
      await shot('rest');

      // — track 25%: reveals card 3 (index 2), velocity parallax spike —
      await tab.evaluate(scrollToSpan.replaceAll('FRACTION', 'span * 0.25'));
      final p25 = await runPhase(2200, 60, shotAt: {1600: 'track-25'});
      result['track25'] = {'ticks': p25};

      // — track 50%: reveals card 4 (index 3) —
      await tab.evaluate(scrollToSpan.replaceAll('FRACTION', 'span * 0.5'));
      final p50 = await runPhase(1900, 60, shotAt: {1500: 'track-50'});
      result['track50'] = {'ticks': p50};

      // — track 100%: reveals card 5 (index 4), zoom about to start —
      await tab.evaluate(scrollToSpan.replaceAll('FRACTION', 'span * 1.0'));
      final p100 = await runPhase(1900, 60, shotAt: {1500: 'track-100'});
      result['track100'] = {'ticks': p100};

      // — zoom fractions —
      final zooms = <String, dynamic>{};
      for (final entry in [
        ['25', 'span + (hiw.offsetHeight - window.innerHeight) * 0.2 * 0.25', ''],
        ['50', 'span + (hiw.offsetHeight - window.innerHeight) * 0.2 * 0.5', 'zoom-mid'],
        ['75', 'span + (hiw.offsetHeight - window.innerHeight) * 0.2 * 0.75', ''],
        ['100', 'span + (hiw.offsetHeight - window.innerHeight) * 0.2 * 1', 'zoom-end'],
      ]) {
        await tab.evaluate(scrollToSpan.replaceAll('FRACTION', entry[1]));
        await Future.delayed(const Duration(milliseconds: 1300));
        zooms[entry[0]] = await sample();
        if (entry[2].isNotEmpty) await shot(entry[2]);
      }
      result['zoom'] = zooms;

      // — release: sticky lets go, logo fades —
      await tab.evaluate(
          r'''(() => { const hiw = document.getElementById('how-it-works'); const scrollable = hiw.offsetHeight - window.innerHeight; window.scrollTo(0, hiw.offsetTop + scrollable + window.innerHeight * 0.3); })()''');
      await Future.delayed(const Duration(milliseconds: 1200));
      result['release'] = await sample();
      await shot('zoom-release');

      if (mobile) {
        // geometry-only mobile verification (no touch synthesis)
        await tab.evaluate(r'''window.scrollTo(0, 0);''');
        await Future.delayed(const Duration(milliseconds: 900));
        result['mobileRest'] = await sample();
      }

      // — derivations —
      Map<String, dynamic>? deriveReveal(List<Map<String, dynamic>> phase, int index) {
        int? onset;
        int? settled;
        for (final tick in phase) {
          final t = tick['t'] as int;
          final s = tick['s'] as Map<String, dynamic>;
          final reveals = s['reveals'] as List<dynamic>?;
          if (reveals == null || reveals.length <= index) continue;
          final r = reveals[index] as Map<String, dynamic>?;
          if (r == null) continue;
          final op = double.parse((r['opacity'] ?? '0').toString());
          if (onset == null && op > 0.05) onset = t;
          if (onset != null && settled == null && op >= 0.95) settled = t;
        }
        return onset == null ? null : {'onset': onset, 'settled': settled};
      }

      Map<String, dynamic>? deriveParallax(List<Map<String, dynamic>> phase) {
        double peak = 0;
        int? peakAt;
        int? settledAt;
        for (final tick in phase) {
          final t = tick['t'] as int;
          final s = tick['s'] as Map<String, dynamic>;
          final cells = s['cells'] as List<dynamic>?;
          if (cells == null || cells.length < 5) continue;
          final last = (cells[4] as num).toDouble();
          if (last.abs() > peak.abs()) {
            peak = last;
            peakAt = t;
          }
          if (peakAt != null && settledAt == null && last.abs() < 0.5) settledAt = t;
        }
        return {'peak': peak, 'peakAt': peakAt, 'settledAt': settledAt};
      }

      result['reveal2'] = deriveReveal(p25, 2);
      result['reveal3'] = deriveReveal(p50, 3);
      result['reveal4'] = deriveReveal(p100, 4);
      result['parallax'] = deriveParallax(p25);
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
