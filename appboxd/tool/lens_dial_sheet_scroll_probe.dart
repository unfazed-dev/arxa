// Sheet scrollbar evidence probe (operator, 2026-08-25): the tray's
// scrollbars carry NO track and a thumb in the sheet's phase (moss over
// glass). Asserts the computed scrollbar-color on a scrolling slide and
// captures the comments slide overflowing as PNG evidence.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/lens/pixels.dart';
import 'package:image/image.dart' as img;

Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
const evidenceDir = '/Volumes/developer_ssd/Developer/totem_labs/'
    'clients/architect-gallore/design/suczka-studio/evidence/sheet-scrollbar';
int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}

Future<void> main() async {
  Directory(evidenceDir).createSync(recursive: true);

  // Seed enough pins to overflow the comments slide vertically.
  final client = HttpClient();
  for (var i = 0; i < 14; i++) {
    final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:4319/__dial/pins'));
    req.headers.set('content-type', 'application/json');
    req.write(jsonEncode({
      'route': '/',
      'viewport': {'w': 1280, 'h': 800},
      'anchor': {'el': null, 'rect': {'x': 10.0 + i, 'y': 10.0, 'w': 100.0, 'h': 20.0}},
      'body': 'scroll evidence pin $i',
    }));
    await req.close();
  }
  client.close();

  final c = await CdpClient.launch();
  final tab = await c.newTab();
  await tab.setViewport(390, 844); // compact rung: tightest tray, list overflows
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/',
      settleMs: 2500);
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': 386 - i, 'y': 840 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  await js(tab, "$sr.querySelector('#dockbtn').click()");
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$sr.querySelector('[data-verb=studio]').click()");
  await Future.delayed(const Duration(milliseconds: 800));

  // land on the comments slide
  await js(tab, '''(() => {
    const track = $sr.querySelector('#track');
    const slides = [...track.querySelectorAll('.slide')];
    const target = track.querySelector('.slide[data-slide=comments]') || slides[1];
    track.scrollTo({left: target.offsetLeft, behavior: 'instant'});
    return target.offsetLeft;
  })()''');
  await Future.delayed(const Duration(milliseconds: 700));

  final facts = await js(tab, '''(() => {
    const track = $sr.querySelector('#track');
    const slides = [...track.querySelectorAll('.slide')];
    const target = track.querySelector('.slide[data-slide=comments]') || slides[1];
    const cs = getComputedStyle(target);
    const r = target.getBoundingClientRect();
    return {
      overflows: target.scrollHeight > target.clientHeight,
      scrollHeight: target.scrollHeight,
      clientHeight: target.clientHeight,
      scrollbarColor: cs.scrollbarColor,
      scrollbarWidth: cs.scrollbarWidth,
      thumbRule: [...$sr.querySelectorAll('style')].some(st => st.textContent.includes('#tray ::-webkit-scrollbar-thumb')),
      rect: {x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height)}
    };
  })()''');
  final m = (facts as Map).cast<String, dynamic>();
  check(m['overflows'] == true,
      'comments slide overflows (scrolls) ${m['scrollHeight']}>${m['clientHeight']}');
  final sc = (m['scrollbarColor'] as String? ?? '');
  check(sc.contains('110, 136, 76'),
      'scrollbar-color is moss ($sc)');
  check(m['scrollbarWidth'] == 'thin', 'scrollbar-width thin');
  check(m['thumbRule'] == true, 'webkit thumb rule present in sheet CSS');

  final bytes = await tab.screenshot();
  final pngBytes = Uint8List.fromList(bytes);
  File('$evidenceDir/sheet-scrollbar-390.png').writeAsBytesSync(pngBytes);
  stdout.writeln('     evidence: $evidenceDir/sheet-scrollbar-390.png');

  // Pixel proof: the 6px thumb strip at the slide's right edge reads MOSS
  // over glass — measurably greener than the slide content beside it.
  final r = (m['rect'] as Map).cast<String, dynamic>();
  stdout.writeln('     slide rect: $r');
  final trayRect = await js(tab, '''(() => {
    const t = $sr.querySelector('#tray');
    const b = t.getBoundingClientRect();
    const cs = getComputedStyle(t);
    return {x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height), open: cs.display};
  })()''');
  stdout.writeln('     tray: $trayRect');
  final im = img.decodeImage(pngBytes)!;
  final tc = im.getPixel(((trayRect as Map)['x'] as num).toInt() + 20, ((trayRect)['y'] as num).toInt() + 20);
  stdout.writeln('     tray-corner px: ${tc.r.toInt()},${tc.g.toInt()},${tc.b.toInt()}');
  final sx = ((r['x'] as num) + (r['w'] as num) - 4).toInt();
  final cy = ((r['y'] as num) + (r['h'] as num) / 2).toInt();
  final strip = regionMeanLab(im, sx, cy - 60, 3, 120);
  final content = regionMeanLab(im, sx - 26, cy - 60, 18, 120);
  stdout.writeln('     thumb Lab ${strip.map((v) => v.toStringAsFixed(1)).toList()} vs content ${content.map((v) => v.toStringAsFixed(1)).toList()}');
  final de = deltaE2000Lab(strip[0], strip[1], strip[2], content[0],
      content[1], content[2]);
  final greener = (content[1] - strip[1]) > 1.0 &&
      (content[2] - strip[2]) > 1.0;
  check(greener && de > 3,
      'thumb strip reads moss over glass (dE ${de.toStringAsFixed(1)})');
  check(tab.pageErrors.isEmpty && tab.consoleErrors.isEmpty, 'no errors');

  stdout.writeln(
      fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await c.close();
  exit(fails == 0 ? 0 : 1);
}
