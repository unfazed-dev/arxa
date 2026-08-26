// Tray-park + sheet-children probe (2026-08-26).
//
// Operator report 1: "when tapping for the first time the dial and opening
// the sheet - they both straight away get hidden until move the cursor to
// show the dial then the sheet reappear and stays." -> park pose scoped to
// #dock (fixed same day; assertions 1-3 below).
//
// Operator report 2 (law): "when the sheet is closed any open card must
// close as well - all the sheet children must close with the sheet - by
// children i mean floating cards and anything else." The sheet SPAWNS
// floating children: the Edit-outline rows arm Edit Mode and open the
// floating smart card; the Comments slide opens the pin thread popover
// over the page; the comment composer can float under the sheet too.
// closeTray() must close ALL of them - the island returns to its resting
// state: dial in, nothing else floating.
//
// Assertions:
//   1. the tray stays rendered the entire sampling window
//   2. the host never goes visibility:hidden while the tray is up
//   3. swap law: the DIAL parks (pose scoped to #dock, ~168px off-screen)
//   4. reveal guard: pointer over the open sheet must NOT un-park the dial
//   5. close springs the dial back in
//   6. CHILD LAW: outline row -> card + Edit Mode + amber outline spawn
//   7. CHILD LAW: sheet close closes the card, disarms Edit Mode, clears
//      the selection outline + handles
//   8. CHILD LAW: the comment composer closes with the sheet
//   9. CHILD LAW: the thread popover (Comments slide, real pin) closes
//  10. no card resurrection after the second close
// Console/page errors fail the probe. Evidence PNG lands in the client
// repo. No writes: pins are only READ (the operator's real pin data).
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
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

// One visibility snapshot of the island's layers.
const sampleJs = '''
  JSON.stringify((() => {
    const host = document.getElementById('arxa-dial-host');
    const sr = host.shadowRoot;
    const dock = sr.getElementById('dock');
    const tray = sr.getElementById('tray');
    return {
      trayOpen: tray.classList.contains('open'),
      trayVis: getComputedStyle(tray).visibility,
      hostVis: host.style.visibility || '(unset)',
      hostT: host.style.transform || '(none)',
      dockVis: dock.style.visibility || '(unset)',
      dockT: dock.style.transform || '(none)'
    };
  })())
''';

Future<Map> sample(CdpSession tab) async {
  final raw = await js(tab, sampleJs);
  return jsonDecode(raw as String) as Map;
}

Future<void> main() async {
  final browser = await CdpClient.launch();
  final tab = await browser.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture(dialUrl, settleMs: 2500);
  check(await js(tab, "!!document.getElementById('arxa-dial-host')") == true,
      'dial island mounted');

  // Reveal: real mouse moves into the 50px hot corner (bottom-right).
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  final revealed = await poll(
      tab,
      "getComputedStyle($sr.getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 4));
  check(revealed, 'corner reveal springs the dial in');

  // Open the fan, then Studio -> the tray (glass bottom sheet).
  await js(tab, "$sr.querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  check(await js(tab, "$sr.getElementById('dock').classList.contains('open')") == true,
      'radial fan opens on dock tap');
  await js(tab, "$sr.querySelector('[data-verb=studio]').click()");
  await Future.delayed(const Duration(milliseconds: 250));
  check(await js(tab, "$sr.getElementById('tray').classList.contains('open')") == true,
      'tray (sheet) opens via the Studio verb');
  // Slide render regression: a draft edit used to kill every slide after
  // Edit (renderLedger passed a patch to the draft-shaped counter).
  await Future.delayed(const Duration(milliseconds: 250));
  check(await js(tab, '''    (() => {
      const track = $sr.getElementById('track');
      const slides = [...track.children];
      return slides.length === 5 && slides.every((s) =>
        s.querySelector('.slidebody') &&
        s.querySelector('.slidebody').children.length > 0);
    })()
  ''') == true, 'all five slides render bodies (ledger TypeError regression)');

  // Sample through the park spring (~340ms) plus settle margin.
  final samples = <Map>[];
  for (var i = 0; i < 25; i++) {
    samples.add(await sample(tab));
    await Future.delayed(const Duration(milliseconds: 100));
  }
  final hostHidden = samples.any((s) => s['hostVis'] == 'hidden');
  final trayAlwaysRendered =
      samples.every((s) => s['trayOpen'] == true && s['trayVis'] == 'visible');
  final dialParked = samples.any(
      (s) => s['dockVis'] == 'hidden' && (s['dockT'] as String).contains('168'));
  stdout.writeln('samples[0]  ${jsonEncode(samples.first)}');
  stdout.writeln('samples[24] ${jsonEncode(samples.last)}');
  stdout.writeln('host went hidden during window: $hostHidden');

  check(trayAlwaysRendered, 'the sheet stays rendered the whole window (no vanish)');
  check(!hostHidden, 'host never hides while the sheet is up');
  check(dialParked, 'swap law: the DIAL parks - pose scoped to #dock (~168px off-screen)');

  // Evidence: sheet open + dial parked, page fully visible.
  final shot = await tab.screenshot();
  final evDir = '/Volumes/developer_ssd/Developer/totem_labs/'
      'clients/architect-gallore/design/suczka-studio/evidence/tray-park';
  Directory(evDir).createSync(recursive: true);
  File('$evDir/dial-tray-open-1280.png').writeAsBytesSync(shot);
  stdout.writeln('evidence: $evDir/dial-tray-open-1280.png');

  // Reveal guard: pointer over the open sheet must NOT spring the dial in.
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseMoved', 'x': 640, 'y': 690});
  await Future.delayed(const Duration(milliseconds: 700));
  final afterHover = await sample(tab);
  check(afterHover['dockVis'] == 'hidden',
      'pointer over the sheet does NOT un-park the dial (swap law guard)');

  // ---- CHILD LAW, part 1: the Edit-outline row spawns floating children.
  check(await js(tab, '''    (() => {
      const row = $sr.querySelector('[data-slide=edit] .row');
      if (!row) return false;
      row.click();
      return true;
    })()
  ''') == true, 'outline row tapped inside the open sheet');
  await Future.delayed(const Duration(milliseconds: 500));
  check(await js(tab, "$sr.getElementById('card').classList.contains('open')") == true,
      'sheet child spawned: the floating card opens from the outline');
  check(await js(tab, "$sr.querySelector('[data-verb=edit]').classList.contains('on')") == true,
      'Edit Mode armed from the sheet outline');
  // CSSOM serializes #f59e0b as rgb(245, 158, 11) - match the readback.
  check(await js(tab, '''
    [...document.querySelectorAll('[data-arxa-id]')].some((e) =>
      (e.style.outline || '').includes('rgb(245, 158, 11)'))
  ''') == true, 'amber selection outline on the canvas');

  // Close #1: children must close WITH the sheet.
  await js(tab, "$sr.getElementById('tclose').click()");
  final backIn = await poll(
      tab,
      "getComputedStyle($sr.getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 4));
  check(backIn, 'tray close springs the dial back in');
  final closed = await sample(tab);
  check(closed['trayOpen'] == false, 'tray closed cleanly');
  check(await js(tab, "!$sr.getElementById('card').classList.contains('open')") == true,
      'CHILD LAW: the floating card closes with the sheet');
  check(await js(tab, "!$sr.querySelector('[data-verb=edit]').classList.contains('on')") == true,
      'CHILD LAW: Edit Mode disarms with the sheet');
  check(await js(tab, '''
    ![...document.querySelectorAll('[data-arxa-id]')].some((e) =>
      (e.style.outline || '').includes('rgb(245, 158, 11)'))
  ''') == true, 'CHILD LAW: the amber selection outline leaves the canvas');
  check(await js(tab, "$sr.getElementById('handles').children.length === 0") == true,
      'CHILD LAW: selection handles cleared');

  // ---- CHILD LAW, part 2: the comment composer. Real flow: fan ->
  // Comment verb -> click the design (composer opens; no server write).
  await js(tab, "$sr.querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 350));
  await js(tab, "$sr.querySelector('[data-verb=comment]').click()");
  await Future.delayed(const Duration(milliseconds: 250));
  final pt2 = await js(tab, '''
    (() => {
      const els = [...document.querySelectorAll('[data-arxa-id]')];
      for (const el of els) {
        const t = (el.textContent || '').trim();
        if (!t || t.length < 3 || el.querySelector('[data-arxa-id]')) continue;
        const r = el.getBoundingClientRect();
        if (r.width > 40 && r.height > 12 && r.x >= 0 && r.y >= 0 &&
            r.x + r.width <= innerWidth && r.y + r.height <= innerHeight) {
          return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2)};
        }
      }
      return null;
    })()
  ''');
  if (pt2 is Map) {
    final cx = (pt2['x'] as num).toInt(), cy = (pt2['y'] as num).toInt();
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': cx, 'y': cy});
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mousePressed', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1});
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseReleased', 'x': cx, 'y': cy, 'button': 'left', 'clickCount': 1});
    await Future.delayed(const Duration(milliseconds: 400));
    check(await js(tab, "$sr.getElementById('composer').classList.contains('open')") == true,
        'sheet child spawned: the comment composer opens on the design');

    // Sheet #2 opens OVER the floating composer.
    await js(tab, "$sr.querySelector('#dockbtn').click()");
    await Future.delayed(const Duration(milliseconds: 350));
    await js(tab, "$sr.querySelector('[data-verb=studio]').click()");
    await Future.delayed(const Duration(milliseconds: 400));
    check(await js(tab, "$sr.getElementById('tray').classList.contains('open')") == true,
        'sheet reopens over the floating composer');

    // ---- CHILD LAW, part 3: the thread popover from the Comments slide
    // (reads the operator's real pin data; writes nothing).
    var threadChild = false;
    final dotTapped = await js(tab, '''      (() => {
        const dot = [...$sr.querySelectorAll('.dotbtn')]
          .find((d) => /comments/i.test(d.getAttribute('aria-label') || ''));
        if (!dot) return false;
        dot.click();
        return true;
      })()
    ''') == true;
    if (dotTapped) {
      await Future.delayed(const Duration(milliseconds: 600));
      final rowTapped = await js(tab, '''        (() => {
          const slide = $sr.querySelector('[data-slide=comments]');
          if (!slide) return false;
          const row = slide.querySelector('.row');
          if (!row) return false;
          row.click();
          return true;
        })()
      ''') == true;
      if (rowTapped) {
        await Future.delayed(const Duration(milliseconds: 400));
        threadChild = await js(tab,
                "$sr.getElementById('thread').classList.contains('open')") ==
            true;
        check(threadChild,
            'sheet child spawned: thread popover opens from the Comments slide');
      }
    }
    if (!threadChild) {
      stdout.writeln('SKIP thread-child (no same-route pin rows this run)');
    }

    // Close #2: EVERY child gone.
    await js(tab, "$sr.getElementById('tclose').click()");
    await Future.delayed(const Duration(milliseconds: 600));
    check(await js(tab, "!$sr.getElementById('composer').classList.contains('open')") == true,
        'CHILD LAW: the comment composer closes with the sheet');
    if (threadChild) {
      check(await js(tab, "!$sr.getElementById('thread').classList.contains('open')") == true,
          'CHILD LAW: the thread popover closes with the sheet');
    }
    check(await js(tab, "!$sr.getElementById('card').classList.contains('open')") == true,
        'CHILD LAW: no card resurrection after the second close');
  } else {
    check(false, 'selectable element for the composer flow');
  }

  // BOTH channels: console.error AND uncaught page exceptions. The lens
  // files them separately (consoleErrors / pageErrors); asserting only the
  // first is how the 2026-08-26 ledger TypeError stayed invisible while
  // four tray slides rendered blank.
  stdout.writeln('console errors: ${tab.consoleErrors.length}; page errors: ${tab.pageErrors.length}');
  for (var e in tab.consoleErrors) {
    stdout.writeln('  console: $e');
  }
  for (var e in tab.pageErrors) {
    stdout.writeln('  page: $e');
  }
  if (tab.consoleErrors.isNotEmpty || tab.pageErrors.isNotEmpty) fails++;
  await browser.close();
  stdout.writeln(fails == 0 ? '\nPROBE VERDICT: PASS' : '\nPROBE VERDICT: FAIL');
  exit(fails == 0 ? 0 : 1);
}
