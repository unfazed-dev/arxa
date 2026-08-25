// Ship probe (slice 5): live status from the real repo, slide rendering,
// disabled-state honesty, and the SAFE refusal path (clean repo -> 409).
// Deliberately NOT exercising PR-open/merge on the operator's repo —
// those verbs are operator taps by law; the git mechanics themselves are
// proven by design_ship_test.dart's captured-argv tests.
//
// 2026-08-25 rework — TRUTH-DERIVED EXPECTATIONS. The probe used to
// hardcode a parked-on-main world (branch main, no PR, a 'wrangler'
// blocker). Three of its checks then FAILED on real, legitimate state:
// the repo sat on design/dial-* with PR #1 open, and wrangler resolved
// via npx (the blocker correctly vanished). The probe now derives every
// expectation from ground truth (git + gh on the real repo, the eject
// dir on disk, npx resolution) and asserts the SERVER AGREES with it.
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const SR = "document.getElementById('arxa-dial-host').shadowRoot";
const clientDir = '/Volumes/developer_ssd/Developer/totem_labs/'
    'clients/architect-gallore';
const artifactDir = '${clientDir}/design/suczka-studio';

int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}

String gitBranch() {
  final r = Process.runSync(
      'git', ['-C', clientDir, 'branch', '--show-current']);
  return (r.stdout as String).trim();
}

/// The open PR for HEAD, exactly the way the design server asks for it.
Map<String, dynamic>? ghPr() {
  final r = Process.runSync(
      'gh', ['pr', 'view', '--json', 'number,state'],
      workingDirectory: clientDir);
  if (r.exitCode != 0) return null;
  return jsonDecode(r.stdout as String) as Map<String, dynamic>;
}

/// Same resolution chain the server's deploy gate uses (_wr in
/// design_ship.dart): PATH wrangler, else npx. Two-sided blocker check.
bool wranglerResolvable() {
  final r = Process.runSync('sh', ['-c', 'wrangler --version >/dev/null 2>&1 || npx --yes wrangler --version >/dev/null 2>&1']);
  return r.exitCode == 0;
}

Future<void> main() async {
  final truthBranch = gitBranch();
  final truthPr = ghPr();
  final ejectExists = Directory('${artifactDir}/eject').existsSync();
  final wrOk = wranglerResolvable();
  stdout.writeln('ground truth: branch=$truthBranch pr=${truthPr == null ? "none" : "#${truthPr['number']} ${truthPr['state']}"} ejectDir=$ejectExists wrangler=$wrOk');

  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);

  // 1. live status must agree with ground truth
  final st = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/ship/status');
      return await r.json();
    })()
  ''');
  final s = (st as Map).cast<String, dynamic>();
  check(s['error'] == null, 'status answers without error');
  check(s['repo'] == 'unfazed-dev/architect-gallore', 'repo slug (${s['repo']})');
  check(s['branch'] == truthBranch,
      'status branch matches git (${s['branch']} vs $truthBranch)');
  final spr = s['pr'] as Map<String, dynamic>?;
  if (truthPr == null) {
    check(spr == null, 'status agrees: no open PR');
  } else {
    check(spr != null &&
        spr['number'] == truthPr['number'] &&
        spr['state'] == truthPr['state'],
        'status agrees: PR #${truthPr['number']} ${truthPr['state']}');
  }

  // 2. safe refusal: clean artifact -> 409 nothing to ship
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

  // 3b. deploy gates: every blocker names a KNOWN gate; eject + wrangler
  // are checked two-sided against the machine's actual state.
  final ready = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/ship/deploy/ready');
      return await r.json();
    })()
  ''');
  final rd2 = (ready as Map).cast<String, dynamic>();
  final blockers = (rd2['blockers'] as List).map((b) => b.toString()).toList();
  const knownGates = [
    'no deployable dir',
    'CLOUDFLARE',
    'ARXA_PAGES_PROJECT',
    'wrangler unresolvable',
  ];
  check(blockers.isNotEmpty, 'deploy blockers listed (${blockers.length})');
  check(blockers.every((b) => knownGates.any((g) => b.contains(g))),
      'every blocker names a known gate (${blockers.join(' | ')})');
  check(blockers.any((b) => b.contains('no deployable dir')) == !ejectExists,
      'eject blocker iff no eject dir (dir=$ejectExists)');
  check(blockers.any((b) => b.contains('wrangler')) == !wrOk,
      'wrangler blocker iff unresolvable (resolvable=$wrOk)');
  final dep = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/ship/deploy', {method: 'POST'});
      return {status: r.status, error: (await r.json()).error};
    })()
  ''');
  final dp = (dep as Map).cast<String, dynamic>();
  check(dp['status'] == 409 && (dp['error'] as String) == blockers.join('; '),
      'deploy tap refuses with exactly the blockers (${dp['status']})');

  // 4. the slide renders pipeline facts + honest disabled states.
  // Expected states are DERIVED from the same status the island renders.
  final onMain = s['branch'] == 'main';
  final dirty = (s['dirty'] as num?)?.toInt() ?? 0;
  final prOpenGreen = spr != null &&
      spr['state'] == 'OPEN' &&
      spr['mergeable'] == true &&
      spr['green'] == true;
  final expectPrDisabled = !(onMain && spr == null && dirty > 0);
  final expectMergeDisabled = !prOpenGreen;
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
  // The slide renders its facts from an async ship-status fetch (gh latency
  // varies seconds); a fixed wait raced it and read an empty body. Poll for
  // the CONTENT, not the clock.
  var slideReady = false;
  final slideDeadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(slideDeadline)) {
    slideReady = await js(tab, '''(() => {
      const b = $SR.querySelector('[data-slide=ship]');
      return !!(b && b.textContent.includes('Deploy gates'));
    })()''') == true;
    if (slideReady) break;
    await Future.delayed(const Duration(milliseconds: 250));
  }
  check(slideReady, 'ship slide rendered its content');
  final slide = await js(tab, '''
    (() => {
      const body = $SR.querySelector('[data-slide=ship]');
      const txt = body ? body.textContent : '';
      const btns = body ? [...body.querySelectorAll('button')] : [];
      const pr = btns.find(b => b.textContent.includes('Branch + PR'));
      const merge = btns.find(b => b.textContent.includes('Merge'));
      const cta = $SR.querySelector('#cta');
      return {
        facts: txt.includes('${s['repo']}') && txt.includes('${s['branch']}'),
        prDisabled: pr ? pr.disabled : null,
        mergeDisabled: merge ? merge.disabled : null,
        saysGreen: txt.includes('Automation up to the button'),
        gatesShown: txt.includes('Deploy gates'),
        ctaDisabled: cta ? cta.disabled : null,
      };
    })()
  ''');
  final sl = (slide as Map).cast<String, dynamic>();
  check(sl['facts'] == true, 'slide shows repo + branch facts (live branch ${s['branch']})');
  check(sl['prDisabled'] == expectPrDisabled,
      'Branch+PR disabled iff not (main, no PR, dirty) (${sl['prDisabled']}, expected $expectPrDisabled)');
  check(sl['mergeDisabled'] == expectMergeDisabled,
      'Merge disabled iff not (OPEN+mergeable+green) (${sl['mergeDisabled']}, expected $expectMergeDisabled)');
  check(sl['saysGreen'] == true, 'slide states the up-to-the-button law');
  check(sl['gatesShown'] == true, 'slide lists the deploy gates');
  check(sl['ctaDisabled'] == true, 'Deploy CTA disabled until gates pass');

  check(tab.consoleErrors.isEmpty, 'console clean (${tab.consoleErrors.length})');
  stdout.writeln(fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await client.close();
  exit(fails == 0 ? 0 : 1);
}
