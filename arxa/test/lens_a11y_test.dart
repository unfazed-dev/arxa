// Accessibility extraction: button/img/heading → ax-tree nodes by role+name.
import 'dart:io';

import 'package:arxa/lens/a11y.dart';
import 'package:test/test.dart';

Future<(HttpServer, String)> bootA11yServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><body>
<h1>Page Title</h1>
<button aria-label="Save">x</button>
<img alt="Logo" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC">
<p>Body text.</p>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

void main() {
  group('extractA11y', () {
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      (server, baseUrl) = await bootA11yServer();
    });
    tearDown(() => server.close());

    test('finds button, image, and heading nodes by role and name', () async {
      final result = await extractA11y(baseUrl, settleMs: 600);

      expect(result['certified'], isTrue);
      final nodes = result['nodes'] as List;
      expect(
        nodes.any((n) => n['role'] == 'button' && n['name'] == 'Save'),
        isTrue,
      );
      expect(
        nodes.any((n) => n['role'] == 'image' && n['name'] == 'Logo'),
        isTrue,
      );
      expect(nodes.any((n) => n['role'] == 'heading'), isTrue);
    });
  });
}
