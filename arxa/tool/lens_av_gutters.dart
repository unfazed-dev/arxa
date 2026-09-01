// arxa-studio GUTTER symmetry driver (2026-09-03).
// User report: the sidebar→composer gap and the composer→artifact-viewer gap
// differed (stock scrollBody reserved scrollbar-gutter stable on the right
// only). Asserts the composer card is EQUIDISTANT from the sidebar column edge
// and the viewer column edge (or window edge when the viewer is closed) at two
// viewports and all three dock states.
//
// Usage: dart run tool/lens_av_gutters.dart <url> <outDir>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_av_gutters.dart <url> <outDir>');
    exit(2);
  }
  final url = argv[0];
  final outDir = Directory(argv[1])..createSync(recursive: true);
  final notes = <String>[];
  final failures = <String>[];

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();

    Future<dynamic> js(String expr) => tab.evaluate(expr);
    Future<Map<String, dynamic>> jmap(String expr) async {
      final r = await js(expr);
      if (r is Map<String, dynamic>) return r;
      return {};
    }

    Future<void> shot(String name) async {
      final png = await tab.screenshot();
      File('${outDir.path}/$name').writeAsBytesSync(png);
    }

    await tab.setViewport(1280, 800);
    await tab.navigateAndSettle(url, settleMs: 3500);
    // Dismiss the DSH "Internal Testing Notice" modal — its translucent
    // backdrop washes the frame and hides the composer in evidence shots.
    await js(
      "(()=>{const b=[...document.querySelectorAll('button')].find(x=>x.textContent.trim()==='Continue');if(b)b.click();return true})()");
    await Future.delayed(const Duration(milliseconds: 600));
    // Evidence in the user's dark shell (same flag the T6f probe flips).
    await js(
      "document.body.setAttribute('data-ds-dark-theme',''); true");
    await Future.delayed(const Duration(milliseconds: 400));

    await jmap(
      "fetch('/__arxa/sidebar/action',{method:'POST',headers:{'content-type':'application/json'},"
      "body:JSON.stringify({action:'org.open',arg:'demo'})}).then(r=>r.json())");
    for (var i = 0; i < 16; i++) {
      await js(
        "(()=>{const row=[...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('DEMO'));"
        "if(row&&row.getAttribute('aria-expanded')!=='true')row.click();return true})()");
      final listed = await js(
        "!![...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('check.sh'))");
      if (listed == true) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await js(
      "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'check.sh'}})); true");
    await Future.delayed(const Duration(milliseconds: 1800));

    const probe = '''
(()=> {
  const ta = document.querySelector("[data-slot='conversation.composer.bar'] textarea");
  if (!ta) return { err: 'no composer textarea' };
  const center = document.querySelector('.aXa_fr_centerCol');
  const side = document.querySelector('.aXa_fr_sidebarCol');
  const viewer = document.querySelector('.aXa_fr_viewerCol');
  const r = (el) => { const b = el.getBoundingClientRect();
    return { l: +b.left.toFixed(1), r: +b.right.toFixed(1) }; };
  let card = null, el = ta;
  while (el && el !== center) {
    if ((el.className || '').toString().includes('_card')) { card = el; break; }
    el = el.parentElement;
  }
  if (card == null) return { err: 'no composer card in chain' };
  const sb = ta.closest('[class*=scrollBody]');
  const gutter = sb == null ? null
    : { reserved: sb.offsetWidth - sb.clientWidth,
        css: getComputedStyle(sb).scrollbarGutter };
  return { card: r(card), sidebar: side == null ? null : r(side),
    viewer: viewer == null ? null : r(viewer), vw: window.innerWidth, gutter };
})()''';

    Future<void> measure(String label, void Function(Map<String, dynamic>) assertFn) async {
      var m = <String, dynamic>{};
      for (var i = 0; i < 16; i++) {
        m = await jmap(probe);
        if (m['err'] == null && m['sidebar'] != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (m['err'] != null || m['sidebar'] == null) {
        failures.add('$label probe: ${m['err'] ?? 'frame sidebarCol never mounted'}');
        return;
      }
      assertFn(m);
      notes.add('$label -> ${jsonEncode(m)}');
    }

    void assertSymmetric(Map<String, dynamic> m) {
      final card = m['card'] as Map<String, dynamic>;
      final side = m['sidebar'] as Map<String, dynamic>;
      final viewer = m['viewer'] as Map<String, dynamic>?;
      final vw = (m['vw'] as num).toDouble();
      final left = (card['l'] as num) - (side['r'] as num);
      final right = (viewer == null ? vw : viewer['l'] as num) - (card['r'] as num);
      final diff = (left - right).abs();
      final ok = diff <= 0.5;
      notes.add('   gaps: left=$left right=$right diff=$diff ${ok ? 'SYMMETRIC' : 'ASYMMETRIC'}');
      if (!ok) failures.add('gaps asymmetric: left=$left right=$right (diff=$diff)');
    }

    await measure('G1 viewer-open@1280', assertSymmetric);
    await shot('gutters-1280-viewer-open.png');

    await tab.setViewport(1600, 900);
    await Future.delayed(const Duration(milliseconds: 600));
    await measure('G2 viewer-open@1600', assertSymmetric);
    await shot('gutters-1600-viewer-open.png');

    await tab.setViewport(1280, 800);
    await Future.delayed(const Duration(milliseconds: 400));
    await js(
      "(()=>{const b=[...document.querySelectorAll('.aXa_av_actions button')].pop();if(b)b.click();return true})()");
    await Future.delayed(const Duration(milliseconds: 800));
    await measure('G3 viewer-closed@1280', assertSymmetric);
    await shot('gutters-1280-viewer-closed.png');

    stdout.writeln('RESULT: ${failures.isEmpty ? 'PASS' : 'FAIL'}');
    for (final f in failures) {
      stdout.writeln('FAIL: $f');
    }
    for (final n in notes) {
      stdout.writeln(n);
    }
  } finally {
    await client.close();
  }
}
