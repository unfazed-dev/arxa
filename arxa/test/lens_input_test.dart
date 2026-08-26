// Lens input driving — proves Input.dispatchKeyEvent / dispatchMouseEvent
// reach the page (the game-screen verification path).
import 'dart:async';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:test/test.dart';

Future<(HttpServer, String)> bootInputServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><body>
<script>
  window.__keys = [];
  window.__clicks = [];
  document.addEventListener('keydown', (e) => window.__keys.push(e.key));
  document.addEventListener('click', (e) => window.__clicks.push([e.clientX, e.clientY]));
</script>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

void main() {
  group('CdpSession input', () {
    late CdpClient client;
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      (server, baseUrl) = await bootInputServer();
      client = await CdpClient.launch();
    });
    tearDown(() async {
      await client.close();
      await server.close();
    });

    test('key() dispatches keydown to the page', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(baseUrl, settleMs: 300);
      await tab.key('ArrowRight');
      await tab.key('a');
      await Future.delayed(const Duration(milliseconds: 200));
      expect(await tab.evaluate('window.__keys.join(",")'), 'ArrowRight,a');
    });

    test('click() dispatches mouse events at coordinates', () async {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(390, 844);
      await tab.navigateAndSettle(baseUrl, settleMs: 300);
      await tab.click(100, 200);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(await tab.evaluate('window.__clicks.length'), 1);
    });
  });
}
