// Control: does this headless Chrome render the design page's own colors
// faithfully? Finds a strongly-colored page element via computed style,
// screenshots, and compares the pixel color at its center.
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:appboxd/cdp.dart';

Future<void> main() async {
  final c = await CdpClient.launch();
  final t = await c.newTab();
  await t.setViewport(390, 844);
  await t.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);
  final found = await t.evaluate('''(() => {
    const sr = document.getElementById('arxa-dial-host').shadowRoot;
    const pins = sr.querySelectorAll('.pin');
    const dock = sr.querySelector('#dock');
    const info = {
      pinCount: pins.length,
      firstPinBg: pins[0] ? getComputedStyle(pins[0]).backgroundColor : null,
      firstPinRect: pins[0] ? JSON.stringify(pins[0].getBoundingClientRect()) : null,
      dockBg: dock ? getComputedStyle(dock).backgroundColor : null,
      dockBorder: dock ? getComputedStyle(dock).borderColor : null
    };
    const target = pins[0] || dock;
    if (target) {
      const rc = target.getBoundingClientRect();
      info.x = Math.round(rc.x + rc.width / 2);
      info.y = Math.round(rc.y + rc.height / 2);
    }
    return info;
  })()''');
  print('DOM says: ' + found.toString());
  if (found is Map) {
    final bytes = await t.screenshot();
    final im = img.decodeImage(Uint8List.fromList(bytes))!;
    final px = im.getPixel((found['x'] as num).toInt(), (found['y'] as num).toInt());
    print('pixel at element center: ' + px.r.toInt().toString() + ',' + px.g.toInt().toString() + ',' + px.b.toInt().toString());
  }
  await c.close();
  exit(0);
}
