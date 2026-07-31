// Network trace: /api/data (200) + 404 asset + genuine failure → folded requests.
import 'dart:io';

import 'package:appboxd/lens/net.dart';
import 'package:test/test.dart';

Future<(HttpServer, String)> bootNetServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    if (req.uri.path == '/api/data') {
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"msg":"hello"}');
    } else if (req.uri.path == '/') {
      req.response.headers.contentType = ContentType.html;
      req.response.write('''
<!DOCTYPE html><html><head>
<link rel="stylesheet" href="http://127.0.0.1:1/dead.css">
</head><body>
<img src="/missing.png">
<script>
fetch('/api/data').then(function (r) { return r.json(); });
</script>
</body></html>
''');
    } else {
      req.response.statusCode = HttpStatus.notFound;
    }
    req.response.close();
  });
  return (server, base);
}

void main() {
  group('traceNet', () {
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      (server, baseUrl) = await bootNetServer();
    });
    tearDown(() => server.close());

    test('folds requests with statuses and a failed flag', () async {
      final result = await traceNet(baseUrl, settleMs: 800, traceMs: 1500);

      final requests = (result['requests'] as List)
          .map((r) => r as Map<String, dynamic>)
          .toList();

      // The data endpoint returned 200.
      expect(
        requests.any((r) => (r['url'] as String).contains('/api/data')),
        isTrue,
      );
      final dataReq = requests.firstWhere(
        (r) => (r['url'] as String).contains('/api/data'),
      );
      expect(dataReq['status'], 200);

      // The missing asset returned 404.
      expect(requests.any((r) => r['status'] == 404), isTrue);

      // The dead stylesheet genuinely failed to load.
      expect(requests.any((r) => r['failed'] == true), isTrue);
    });
  });
}
