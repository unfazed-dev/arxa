// CDP domain extensions: screencast, Network trace, AX tree,
// DOMSnapshot, emulated media, element clip screenshot.
import 'dart:async';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:test/test.dart';

// bootFixtureServer() — same shape as lens_input_test.dart's bootInputServer():
// '/' serves an animated page (a #box div whose background toggles every
// animation frame so the page keeps painting for screencast) that fires
// fetch('/api/data') on load; '/api/data' serves JSON.
Future<(HttpServer, String)> bootFixtureServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    if (req.uri.path == '/api/data') {
      req.response.headers.contentType = ContentType.json;
      req.response.write('{}');
      req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><body>
<p>Animated box demo</p>
<div id="box" style="width:100px;height:100px;background:linear-gradient(135deg,red,orange,yellow)"></div>
<script>
  const box = document.getElementById('box');
  let on = true;
  function tick() {
    on = !on;
    box.style.background = on
      ? 'linear-gradient(135deg,red,orange,yellow)'
      : 'linear-gradient(135deg,blue,cyan,green)';
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
  fetch('/api/data');
</script>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

void main() {
  group('CDP domains', () {
    late CdpClient client;
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      (server, baseUrl) = await bootFixtureServer();
      client = await CdpClient.launch();
    });
    tearDown(() async {
      await client.close();
      await server.close();
    });

    test('screencast delivers acked frames until stopped', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(390, 844);
      await tab.navigateAndSettle(baseUrl, settleMs: 500);
      final cast = await tab.screencast(format: 'jpeg', quality: 60);
      final frames = <ScreencastFrame>[];
      final sub = cast.frames.listen(frames.add);
      await Future.delayed(const Duration(seconds: 2));
      await cast.stop();
      await sub.cancel();
      expect(frames.length, greaterThan(3)); // animated page keeps painting
      expect(frames.first.bytes.length, greaterThan(1000));
    });

    test('traceNetwork captures the page fetch', () async {
      final tab = await client.newTab();
      await tab.enable();
      final traceDone = tab.traceNetwork(const Duration(seconds: 3));
      await tab.navigateAndSettle(baseUrl, settleMs: 800);
      final events = await traceDone;
      final urls = events
          .where((e) => e['method'] == 'Network.requestWillBeSent')
          .map((e) => ((e['params'] as Map)['request'] as Map)['url'])
          .toList();
      expect(urls.any((u) => u == '$baseUrl/api/data'), isTrue);
    });

    test('getFullAxTree returns role/name nodes', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(baseUrl, settleMs: 500);
      final nodes = await tab.getFullAxTree();
      expect(nodes, isNotEmpty);
      expect(nodes.any((n) => (n['role'] as Map?)?['value'] == 'StaticText' ||
          (n['role'] as Map?)?['value'] == 'text'), isTrue);
    });

    test('captureDomSnapshot returns documents with layout', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(baseUrl, settleMs: 500);
      final snap = await tab.captureDomSnapshot(['display', 'color']);
      expect(snap['documents'], isA<List>());
      expect((snap['documents'] as List), isNotEmpty);
    });

    test('setEmulatedMedia flips prefers-color-scheme', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(baseUrl, settleMs: 300);
      await tab.setEmulatedMedia(features: {
        'prefers-color-scheme': 'dark',
        'prefers-reduced-motion': 'reduce',
      });
      expect(
          await tab.evaluate(
              'matchMedia("(prefers-color-scheme: dark)").matches'),
          isTrue);
      expect(
          await tab.evaluate(
              'matchMedia("(prefers-reduced-motion: reduce)").matches'),
          isTrue);
    });

    test('elementScreenshot clips to the element box', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(390, 844);
      await tab.navigateAndSettle(baseUrl, settleMs: 500);
      final png = await tab.elementScreenshot('#box');
      expect(png.length, greaterThan(500));
      // Decode-free size check: a 100x100 clip PNG is far smaller than
      // a 390x844 viewport PNG.
      final full = await tab.screenshot();
      expect(png.length, lessThan(full.length));
    });
  });
}
