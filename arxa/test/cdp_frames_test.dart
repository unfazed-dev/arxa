// Frame semantics, against real Chrome.
//
// These are the properties the island probes (inspect, flowwalk) depend on and
// cannot check for themselves — when one of them breaks, the probe reports a
// broken studio rather than a broken engine, which is the failure mode worth
// paying a test to avoid:
//
// - a pointer aimed at an element inside a SCALED iframe lands on it. The
//   fixture scales the frame by 0.5 on purpose: an implementation that adds an
//   in-frame `getBoundingClientRect()` to the iframe's own rect passes every
//   unscaled test and misses every element here by half the offset.
// - the child hears a `pointermove`, not merely a `pointerover`. The first
//   move into a frame Chrome has not yet routed a pointer to delivers
//   over/enter and no move, and moves dispatched inside one compositor frame
//   are coalesced into one — so a single dispatch can leave an island that
//   tracks hovers the ordinary way having heard nothing at all.
// - `evaluateInFrame` runs in the CHILD's world. Reading the child through the
//   parent's `contentDocument` is the tempting shortcut and it makes
//   `window.parent` resolve against the wrong window, turning a bridge check
//   into an assertion that cannot fail.

import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:test/test.dart';

/// A parent page holding a half-scale iframe, and the child it frames.
///
/// The child records what each pointer event reached, so a test can tell
/// "landed on the target" apart from "landed in the frame somewhere".
Future<(HttpServer, String)> bootFrameServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';

  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    if (req.uri.path == '/child') {
      req.response.write('''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>child</title>
<style>
  body { margin: 0; }
  #card { position: absolute; left: 60px; top: 120px; width: 200px; height: 80px; background: #cde; }
  #far { position: absolute; left: 60px; top: 300px; width: 200px; height: 40px; background: #edc; }
</style></head>
<body>
  <div id="card" data-el="card:One"></div>
  <div id="far" data-el="card:Two"></div>
  <script>
    window.__inChild = 'yes';
    window.__moves = [];
    window.__clicks = [];
    document.addEventListener('pointermove', (e) => {
      const el = e.target.closest('[data-el]');
      window.__moves.push(el ? el.dataset.el : 'none');
    }, true);
    document.addEventListener('click', (e) => {
      const el = e.target.closest('[data-el]');
      window.__clicks.push(el ? el.dataset.el : 'none');
    }, true);
  </script>
</body></html>
''');
    } else {
      // transform: scale() is the whole point — see the header.
      req.response.write('''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>parent</title>
<style>
  body { margin: 0; }
  #tile { position: absolute; left: 200px; top: 100px; width: 200px; height: 200px; overflow: hidden; }
  #f { width: 400px; height: 400px; border: 0; transform: scale(0.5); transform-origin: top left; }
</style></head>
<body>
  <div id="tile"><iframe id="f" src="/child"></iframe></div>
  <script>window.__inParent = 'yes';</script>
</body></html>
''');
    }
    req.response.close();
  });

  return (server, base);
}

void main() {
  group('CdpSession frames', () {
    late CdpClient client;
    late CdpSession session;
    late HttpServer server;
    late String base;

    // One browser and one fixture server for the group, a fresh TAB per test.
    // Launching Chrome per test cost nine launches in a suite that is already
    // Chrome-bound, and the contention showed up as `DevToolsActivePort`
    // timeouts in whichever test happened to start while the others were
    // booting — a failure that says nothing about the code under test.
    setUpAll(() async {
      (server, base) = await bootFrameServer();
      client = await CdpClient.launch();
    });

    tearDownAll(() async {
      await client.close();
      await server.close(force: true);
    });

    setUp(() async {
      session = await client.newTab();
      await session.enable();
      await session.setViewport(800, 600);
      await session.navigate(base);
      // The child is a separate document; the parent's load event does not
      // wait for it in every timing, and every test below reads it.
      await session.waitForFunction(
          "(() => { const f = document.getElementById('f');"
          " return !!f && !!f.contentDocument"
          " && !!f.contentDocument.querySelector('#card'); })()");
    });

    tearDown(() async {
      await client.send('Target.closeTarget', {'targetId': session.targetId});
    });

    test('frames() lists the main frame first, then the child', () async {
      final frames = await session.frames();
      expect(frames.length, 2);
      expect(frames.first.isMain, isTrue);
      expect(frames.last.isMain, isFalse);
      expect(frames.last.url, endsWith('/child'));
      expect(frames.last.parentId, frames.first.id);
    });

    test('frameForSelector resolves an iframe element to its frame', () async {
      final frame = await session.frameForSelector('#f');
      expect(frame, isNotNull);
      expect(frame!.url, endsWith('/child'));
    });

    test('frameForSelector reports a missing element rather than throwing',
        () async {
      expect(
          await session.frameForSelector('#nope',
              timeout: const Duration(milliseconds: 300)),
          isNull);
      // An element that exists but frames nothing is also null, not an error.
      expect(
          await session.frameForSelector('#tile',
              timeout: const Duration(milliseconds: 300)),
          isNull);
    });

    test('evaluateInFrame runs in the child world, not the parent', () async {
      final frame = (await session.frameForSelector('#f'))!;
      expect(await session.evaluateInFrame(frame, 'window.__inChild'), 'yes');
      expect(await session.evaluateInFrame(frame, 'window.__inParent'), isNull);
      // The parent is reachable FROM the child — the flowwalk island's bridge.
      // Asked from the parent instead, `window.parent` is the parent itself
      // and this passes whether or not the child could see anything.
      expect(
          await session.evaluateInFrame(frame, 'window.parent.__inParent'), 'yes');
    });

    test('waitForFunctionInFrame polls the child, and gives up bounded',
        () async {
      final frame = (await session.frameForSelector('#f'))!;
      expect(await session.waitForFunctionInFrame(frame, 'window.__inChild === "yes"'),
          isTrue);
      expect(
          await session.waitForFunctionInFrame(frame, 'window.__never === 1',
              timeout: const Duration(milliseconds: 300)),
          isFalse);
    });

    test('hoverSelectorInFrame lands a pointermove on the target through a scale',
        () async {
      final frame = (await session.frameForSelector('#f'))!;
      expect(await session.hoverSelectorInFrame(frame, '[data-el="card:One"]'),
          isTrue);
      final moves = await session.evaluateInFrame(
          frame, 'JSON.stringify(window.__moves)') as String;
      // Reached the child at all — a single un-spaced dispatch delivers
      // pointerover and no pointermove, and this list comes back empty.
      expect(moves, isNot('[]'),
          reason: 'the child heard no pointermove, so an island tracking '
              'hovers would not have reacted');
      // And landed on the right element. Under the 0.5 scale the card's parent
      // -space centre is nowhere near its in-child coordinates, so a naive
      // offset sum reports "none" here rather than the target.
      expect(moves, contains('card:One'));
      expect(moves, isNot(contains('card:Two')));
    });

    test('clickSelectorInFrame clicks the element the pointer is over',
        () async {
      final frame = (await session.frameForSelector('#f'))!;
      expect(await session.clickSelectorInFrame(frame, '[data-el="card:Two"]'),
          isTrue);
      expect(
          await session.evaluateInFrame(
              frame, 'JSON.stringify(window.__clicks)'),
          '["card:Two"]');
    });

    test('a synthetic click reaches a target no pointer could', () async {
      final frame = (await session.frameForSelector('#f'))!;
      // #far sits at y=300 in the child; the tile crops the frame at 200px of
      // scaled height (=400 child px), so it is inside — but the synthetic
      // path is what a probe uses when the element genuinely is not hittable.
      expect(
          await session.clickSelectorInFrame(frame, '[data-el="card:One"]',
              synthetic: true),
          isTrue);
      expect(
          await session.evaluateInFrame(
              frame, 'JSON.stringify(window.__clicks)'),
          '["card:One"]');
    });

    test('a missing in-frame element is reported, not thrown', () async {
      final frame = (await session.frameForSelector('#f'))!;
      expect(
          await session.hoverSelectorInFrame(frame, '#nope',
              timeout: const Duration(milliseconds: 400)),
          isFalse);
      expect(
          await session.clickSelectorInFrame(frame, '#nope',
              timeout: const Duration(milliseconds: 400)),
          isFalse);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
