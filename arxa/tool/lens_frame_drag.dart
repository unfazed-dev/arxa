// arxa-frame viewer drag evidence driver (2026-09 inverted-sign regression).
// Boots against an isolated evidence instance, opens the org lane, opens the
// viewer column, then drives TRUSTED drags on the viewer edge handle
// (CdpSession.dragSelector → Input.dispatchMouseEvent — synthetic JS events
// cannot pass DragHandle's setPointerCapture/hasPointerCapture gates).
//
// Asserts (docs/plans/artifact-viewer-docked-column.md D88–D93):
//   T0  viewer opens at the 420 default
//   T1  drag LEFT 200 → viewer grows ~200 (width FOLLOWS the drag; the
//       regression grew toward the window edge and clamped at 320 going left)
//   T2  drag RIGHT 80 → viewer shrinks ~80
//   T3  drag RIGHT far → 320 floor
//   T4  maximize ⤢ → viewport − sidebar(280) − details(0) − 640 = 360
//   T5  sidebar dragged 280→264 → max becomes 1280−264−640 = 376
// Console/page errors always fail (lens doctrine).
// Usage: dart run tool/lens_frame_drag.dart <url> <outDir>
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_frame_drag.dart <url> <outDir>');
    exit(2);
  }
  final url = argv[0];
  final outDir = Directory(argv[1])..createSync(recursive: true);
  final failures = <String>[];
  final notes = <String>[];

  const frameSel = '.aXa_fr_frame';
  const viewerHandle = '.aXa_fr_handle[data-side=viewer]';
  const sidebarHandle = '.aXa_fr_handle[data-side=sidebar]';
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

    Future<Map<String, num>> cols() async {
      final r = await tab.evaluate(colsJs);
      return {
        'sidebar': (r['sidebar'] as num?) ?? -1,
        'details': (r['details'] as num?) ?? -1,
        'viewer': (r['viewer'] as num?) ?? -1,
      };
    }

    Future<void> shot(String name) async {
      final png = await tab.screenshot();
      File('${outDir.path}/$name').writeAsBytesSync(png);
    }

    void expectEq(String label, num got, num want, {num tol = 2}) {
      final ok = (got - want).abs() <= tol;
      notes.add('${ok ? 'PASS' : 'FAIL'}  $label — got $got, want $want (±$tol)');
      if (!ok) failures.add(label);
    }

    // First-run notice modal (seen on fresh DSH_HOME boots): dismiss.
    await tab.evaluate(
        "(()=>{const b=[...document.querySelectorAll('button')].find(x=>/continue/i.test(x.textContent));if(b){b.click();return true}return false})()");
    await Future<void>.delayed(const Duration(milliseconds: 700));

    // Open the rig org through the sidebar's host action route (deterministic;
    // the OrgBrowser click dance is not the surface under test).
    final opened = await tab.evaluate(
        "fetch('/__arxa/sidebar/action',{method:'POST',headers:{'content-type':'application/json'},"
        "body:JSON.stringify({action:'org.open',arg:'dragorg'})}).then(r=>r.json()).catch(e=>String(e))");
    notes.add('org.open response: $opened');
    if (opened is! Map || opened['ok'] != true) {
      failures.add('org.open failed for dragorg: $opened');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final gateUp = await tab.evaluate(
        "(()=>{const o=document.querySelector('[data-shell-overlay]');return o?o.children.length:-1})()");
    notes.add('shell.overlay children after org.open: $gateUp');

    // Open the viewer column through the public ingress event (same event the
    // sidebar file rows and chat chips dispatch).
    await tab.evaluate(
        "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'note-001.md'}}));true");
    final handleUp = await tab.waitForSelector(viewerHandle);
    if (!handleUp) failures.add('viewer handle never appeared');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    var c = await cols();
    // Relationship assertions only: the default is VIEWPORT-DERIVED
    // (clamp(W/3, 320, 560) — VS Code first-run sizing), everything else is
    // measured deltas and the named contract floors.
    const W = 1600;
    final derivedDefault = (W / 3).round().clamp(320, 560);
    expectEq('T0 viewer opens at the viewport-derived default (W/3 clamped)', c['viewer']!, derivedDefault, tol: 6);
    expectEq('T0 sidebar at the stock contract default', c['sidebar']!, 280);
    final defaultV = c['viewer']!;
    final fullW = W - c['sidebar']!.toInt();
    final floorRestV = W - c['sidebar']!.toInt() - 220; // resting CENTER_MIN floor
    await shot('frame-drag-baseline-1600.png');

    // T1: left drag grows; sample MID-DRAG (beforeRelease) to prove the width
    // follows the pointer, not just the drop point.
    var midViewer = -1;
    final startV = c['viewer']!;
    final dragged = await tab.dragSelector(viewerHandle,
        dx: -200, dy: 0, beforeRelease: () async {
      midViewer = ((await cols())['viewer'] ?? -1).toInt();
    });
    if (!dragged) failures.add('T1 drag could not grab the viewer handle');
    c = await cols();
    expectEq('T1 drag LEFT grows the viewer by the drag delta', c['viewer']!, startV + 200, tol: 6);
    if (midViewer <= startV) {
      failures.add('T1 mid-drag width did not follow the pointer (mid=$midViewer, start=$startV)');
    } else {
      notes.add('PASS  T1 mid-drag width follows the pointer (mid=$midViewer > $startV)');
    }
    await shot('frame-drag-left-1600.png');

    // T2: right drag shrinks back by the same relationship.
    final v1 = c['viewer']!;
    await tab.dragSelector(viewerHandle, dx: 80, dy: 0);
    c = await cols();
    expectEq('T2 drag RIGHT shrinks the viewer by the drag delta', c['viewer']!, v1 - 80, tol: 6);

    // T-slow: the 2026-09-01 dead-zone regression. SLOW multi-stroke drag —
    // every stroke must move the handle by the stroke delta with NO stall,
    // through the resting floor and into the snap-to-full. Sequence pins the
    // whole state machine: continuous → resting 220 floor → floor stall
    // (by design) → magnetic snap to full.
    var prev = c['viewer']!;
    for (var i = 1; i <= 5; i++) {
      await tab.dragSelector(viewerHandle, dx: -80, dy: 0);
      c = await cols();
      expectEq('T-slow stroke $i follows the pointer (+80, no stall)', c['viewer']!, prev + 80, tol: 6);
      prev = c['viewer']!;
    }
    // Next strokes enter the resting floor zone (center < 220 at rest).
    await tab.dragSelector(viewerHandle, dx: -80, dy: 0);
    c = await cols();
    expectEq('T-slow stroke 6 settles at the resting 220 floor', c['viewer']!, floorRestV, tol: 6);
    final centerAtFloor = W - c['sidebar']!.toInt() - c['viewer']!.toInt();
    expectEq('T-slow resting center is exactly CENTER_VIEWER_MIN', centerAtFloor, 220, tol: 2);
    // A small stroke at the floor re-settles (floor reasserts at rest — the
    // designed resting behavior, not a mid-gesture dead zone).
    await tab.dragSelector(viewerHandle, dx: -80, dy: 0);
    c = await cols();
    expectEq('T-slow small stroke at the floor re-settles (resting floor holds)', c['viewer']!, floorRestV, tol: 6);
    // A stroke carrying the center under half the minimum (< snap threshold)
    // magnetically snaps to FULL TAKEOVER on release.
    await tab.dragSelector(viewerHandle, dx: -130, dy: 0);
    c = await cols();
    expectEq('T-slow stroke past half the floor snaps to full takeover', c['viewer']!, fullW, tol: 2);
    final centerAtFull = W - c['sidebar']!.toInt() - c['viewer']!.toInt();
    expectEq('T-slow full takeover hides the center', centerAtFull, 0);
    await shot('frame-drag-full-1600.png');

    // T3: far right clamps at the lane minimum (named contract floor).
    await tab.dragSelector(viewerHandle, dx: 3000, dy: 0);
    c = await cols();
    expectEq('T3 drag RIGHT far clamps at the lane minimum', c['viewer']!, 320);
    final preMaxV = c['viewer']!;

    // T4: maximize ⤢ → full takeover (viewport − sidebar, center hidden);
    // second click TOGGLES back to the pre-max width (VS Code
    // toggleMaximizedPanel: hide, then restore lastNonMaximized size).
    final maximized = await tab.clickSelector('.aXa_fr_viewerCol button[aria-label=Maximize]');
    if (!maximized) failures.add('T4 maximize button not found');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    c = await cols();
    expectEq('T4 maximize = full takeover (viewport − sidebar)', c['viewer']!, fullW);
    await tab.clickSelector('.aXa_fr_viewerCol button[aria-label=Maximize]');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    c = await cols();
    expectEq('T4 toggle restores the pre-max width', c['viewer']!, preMaxV);

    // T5: drag the sidebar to its stock contract floor → the max tracks the
    // sidebar state. (Must run OUTSIDE full takeover: at full, the viewer
    // handle owns the shared boundary at x=sidebar.)
    await tab.dragSelector(sidebarHandle, dx: -100, dy: 0);
    c = await cols();
    expectEq('T5 sidebar drags to its contract floor', c['sidebar']!, 264);
    final fullAtNarrowSidebar = W - c['sidebar']!.toInt();
    await tab.clickSelector('.aXa_fr_viewerCol button[aria-label=Maximize]');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    c = await cols();
    expectEq('T5 max tracks the sidebar width (viewport − 264)', c['viewer']!, fullAtNarrowSidebar);
    await shot('frame-drag-max-1600.png');

    // T6: sash double-click reset (VS Code onDidReset → preferred size):
    // dblclick the viewer handle → back to the DERIVED preferred width. A
    // synthetic dblclick is fine here — no pointer capture on this path.
    await tab.evaluate(
        "document.querySelector('$viewerHandle').dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));true");
    await Future<void>.delayed(const Duration(milliseconds: 400));
    c = await cols();
    expectEq('T6 dblclick resets the viewer to the derived default', c['viewer']!, derivedDefault, tol: 6);

    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    if (errors.isNotEmpty) {
      failures.add('${errors.length} console/page error(s): ${errors.first}');
    }
  } finally {
    await client.close();
  }

  for (final n in notes) {
    stdout.writeln(n);
  }
  if (failures.isNotEmpty) {
    stderr.writeln('frame drag evidence FAILED:\n  ${failures.join('\n  ')}');
    exit(1);
  }
  stdout.writeln('frame drag evidence ok -> ${outDir.path}');
}
