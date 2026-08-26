
import 'dart:io';
import 'package:arxa/cdp.dart';

Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.enable();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettle('http://127.0.0.1:7891/', settleMs: 3000);
  await tab.evaluate('(async () => {'
      ' const span = [...document.querySelectorAll("span")].find(e => e.textContent.trim() === "Pricing card UI generation");'
      ' let el = span;'
      ' for (let i = 0; i < 5 && el; i++) { if (el.onclick || el.tagName === "A" || el.tagName === "BUTTON" || el.tagName === "LI") break; el = el.parentElement; }'
      ' (el || span).click();'
      ' await new Promise(r => setTimeout(r, 2500));'
      ' [...document.querySelectorAll("button")].find(b => b.textContent.trim() === "Start free")?.scrollIntoView({block: "center"});'
      ' await new Promise(r => setTimeout(r, 600));'
      ' return "ok";'
      '})()');
  final png = await tab.screenshot();
  File('/tmp/replay-fixed.png').writeAsBytesSync(png);
  print('shot written');
  await client.close();
}
