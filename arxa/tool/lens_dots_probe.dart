// Dot-grid staleness probe: flip palettes WITHOUT scrolling and dump the
// actual fill attributes of the 5x5 dots + petals after each flip.
// Usage: dart run tool/lens_dots_probe.dart <url>
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(argv[0], settleMs: 3500);
    await tab.evaluate("(() => { const el = document.querySelector('[data-grid-dot]'); "
        "if (el) el.scrollIntoView({ block: 'center' }); return !!el; })()");
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    const dump = "(() => { const dots = [...document.querySelectorAll('[data-grid-dot]')]"
        ".map(d => d.getAttribute('fill')); "
        "const petals = [...document.querySelectorAll('[data-grid-petal]')]"
        ".map(p => { const path = p.querySelector('path'); return path ? (path.getAttribute('fill') || 'none') : 'no-path'; }); "
        "const uniq = (a) => [...new Set(a)]; "
        "return { palette: document.documentElement.getAttribute('data-palette'), "
        "dotFills: uniq(dots), petalFills: uniq(petals), petalCount: petals.length, "
        "accent: getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() }; })()";
    for (final pal in ['c-293f14', 'c-2e1f27', 'marine']) {
      await tab.evaluate("window.__arxaPalette.set('" + pal + "')");
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final r = await tab.evaluate(dump);
      stdout.writeln(pal + ' -> ' + r.toString());
    }
    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    if (errs.isNotEmpty) stdout.writeln('console: ' + errs.join(' | '));
  } finally {
    await client.close();
  }
}
