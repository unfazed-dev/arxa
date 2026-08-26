// Diagnose the element-capture null: which stage fails?
import 'dart:io';
import 'package:arxa/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);
  final out = await js(tab, '''
    (async () => {
      const el = document.querySelector('[data-arxa-id]');
      if (!el) return {stage: 'no-element'};
      try {
        const r = el.getBoundingClientRect();
        const w = Math.min(480, Math.max(2, Math.round(r.width)));
        const h = Math.max(2, Math.round(r.height * (w / r.width)));
        const clone = el.cloneNode(true);
        const cs = getComputedStyle(el);
        const decls = ['font','color','background','padding']
          .filter((p) => cs.getPropertyValue(p))
          .map((p) => p + ':' + cs.getPropertyValue(p)).join(';');
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '">' +
          '<foreignObject width="100%" height="100%">' +
          '<div xmlns="http://www.w3.org/1999/xhtml" style="' + decls + '">' +
          new XMLSerializer().serializeToString(clone) + '</div></foreignObject></svg>';
        const url = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
        const img = new Image();
        const loadResult = await new Promise((res) => {
          img.onload = () => res('loaded natural=' + img.naturalWidth + 'x' + img.naturalHeight);
          img.onerror = (e) => res('onerror');
          setTimeout(() => res('timeout'), 2000);
          img.src = url;
        });
        if (loadResult !== 'loaded') return {stage: 'img-load', result: loadResult, svgHead: svg.slice(0, 120)};
        const c = document.createElement('canvas');
        c.width = w; c.height = h;
        c.getContext('2d').drawImage(img, 0, 0);
        const out = c.toDataURL('image/png');
        return {stage: 'ok', len: out.length, w: w, h: h};
      } catch (err) {
        return {stage: 'exception', err: String(err)};
      }
    })()
  ''');
  stdout.writeln(out.toString());
  await client.close();
}
