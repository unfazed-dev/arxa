// Color-leak sweep (operator, 2026-09-09): collect computed color-bearing
// styles for every element under palette A, full-reload under palette B,
// re-collect, and report elements IDENTICAL across both yet chromatic —
// a palette-member color must MOVE with the flip; one that does not is a
// leak. Usage: dart run tool/lens_leak_sweep.dart <url> <palA> <palB> <out.json>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

const collector = r"""
(() => {
  const props = ['color','background-color','border-top-color','border-right-color',
    'border-bottom-color','border-left-color','outline-color','fill','stroke',
    'caret-color','text-decoration-color','accent-color','-webkit-text-fill-color',
    'column-rule-color','box-shadow','text-shadow','background-image'];
  const out = {};
  const seen = {};
  const els = document.querySelectorAll('*');
  for (const el of els) {
    const tag = el.tagName.toLowerCase();
    if (['script','style','link','meta','title','head','br'].includes(tag)) continue;
    const cs = getComputedStyle(el);
    const rec = {};
    let chromatic = false;
    for (const p of props) {
      const v = cs.getPropertyValue(p);
      if (!v || v === 'none' || v === 'normal' || v === 'auto' || v === 'currentcolor'
          || v === 'transparent' || v === 'rgba(0, 0, 0, 0)') continue;
      rec[p] = v;
      const rgbs = v.match(/rgba?\([^)]*\)/g) || [];
      for (const c of rgbs) {
        const n = c.match(/[\d.]+/g).map(Number);
        const mx = Math.max(n[0], n[1], n[2]), mn = Math.min(n[0], n[1], n[2]);
        if (mx > 20 && (mx - mn) / mx > 0.18) chromatic = true;
      }
    }
    if (!chromatic || Object.keys(rec).length === 0) continue;
    const key = tag + '|' + el.id + '|' + (typeof el.className === 'string' ? el.className : '');
    const idx = seen[key] = (seen[key] || 0) + 1;
    out[key + '|' + idx] = rec;
  }
  return out;
})()
""";

Future<Map<String, dynamic>> collect(CdpSession tab, String url, String palette) async {
  await tab.navigateAndSettle(url + '?palette=' + palette, settleMs: 4000);
  return (await tab.evaluate(collector)) as Map<String, dynamic>;
}

Future<void> main(List<String> argv) async {
  final url = argv[0];
  final palA = argv[1], palB = argv[2];
  final out = argv[3];
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    final a = await collect(tab, url, palA);
    final b = await collect(tab, url, palB);
    final leaks = <String, dynamic>{};
    final keys = <String>{...a.keys, ...b.keys};
    for (final k in keys) {
      final ra = a[k] as Map?, rb = b[k] as Map?;
      if (ra == null || rb == null) continue;
      if (jsonEncode(ra) == jsonEncode(rb)) leaks[k] = ra;
    }
    File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'url': url, 'palettes': [palA, palB],
      'elementsA': a.length, 'elementsB': b.length,
      'leaks': leaks,
    }));
    stdout.writeln('leak sweep: ' + a.length.toString() + ' chromatic els; '
        + leaks.length.toString() + ' did not move between ' + palA + ' and ' + palB);
    for (final e in [...tab.consoleErrors, ...tab.pageErrors]) {
      stderr.writeln('console: ' + e);
    }
  } finally {
    await client.close();
  }
}
