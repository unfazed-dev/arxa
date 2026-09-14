// lens_probe_pf_qcolor.dart — question-text span colors + data-open state,
// default and after opening row 2 (the span, not the button: the accent
// lives on .faq-question-text).
// Usage: dart run tool/lens_probe_pf_qcolor.dart <url> <outJson>
import 'dart:convert';
import 'dart:io';
import 'package:arxa/lens/daemon.dart';

String _revealJs() {
  return r"""
(() => {
  const overlay = [...document.querySelectorAll('div')].find(d => {
    const s = getComputedStyle(d);
    return s.position === 'fixed' && (s.zIndex === '9999' || s.zIndex === '99999');
  });
  return !overlay;
})()
""";
}

String _stateJs() {
  return r"""
(() => {
  const sec = document.getElementById('faq');
  return JSON.stringify([...sec.querySelectorAll('.faq-item')].slice(0, 2).map((item, i) => ({
    i: i,
    open: item.getAttribute('data-open'),
    spanColor: getComputedStyle(item.querySelector('.faq-question-text')).color,
    rowH: Math.round(item.getBoundingClientRect().height * 10) / 10
  })));
})()
""";
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4319/';
  final outJson = args.length > 1 ? args[1] : '/tmp/arxa-compare/pf/qcolor.json';
  final result = <String, dynamic>{};
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1713, 1098);
    await tab.navigateAndSettle(url, settleMs: 700);
    final w = Stopwatch()..start();
    while (w.elapsedMilliseconds < 30000) {
      final ok = await tab.evaluate(_revealJs());
      if (ok == true) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 600));
    await tab.evaluate(r"""
(() => { const btn = [...document.querySelectorAll('button')].find(b => /^(accept)$/i.test((b.textContent || '').trim())); if (btn) btn.click(); return 1; })()
""");
    for (int i = 0; i < 6; i++) {
      final s = await tab.evaluate(r"""
(() => { const el = document.getElementById('faq'); return el ? el.getBoundingClientRect().top : null; })()
""");
      final top = (s is num) ? s.toDouble() : null;
      if (top != null && (top.round() - 110).abs() < 5) break;
      await tab.evaluate(r"""
(() => { window.scrollBy(0, D); return window.scrollY; })()
""".replaceAll('D', ((top ?? 0).round() - 110).toString()));
      await Future.delayed(const Duration(milliseconds: 650));
    }
    await Future.delayed(const Duration(milliseconds: 700));
    final pre = await tab.evaluate(_stateJs());
    result['default'] = jsonDecode(pre is String ? pre : jsonEncode(pre));
    await tab.evaluate(r"""
(() => { const b = [...document.querySelectorAll('.faq-item .faq-question')][1]; b.click(); return 1; })()
""");
    await Future.delayed(const Duration(milliseconds: 800));
    final post = await tab.evaluate(_stateJs());
    result['open2'] = jsonDecode(post is String ? post : jsonEncode(post));
    File(outJson).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
    stdout.writeln('qcolor ok -> ' + outJson);
  } finally {
    await client.close();
  }
}

