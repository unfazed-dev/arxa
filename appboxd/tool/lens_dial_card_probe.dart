// Arxa card dial probe (2026-08-26).
//
// Operator spec: "the dial must now be a square(card) that must display
// Arxa and arxa logo (an 'A' at the moment) - when user taps edit mode,
// the arxa logo and arxa must animate and change to edit mode with the
// corresponding edit icon and so on for the rest (except for studio as we
// do not see the dial in studio mode as there is the sheet that pops up)
// -- the square dial must also be the colors of arxa studio with gradient"
//
// Brand ground truth (arxa-studio plugins/brand + gen-ui): moss ramp
// rgb(139,165,101) -> rgb(106,133,74) (favicon bg) -> deeper greens,
// off-white rgb(243,246,238) marks, dark #0b0b10 family; today's logo is
// a rounded square with a bold 'a'.
//
// Assertions:
//   1. the dock button is a SQUARE card (equal sides, >= 60px) with a
//      card radius (NOT the old 50% circle)
//   2. the card paints an arxa-studio GRADIENT (moss ramp)
//   3. rest face: 'A' mark + 'arxa' wordmark visible, no data-mode
//   4. arming Edit (fan -> Edit verb) flips the card: data-mode=edit,
//      edit face (icon + Edit) visible, rest face hidden
//   5. disarming returns the rest face
//   6. arming Comment flips to data-mode=comment; toggling off restores
//   7. the pins badge still lives on the card
//   8. park law still holds at the new size: sheet open -> card fully
//      off-screen; close -> back in
//   9. zero console AND page errors
// Evidence: full-page + 2x-clipped card PNGs land in the client repo.
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const SR = "document.getElementById('arxa-dial-host').shadowRoot";
const dialUrl = 'http://127.0.0.1:4319/';

int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}

Future<bool> poll(CdpSession tab, String expr, Duration limit) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await js(tab, expr) == true) return true;
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

const CARD = '''
  JSON.stringify((() => {
    const b = ''' + SR + '''.getElementById('dockbtn');
    const cs = getComputedStyle(b);
    const faces = [...b.querySelectorAll('.face')];
    const vis = (f) => f && getComputedStyle(f).opacity === '1';
    return {
      w: Math.round(parseFloat(cs.width)),
      h: Math.round(parseFloat(cs.height)),
      radius: cs.borderTopLeftRadius,
      grad: (cs.backgroundImage || '').replace(/\s+/g, ' '),
      mode: b.getAttribute('data-mode') || '',
      text: (b.textContent || '').replace(/\s+/g, ' ').trim(),
      restVis: vis(faces.find((f) => f.classList.contains('rest'))),
      editVis: vis(faces.find((f) => f.classList.contains('edit'))),
      commentVis: vis(faces.find((f) => f.classList.contains('comment'))),
      editHasSvg: !!(() => { const f = faces.find((x) => x.classList.contains('edit')); return f && f.querySelector('svg'); })(),
      commentHasSvg: !!(() => { const f = faces.find((x) => x.classList.contains('comment')); return f && f.querySelector('svg'); })(),
      badge: !!b.querySelector('.dot')
    };
  })())
''';

Future<Map> card(CdpSession tab) async =>
    jsonDecode((await js(tab, CARD)) as String) as Map;

Future<void> main() async {
  final browser = await CdpClient.launch();
  final tab = await browser.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture(dialUrl, settleMs: 2500);

  // Reveal the card.
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await poll(tab,
      "getComputedStyle(" + SR + ".getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 4));

  // 1. square card, card radius (not a 50% circle).
  var c = await card(tab);
  stdout.writeln('card: ' + jsonEncode(c));
  check(c['w'] == c['h'] && (c['w'] as num) >= 60,
      'square card (>=60px): ' + c['w'].toString() + 'x' + c['h'].toString());
  final radius = (c['radius'] as String).trim();
  check(!radius.contains('%') && (double.tryParse(radius.replaceAll('px', '')) ?? 99) < 20,
      'card radius (square, not circle): ' + radius);

  // 2. arxa-studio gradient (moss ramp).
  final grad = c['grad'] as String;
  check(grad.contains('linear-gradient') &&
      (grad.contains('139, 165, 101') || grad.contains('139,165,101') ||
       grad.contains('106, 133, 74') || grad.contains('106,133,74')),
      'arxa-studio moss gradient painted');

  // 3. rest face.
  check(c['mode'] == '' && c['restVis'] == true, 'rest face visible (no mode armed)');
  check(((c['text'] as String).toLowerCase().contains('arxa')),
      'card displays the arxa wordmark: "' + (c['text'] as String) + '"');
  check(c['badge'] == true, 'pins badge lives on the card');

  // 4. arm Edit through the real fan.
  await js(tab, SR + ".querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 350));

  // 4a. the fan's expanded items share the card treatment: square,
  // card radius, the arxa moss gradient (operator, 2026-08-26).
  final verbsRaw = await js(tab, '''
    (() => {
      const sr = ''' + SR + ''';
      const dr = sr.getElementById('dock').getBoundingClientRect();
      const dc = { x: dr.left + dr.width / 2, y: dr.top + dr.height / 2 };
      const vs = [...sr.querySelectorAll('.verb')];
      const geo = vs.map((v) => {
        const cs = getComputedStyle(v);
        const r = v.getBoundingClientRect();
        const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
        return {
          w: Math.round(parseFloat(cs.width)),
          h: Math.round(parseFloat(cs.height)),
          radius: cs.borderTopLeftRadius,
          grad: (cs.backgroundImage || '').replace(/\s+/g, ' '),
          // legacy = pure percent ("-83.847%"); square-era = calc(50% + Npx)
          unit: /^-?[\d.]+%\$/.test(v.style.left.trim()) ? 'pct' : 'px',
          dist: Math.round(Math.hypot(cx - dc.x, cy - dc.y)),
          ang: Math.round(Math.atan2(-(cy - dc.y), cx - dc.x) * 180 / Math.PI),
          cx: Math.round(cx), cy: Math.round(cy)
        };
      });
      // chord = distance between consecutive verb centers along the arc
      const chords = [];
      for (let i = 0; i + 1 < geo.length; i++) {
        chords.push(Math.round(Math.hypot(geo[i].cx - geo[i+1].cx, geo[i].cy - geo[i+1].cy)));
      }
      return JSON.stringify({ geo: geo, chords: chords });
    })()
  ''');
  var verbsOk = 0;
  var verbsTotal = 0;
  var allPx = true;
  var dists = <int>[];
  var chordsOk = true;
  const kBtn = 44, kGap = 8;
  if (verbsRaw is String && verbsRaw.length > 4) {
    final parsed = jsonDecode(verbsRaw) as Map;
    final vs = (parsed['geo'] as List).cast<Map>();
    final chords = (parsed['chords'] as List).cast<num>().map((c) => c.toInt()).toList();
    verbsTotal = vs.length;
    for (final v in vs) {
      final rad = (v['radius'] as String).trim();
      final okShape = v['w'] == v['h'] &&
          !rad.contains('%') &&
          (double.tryParse(rad.replaceAll('px', '')) ?? 99) < 20;
      final g = v['grad'] as String;
      final okGrad = g.contains('linear-gradient') &&
          (g.contains('139, 165, 101') || g.contains('106, 133, 74'));
      if (okShape && okGrad) verbsOk++;
      if (v['unit'] != 'px') allPx = false;
      dists.add((v['dist'] as num).toInt());
    }
    // square-era chord law: consecutive centers >= button + gap (squares
    // need corner clearance, circles only needed edge-touching)
    for (final c in chords) {
      if (c < kBtn + kGap) chordsOk = false;
    }
    stdout.writeln('fan geometry: dists=' + dists.toString() +
        ' chords=' + chords.toString() + ' unit=' + (allPx ? 'px' : 'pct(legacy)'));
  }
  check(verbsTotal >= 2 && verbsOk == verbsTotal,
      'fan items are square with the arxa gradient (same treatment as the card)');
  // recalculated radius (operator, 2026-08-26): pixel-exact fan law
  // R = (44+8) / (2 sin(17deg)) = 88.9 - uniform, not %-stretched.
  final uniform = dists.isNotEmpty &&
      dists.every((d) => (d - dists.first).abs() <= 2);
  check(allPx, 'verb positions are pixel-exact (no %-of-dock coupling)');
  check(uniform && dists.isNotEmpty && (dists.first - 89).abs() <= 3,
      'fan radius recalculated for squares: uniform ~89px (was 86 %-stretched)');
  check(chordsOk, 'neighbor chords >= 52px (44px squares + 8px clearance)');

  // Evidence: the open fan with the treated verbs.
  final evFan = '/Volumes/developer_ssd/Developer/totem_labs/'
      'clients/architect-gallore/design/suczka-studio/evidence/dial-card';
  File(evFan + '/arxa-fan-open-1280.png').writeAsBytesSync(await tab.screenshot());

  await js(tab, SR + ".querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 450));
  c = await card(tab);
  stdout.writeln('edit armed: ' + jsonEncode(c));
  check(c['mode'] == 'edit' && c['editVis'] == true && c['restVis'] == false,
      'Edit tap flips the card to the edit face (animated swap)');
  check(c['editHasSvg'] == true, 'edit face carries the edit icon');

  // 5. disarm Edit (verb toggles).
  await js(tab, SR + ".querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 350));
  await js(tab, SR + ".querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 450));
  c = await card(tab);
  check(c['mode'] == '' && c['restVis'] == true && c['editVis'] == false,
      'disarm returns the arxa rest face');

  // 6. arm Comment, then toggle off.
  await js(tab, SR + ".querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 350));
  await js(tab, SR + ".querySelector('[data-verb=comment]').click()");
  await Future.delayed(const Duration(milliseconds: 450));
  c = await card(tab);
  stdout.writeln('comment armed: ' + jsonEncode(c));
  check(c['mode'] == 'comment' && c['commentVis'] == true && c['restVis'] == false,
      'Comment tap flips the card to the comment face');
  check(c['commentHasSvg'] == true, 'comment face carries the comment icon');
  await js(tab, SR + ".querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 350));
  await js(tab, SR + ".querySelector('[data-verb=comment]').click()");
  await Future.delayed(const Duration(milliseconds: 450));
  c = await card(tab);
  check(c['mode'] == '' && c['restVis'] == true,
      'comment disarm returns the arxa rest face');

  // Evidence: rest-face card, clipped at 2x for OCR-able pixels.
  Future<List<int>> clipCard() async {
    final rect = await js(tab, '''
      (() => { const r = ''' + SR + '''.getElementById('dockbtn').getBoundingClientRect();
        return JSON.stringify({x: r.x, y: r.y, w: r.width, h: r.height}); })()
    ''');
    final rc = jsonDecode(rect as String) as Map;
    final shot = await tab.send('Page.captureScreenshot', {
      'format': 'png',
      'clip': {
        'x': (rc['x'] as num).toDouble() - 8,
        'y': (rc['y'] as num).toDouble() - 8,
        'width': (rc['w'] as num).toDouble() + 16,
        'height': (rc['h'] as num).toDouble() + 16,
        'scale': 2,
      },
    });
    return base64Decode(shot['result']['data'] as String);
  }
  final evDir = '/Volumes/developer_ssd/Developer/totem_labs/'
      'clients/architect-gallore/design/suczka-studio/evidence/dial-card';
  Directory(evDir).createSync(recursive: true);
  File(evDir + '/arxa-card-rest-2x.png').writeAsBytesSync(await clipCard());
  // full page with the branded card in the corner
  final full = await tab.screenshot();
  File(evDir + '/page-with-card-1280.png').writeAsBytesSync(full);
  stdout.writeln('evidence: ' + evDir);

  // 8. park law at the new size: sheet open parks the card off-screen.
  await js(tab, SR + ".querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 350));
  await js(tab, SR + ".querySelector('[data-verb=studio]').click()");
  await Future.delayed(const Duration(milliseconds: 900));
  final parked = await js(tab, '''
    (() => { const r = ''' + SR + '''.getElementById('dockbtn').getBoundingClientRect();
      return r.left >= innerWidth || r.top >= innerHeight; })()
  ''') == true;
  check(parked, 'sheet open parks the square card fully off-screen');
  await js(tab, SR + ".getElementById('tclose').click()");
  final back = await poll(tab,
      "getComputedStyle(" + SR + ".getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 4));
  check(back, 'sheet close springs the card back in');

  stdout.writeln('console errors: ' + tab.consoleErrors.length.toString() +
      '; page errors: ' + tab.pageErrors.length.toString());
  tab.consoleErrors.forEach((e) => stdout.writeln('  console: ' + e));
  tab.pageErrors.forEach((e) => stdout.writeln('  page: ' + e));
  if (tab.consoleErrors.isNotEmpty || tab.pageErrors.isNotEmpty) fails++;
  await browser.close();
  stdout.writeln(fails == 0 ? '\nPROBE VERDICT: PASS' : '\nPROBE VERDICT: FAIL');
  exit(fails == 0 ? 0 : 1);
}
