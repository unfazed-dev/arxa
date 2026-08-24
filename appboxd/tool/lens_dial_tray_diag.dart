// Diagnostics for the two failing tray-probe checks.
import 'dart:io';
import 'package:appboxd/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const SR = "document.getElementById('arxa-dial-host').shadowRoot";
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  await js(tab, '$SR.querySelector("#dockbtn").click()');
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$SR.querySelector('[data-verb=studio]').click()");
  await Future.delayed(const Duration(milliseconds: 700));

  // --- Ship CTA diagnostics ---
  await js(tab, "$SR.querySelectorAll('#dots .dotbtn')[4].click()");
  await Future.delayed(const Duration(milliseconds: 900));
  final d1 = await js(tab, '''
    (() => {
      const t = $SR.querySelector('#track');
      return {
        scrollLeft: t.scrollLeft, clientWidth: t.clientWidth,
        kids: [...t.children].map(s => s.dataset.slide + '@' + s.offsetLeft).join(' '),
        cta: $SR.querySelector('#cta').textContent,
        ctaClass: $SR.querySelector('#cta').className,
        disabled: $SR.querySelector('#cta').disabled,
      };
    })()
  ''');
  stdout.writeln('SHIP-DIAG: ' + d1.toString());

  // --- Card diagnostics ---
  await js(tab, '$SR.querySelector("#tclose").click()');
  await Future.delayed(const Duration(milliseconds: 900));
  await js(tab, '$SR.querySelector("#dockbtn").click()');
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$SR.querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  final armed = await js(tab, '''
    (() => {
      const v = $SR.querySelector('[data-verb=edit]');
      return { on: v ? v.classList.contains('on') : 'gone', hover: $SR.querySelector('#hover').style.display };
    })()
  ''');
  stdout.writeln('ARMED: ' + armed.toString());
  final tgt = await js(tab, '''
    (() => {
      const el = document.querySelector('[data-arxa-id]');
      if (!el) return null;
      const r = el.getBoundingClientRect();
      const stack = document.elementsFromPoint(r.x + r.width/2, r.y + 20);
      return { el: el.getAttribute('data-el'), x: r.x + r.width/2, y: r.y + 20,
               top: stack.slice(0,3).map(e => e.id || e.tagName).join(',') };
    })()
  ''');
  stdout.writeln('TARGET: ' + tgt.toString());
  if (tgt is Map) {
    final x = (tgt['x'] as num).toInt(), y = (tgt['y'] as num).toInt();
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
    await Future.delayed(const Duration(milliseconds: 200));
    final hov = await js(tab, '$SR.querySelector("#hover").style.display');
    stdout.writeln('HOVER-AFTER-MOVE: ' + hov.toString());
    await tab.send('Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
    await Future.delayed(const Duration(milliseconds: 600));
    final after = await js(tab, '''
      (() => ({
        cardOpen: $SR.querySelector('#card').classList.contains('open'),
        cardRect: JSON.stringify($SR.querySelector('#card').getBoundingClientRect()),
        head: $SR.querySelector('#chead').textContent,
        outline: document.querySelector('[data-arxa-id]').style.outline,
      }))()
    ''');
    stdout.writeln('AFTER-CLICK: ' + after.toString());
  }
  stdout.writeln('console errors: ${tab.consoleErrors.length}');
  await client.close();
}
