// lens_probe_stories.dart — numeric ground truth for the client-stories
// stage and the case portals. Same scripted drive on the reference and the
// build: pin fractions (card poses, heading dim, counter), the zoom
// transition (stage scale + origin, then portal open state), the case
// page scroll (parallax gallery + ticket card, CTA reveal), the close
// cycle (nav restore, stage reset), and the #slug deep link. Anchor
// screenshots make the side-by-side pairs. Locators are structure/
// style-signature based (the reference renders bare React nodes) so the
// same code reads both sites.
// Usage:
//   dart run tool/lens_probe_stories.dart <url> [width] [height] [outJson]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/daemon.dart';

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

// stage + cards sampler (pin phases)
String _sampleJs() {
  return r'''
(() => {
  const out = {};
  const section = document.getElementById('clientstories');
  if (!section) { out.err = 'no section'; return out; }
  const stage = [...section.children].find(d => getComputedStyle(d).position === 'sticky') || section.firstElementChild;
  if (!stage) { out.err = 'no stage'; return out; }
  const st = getComputedStyle(stage);
  const tm = st.transform.match(/matrix\(([^)]+)\)/);
  out.geometry = { offsetHeight: section.offsetHeight, top: Math.round(section.getBoundingClientRect().top), vh: window.innerHeight, vw: window.innerWidth };
  out.stage = { transform: st.transform, scale: tm ? parseFloat(tm[1].split(',')[0]) : 1, origin: st.transformOrigin, opacity: st.opacity };
  const head = [...stage.querySelectorAll('div')].find(d => { const h = d.querySelector('h2'); return h && (h.textContent || '').indexOf('Stories of') !== -1; });
  out.head = head ? { opacity: getComputedStyle(head).opacity } : null;
  const countBox = head ? head.querySelector('p') : null;
  out.count = countBox ? countBox.textContent.trim().slice(0, 60) : null;
  out.cards = [...stage.children].filter(d => {
    const cs = getComputedStyle(d);
    return cs.position === 'absolute' && d.offsetWidth === 280;
  }).map(d => {
    const cs = getComputedStyle(d);
    const cm = cs.transform.match(/matrix\(([^)]+)\)/);
    let rot = 0;
    if (cm) { rot = Math.round(Math.atan2(parseFloat(cm[1].split(',')[1]), parseFloat(cm[1].split(',')[0])) * 180 / Math.PI); }
    const r = d.getBoundingClientRect();
    return { left: cs.left, top: cs.top, opacity: cs.opacity, rot, z: cs.zIndex, x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) };
  });
  return JSON.stringify(out);
})()
''';
}
// case-portal sampler
String _caseJs() {
  return r'''
(() => {
  const out = {};
  const fixedDivs = [...document.querySelectorAll('div')].filter(d => getComputedStyle(d).position === 'fixed');
  const frame = fixedDivs.find(d => getComputedStyle(d).zIndex === '10002' && d.offsetWidth > 300) ||
    fixedDivs.find(d => getComputedStyle(d).backgroundColor === 'rgb(242, 243, 245)' && getComputedStyle(d).borderRadius === '24px');
  const backdrop = fixedDivs.find(d => getComputedStyle(d).zIndex === '10001') ||
    fixedDivs.find(d => getComputedStyle(d).backgroundColor === 'rgba(10, 13, 18, 0.5)');
  if (!frame) { out.open = false; return JSON.stringify(out); }
  out.open = true;
  const bs = backdrop ? getComputedStyle(backdrop) : null;
  out.backdrop = bs ? { opacity: bs.opacity, blur: bs.backdropFilter } : null;
  const fs = getComputedStyle(frame);
  const r = frame.getBoundingClientRect();
  out.frame = { top: Math.round(r.top), left: Math.round(r.left), w: Math.round(r.width), h: Math.round(r.height), radius: fs.borderRadius, opacity: fs.opacity, transform: fs.transform, bg: fs.backgroundColor };
  const scroller = frame.firstElementChild;
  out.scrollerOverflow = scroller ? getComputedStyle(scroller).overflowY : null;
  const hero = scroller ? scroller.firstElementChild : null;
  const heroVideo = hero ? hero.querySelector('video') : null;
  out.heroVideoTransform = heroVideo ? heroVideo.style.transform || getComputedStyle(heroVideo).transform : null;
  const h1 = hero ? hero.querySelector('h1') : null;
  out.h1 = h1 ? { text: (h1.textContent || '').slice(0, 40), size: getComputedStyle(h1).fontSize, color: getComputedStyle(h1).color } : null;
  const staged = scroller ? scroller.children[1] : null;
  if (staged) {
    const ss = getComputedStyle(staged);
    out.staged = { opacity: ss.opacity, transform: ss.transform, padding: ss.padding };
    const aside = [...staged.querySelectorAll('*')].find(d => getComputedStyle(d).position === 'sticky');
    out.aside = aside ? { pos: 'sticky', top: getComputedStyle(aside).top, w: getComputedStyle(aside).width } : null;
    const galleryImg = staged.querySelector('img');
    out.galleryImgTransform = galleryImg ? galleryImg.style.transform || getComputedStyle(galleryImg).transform : null;
    const ticket = [...staged.querySelectorAll('div')].find(d => getComputedStyle(d).position === 'absolute' && getComputedStyle(d).borderRadius === '20px');
    out.ticket = ticket ? { transform: ticket.style.transform || getComputedStyle(ticket).transform, w: getComputedStyle(ticket).width, bottom: getComputedStyle(ticket).bottom, radius: getComputedStyle(ticket).borderRadius } : null;
    const ctaH2 = [...staged.querySelectorAll('h2')].find(h => (h.textContent || '').indexOf('Get your first designs') !== -1);
    out.cta = ctaH2 ? { transform: ctaH2.style.transform || getComputedStyle(ctaH2).transform, size: getComputedStyle(ctaH2).fontSize } : null;
    const stats = [...staged.querySelectorAll('div')].filter(d => getComputedStyle(d).borderTopWidth === '1px' && getComputedStyle(d).borderTopStyle === 'solid' && getComputedStyle(d).borderBottomStyle === 'solid');
    out.statsRows = stats.length;
    const designers = [...staged.querySelectorAll('p')].filter(p => (p.textContent || '') === 'Designers');
    out.designersBlocks = designers.length;
  }
  const closeBtn = frame.querySelector('button');
  out.closeBtn = closeBtn ? { opacity: getComputedStyle(closeBtn).opacity, size: getComputedStyle(closeBtn).width } : null;
  const nav = [...document.querySelectorAll('*')].find(d => { const s = getComputedStyle(d); return s.position === 'fixed' && s.top === '16px'; });
  out.nav = nav ? { visibility: getComputedStyle(nav).visibility } : null;
  return JSON.stringify(out);
})()
''';
}

// mobile stacked sampler
String _mobileJs() {
  return r'''
(() => {
  const out = {};
  const section = document.getElementById('clientstories');
  if (!section) { out.err = 'no section'; return JSON.stringify(out); }
  const stage = section.firstElementChild;
  const ss = getComputedStyle(stage);
  out.stage = { position: ss.position, height: ss.height, display: ss.display, padTop: ss.paddingTop, gap: ss.gap };
  out.sectionH = section.offsetHeight;
  const cards = [...stage.children].filter(d => d.querySelector('video'));
  out.cards = cards.map(d => {
    const cs = getComputedStyle(d);
    const r = d.getBoundingClientRect();
    return { position: cs.position, w: Math.round(r.width), h: Math.round(r.height), radius: cs.borderRadius };
  });
  const veil = cards.length ? cards[0].querySelector('div') : null;
  out.veil = veil ? { opacity: getComputedStyle(veil).opacity, bg: getComputedStyle(veil).backgroundColor } : null;
  const h2 = stage.querySelector('h2');
  out.h2 = h2 ? getComputedStyle(h2).fontSize : null;
  return JSON.stringify(out);
})()
''';
}
Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final width = args.length > 1 ? int.parse(args[1]) : 1280;
  final height = args.length > 2 ? int.parse(args[2]) : 832;
  final outPath = args.length > 3 ? args[3] : '/tmp/arxa-compare/cs/probe-stories.json';
  final mobile = args.length > 4 ? args[4] == 'mobile' : false;
  final result = <String, dynamic>{ 'url': url, 'viewport': '$width x $height' };
  final shots = <String, String>{};
  final client = await LensDaemon.acquire();
  Future<void> shot(name, tab) async {
    // headless capture freezes on autoplaying video frames — pause media
    // and let the compositor settle before pulling the frame
    await tab.evaluate(r'''(() => { document.querySelectorAll('video').forEach(v => v.pause()); return document.querySelectorAll('video').length; })()''');
    await Future.delayed(const Duration(milliseconds: 300));
    final png = await tab.screenshot();
    final name2 = outPath.replaceAll('.json', '-' + name + '.png');
    File(name2).writeAsBytesSync(png);
    shots[name] = name2;
  }
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: 700);
    final watch = Stopwatch()..start();
    int? tReveal;
    while (watch.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) { tReveal = watch.elapsedMilliseconds; break; }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    result['tRevealMs'] = tReveal;
    if (tReveal == null) {
      result['error'] = 'intro overlay never cleared';
    } else {
      await Future.delayed(const Duration(milliseconds: 800));
      await tab.evaluate(r'''(() => { window.__errs = []; window.onerror = (m) => { window.__errs.push(String(m)); return false; }; const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return !!btn; })()''');
      await Future.delayed(const Duration(milliseconds: 300));
      final goStories = r'''(() => { const s = document.getElementById('clientstories'); const span = s.offsetHeight - window.innerHeight; window.scrollTo(0, s.offsetTop + FRACTION); return s.offsetTop; })()''';
      if (mobile) {
        await tab.evaluate(goStories.replaceAll('FRACTION', '0'));
        await Future.delayed(const Duration(milliseconds: 600));
        final m1 = await tab.evaluate(_mobileJs());
        result['mobileRest'] = m1;
        await shot('mobile-rest', tab);
        await tab.evaluate(r'''(() => { const cards = [...document.querySelectorAll('#clientstories *')].filter(d => d.querySelector('video') && getComputedStyle(d).position === 'relative'); if (cards[1]) cards[1].click(); })()''');
        await Future.delayed(const Duration(milliseconds: 1100));
        final m2 = await tab.evaluate(_caseJs());
        result['mobileCase'] = m2;
        await shot('mobile-case', tab);
      } else {
        await tab.evaluate(goStories.replaceAll('FRACTION', '0'));
        await Future.delayed(const Duration(milliseconds: 700));
        result['rest'] = await tab.evaluate(_sampleJs());
        await shot('rest', tab);
        for (final f in ['span * 0.25', 'span * 0.5', 'span * 0.75', 'span * 1.0']) {
          await tab.evaluate(goStories.replaceAll('FRACTION', f));
          await Future.delayed(const Duration(milliseconds: 500));
          final key = f.contains('0.25') ? 'pin25' : f.contains('0.5') ? 'pin50' : f.contains('0.75') ? 'pin75' : 'pin100';
          result[key] = await tab.evaluate(_sampleJs());
          if (key == 'pin50' || key == 'pin100') await shot(key, tab);
        }
        // zoom transition: click the middle card at full pin
        await tab.evaluate(r'''(() => { const stage = document.getElementById('clientstories').firstElementChild; const cards = [...stage.children].filter(d => getComputedStyle(d).position === 'absolute' && d.offsetWidth === 280); if (cards[1]) cards[1].click(); return cards.length; })()''');
        // zoom tick series: the transition is sampled through its curve so
        // the max scale and the end state are comparable across sites
        final zoomTicks = <Map<String, dynamic>>[];
        for (int t = 0; t < 7; t++) {
          await Future.delayed(const Duration(milliseconds: 150));
          final s = await tab.evaluate(_sampleJs());
          zoomTicks.add({ 't': (t + 1) * 150, 's': s });
        }
        result['zoomTicks'] = zoomTicks;
        await Future.delayed(const Duration(milliseconds: 400));
        result['caseOpen'] = await tab.evaluate(_caseJs());
        await shot('case-open', tab);
        // scroll the case page to the gallery and the CTA
        await tab.evaluate(r'''(() => { const frame = [...document.querySelectorAll('div')].find(d => getComputedStyle(d).zIndex === '10002'); const sc = frame.firstElementChild; const gal = sc.querySelectorAll('img')[0]; if (gal) gal.scrollIntoView({block: 'center'}); })()''');
        await Future.delayed(const Duration(milliseconds: 600));
        result['caseGallery'] = await tab.evaluate(_caseJs());
        await shot('case-gallery', tab);
        await tab.evaluate(r'''(() => { const frame = [...document.querySelectorAll('div')].find(d => getComputedStyle(d).zIndex === '10002'); const sc = frame.firstElementChild; sc.scrollTop = sc.scrollHeight; })()''');
        await Future.delayed(const Duration(milliseconds: 1400));
        result['caseCta'] = await tab.evaluate(_caseJs());
        await shot('case-cta', tab);
        // close via Escape
        await tab.evaluate(r'''window.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape'})); ''');
        await Future.delayed(const Duration(milliseconds: 500));
        await tab.evaluate(r'''window.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape'})); ''');
        await Future.delayed(const Duration(milliseconds: 800));
        result['afterClose'] = await tab.evaluate(_caseJs());
        result['afterCloseState'] = await tab.evaluate(r'''JSON.stringify((() => { const p = document.querySelector('[data-case="alpin-capital"]'); return { open: p ? p.getAttribute('data-open') : null, cls: p ? p.className : null, errs: window.__errs || [] }; })())''');
        result['afterCloseStage'] = await tab.evaluate(_sampleJs());
      }
      // deep link (second navigation in one tab — the case page's own
      // media can starve the network-idle wait, so keep a fallback settle)
      try {
        // same-URL + fragment would scroll instead of reloading — go through
        // about:blank so both sites boot fresh with the hash present
        await tab.navigateAndSettle('about:blank', settleMs: 300);
        await tab.navigateAndSettle(url + '#alpa', settleMs: 5500);
      } catch (_) {}
      // wait out the site's own intro on the fresh load before sampling
      final w2 = Stopwatch()..start();
      while (w2.elapsedMilliseconds < 20000) {
        final ok = await tab.evaluate(_revealJs());
        if (ok == true) break;
        await Future.delayed(const Duration(milliseconds: 150));
      }
      await Future.delayed(const Duration(milliseconds: 900));
      result['deepLink'] = await tab.evaluate(_caseJs());
      await shot('deeplink', tab);
    }
    result['shots'] = shots;
    File(outPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('probe stories ok -> ' + outPath);
  } finally {
    await client.close();
  }
}