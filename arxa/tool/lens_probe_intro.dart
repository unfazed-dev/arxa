// arxa lens intro-probe driver: numeric ground truth for the intro
// sequence + hero entrance. Polls the page from first paint of the
// intro system at 100ms resolution and samples EVERY layer by style
// signature (the reference renders bare React nodes — no ids): the
// overlay (fixed z 9999), its headline word spans' transforms, the
// subline, the 891x634 phone stage's scale matrix, the notification
// card's height, the status bar/backdrop opacities, the video's playing
// state, the nav pill's reveal transform, and the overlay's removal.
// From the tick timeline it derives each transition's onset (bg flip,
// scale settle, card expansion, word rise, subline, video, nav, release)
// and the hero stage's entrance slide after release (visible only at
// viewport heights above 1038px — run 1280x1200 to see it move).
// Prints one JSON document to stdout.
// Usage:
//   dart run tool/lens_probe_intro.dart <url> [width] [height] [budgetMs] [outJson]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/daemon.dart';

// one sampler pass — every value read fresh; locators are style-signature
// based so the same code reads the reference and the build
String _sampleJs() {
  return r'''
(() => {
  const out = {};
  const px = v => parseFloat(v) || 0;
  const ov = [...document.querySelectorAll('div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && s.zIndex === '9999';
  }) || null;
  out.overlay = ov === null ? null : (() => {
    const s = getComputedStyle(ov);
    return { bg: s.backgroundColor, opacity: s.opacity };
  })();

  const pre = [...document.querySelectorAll('div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && s.zIndex === '99999';
  }) || null;
  out.preloader = pre !== null;

  if (ov) {
    const words = [...ov.querySelectorAll('h1 span')].filter(sp => {
      const cs = getComputedStyle(sp);
      return cs.display === 'inline-block' && cs.transform !== 'none' && sp.textContent.trim().length > 0;
    });
    out.words = words.map(sp => {
      const t = getComputedStyle(sp).transform;
      const m = t.match(/matrix\(([^)]+)\)/);
      const ty = m ? px(m[1].split(',')[5]) : null;
      return { ty: ty === null ? null : Math.round(ty * 10) / 10, delay: sp.style.transitionDelay };
    });
    const p = ov.querySelector('p');
    if (p) {
      const s = getComputedStyle(p);
      out.sub = { opacity: s.opacity, transform: s.transform };
      const rot = p.querySelector('strong span');
      out.rotator = rot ? { text: rot.textContent.trim(), opacity: getComputedStyle(rot).opacity } : null;
    }
    const stage = [...ov.querySelectorAll('div')].find(d => {
      const s = getComputedStyle(d);
      return s.position === 'relative' && s.width === '891px' && s.height === '634px';
    });
    if (stage) {
      const s = getComputedStyle(stage);
      const m = s.transform.match(/matrix\(([^)]+)\)/);
      out.stage = {
        scale: m ? Math.round(px(m[1].split(',')[0]) * 1000) / 1000 : s.transform,
        origin: s.transformOrigin,
        transition: s.transitionDuration + '|' + s.transitionTimingFunction
      };
      const card = [...stage.querySelectorAll('div')].find(d => {
        const c = getComputedStyle(d);
        return c.position === 'absolute' && c.borderRadius === '17px';
      });
      if (card) {
        const c = getComputedStyle(card);
        out.card = { h: Math.round(px(c.height)), opacity: c.opacity, transform: c.transform };
        const video = card.querySelector('video');
        if (video) out.video = { paused: video.paused, t: Math.round(video.currentTime * 100) / 100, ready: video.readyState };
      }
      const bar = [...stage.querySelectorAll('div')].find(d => {
        const c = getComputedStyle(d);
        return c.position === 'absolute' && c.width === '249px' && c.height === '38px';
      });
      if (bar) out.statusbar = { opacity: getComputedStyle(bar).opacity };
      const back = [...stage.querySelectorAll('*')].find(d => {
        const c = getComputedStyle(d);
        return c.position === 'absolute' && c.width === '1061px' && c.height === '707px';
      });
      if (back) out.backdrop = { opacity: getComputedStyle(back).opacity };
    }
  }

  const nav = [...document.querySelectorAll('header, div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && s.top === '16px' && s.display === 'flex' && s.justifyContent === 'center';
  });
  if (nav) {
    const s = getComputedStyle(nav);
    const m = s.transform.match(/matrix\(([^)]+)\)/);
    out.nav = {
      opacity: s.opacity,
      ty: m ? Math.round(px(m[1].split(',')[5])) : null,
      z: s.zIndex
    };
  }

  const heroSec = document.getElementById('hero-section');
  if (heroSec && !ov) {
    const st = [...heroSec.querySelectorAll('div')].find(d => {
      const c = getComputedStyle(d);
      return c.position === 'relative' && c.width === '891px' && c.height === '634px';
    });
    if (st) {
      const c = getComputedStyle(st);
      const m = c.transform.match(/matrix\(([^)]+)\)/);
      out.heroStage = {
        ty: m ? Math.round(px(m[1].split(',')[5])) : null,
        transform: c.transform === 'none' ? null : c.transform,
        transition: c.transitionDuration,
        secMarginLeft: getComputedStyle(heroSec).marginLeft,
        secRadius: getComputedStyle(heroSec).borderBottomLeftRadius
      };
    }
  }
  return out;
})()
''';
}

String _num(Object? v) => v is num ? v.toString() : (v == null ? 'null' : v.toString());

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/lens_probe_intro.dart <url> [width] [height] '
        '[budgetMs] [outJson]');
    exit(2);
  }
  final url = argv[0];
  final width = argv.length > 1 ? int.parse(argv[1]) : 1280;
  final height = argv.length > 2 ? int.parse(argv[2]) : 832;
  final budgetMs = argv.length > 3 ? int.parse(argv[3]) : 9000;
  final outPath = argv.length > 4 ? argv[4] : '';
  final result = <String, dynamic>{
    'url': url,
    'viewport': width.toString() + 'x' + height.toString(),
    'budgetMs': budgetMs,
  };

  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    // short settle: just enough for the modules to eval; the timeline is
    // measured from the intro system's first paint, not from navigation
    await tab.navigateAndSettle(url, settleMs: 700);

    final ticks = <Map<String, dynamic>>[];
    final watch = Stopwatch()..start();
    int? t0;
    while (watch.elapsedMilliseconds < budgetMs) {
      final seen = await tab.evaluate(
          '(() => { const ov = [...document.querySelectorAll("div")].find(d => { const s = getComputedStyle(d); return s.position === "fixed" && (s.zIndex === "9999" || s.zIndex === "99999"); }); return !!ov; })()');
      if (seen == true) {
        t0 = watch.elapsedMilliseconds;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
    result['t0Ms'] = t0;
    if (t0 == null) {
      result['error'] = 'intro system never painted within budget';
    } else {
      // anchor frames: screenshots at the canonical stage boundaries past
      // t0 — the same offsets on both sides make the side-by-side pairs
      final targets = [450, 1850, 3250, 4400, 5450, 7200];
      final shotTargets = <int>{};
      for (final target in targets) {
        shotTargets.add(target);
      }
      while (watch.elapsedMilliseconds - t0 < 8000) {
        final t = watch.elapsedMilliseconds - t0;
        final sample = await tab.evaluate(_sampleJs());
        ticks.add({'t': t, 's': sample});
        for (final target in targets) {
          if (shotTargets.contains(target) && t >= target) {
            shotTargets.remove(target);
            if (outPath.isNotEmpty) {
              final png = await tab.screenshot();
              final name = outPath.replaceAll('.json', '-s' + target.toString() + '.png');
              File(name).writeAsBytesSync(png);
              ticks.add({'t': t, 's': {'screenshot': name}});
            }
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      result['ticks'] = ticks;

      String? bgAccentAt;
      String? stageSettledAt;
      String? cardInAt;
      String? cardExpandedAt;
      String? wordsRisenAt;
      String? subInAt;
      String? videoPlayingAt;
      String? navInAt;
      String? overlayGoneAt;
      String? heroShiftPeakAt;
      num? heroShiftPeak;
      for (final tick in ticks) {
        final tInt = tick['t'] as int;
        final t = tInt.toString();
        final s = tick['s'] as Map<String, dynamic>;
        final ov = s['overlay'] as Map<String, dynamic>?;
        if (bgAccentAt == null && ov != null) {
          final bg = (ov['bg'] ?? '').toString();
          if (bg.contains('255, 105, 46')) bgAccentAt = t;
        }
        final stage = s['stage'] as Map<String, dynamic>?;
        if (stage != null) {
          final scale = (stage['scale'] is num) ? stage['scale'] as num : null;
          if (scale != null) {
            if (stageSettledAt == null && scale < 1.05 && tInt > 1500) stageSettledAt = t;
          }
        }
        final card = s['card'] as Map<String, dynamic>?;
        if (card != null) {
          final h = (card['h'] is num) ? card['h'] as num : 0;
          final op = double.tryParse((card['opacity'] ?? '0').toString()) ?? 0;
          if (cardInAt == null && op > 0.9 && h < 200) cardInAt = t;
          if (cardExpandedAt == null && h > 300) cardExpandedAt = t;
        }
        final words = s['words'] as List<dynamic>?;
        if (words != null && words.isNotEmpty && wordsRisenAt == null) {
          final allRisen = words.every((w) {
            final ty = w is Map ? w['ty'] : null;
            return ty is num && ty.abs() < 1.5;
          });
          if (allRisen && tInt > 3000) wordsRisenAt = t;
        }
        final sub = s['sub'] as Map<String, dynamic>?;
        if (sub != null && subInAt == null) {
          final op = double.tryParse((sub['opacity'] ?? '0').toString()) ?? 0;
          if (op > 0.9 && tInt > 3400) subInAt = t;
        }
        final video = s['video'] as Map<String, dynamic>?;
        if (video != null && videoPlayingAt == null) {
          final paused = video['paused'] == true;
          final ct = (video['t'] is num) ? video['t'] as num : 0.0;
          if (!paused && ct > 0.05) videoPlayingAt = t;
        }
        final nav = s['nav'] as Map<String, dynamic>?;
        if (nav != null && navInAt == null) {
          final op = double.tryParse((nav['opacity'] ?? '0').toString()) ?? 0;
          final ty = nav['ty'];
          if (op > 0.9 && ty is num && ty.abs() < 2) navInAt = t;
        }
        if (overlayGoneAt == null && ov == null && tInt > 4000) overlayGoneAt = t;
        final heroStage = s['heroStage'] as Map<String, dynamic>?;
        if (heroStage != null && overlayGoneAt != null) {
          final ty = heroStage['ty'];
          if (ty is num && ty.abs() > (heroShiftPeak ?? 0)) {
            heroShiftPeak = ty;
            heroShiftPeakAt = t;
          }
        }
      }
      result['summary'] = {
        'bgAccentAt': bgAccentAt,
        'stageSettledAt': stageSettledAt,
        'cardInAt': cardInAt,
        'cardExpandedAt': cardExpandedAt,
        'wordsRisenAt': wordsRisenAt,
        'subInAt': subInAt,
        'videoPlayingAt': videoPlayingAt,
        'navInAt': navInAt,
        'overlayGoneAt': overlayGoneAt,
        'heroShiftPeakAt': heroShiftPeakAt,
        'heroShiftPeak': heroShiftPeak,
      };
      Map<String, dynamic>? at(int target) {
        Map<String, dynamic>? best;
        int bestDelta = 1 << 30;
        for (final tick in ticks) {
          final t = tick['t'] as int;
          final d = (t - target).abs();
          if (d < bestDelta) {
            bestDelta = d;
            best = tick;
          }
        }
        return best;
      }
      result['atStage1'] = at(430);
      result['atStage2'] = at(1830);
      result['atStage3'] = at(3230);
      result['atSub'] = at(3830);
      result['atEnd'] = at(5430);
      result['atSettled'] = ticks.isNotEmpty ? ticks.last : null;
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
