// Diagnostic: which pointer events actually reach #dockbtn?
import 'dart:io';
import 'package:appboxd/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
Future<void> mouse(CdpSession t, String type, int x, int y, {Map<String, dynamic>? extra}) async {
  await t.send('Input.dispatchMouseEvent', {'type': type, 'x': x, 'y': y, ...?extra});
}
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);
  for (var i = 0; i < 5; i++) {
    await mouse(tab, 'mouseMoved', 1276 - i, 796 - i);
    await Future.delayed(Duration(milliseconds: 80));
  }
  await Future.delayed(Duration(milliseconds: 900));
  // arm listeners INSIDE the shadow root
  await js(tab, '''
    (() => {
      const sr = document.getElementById('arxa-dial-host').shadowRoot;
      const b = sr.querySelector('#dockbtn');
      window.__ev = { down: 0, move: 0, up: 0, cap: '' };
      b.addEventListener('pointerdown', () => { window.__ev.down++; });
      b.addEventListener('pointermove', () => { window.__ev.move++; });
      b.addEventListener('pointerup',   () => { window.__ev.up++; });
      b.addEventListener('pointerdown', () => {
        try { b.setPointerCapture(1); window.__ev.cap = 'captured-1'; }
        catch (err) { window.__ev.cap = 'ERR:' + err.message; }
      });
      const d = sr.querySelector('#dock');
      window.__elAt = (document.elementFromPoint(1228, 748) || {}).id || document.elementFromPoint(1228, 748)?.tagName || 'none';
      window.__dockPE = getComputedStyle(d).pointerEvents;
      window.__hostT = document.getElementById('arxa-dial-host').style.transform;
    })()
  ''');
  stdout.writeln('elementFromPoint@FAB: ${await js(tab, 'window.__elAt')}');
  stdout.writeln('dock pointer-events : ${await js(tab, 'window.__dockPE')}');
  stdout.writeln('host transform      : ${await js(tab, 'window.__hostT')}');
  await mouse(tab, 'mousePressed', 1228, 748, extra: {'button': 'left', 'buttons': 1, 'clickCount': 1});
  for (var i = 1; i <= 5; i++) {
    await mouse(tab, 'mouseMoved', 1228 - i * 40, 748 - i * 20, extra: {'buttons': 1});
    await Future.delayed(Duration(milliseconds: 60));
  }
  await mouse(tab, 'mouseReleased', 1028, 648, extra: {'button': 'left'});
  await Future.delayed(Duration(milliseconds: 200));
  stdout.writeln('events: ${await js(tab, 'JSON.stringify(window.__ev)')}');
  stdout.writeln('dock inline left/top: ${await js(tab,
      '(() => { const sr = document.getElementById("arxa-dial-host").shadowRoot; const d = sr.querySelector("#dock"); return d.style.left + " | " + d.style.top; })()')}');
  stdout.writeln('console errors: ${tab.consoleErrors.length}');
  await client.close();
}
