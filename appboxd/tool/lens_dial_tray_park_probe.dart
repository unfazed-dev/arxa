// Tray-park visibility probe (2026-08-26).
//
// Operator report: "when tapping for the first time the dial and opening
// the sheet - they both straight away get hidden until move the cursor to
// show the dial then the sheet reappear and stays."
//
// Root cause this probe pins (see dial_island.js dialApplyPose): the park
// pose - transform + opacity + visibility:hidden - was written onto the
// SHARED host (#arxa-dial-host) that carries the dock AND the tray AND the
// card/thread/composer/pins. openTray() -> dialPark() -> spring settles ->
// host.style.visibility='hidden' ~340ms after the sheet opens, so the
// just-opened sheet vanished with the dial. Only the 50px hot corner could
// spring it back (dialShow), which is exactly the operator's workaround.
//
// Assertions (all must hold on FIXED code):
//   1. the tray stays rendered the entire sampling window
//   2. the host never goes visibility:hidden while the tray is up
//   3. swap law still honored: the DIAL parks - scoped pose on #dock
//      (dock visibility:hidden + transform ~168px off-screen)
//   4. reveal guard: pointer over the open tray must NOT spring the dial
//      back in (tray open => dial stays parked until close)
//   5. close tray (#tclose) springs the dial back in
// Console/page errors fail the probe. Evidence PNG lands in the client repo.
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

// One visibility snapshot of the island's layers.
const SAMPLE = '''
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
  final raw = await js(tab, SAMPLE);
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
      "getComputedStyle(" + SR + ".getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 4));
  check(revealed, 'corner reveal springs the dial in');

  // Open the fan, then Studio -> the tray (glass bottom sheet).
  await js(tab, SR + ".querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  check(await js(tab, SR + ".getElementById('dock').classList.contains('open')") == true,
      'radial fan opens on dock tap');
  await js(tab, SR + ".querySelector('[data-verb=studio]').click()");
  await Future.delayed(const Duration(milliseconds: 250));
  check(await js(tab, SR + ".getElementById('tray').classList.contains('open')") == true,
      'tray (sheet) opens via the Studio verb');

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
  stdout.writeln('samples[0]  ' + jsonEncode(samples.first));
  stdout.writeln('samples[12] ' + jsonEncode(samples[12]));
  stdout.writeln('samples[24] ' + jsonEncode(samples.last));
  stdout.writeln('host went hidden during window: ' + hostHidden.toString());

  check(trayAlwaysRendered, 'the sheet stays rendered the whole window (no vanish)');
  check(!hostHidden, 'host never hides while the sheet is up');
  check(dialParked, 'swap law: the DIAL parks - pose scoped to #dock (~168px off-screen)');

  // Evidence: sheet open + dial parked, page fully visible.
  final shot = await tab.screenshot();
  final evDir = '/Volumes/developer_ssd/Developer/totem_labs/'
      'clients/architect-gallore/design/suczka-studio/evidence/tray-park';
  Directory(evDir).createSync(recursive: true);
  File(evDir + '/dial-tray-open-1280.png').writeAsBytesSync(shot);
  stdout.writeln('evidence: ' + evDir + '/dial-tray-open-1280.png');

  // Reveal guard: pointer over the open tray must NOT spring the dial in.
  await tab.send('Input.dispatchMouseEvent',
      {'type': 'mouseMoved', 'x': 640, 'y': 690});
  await Future.delayed(const Duration(milliseconds: 700));
  final afterHover = await sample(tab);
  check(afterHover['dockVis'] == 'hidden',
      'pointer over the sheet does NOT un-park the dial (swap law guard)');

  // Close: the dial springs back in.
  await js(tab, SR + ".getElementById('tclose').click()");
  final backIn = await poll(
      tab,
      "getComputedStyle(" + SR + ".getElementById('dockbtn')).visibility === 'visible'",
      const Duration(seconds: 4));
  check(backIn, 'tray close springs the dial back in');
  final closed = await sample(tab);
  check(closed['trayOpen'] == false, 'tray closed cleanly');

  stdout.writeln('console errors: ' + tab.consoleErrors.length.toString());
  if (tab.consoleErrors.isNotEmpty) fails++;
  await browser.close();
  stdout.writeln(fails == 0 ? '\nPROBE VERDICT: PASS' : '\nPROBE VERDICT: FAIL');
  exit(fails == 0 ? 0 : 1);
}
