// DOM extraction: nested list → DOMSnapshot envelope with documents + strings.
import 'dart:io';

import 'package:appboxd/lens/dom.dart';
import 'package:test/test.dart';

Future<(HttpServer, String)> bootDomServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><body>
<ul>
  <li><span>Item Alpha</span><ul><li>Nested Beta</li></ul></li>
  <li>Item Gamma</li>
</ul>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

void main() {
  group('extractDom', () {
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      (server, baseUrl) = await bootDomServer();
    });
    tearDown(() => server.close());

    test('captures snapshot envelope with documents and strings', () async {
      final result = await extractDom(baseUrl, settleMs: 600);

      expect(result['certified'], isTrue);
      final snapshot = result['snapshot'] as Map;
      expect((snapshot['documents'] as List).isNotEmpty, isTrue);
      expect((snapshot['strings'] as List).contains('Item Alpha'), isTrue);
    });
  });
}
