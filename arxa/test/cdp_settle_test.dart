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

import 'package:arxa/cdp.dart';
import 'package:arxa/lens.dart';
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

/// Nothing animated at load; a CSS animation AND an SMIL svg appear 150ms
/// later. This is the only page here that exercises the SECOND freeze pass
/// doing real work — at step 1 there is nothing to freeze, so `frozen` is
/// zeros and `frozenLate` carries the whole story.
///
/// `both` fill matters: without it the finished animation drops out of
/// `getAnimations()` and the second pass finds nothing, which would make this
/// page indistinguishable from one that never animated at all.
///
/// The late svg is here because `getAnimations()` cannot see SMIL at all — it
/// is paused through a separate code path with a separate counter. A fixture
/// with only the CSS half would pass just as green if the late-warning ignored
/// the other two categories, which is exactly what it did until this grew.
///
/// The STATIC svg is load-bearing too, and less obvious. Without it, a late
/// svg is counted 1 by the second pass whether or not `freezeAnimations`
/// marks what it has already frozen — because it did not exist at the first
/// pass either way. Only an element present at BOTH passes can tell "counted
/// once" apart from "recounted every time", and recounting is what the code
/// actually did (measured: a second pass returned the same census as the
/// first, static never-animated svgs included).
const _lateAnimation = '''
<!doctype html><meta charset=utf-8><title>late</title>
<style>body{margin:0;background:#fff}
@keyframes slide{from{transform:translateX(-80px)}to{transform:none}}
.s{width:120px;height:120px;margin:40px;background:#c17d11;
   animation:slide 200ms linear both}</style>
<svg id=static width=40 height=40><rect width=40 height=40 fill="#4e9a06"/></svg>
<div id=host></div>
<script>
  window.addEventListener('load', function () {
    setTimeout(function () {
      var d = document.createElement('div');
      d.className = 's';
      document.getElementById('host').appendChild(d);
      document.getElementById('host').insertAdjacentHTML('beforeend',
        '<svg width=80 height=80><circle cx=40 cy=40 r=15 fill="#204a87">' +
        '<animate attributeName="r" from="10" to="30" dur="900ms" ' +
        'repeatCount="indefinite"/></circle></svg>');
    }, 150);
  });
</script>
''';

/// Captures `stderr` inside an [IOOverrides] zone. `noSuchMethod` swallows the
/// rest of the [Stdout] surface — the tests below only ever call `writeln`.
class _CapturedStderr implements Stdout {
  final buffer = StringBuffer();
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
  @override
  void write(Object? object) => buffer.write(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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
        '/late': _lateAnimation,
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

    test('settleForCapture reports the FIRST freeze, not the emptied second',
        () async {
      // REGRESSION. This returned the second freeze's map until 2026-08-21.
      // The first pass strips `animation` from every element, so the second
      // finds nothing and reports all zeros — on a page it froze perfectly.
      // `frozen` therefore read identically whether the freeze did everything
      // or nothing, which is this project's oldest failure shape, built into
      // the very API meant to avoid it.
      //
      // Note where the existing coverage failed: there IS a test above that
      // exercises freezeAnimations directly and asserts it counts honestly.
      // It passed throughout. Testing the method never sees a caller that
      // wires it up backwards — the defect lived in settleForCapture, so the
      // test has to go THROUGH settleForCapture.
      final client = await CdpClient.launch();
      try {
        final tab = await client.newTab();
        await tab.enable();
        await tab.setViewport(390, 300);
        final r = await tab.navigateAndSettleForCapture('$base/animated',
            settleMs: 100);
        expect(r.frozen['infinite'], 1,
            reason: 'the spin animation must be reported by the pass that '
                'actually froze it');
        expect(r.frozen['committed'], 1);
        // The second pass legitimately finds nothing left — that is the whole
        // reason it must not be what `frozen` reports. Asserting it keeps the
        // two from being quietly swapped back.
        expect(r.frozenLate['committed'], 0);

        // Control: a page with nothing to freeze must report zeros in the
        // SAME field. Without this, `frozen` could be hardcoded non-zero and
        // the assertions above would still pass.
        final plain = await tab.navigateAndSettleForCapture('$base/settles',
            settleMs: 100);
        expect(plain.frozen['infinite'], 0);
        expect(plain.frozen['committed'], 0);
      } finally {
        await client.close();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a late-starting animation warns instead of being returned silently',
        () async {
      // `frozenLate` was computed correctly and read by NOTHING outside this
      // file — the third shape of "pass outcome == did-not-run outcome" this
      // project collects, and the one hardest to see, because the field is
      // right there in the return type and reads as coverage. The fix is the
      // same one `converged` got: warn at the source, where no future caller
      // can forget to look. So the assertion is on the WARNING, not on the
      // field — asserting the field is what let this sit unread.
      final captured = _CapturedStderr();
      await IOOverrides.runZoned(() async {
        final client = await CdpClient.launch();
        try {
          final tab = await client.newTab();
          await tab.enable();
          await tab.setViewport(390, 300);
          final r = await tab.navigateAndSettleForCapture('$base/late',
              settleMs: 100);
          // Pass 1 sees no animation, but it does see the static svg — and
          // that one must NOT be counted again below.
          expect(r.frozen['finite'], 0);
          expect(r.frozen['smil'], 1);
          expect(r.frozenLate['finite'], 1,
              reason: 'the animation appeared after the first freeze, so only '
                  'the second pass can account for it');
          // The non-CSS half. getAnimations() cannot see SMIL, so this is a
          // genuinely separate path — and the counter only reads as "new"
          // because freezeAnimations marks what it has already frozen.
          expect(r.frozenLate['smil'], 1,
              reason: 'a late svg must be counted by the pass that first saw '
                  'it, not recounted on every pass');
          // Not a failure: loop 2 ran after that freeze and settled.
          expect(r.converged, isTrue);

          // Control, in the same zone: a page with no late animation must not
          // produce the warning. Without this the assertion below would pass
          // just as well if the warning were unconditional.
          final before = captured.buffer.length;
          await tab.navigateAndSettleForCapture('$base/settles',
              settleMs: 100);
          expect(captured.buffer.length, before,
              reason: 'a page with nothing to freeze late must stay quiet');
        } finally {
          await client.close();
        }
      }, stderr: () => captured);

      // 2 = the CSS animation plus the SMIL svg. Asserting the total rather
      // than "warning present" is what keeps a category from being dropped
      // back out of the sum without a test noticing.
      expect(captured.buffer.toString(),
          contains('2 animation(s)/media element(s) APPEARED during settle'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('settleForCapture reports its own screenshot cost', () async {
      // This number is the unit a warm-Chrome recycle policy is denominated
      // in. It was unobservable until the field existed — a memory probe had
      // to replicate the whole sequence out of public methods to learn it.
      final client = await CdpClient.launch();
      try {
        final tab = await client.newTab();
        await tab.enable();
        await tab.setViewport(390, 300);
        final settled = await tab.navigateAndSettleForCapture('$base/settles',
            settleMs: 100);
        expect(settled.converged, isTrue);
        // Two loops, each converging on its first agreement = 2 captures each.
        expect(settled.screenshots, 4,
            reason: 'a settled page costs two captures per loop; a change here '
                'changes the recycle policy denominated in screenshots');

        // The control: a page that CANNOT converge must cost dramatically
        // more, or the number above is a constant rather than a measurement.
        final stuck = await tab.navigateAndSettleForCapture('$base/never',
            settleMs: 0, timeoutMs: 1200);
        expect(stuck.converged, isFalse);
        expect(stuck.screenshots, greaterThan(settled.screenshots * 2),
            reason: 'a timed-out settle burns the whole window at the poll '
                'interval — that spread is exactly why callers must report a '
                'distribution and never a mean');
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
