// Reusable footer/scroll-animation state probe for replica-vs-reference parity.
//
// Drives a page to its bottom (stepwise or jump), sampling the mod-footer
// card's animation state (year/name-chars/text-spans/media clip+parallax) as a
// change-only JSONL trace plus keyframe PNGs. Scroll-container aware: uses
// window scroll normally, #smooth-wrapper element scroll when the page's
// mobile branch scrolls the wrapper (body overflow hidden).
//
// Usage:
//   dart run tool/lens_footer_states.dart <url> <outdir> <label> [w] [h] [mode]
//     mode: step (default) | jump
// Output: <outdir>/<label>.jsonl  +  <outdir>/<label>-*.png
import 'dart:io';

import 'package:appboxd/cdp.dart';

const _stateFn = '''
(function(){
  function tf(el){ if(!el) return 'x'; var s=getComputedStyle(el); var m=s.transform;
    if(m && m.indexOf('matrix')===0){ var p=m.split(','); m='ty'+Math.round(parseFloat(p[p.length-1])); }
    return m + '/' + s.opacity; }
  var w=document.getElementById('smooth-wrapper');
  var wrapperScrolls = w && getComputedStyle(document.body).overflowY==='hidden'
    && w.scrollHeight > innerHeight + 10;
  var y = wrapperScrolls ? w.scrollTop : scrollY;
  var f=document.querySelector('.mod-footer');
  if(!f) return JSON.stringify({noFooter:true});
  var r=f.getBoundingClientRect();
  var year=f.querySelector('.mod-footer__content__project__year');
  var name=f.querySelector('.mod-footer__content__project__name');
  var kids=name?name.children.length:0;
  var spans=f.querySelectorAll('.mod-footer__content__project__text span');
  var sp=[]; spans.forEach(function(s){sp.push(tf(s));});
  var sts=window.ScrollTrigger?ScrollTrigger.getAll().filter(function(t){var el=t.trigger;return el&&el.closest&&el.closest('.mod-footer');}).length:-1;
  var media=f.querySelector('.mod-footer__content__project__wrap-image .media');
  var mcs=media?getComputedStyle(media):null;
  var stretch=f.querySelector('.mod-footer__bg .stretch .piece-bottom');
  return JSON.stringify({y:Math.round(y), fTop:Math.round(r.top), sts:sts,
    year:tf(year), kids:kids, c0:kids?tf(name.children[0]):'x',
    spanN:spans.length, sp:sp,
    tY:mcs?mcs.getPropertyValue('--transY').trim():null,
    clip:mcs?mcs.getPropertyValue('--clipPath').trim():null,
    stretch:stretch?tf(stretch):null});
})()
''';

Future<void> main(List<String> argv) async {
  if (argv.length < 3) {
    stderr.writeln('usage: lens_footer_states.dart <url> <outdir> <label> [w] [h] [step|jump]');
    exit(2);
  }
  final url = argv[0], outDir = argv[1], label = argv[2];
  final w = argv.length > 3 ? int.parse(argv[3]) : 1280;
  final h = argv.length > 4 ? int.parse(argv[4]) : 832;
  final jump = argv.length > 5 && argv[5] == 'jump';
  Directory(outDir).createSync(recursive: true);
  final trace = File('$outDir/$label.jsonl').openWrite();

  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.enable();
  await tab.setViewport(w, h);
  await tab.navigateAndSettle(url, settleMs: 3000);
  await tab.evaluate("try{localStorage.setItem('first_charge','1')}catch(e){}; 'ok'");
  await tab.navigateAndSettle(url, settleMs: 4500);
  await Future<void>.delayed(const Duration(seconds: 4));

  String scrollJs(String expr) => '''
(function(){
  var w=document.getElementById('smooth-wrapper');
  var wrapperScrolls = w && getComputedStyle(document.body).overflowY==='hidden'
    && w.scrollHeight > innerHeight + 10;
  var max = wrapperScrolls ? (w.scrollHeight - innerHeight) : (document.documentElement.scrollHeight - innerHeight);
  var cur = wrapperScrolls ? w.scrollTop : scrollY;
  var next = $expr;
  if (wrapperScrolls) w.scrollTop = next; else scrollTo(0, next);
  return 'ok';
})()
''';

  void log(String phase, Object s) {
    final line = '{"phase":"$phase","t":${DateTime.now().millisecondsSinceEpoch},"s":$s}';
    trace.writeln(line);
    stdout.writeln('$phase $label: $s');
  }

  log('t0', await tab.evaluate(_stateFn));

  if (jump) {
    await tab.evaluate(scrollJs('max'));
  } else {
    // stepwise ride to the bottom, half-viewport per 120ms
    for (var i = 0; i < 260; i++) {
      await tab.evaluate(scrollJs('Math.min(cur + ${h ~/ 2}, max)'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final s = await tab.evaluate(_stateFn) as String;
      if (s.contains('"noFooter"')) break;
      final m = RegExp(r'"fTop":(-?\d+)').firstMatch(s);
      if (m != null && int.parse(m.group(1)!) < h + 300) { log('approach', s); break; }
    }
  }
  File('$outDir/$label-approach.png').writeAsBytesSync(await tab.screenshot());

  // fine phase: creep to max while sampling change-only at 60ms
  String last = '';
  var shotIdx = 0, lastShotAt = 0;
  final t0 = DateTime.now();
  for (var i = 0; i < 80; i++) {
    if (!jump && i % 3 == 0) await tab.evaluate(scrollJs('Math.min(cur + 160, max)'));
    final ms = DateTime.now().difference(t0).inMilliseconds;
    final s = await tab.evaluate(_stateFn) as String;
    if (s != last) {
      log('b+$ms', s);
      last = s;
      if (ms - lastShotAt > 350 && shotIdx < 6) {
        lastShotAt = ms;
        File('$outDir/$label-b$shotIdx.png').writeAsBytesSync(await tab.screenshot());
        shotIdx++;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
  await tab.evaluate(scrollJs('max'));
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  log('settled', await tab.evaluate(_stateFn));
  File('$outDir/$label-settled.png').writeAsBytesSync(await tab.screenshot());

  log('console', '"${tab.consoleErrors.join('; ').replaceAll('"', "'")}"');
  log('pageerr', '"${tab.pageErrors.join('; ').replaceAll('"', "'")}"');
  await trace.close();
  await client.close();
}
