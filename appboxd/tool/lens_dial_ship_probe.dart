// Ship probe (slice 5): live status from the real repo, slide rendering,
// disabled-state honesty, and the SAFE refusal path (clean repo → 409).
// Deliberately NOT exercising PR-open/merge on the operator's repo —
// those verbs are operator taps by law; the git mechanics themselves are
// proven by design_ship_test.dart's captured-argv tests.
import 'dart:io';
import 'package:appboxd/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const SR = "document.getElementById('arxa-dial-host').shadowRoot";
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

  // 1. live status: real repo, branch, no PR
  final st = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/ship/status');
      return await r.json();
    })()
  ''');
  final s = (st as Map).cast<String, dynamic>();
  check(s['error'] == null, 'status answers without error');
  check(s['repo'] == 'unfazed-dev/normal_is_boring', 'repo slug (${s['repo']})');
  check(s['branch'] == 'main', 'branch main (${s['branch']})');
  check(s['pr'] == null, 'no open PR');

  // 2. safe refusal: clean artifact → 409 nothing to ship
  final refuse = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/ship/pr', {method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({title: 'probe'})});
      return {status: r.status, error: (await r.json()).error};
    })()
  ''');
  final rf = (refuse as Map).cast<String, dynamic>();
  check(rf['status'] == 409 && (rf['error'] as String? ?? '').contains('nothing to ship'),
      'clean repo refuses PR safely (${rf['status']}: ${rf['error']})');

  // 3. guest 403
  final guest = await js(tab, '''
    (async () => {
      const m = await (await fetch('/__dial/share', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'})).json();
      const r = await fetch('/__dial/ship/status?dial=' + m.token);
      return r.status;
    })()
  ''');
  check(guest == 403, 'guest ship status 403 (got $guest)');

  // 4. the slide renders pipeline facts + honest disabled states
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  await js(tab, '$SR.querySelector("#dockbtn").click()');
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$SR.querySelector('[data-verb=studio]').click()");
  await Future.delayed(const Duration(milliseconds: 700));
  await js(tab, "$SR.querySelectorAll('#dots .dotbtn')[4].click()");
  await Future.delayed(const Duration(milliseconds: 1400));
  final slide = await js(tab, '''
    (() => {
      const body = $SR.querySelector('[data-slide=ship]');
      const txt = body ? body.textContent : '';
      const btns = body ? [...body.querySelectorAll('button')] : [];
      const pr = btns.find(b => b.textContent.includes('Branch + PR'));
      const merge = btns.find(b => b.textContent.includes('Merge'));
      return {
        facts: txt.includes('unfazed-dev/normal_is_boring') && txt.includes('main'),
        prDisabled: pr ? pr.disabled : null,
        mergeDisabled: merge ? merge.disabled : null,
        saysGreen: txt.includes('Automation up to the button'),
      };
    })()
  ''');
  final sl = (slide as Map).cast<String, dynamic>();
  check(sl['facts'] == true, 'slide shows repo + branch facts');
  check(sl['prDisabled'] == true, 'Branch+PR disabled (nothing dirty)');
  check(sl['mergeDisabled'] == true, 'Merge disabled (no PR)');
  check(sl['saysGreen'] == true, 'slide states the up-to-the-button law');

  check(tab.consoleErrors.isEmpty, 'console clean (${tab.consoleErrors.length})');
  stdout.writeln(fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await client.close();
  exit(fails == 0 ? 0 : 1);
}
