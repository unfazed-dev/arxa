import 'dart:convert';
import 'dart:io';

import 'package:appboxd/config.dart';
import 'package:appboxd/server.dart';
import 'package:test/test.dart';

Future<(HttpClientResponse, String)> _get(HttpClient client, int port, String path,
    {String method = 'GET'}) async {
  final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  return (response, body);
}

void main() {
  late Directory fixture;
  late HttpServer server;
  late HttpClient client;
  late int port;

  setUp(() async {
    fixture = Directory.systemTemp.createTempSync('appboxd_test_');
    // Web root fixture.
    Directory('${fixture.path}/web').createSync();
    File('${fixture.path}/web/index.html')
        .writeAsStringSync('<h1>app-box</h1>');
    File('${fixture.path}/web/app.js').writeAsStringSync('console.log(1);');
    // Pipeline fixture: a fake pipeline.sh that echoes its gate invocation.
    Directory('${fixture.path}/pipeline').createSync();
    File('${fixture.path}/pipeline/pipeline.sh').writeAsStringSync(
        '#!/usr/bin/env bash\n'
        'echo "gate \$2 on \$(basename \$(pwd))"\n'
        'echo "warn" >&2\n'
        'exit 0\n');

    final config = AppboxdConfig(
      repoRoot: fixture.path,
      port: 0,
      webRoot: '${fixture.path}/web',
    );
    server = await startServer(config);
    port = server.port;
    client = HttpClient();
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    fixture.deleteSync(recursive: true);
  });

  test('serves a static file with the right content type', () async {
    final (response, body) = await _get(client, port, '/app.js');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType.toString(), contains('javascript'));
    expect(body, 'console.log(1);');
  });

  test('serves index.html for the root path', () async {
    final (response, body) = await _get(client, port, '/');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType.toString(), contains('text/html'));
    expect(body, contains('app-box'));
  });

  test('GET /api/health answers ok', () async {
    final (response, body) = await _get(client, port, '/api/health');
    expect(response.statusCode, HttpStatus.ok);
    final json = jsonDecode(body) as Map;
    expect(json['status'], 'ok');
  });

  test('GET /api/phases lists the pipeline phases', () async {
    final (response, body) = await _get(client, port, '/api/phases');
    expect(response.statusCode, HttpStatus.ok);
    final json = jsonDecode(body) as Map;
    expect(json['phases'], containsAll(['intake', 'design', 'build', 'deploy']));
  });

  test('refuses path traversal', () async {
    for (final attempt in [
      '/../pipeline/pipeline.sh',
      '/%2e%2e/%2e%2e/etc/passwd',
      '/../../secret',
    ]) {
      final (response, _) = await _get(client, port, attempt);
      expect(response.statusCode, isIn([HttpStatus.forbidden, HttpStatus.notFound]),
          reason: attempt);
    }
  });

  test('POST /api/phases/<name>/run captures output and exit code', () async {
    final (response, body) =
        await _get(client, port, '/api/phases/design/run', method: 'POST');
    expect(response.statusCode, HttpStatus.ok);
    final json = jsonDecode(body) as Map;
    expect(json['phase'], 'design');
    expect(json['exitCode'], 0);
    expect(json['stdout'], contains('gate design'));
    expect(json['stderr'], contains('warn'));
  });

  test('unknown phase run is a 404', () async {
    final (response, _) =
        await _get(client, port, '/api/phases/bogus/run', method: 'POST');
    expect(response.statusCode, HttpStatus.notFound);
  });
}
