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
