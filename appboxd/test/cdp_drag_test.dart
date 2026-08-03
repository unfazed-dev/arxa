// Drag semantics, against real Chrome.
//
// These are the properties a resize probe depends on and cannot check for
// itself: that the travel arrives as many moves rather than one jump, that
// `beforeRelease` observes the page with the button still down, and that the
// button always comes back up. The last one is the reason the others are
// testable at all — the probe runner shares one browser across a suite, so a
// button left down by a failed drag lands on some later probe and gets
// diagnosed there instead of here.

import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:test/test.dart';

/// A page that records every pointer event with the button mask at the time.
Future<(HttpServer, String)> bootDragServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';

  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>drag</title>
<style>
  body { margin: 0; }
  #rail { position: absolute; left: 100px; top: 100px; width: 40px; height: 40px; background: #333; }
  /* A hover-revealed tool rail — the studio shape shell-chrome section F
     drives: the tool is not a hit target until its tile is hovered. */
  #tile { position: absolute; left: 400px; top: 200px; width: 120px; height: 80px; background: #eee; }
  #tool { display: none; width: 40px; height: 20px; background: #666; }
  #tile:hover #tool { display: block; }
  /* The badge exists only while a drag is live — the shape probe-panel-resize
     asserts against, and the reason a post-release read is worthless. */
  #badge { display: none; position: absolute; left: 300px; top: 20px; }
  body.dragging #badge { display: block; }
</style>
</head>
<body>
  <div id="rail"></div>
  <div id="badge">0</div>
  <div id="tile"><div id="tool"></div></div>
  <script>
    window.__toolClicks = 0;
    window.__events = [];
    const rail = document.getElementById('rail');
    const badge = document.getElementById('badge');
    let dragging = false;
    let startX = 0;
    rail.addEventListener('pointerdown', (e) => {
      dragging = true; startX = e.clientX;
      document.body.classList.add('dragging');
      window.__events.push({type: 'down', buttons: e.buttons, x: e.clientX});
    });
    addEventListener('pointermove', (e) => {
      window.__events.push({type: 'move', buttons: e.buttons, x: e.clientX});
      if (dragging) badge.textContent = String(e.clientX - startX);
    });
    document.getElementById('tool')
      .addEventListener('click', () => { window.__toolClicks++; });
    addEventListener('pointerup', (e) => {
      dragging = false;
      document.body.classList.remove('dragging');
      window.__events.push({type: 'up', buttons: e.buttons, x: e.clientX});
    });
  </script>
</body>
</html>
''');
    req.response.close();
  });

  return (server, base);
}

void main() {
  group('CdpSession.drag', () {
    late CdpClient client;
    late CdpSession session;
    late HttpServer server;
    late String base;

    setUp(() async {
      (server, base) = await bootDragServer();
      client = await CdpClient.launch();
      session = await client.newTab();
      await session.setViewport(800, 600);
      await session.navigate(base);
    });

    tearDown(() async {
      await client.close();
      await server.close(force: true);
    });

    test('travel arrives as many moves, not one jump', () async {
      await session.drag(120, 120, 220, 120,
          steps: 14, stepDelay: const Duration(milliseconds: 1));
      final moves = await session.evaluate(
          "window.__events.filter(e => e.type === 'move').length");
      // A drag-threshold listener needs the intermediate points; one jump
      // reads as a click and the interaction under test never happens.
      expect(moves, greaterThanOrEqualTo(14));
    });

    test('the moves carry the button-down mask', () async {
      await session.drag(120, 120, 220, 120,
          steps: 4, stepDelay: const Duration(milliseconds: 1));
      final movesWithButton = await session.evaluate(
          "window.__events.filter(e => e.type === 'move' && e.buttons === 1).length");
      expect(movesWithButton, greaterThanOrEqualTo(4),
          reason: 'a move without buttons:1 is delivered as a hover, so the '
              'page sees the drag end at the first move');
    });

    test('beforeRelease observes the page mid-drag, with the button still down',
        () async {
      String? badgeDuring;
      var visibleDuring = false;
      await session.drag(120, 120, 220, 120,
          steps: 6,
          stepDelay: const Duration(milliseconds: 1), beforeRelease: () async {
        badgeDuring = await session
            .evaluate("document.getElementById('badge').textContent") as String?;
        visibleDuring = await session.evaluate(
            "getComputedStyle(document.getElementById('badge')).display !== 'none'") as bool;
      });

      expect(visibleDuring, isTrue);
      // Travel was 100px, so the badge should have counted to it.
      expect(badgeDuring, '100');

      // And the point of the whole exercise: after the release the badge is
      // gone, so a probe reading it here would assert against nothing.
      final visibleAfter = await session.evaluate(
          "getComputedStyle(document.getElementById('badge')).display !== 'none'");
      expect(visibleAfter, isFalse,
          reason: 'if this ever passes, the mid-drag read is no longer needed '
              '— but so long as it fails, a post-release read is vacuous');
    });

    test('the button is released even when beforeRelease throws', () async {
      await expectLater(
        session.drag(120, 120, 220, 120,
            steps: 3,
            stepDelay: const Duration(milliseconds: 1),
            beforeRelease: () async => throw StateError('observer blew up')),
        throwsA(isA<StateError>()),
      );

      // The throw must propagate (the probe has to hear about it) AND the
      // button must still be up, or every later interaction in this browser
      // is dragging something.
      final ups = await session
          .evaluate("window.__events.filter(e => e.type === 'up').length");
      expect(ups, 1, reason: 'the release is in a finally for exactly this case');

      final stillDragging =
          await session.evaluate("document.body.classList.contains('dragging')");
      expect(stillDragging, isFalse);
    });

    test('dragSelector grabs the element centre and forwards beforeRelease',
        () async {
      var sawBadge = false;
      final ok = await session.dragSelector('#rail',
          dx: 80,
          dy: 0,
          steps: 5, beforeRelease: () async {
        sawBadge = await session.evaluate(
            "getComputedStyle(document.getElementById('badge')).display !== 'none'") as bool;
      });
      expect(ok, isTrue);
      expect(sawBadge, isTrue);

      final down = await session.evaluate(
          "JSON.stringify(window.__events.find(e => e.type === 'down') || null)");
      // #rail spans x 100..140, so its centre is 120.
      expect(down, contains('"x":120'));
    });

    test('a missing element is reported, not thrown', () async {
      expect(await session.dragSelector('#nope',
          dx: 10, dy: 0, timeout: const Duration(milliseconds: 300)), isFalse);
    });

    test('steps below 1 is rejected rather than silently becoming a jump', () {
      expect(() => session.drag(0, 0, 10, 10, steps: 0),
          throwsA(isA<ArgumentError>()));
    });

    // shell-chrome section F's shape: hover a tile to reveal a tool, click the
    // tool. Ordered so the first case proves the second one is necessary —
    // otherwise a passing hover test says nothing about whether the hover did
    // any work.
    test('a hover-revealed tool is unreachable without hovering its tile',
        () async {
      final clicked = await session.clickSelector('#tool',
          timeout: const Duration(milliseconds: 400));
      expect(clicked, isFalse,
          reason: 'the tool has no box until the tile is hovered, so there is '
              'nowhere to aim — if this ever passes, the fixture stopped '
              'modelling the studio and the test below is worthless');
      expect(await session.evaluate('window.__toolClicks'), 0);
    });

    test('hoverSelector reveals it, and clickSelector then lands on it',
        () async {
      expect(await session.hoverSelector('#tile'), isTrue);
      expect(await session.clickSelector('#tool'), isTrue);
      expect(await session.evaluate('window.__toolClicks'), 1);
    });

    test('hoverSelector reports a missing element rather than throwing',
        () async {
      expect(
          await session.hoverSelector('#nope',
              timeout: const Duration(milliseconds: 300)),
          isFalse);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
