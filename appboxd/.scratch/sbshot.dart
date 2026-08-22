import 'dart:async';
import 'dart:io';
import 'package:appboxd/cdp.dart';

Future<void> main() async {
  final client = await CdpClient.launch();
  final s = await client.newTab();
  await s.enable();
  await s.setViewport(1500, 1100);
  await s.navigate('http://arxa.studio.localhost:7891/');
  await Future<void>.delayed(const Duration(seconds: 5));
  await s.evaluate(r'''(() => {
    const hit = [...document.querySelectorAll('a,button,[role=button],li,div')]
      .filter(e => (e.textContent||'').trim().startsWith('Help me pick a datab'))
      .sort((a,b) => (a.textContent||'').length - (b.textContent||'').length)[0];
    if (hit) hit.click(); return !!hit; })()''');
  await Future<void>.delayed(const Duration(seconds: 7));

  for (final rung in ['mobile', 'tablet']) {
    await s.evaluate('''(() => {
      const row = [...document.querySelectorAll('[data-chat-call-id]')].reverse()
        .find(r => (r.innerText||'').includes('viewport ladder'));
      const b = [...row.querySelectorAll('button')]
        .find(b => (b.textContent||'').startsWith('$rung'));
      if (b) b.click(); return !!b; })()''');
    await Future<void>.delayed(const Duration(seconds: 3));
    // Who in OUR tree can scroll?
    final m = await s.evaluate(r'''(() => {
      const row = [...document.querySelectorAll('[data-chat-call-id]')].reverse()
        .find(r => (r.innerText||'').includes('viewport ladder'));
      const out = [];
      let el = row.querySelector('iframe');
      while (el && el !== document.body) {
        const cs = getComputedStyle(el);
        const scrollsY = el.scrollHeight > el.clientHeight + 1;
        const scrollsX = el.scrollWidth > el.clientWidth + 1;
        if (scrollsY || scrollsX || /auto|scroll/.test(cs.overflowY + cs.overflowX)) {
          out.push({ tag: el.tagName, cls: (el.className||'').toString().slice(0,24),
            oy: cs.overflowY, ox: cs.overflowX,
            sh: el.scrollHeight, ch: el.clientHeight,
            sw: el.scrollWidth, cw: el.clientWidth });
        }
        el = el.parentElement;
      }
      return JSON.stringify(out);
    })()''');
    print('$rung ancestors that scroll -> $m');
    File('.scratch/sb-$rung.png').writeAsBytesSync(await s.screenshot());
  }
  await client.close();
}
