// lens_cursor_onepoint — one-off diagnostic (2026-09-13): dump the law
// belief, the full elementsFromPoint paint chain, and the rendered pixel
// at one grid point. Usage:
//   dart run tool/lens_cursor_onepoint.dart <url> <fx> <fy> [sectionId] [progress] [palette]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:arxa/lens/pixels.dart' show decodePng;

Future<void> main(List<String> argv) async {
  final url = argv[0];
  final fx = double.parse(argv[1]);
  final fy = double.parse(argv[2]);
  final section = argv.length > 3 && argv[3] != 'null' ? argv[3] : 'how-it-works';
  final progress = argv.length > 4 && argv[4] != 'null' ? argv[4] : null;
  final palette = argv.length > 5 ? argv[5] : null;
  final target = palette != null ? url + '?palette=' + palette : url;
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(target, settleMs: 9000);
    final scrollJs = '(async () => { const el = document.getElementById(' + jsonEncode(section) +
        ') || document.querySelector(' + jsonEncode('.' + section) + '); if (el) { ' +
        (progress != null
            ? 'const p = parseFloat(' + jsonEncode(progress) + '); const rect = el.getBoundingClientRect(); window.scrollTo(0, rect.top + window.scrollY + p * Math.max(1, el.offsetHeight - window.innerHeight));'
            : 'el.scrollIntoView({ block: ' + jsonEncode('center') + ' });') +
        ' } await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); await new Promise((r) => setTimeout(r, 400)); return true; })()';
    await tab.evaluate(scrollJs, awaitPromise: true);
    final x = (1280 * fx).round();
    final y = (832 * fy).round();
    final infoJs = '(async () => { const x = ' + x.toString() + ', y = ' + y.toString() +
        '; document.dispatchEvent(new MouseEvent(' + jsonEncode('mousemove') +
        ', { clientX: x, clientY: y })); await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); await new Promise((r) => setTimeout(r, 80));' +
        ' const chain = document.elementsFromPoint(x, y).filter((e) => !(e.id && e.id.indexOf(' + jsonEncode('cursor-') +
        ') === 0)); const dump = chain.map((e) => { const s = getComputedStyle(e); return e.tagName.toLowerCase() +' +
        ' (e.className && typeof e.className === ' + jsonEncode('string') + ' ? ' + jsonEncode('.') + ' + e.className.split(' + jsonEncode(' ') +
        ').slice(0, 2).join(' + jsonEncode('.') + ') : ' + jsonEncode('') + ') + ' + jsonEncode('|bg=') + ' + s.backgroundColor + ' + jsonEncode('|img=') +
        ' + s.backgroundImage.slice(0, 70) + ' + jsonEncode('|op=') + ' + s.opacity + ' + jsonEncode('|z=') + ' + s.zIndex; });' +
        ' const hit = document.elementFromPoint(x, y); const anc = []; let n = hit;' +
        ' while (n && n !== document.documentElement) { anc.push(n.tagName.toLowerCase() + (n.className && typeof n.className === ' + jsonEncode('string') +
        ' ? ' + jsonEncode('.') + ' + String(n.className).split(' + jsonEncode(' ') + ').slice(0, 2).join(' + jsonEncode('.') + ') : ' + jsonEncode('') + ')); n = n.parentElement; }' +
        ' return { belief: document.__arxaCursor || null, chain: dump, anc: anc.join(' + jsonEncode(' > ') + ') }; })()';
    final info = await tab.evaluate(infoJs, awaitPromise: true);
    stdout.writeln('belief: ' + (info['belief']?.toString() ?? 'null'));
    stdout.writeln('hit ancestors: ' + info['anc'].toString());
    stdout.writeln('elementsFromPoint chain:');
    for (final line in (info['chain'] as List)) {
      stdout.writeln('          ' + line.toString());
    }
    await tab.evaluate('(async () => { document.getElementById(' + jsonEncode('cursor-dot') + ').style.display = ' + jsonEncode('none') +
        '; document.getElementById(' + jsonEncode('cursor-canvas') + ').style.display = ' + jsonEncode('none') +
        '; await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); return true; })()', awaitPromise: true);
    final png = await tab.screenshot();
    final image = decodePng(png);
    final p = image.getPixel(x, y);
    stdout.writeln('rendered pixel: [' + p.r.toInt().toString() + ',' + p.g.toInt().toString() + ',' + p.b.toInt().toString() + ']');
    await client.close();
    exit(0);
  } catch (e) {
    stderr.writeln('onepoint error: ' + e.toString());
    await client.close();
    exit(1);
  }
}
