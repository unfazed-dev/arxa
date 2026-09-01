// Live-instance artifact-viewer handle smoke (2026-09): proves the RUNNING
// app serves the fixed arxa-frame — trusted drags on the viewer edge handle
// move the column (the packaged-app stale-payload regression shipped the
// inverted sign to :7891; this is the delivery gate).
//
// Differences from tool/lens_frame_drag.dart (isolated-rig evidence driver):
// no rig org — the viewer column opens on the public ingress event alone
// (panels.viewer > 0; a missing file resolves to a graceful panel state with
// no console errors, proven in the rig), and assertions are behavioral
// deltas, not absolute defaults. Overlay hit-test reported for diagnosis.
// Usage: dart run tool/lens_av_handle_smoke.dart <url> <out.png>
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_av_handle_smoke.dart <url> <out.png>');
    exit(2);
  }
  final url = argv[0];
  final out = File(argv[1])..parent.createSync(recursive: true);
  final failures = <String>[];
  final notes = <String>[];

  const frameSel = '.aXa_fr_frame';
  const viewerHandle = '.aXa_fr_handle[data-side=viewer]';
  const colsJs =
      "(()=>{const g=document.querySelector('$frameSel').style.gridTemplateColumns;"
      "const p=g.split(' ').filter(x=>x.endsWith('px')).map(parseFloat);"
      "return {sidebar:p[0],details:p[1],viewer:p[2],raw:g}})()";

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1600, 900);
    await tab.navigateAndSettle(url, settleMs: 3500);

    Future<num> viewerWidth() async {
      final r = await tab.evaluate(colsJs);
      return (r['viewer'] as num?) ?? -1;
    }

    // First-run notice modal: dismiss when present.
    await tab.evaluate(
        "(()=>{const b=[...document.querySelectorAll('button')].find(x=>/continue/i.test(x.textContent));if(b){b.click();return true}return false})()");
    await Future<void>.delayed(const Duration(milliseconds: 700));

    // Open the viewer column via the public ingress event (no file needed —
    // the column geometry is the surface under test).
    await tab.evaluate(
        "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'lens-smoke.md'}}));true");
    if (!await tab.waitForSelector(viewerHandle)) {
      failures.add('viewer handle never appeared');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Hit-test diagnosis: is the handle actually the top element at its
    // center? (A full-frame overlay would eat the drag.)
    final hit = await tab.evaluate(
        "(()=>{const h=document.querySelector('$viewerHandle');if(!h)return 'no-handle';"
        "const r=h.getBoundingClientRect();const el=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);"
        "return el===h?'handle':(el?el.className.toString().slice(0,60):'null')})()");
    notes.add('hit-test at handle center: $hit');

    final v0 = await viewerWidth();
    notes.add('baseline viewer width: $v0');
    if (v0 < 0) failures.add('viewer column not measurable');

    // T1: drag LEFT 200 → grows ~200 (or clamps at the concession max).
    final s = (await tab.evaluate(colsJs))['sidebar'] as num? ?? -1;
    final d = (await tab.evaluate(colsJs))['details'] as num? ?? -1;
    final maxV = 1600 - s - (d > 0 ? d : 0) - 640;
    final dragged = await tab.dragSelector(viewerHandle, dx: -200, dy: 0);
    if (!dragged) failures.add('could not grab the viewer handle');
    final v1 = await viewerWidth();
    final want1 = v0 + 200 > maxV ? maxV : v0 + 200;
    final ok1 = (v1 - want1).abs() <= 6;
    notes.add('${ok1 ? 'PASS' : 'FAIL'}  drag LEFT 200 — $v0 -> $v1 (want $want1, max $maxV)');
    if (!ok1) failures.add('left drag did not grow the viewer');

    // T3: drag far RIGHT → 320 floor.
    await tab.dragSelector(viewerHandle, dx: 3000, dy: 0);
    final v3 = await viewerWidth();
    final ok3 = (v3 - 320).abs() <= 2;
    notes.add('${ok3 ? 'PASS' : 'FAIL'}  drag RIGHT far — $v3 (want 320 floor)');
    if (!ok3) failures.add('right drag did not clamp at the 320 floor');

    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    if (errors.isNotEmpty) {
      failures.add('${errors.length} console/page error(s): ${errors.first}');
    }
    out.writeAsBytesSync(await tab.screenshot());
  } finally {
    await client.close();
  }

  for (final n in notes) {
    stdout.writeln(n);
  }
  if (failures.isNotEmpty) {
    stderr.writeln('av handle smoke FAILED: $url\n  ${failures.join('\n  ')}');
    exit(1);
  }
  stdout.writeln('av handle smoke ok: $url -> ${out.path}');
}
