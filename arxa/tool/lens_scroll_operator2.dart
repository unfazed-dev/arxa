// Operator instrument v2 - input attribution. v6 proved the reversal is
// driven by the INPUT PIPELINE: the operator's down-wheels stop reaching the
// frame for ~1.8s mid-cadence, then a burst of 8 hardware-shaped NEGATIVE
// wheels arrives and the page (correctly) scrolls up 699px. Every in-page
// actor was exonerated (dock static, no remount, no reload, module healthy).
// v7 records, per wheel, in BOTH the parent studio page and the iframe:
//   isTrusted (OS input vs script-synthesized), client + screen coords,
//   the element under the cursor (dial host? panel chrome? iframe?), delta
// so the silent 1.8s gap and the phantom up-burst can be attributed to a
// surface, a device, or a synthesizer.
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

const studio = 'http://arxa.studio.localhost:7891/';
const capSeconds = 150;

const parentSampler = '''
  window.__w = [];
  window.addEventListener('wheel', function (e) {
    var el = document.elementFromPoint(e.clientX, e.clientY);
    var tag = el ? (el.id || el.className || el.tagName) : 'null';
    if (el && el.host) tag = 'shadow-host:' + (el.id || el.tagName);
    var host = el;
    while (host && host !== document.body) {
      if (host.id === 'arxa-dial-host') { tag = 'DIAL'; break; }
      host = host.parentElement;
    }
    window.__w.push({ t: Math.round(e.timeStamp), dy: Math.round(e.deltaY),
      tr: e.isTrusted ? 1 : 0, cx: e.clientX, cy: e.clientY,
      sx: e.screenX, sy: e.screenY, on: String(tag).slice(0, 40) });
  }, { passive: true, capture: true });
  'armed-parent'
''';

const frameSampler = '''
  window.__fw = [];
  window.addEventListener('wheel', function (e) {
    window.__fw.push({ t: Math.round(e.timeStamp), dy: Math.round(e.deltaY),
      tr: e.isTrusted ? 1 : 0, cx: e.clientX, cy: e.clientY,
      sx: e.screenX, sy: e.screenY, pd: e.defaultPrevented ? 1 : 0 });
  }, { passive: true, capture: true });
  window.__ft = [];
  function __ts() {
    var w = document.getElementById('smooth-wrapper');
    window.__ft.push(Math.round(w ? w.scrollTop : window.scrollY || 0));
    requestAnimationFrame(__ts);
  }
  requestAnimationFrame(__ts);
  'ok'
''';

Future<void> main() async {
  LensSession.visible = true;
  LensSession.windowW = 1440;
  LensSession.windowH = 880;
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.setViewport(1440, 880);
    await tab.navigateAndSettle(studio, settleMs: 2500);
    for (var i = 0; i < 40; i++) {
      if (await tab.evaluate(
              "(() => { const b = Array.from(document.querySelectorAll('button')).find(x => (x.textContent || '').trim() === 'design'); if (b) { b.click(); return true; } return false; })()") ==
          true) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await Future.delayed(const Duration(milliseconds: 600));
    await tab.evaluate(parentSampler);

    const labels = ['mobile', 'tablet', 'desktop'];
    const widths = [390, 744, 1280];
    for (var i = 0; i < labels.length; i++) {
      await tab.evaluate(
          "(() => { const b = Array.from(document.querySelectorAll('button')).find(x => (x.textContent || '').trim().indexOf('${labels[i]}') === 0); if (b) b.click(); return true; })()");
      await Future.delayed(const Duration(milliseconds: 700));
    }
    await tab.evaluate(
        "(() => { const b = Array.from(document.querySelectorAll('button')).find(x => (x.textContent || '').trim().indexOf('mobile') === 0); if (b) b.click(); return true; })()");

    final kids = <int, CdpSession>{};
    for (var i = 0; i < widths.length; i++) {
      final c = await client.attachIframeSession(tab, urlPrefix: 'http://127.0.0.1:4319/', wantInnerWidth: widths[i]);
      if (c != null) {
        await c.evaluate(frameSampler);
        kids[widths[i]] = c;
        stdout.writeln('rung ${widths[i]}: instrumented');
      }
    }
    await Future.delayed(const Duration(milliseconds: 7000));
    stdout.writeln('');
    stdout.writeln('==========================================================');
    stdout.writeln(' INSTRUMENT READY (attribution mode) - reproduce the bug');
    stdout.writeln(' with your mouse wheel now. Keep your hand moving ONE');
    stdout.writeln(' direction only (down), so any up-events are not yours.');
    stdout.writeln('==========================================================');

    final deadline = DateTime.now().add(Duration(seconds: capSeconds));
    var detected = false;
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 400));
      for (final e in kids.entries) {
        try {
          final r = await e.value.evaluate(
              "JSON.stringify({neg: __fw.filter(function(w){return w.dy < 0}).length})");
          final m = r is String ? jsonDecode(r) as Map : null;
          if (m != null && (m['neg'] as num? ?? 0) > 0) {
            stdout.writeln('NEGATIVE WHEELS CAPTURED at rung ${e.key}');
            detected = true;
          }
        } catch (_) {}
      }
      if (detected) break;
    }
    // Let the tail land before the dump.
    await Future.delayed(const Duration(milliseconds: 1200));

    stdout.writeln('');
    stdout.writeln('=================== ATTRIBUTION DUMP ===================');
    final pw = await tab.evaluate('JSON.stringify(__w.slice(-160))');
    stdout.writeln('PARENT wheels (last 160):');
    if (pw is String) {
      for (final w in (jsonDecode(pw) as List)) {
        final m = w as Map;
        stdout.writeln('  t=${m['t']} dy=${m['dy']} trusted=${m['tr']} client=${m['cx']},${m['cy']} screen=${m['sx']},${m['sy']} on=${m['on']}');
      }
    }
    for (final e in kids.entries) {
      try {
        final fw = await e.value.evaluate('JSON.stringify(__fw.slice(-160))');
        stdout.writeln('RUNG ${e.key} wheels (last 160):');
        if (fw is String) {
          for (final w in (jsonDecode(fw) as List)) {
            final m = w as Map;
            stdout.writeln('  t=${m['t']} dy=${m['dy']} trusted=${m['tr']} client=${m['cx']},${m['cy']} screen=${m['sx']},${m['sy']} pd=${m['pd']}');
          }
        }
        final ft = await e.value.evaluate('JSON.stringify(__ft.slice(-400))');
        if (ft is String) {
          final s = (jsonDecode(ft) as List).cast<num>();
          var maxSoFar = -1e9;
          var worst = 0.0;
          var wi = -1;
          for (var i = 0; i < s.length; i++) {
            if (s[i] > maxSoFar) maxSoFar = s[i].toDouble();
            if (maxSoFar - s[i] > worst) {
              worst = maxSoFar - s[i];
              wi = i;
            }
          }
          stdout.writeln('RUNG ${e.key} position: worst drop ${worst.toStringAsFixed(0)}px at sample #$wi end=${s.isEmpty ? '-' : s.last.toString()}');
        }
      } catch (_) {
        stdout.writeln('RUNG ${e.key}: session gone');
      }
    }
    stdout.writeln(detected ? '\nVERDICT: NEGATIVE INPUT CAPTURED' : '\nVERDICT: none captured this run');
  } finally {
    await client.close();
  }
  exit(0);
}
