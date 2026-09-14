// Tier-card hover tint probe: hover each pricing card under a palette,
// capture, and read the ::after overlay opacity + photo filter state.
// Usage: dart run tool/lens_tier_probe.dart <url> <palette> <outPrefix>
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  final url = argv[0], pal = argv[1], outPrefix = argv[2];
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(url + '?palette=' + pal, settleMs: 4000);
    await tab.evaluate("document.querySelector('.tier-card').scrollIntoView({ block: 'center' })");
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final rects = await tab.evaluate(
        "[...document.querySelectorAll('.tier-card')].map(c => { const r = c.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + 120 }; })") as List;
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i] as Map;
      await tab.hover((r['x'] as num).round(), (r['y'] as num).round());
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final st = await tab.evaluate(
          "(() => { const c = document.querySelectorAll('.tier-card')[" + i.toString() + "]; "
          "const ov = getComputedStyle(c.querySelector('.tier-media'), '::after'); "
          "const photo = c.querySelector('.tier-photo'); "
          "return { overlay: ov.opacity, overlayBg: ov.backgroundColor, "
          "filter: photo ? getComputedStyle(photo).filter : 'mark', "
          "price: getComputedStyle(c.querySelector('.tier-price')).color }; })()");
      stdout.writeln('card ' + i.toString() + ' hovered: ' + st.toString());
      File(outPrefix + '-card' + i.toString() + '-' + pal + '.png')
          .writeAsBytesSync(await tab.screenshot());
    }
    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    if (errs.isNotEmpty) stdout.writeln('console: ' + errs.join(' | '));
  } finally {
    await client.close();
  }
}
