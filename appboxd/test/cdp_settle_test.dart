// Capture-settle regression tests.
//
// EVERY determinism test here runs the OLD path in the same test as the new
// one, and asserts the OLD path FAILS. That is not belt-and-braces; it is the
// only thing separating this file from six earlier checks in this project whose
// "pass" outcome was also their "did not run" outcome. A test that captures
// five images through settleForCapture and asserts they match would pass just
// as green if the page were never nondeterministic, if the freeze silently
// no-opped, or if the loop returned immediately. Asserting `old > 1 && new == 1`
// in one run makes the page's nondeterminism a precondition of the test.
//
// Chrome is required; these are integration tests, not unit tests.

import 'dart:async';
import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/lens.dart';
import 'package:test/test.dart';

/// Infinite CSS animation on a gradient. Two independent sources of variance:
/// the animation's phase, and the compositor layer the animation promotes it
/// onto. The second survives a naive pause — see [CdpTab.freezeAnimations].
const _animated = '''
<!doctype html><meta charset=utf-8><title>animated</title>
<style>body{margin:0;background:#111}
@keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
#s{width:160px;height:160px;margin:80px auto;background:linear-gradient(#e33,#3e3);
   animation:spin 2s linear infinite}</style>
<div id=s></div>
''';

/// Async work of variable duration AFTER the load event, then a transition.
/// Pre-load slowness would NOT reproduce the defect: navigate() waits for
/// `Page.loadEventFired` and the settle timer starts there, so a slow head just
/// shifts the whole timeline and a flat timer stays phase-locked to it.
const _variableLoad = '''
<!doctype html><meta charset=utf-8><title>variable</title>
<style>body{margin:0;background:#fff}
#c{padding:40px;font:20px/1.5 sans-serif;color:#204a87;opacity:0;
   transform:translateY(40px);
   transition:opacity 900ms ease-out,transform 900ms ease-out}
body.ready #c{opacity:1;transform:none}
.sq{width:100px;height:100px;background:#c17d11;margin-top:20px}</style>
<div id=c>variable load, fixed outcome<div class=sq></div></div>
<script>window.addEventListener('load',function(){setTimeout(function(){
  document.body.classList.add('ready');},100+Math.floor(Math.random()*1100));});
</script>
''';

/// Finite animation with `fill: both`, holding a non-default end state. Guards
/// the one way the de-promotion could silently corrupt a golden: dropping the
/// `animation` property without first committing what fill-mode was holding
/// would snap the element back to `opacity: 0`.
const _fillForwards = '''
<!doctype html><meta charset=utf-8><title>fill</title>
<style>body{margin:0;background:#fff}
@keyframes reveal{from{opacity:0}to{opacity:1}}
#s{width:200px;height:200px;background:#204a87;opacity:0;
   animation:reveal 300ms linear both}</style>
<div id=s></div>
''';

/// A page nothing can freeze. `setInterval` repainting text is not a WAAPI
/// animation, not SMIL, and not a video, so `getAnimations()` cannot see it and
/// `freezeAnimations` cannot stop it. It stands in for the real cases the
/// settle genuinely cannot handle — an animated GIF or APNG (no pause API
/// exists at all), a clock widget, a buffering video. The settle MUST report
/// non-convergence here, and callers must act on it.
const _neverSettles = '''
<!doctype html><meta charset=utf-8><title>never</title>
<style>body{margin:0;font:40px monospace;padding:40px}</style>
<div id=t>0</div>
<script>var n=0;setInterval(function(){
  document.getElementById('t').textContent=String(++n);},80);</script>
''';

/// The control page for every "did not write / did fail" assertion below.
const _settles = '''
<!doctype html><meta charset=utf-8><title>settles</title>
<style>body{margin:0;background:#204a87}</style><div>stable</div>
''';

Future<(HttpServer, String)> _serve(Map<String, String> pages) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final body = pages[req.uri.path];
    if (body == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType.html;
    req.response.headers.set('cache-control', 'no-store');
    req.response.write(body);
    await req.response.close();
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

/// [n] captures of [url], each in its OWN Chrome — the real usage pattern, and
/// the one that exposes cross-launch raster variance that a single reused
/// browser would hide.
Future<List<String>> _capture(String url, int n,
    {required bool useCaptureSettle}) async {
  final shots = <String>[];
  for (var i = 0; i < n; i++) {
    final client = await CdpClient.launch();
    try {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(390, 844);
      if (useCaptureSettle) {
        await tab.navigateAndSettleForCapture(url, settleMs: 1500);
      } else {
        await tab.navigateAndSettle(url, settleMs: 1500);
      }
      shots.add(String.fromCharCodes(await tab.screenshot()));
    } finally {
      await client.close();
    }
  }
  // A short list would make `toSet().length == 1` trivially true. Fail loudly
  // instead: this is mechanism (A) from the project's false-pass history — an
  // absent measurement reading as a good one.
  expect(shots, hasLength(n), reason: 'a capture was lost; results are void');
  return shots;
}

void main() {
  group('capture settle determinism', () {
    late HttpServer server;
    late String base;

    setUp(() async {
      (server, base) = await _serve({
        '/animated': _animated,
        '/variable': _variableLoad,
        '/fill': _fillForwards,
        '/never': _neverSettles,
        '/settles': _settles,
      });
    });

    tearDown(() async => server.close(force: true));

    test('animated page: flat timer is nondeterministic, capture settle is not',
        () async {
      final url = '$base/animated';
      final old = await _capture(url, 4, useCaptureSettle: false);
      final now = await _capture(url, 4, useCaptureSettle: true);

      // THE CONTROL. If this ever passes with 1, the page stopped being
      // nondeterministic and the assertion below proves nothing.
      expect(old.toSet().length, greaterThan(1),
          reason: 'flat-timer control produced identical images — the page is '
              'no longer a nondeterminism reproducer, so the assertion below '
              'would pass on a no-op. Fix the page, not the assertion.');
      expect(now.toSet().length, 1,
          reason: 'capture settle must collapse the animated page to one image');
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('variable post-load work: flat timer races it, capture settle waits',
        () async {
      final url = '$base/variable';
      final old = await _capture(url, 4, useCaptureSettle: false);
      final now = await _capture(url, 4, useCaptureSettle: true);

      expect(old.toSet().length, greaterThan(1),
          reason: 'flat-timer control produced identical images — the random '
              'post-load delay is no longer straddling the 1500ms timer');
      expect(now.toSet().length, 1);
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('freeze preserves an animation-fill-mode end state', () async {
      final client = await CdpClient.launch();
      try {
        final tab = await client.newTab();
        await tab.enable();
        await tab.setViewport(390, 844);
        await tab.navigateAndSettleForCapture('$base/fill', settleMs: 300);
        // `both` holds opacity 1 at the end. A de-promotion that dropped the
        // animation without committing first would read back 0.
        final opacity = await tab.evaluate(
            "getComputedStyle(document.getElementById('s')).opacity");
        expect(opacity, '1');
        // ...and the animation really is gone, which is the point of the
        // commit-then-drop. Without this the test above passes on a no-op.
        final anim = await tab.evaluate(
            "getComputedStyle(document.getElementById('s')).animationName");
        expect(anim, 'none');
      } finally {
        await client.close();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('freezeAnimations reports what it froze, and reports zero honestly',
        () async {
      final client = await CdpClient.launch();
      try {
        final tab = await client.newTab();
        await tab.enable();
        await tab.navigate('$base/animated');
        final froze = await tab.freezeAnimations();
        expect(froze['infinite'], 1, reason: 'the spin animation is infinite');
        expect(froze['finite'], 0);
        expect(froze['committed'], 1);
        // Second call: nothing left to freeze. A count that stayed at 1 here
        // would mean the numbers are hardcoded rather than measured.
        final again = await tab.freezeAnimations();
        expect(again['infinite'], 0);
        expect(again['committed'], 0);
      } finally {
        await client.close();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ── the callers must ACT on non-convergence ────────────────────────────
    //
    // The tests above prove the settle DETECTS an unsettled page. That is only
    // half of it: the six migrated call sites originally took the record and
    // dropped it on the floor, so a page that never converged still produced a
    // green golden. Detection nobody consumes is the same as no detection.

    test('captureGolden REFUSES to write a golden from an unsettled page',
        () async {
      final dir = Directory.systemTemp.createTempSync('lens-unstable');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = '${dir.path}/bad.png';
      final good = '${dir.path}/good.png';

      await expectLater(
        captureGolden('$base/never', 390, 300, goldenPath: bad, settleMs: 100),
        throwsA(isA<LensUnstableCapture>()),
      );
      expect(File(bad).existsSync(), isFalse,
          reason: 'a golden written from an unsettled page poisons every future '
              'comparison — it passes against itself and fails against all else');

      // THE CONTROL. Without it, "no file" would also be the outcome of
      // captureGolden being broken outright, or of the server 404ing.
      await captureGolden('$base/settles', 390, 300,
          goldenPath: good, settleMs: 100);
      expect(File(good).existsSync(), isTrue,
          reason: 'the settling page must still produce a golden, or the '
              'refusal above proves nothing');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('captureGolden writes anyway under allowUnstable', () async {
      final dir = Directory.systemTemp.createTempSync('lens-allow');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = '${dir.path}/forced.png';
      await captureGolden('$base/never', 390, 300,
          goldenPath: out, settleMs: 100, allowUnstable: true);
      expect(File(out).existsSync(), isTrue);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('compareGolden fails an unsettled page instead of comparing it',
        () async {
      final dir = Directory.systemTemp.createTempSync('lens-cmp');
      addTearDown(() => dir.deleteSync(recursive: true));
      final golden = '${dir.path}/g.png';
      // Seed a golden from the same page so the comparison COULD accidentally
      // pass on a lucky frame. That is the failure being prevented: a spurious
      // PASS is worse than a spurious FAIL, because nobody investigates it.
      await captureGolden('$base/never', 390, 300,
          goldenPath: golden, settleMs: 100, allowUnstable: true);

      final result =
          await compareGolden('$base/never', golden, 390, 300, settleMs: 100);
      expect(result.passed, isFalse);
      expect(result.note, contains('did not converge'));

      // Control: the same comparison on a settling page passes, so the failure
      // above is attributable to non-convergence and not to compareGolden
      // being broken.
      final ok = '${dir.path}/ok.png';
      await captureGolden('$base/settles', 390, 300,
          goldenPath: ok, settleMs: 100);
      final good =
          await compareGolden('$base/settles', ok, 390, 300, settleMs: 100);
      expect(good.passed, isTrue, reason: good.note);
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('settleUntilStable reports non-convergence instead of pretending',
        () async {
      final client = await CdpClient.launch();
      try {
        final tab = await client.newTab();
        await tab.enable();
        await tab.navigate('$base/animated');
        // No freeze: an infinite animation can never satisfy the loop. The
        // contract under test is that it says so rather than returning a
        // cheerful `converged: true` after burning the timeout.
        final r = await tab.settleUntilStable(timeoutMs: 1200, minWaitMs: 0);
        expect(r.converged, isFalse);
        expect(r.captures, greaterThan(1));
      } finally {
        await client.close();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
