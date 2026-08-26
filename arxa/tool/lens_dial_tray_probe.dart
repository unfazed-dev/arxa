// Tray probe (rework 2026-08-24): proves the 3-trigger fan, the Studio
// tray (opens, parks the dial, 5 slides author / 1 slide guest), the tray
// close spring-back, the floating card on a real element, and a clean
// console — in real Chrome over the live design server.
import 'dart:io';
import 'package:arxa/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> mouse(CdpSession t, int x, int y) async {
  await t.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
}
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);

  // 1. hot corner reveal
  for (var i = 0; i < 5; i++) {
    await mouse(tab, 1276 - i, 796 - i);
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  final shown = await js(tab, '$sr.querySelector("#dockbtn").getBoundingClientRect().x');
  check((shown as num) > 900, 'dial revealed from hot corner (x=$shown)');

  // 2. fan: exactly 3 triggers with the right ids
  await js(tab, '$sr.querySelector("#dockbtn").click()');
  await Future.delayed(const Duration(milliseconds: 500));
  final ids = await js(tab, '''
    (() => { return [...$sr.querySelectorAll('.verb')].map(v => v.dataset.verb).join(','); })()
  ''');
  check(ids == 'edit,comment,studio', 'fan = 3 triggers ($ids)');

  // 3. no-overlap: neighbor centers >= 40px apart
  final chords = await js(tab, '''
    (() => {
      const vs = [...$sr.querySelectorAll('.verb')].map(v => {
        const r = v.getBoundingClientRect(); return {x: r.x + r.width/2, y: r.y + r.height/2};
      });
      let m = 1e9;
      for (let i = 1; i < vs.length; i++) m = Math.min(m, Math.hypot(vs[i].x - vs[i-1].x, vs[i].y - vs[i-1].y));
      return Math.round(m);
    })()
  ''');
  check((chords as num) >= 40, 'fan neighbors never overlap (min chord=$chords px)');

  // 4. Studio: tray opens, dial parks, 5 slides + 5 dots
  await js(tab, "$sr.querySelector('[data-verb=studio]').click()");
  await Future.delayed(const Duration(milliseconds: 700));
  final trayOpen = await js(tab, '$sr.querySelector("#tray").classList.contains("open")');
  final dockX = await js(tab, '$sr.querySelector("#dockbtn").getBoundingClientRect().x');
  final slides = await js(tab, '$sr.querySelectorAll("#track .slide").length');
  final dotsN = await js(tab, '$sr.querySelectorAll("#dots .dotbtn").length');
  final slideIds = await js(tab, '''
    (() => { return [...$sr.querySelectorAll('#track .slide')].map(s => s.dataset.slide).join(','); })()
  ''');
  check(trayOpen == true, 'tray opens on Studio');
  check((dockX as num) > 1300, 'dial parked while tray open (x=$dockX)');
  check(slides == 5 && dotsN == 5, '5 slides, 5 dots ($slides/$dotsN)');
  check(slideIds == 'edit,comments,settings,tweak,ship', 'slide order ($slideIds)');

  // 5. CTA per slide: Edit -> Commit, Comments -> Share, Ship -> Deploy
  await js(tab, "$sr.querySelectorAll('#dots .dotbtn')[1].click()");
  await Future.delayed(const Duration(milliseconds: 900));
  final ctaComments = await js(tab, '$sr.querySelector("#cta").textContent');
  await js(tab, "$sr.querySelectorAll('#dots .dotbtn')[4].click()");
  await Future.delayed(const Duration(milliseconds: 900));
  final ctaShip = await js(tab, '$sr.querySelector("#cta").textContent');
  final ctaDisabled = await js(tab, '$sr.querySelector("#cta").disabled');
  check(ctaComments == 'Share', 'Comments CTA = Share ($ctaComments)');
  check(ctaShip == 'Deploy' && ctaDisabled == true, 'Ship CTA = Deploy, disabled until slice 6');

  // 6. close: dial springs back
  await js(tab, '$sr.querySelector("#tclose").click()');
  await Future.delayed(const Duration(milliseconds: 900));
  final dockBack = await js(tab, '$sr.querySelector("#dockbtn").getBoundingClientRect().x');
  final trayClosed = await js(tab, '$sr.querySelector("#tray").classList.contains("open")');
  check((dockBack as num) < 1300 && trayClosed == false, 'tray close springs dial back (x=$dockBack)');

  // 7. Edit trigger -> select a real element -> card opens with facets
  await js(tab, '$sr.querySelector("#dockbtn").click()');
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$sr.querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  final clicked = await js(tab, '''
    (() => {
      const el = document.querySelector('[data-arxa-id]');
      if (!el) return 'no data-arxa-id';
      const r = el.getBoundingClientRect();
      return {x: Math.round(r.x + r.width/2), y: Math.round(r.y + Math.min(r.height/2, 30))};
    })()
  ''');
  if (clicked is Map) {
    await mouse(tab, (clicked['x'] as num).toInt(), (clicked['y'] as num).toInt());
    await tab.send('Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': (clicked['x'] as num).toInt(), 'y': (clicked['y'] as num).toInt(), 'button': 'left', 'clickCount': 1});
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': (clicked['x'] as num).toInt(), 'y': (clicked['y'] as num).toInt(), 'button': 'left', 'clickCount': 1});
    await Future.delayed(const Duration(milliseconds: 500));
    final cardOpen = await js(tab, '$sr.querySelector("#card").classList.contains("open")');
    final facets = await js(tab, '$sr.querySelectorAll("#card .facet").length');
    final inViewport = await js(tab, '''
      (() => { const r = $sr.querySelector("#card").getBoundingClientRect();
        return r.x >= 0 && r.x + r.width <= innerWidth && r.y >= 0 && r.y + r.height <= innerHeight; })()
    ''');
    check(cardOpen == true, 'card opens on element click');
    check((facets as num) >= 2, 'card shows facet editors ($facets)');
    check(inViewport == true, 'card clamped in viewport');
    await js(tab, 'document.activeElement != null && null');
  } else {
    check(false, 'artifact has data-el to select ($clicked)');
  }

  // 8. console clean
  await Future.delayed(const Duration(milliseconds: 300));
  stdout.writeln('console errors: ${tab.consoleErrors.length}');
  check(tab.consoleErrors.isEmpty, 'console clean');

  // 9. guest: mint a token, fan = 2 triggers, tray = comments only
  final guest = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/share', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'});
      const j = await r.json();
      return j.token;
    })()
  ''');
  if (guest is String && guest.isNotEmpty) {
    final tab2 = await client.newTab();
    await tab2.setViewport(390, 844);
    await tab2.navigateAndSettleForCapture('http://127.0.0.1:4319/?dial=$guest', settleMs: 2500);
    for (var i = 0; i < 5; i++) {
      await tab2.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': 386 - i, 'y': 840 - i});
      await Future.delayed(const Duration(milliseconds: 80));
    }
    await Future.delayed(const Duration(milliseconds: 900));
    await tab2.evaluate("document.getElementById('arxa-dial-host').shadowRoot.querySelector('#dockbtn').click()");
    await Future.delayed(const Duration(milliseconds: 500));
    final gids = await tab2.evaluate(
      "(() => { return [...document.getElementById('arxa-dial-host').shadowRoot.querySelectorAll('.verb')].map(v => v.dataset.verb).join(','); })()");
    await tab2.evaluate("document.getElementById('arxa-dial-host').shadowRoot.querySelector('[data-verb=studio]').click()");
    await Future.delayed(const Duration(milliseconds: 700));
    final gslides = await tab2.evaluate(
      "document.querySelectorAll('#arxa-dial-host').length && [...document.getElementById('arxa-dial-host').shadowRoot.querySelectorAll('#track .slide')].map(s => s.dataset.slide).join(',')");
    check(gids == 'comment,studio', 'guest fan = comment+studio ($gids)');
    check(gslides == 'comments', 'guest tray = comments only ($gslides)');
    stdout.writeln('guest console errors: ${tab2.consoleErrors.length}');
  } else {
    check(false, 'share mint returned a token');
  }

  stdout.writeln(fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await client.close();
  exit(fails == 0 ? 0 : 1);
}
