import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'gateway.dart';
import 'memory_analytics.dart' as memory_analytics;
import 'phases.dart' as pipeline;

/// Starts the appboxd HTTP server: static web builder UI + /api/ endpoints,
/// plus the /llm/ loopback gateway (E2) when [gateway] is supplied.
Future<HttpServer> startServer(AppboxdConfig config,
    {InternetAddress? address, Gateway? gateway}) async {
  final server = await HttpServer.bind(
    address ?? InternetAddress.loopbackIPv4,
    config.port,
  );
  server.listen((request) => _handle(config, request, gateway));
  return server;
}

Future<void> _handle(AppboxdConfig config, HttpRequest request, Gateway? gateway) async {
  final path = request.uri.path;
  if (path.startsWith('/llm/')) {
    if (gateway == null) {
      return _json(request, {'error': 'llm gateway not configured'},
          status: HttpStatus.serviceUnavailable);
    }
    return gateway.handle(request);
  }
  if (path == '/api/health') {
    return _json(request, {
      'status': 'ok',
      'repoRoot': config.repoRoot,
      'webRoot': config.webRoot,
    });
  }
  if (path == '/api/phases') {
    return _json(request, {
      'phases': pipeline.phases,
      'current': pipeline.currentPhase(config.repoRoot),
    });
  }
  final runMatch = RegExp(r'^/api/phases/([a-z]+)/run$').firstMatch(path);
  if (runMatch != null) {
    if (request.method != 'POST') {
      return _json(request, {'error': 'POST required'}, status: HttpStatus.methodNotAllowed);
    }
    final phase = runMatch.group(1)!;
    if (!pipeline.phases.contains(phase)) {
      return _json(request, {'error': 'unknown phase: $phase'}, status: HttpStatus.notFound);
    }
    final result = await pipeline.runPhase(config.repoRoot, phase);
    return _json(request, result.toJson(),
        status: result.exitCode == 0 ? HttpStatus.ok : HttpStatus.badGateway);
  }
  if (path == '/api/memory/briefing') {
    // M1 operator briefing: read-only rollup over the pipeline JSONL
    // streams; missing streams degrade to one-line notes inside the
    // briefing itself, so this is 200 from day zero.
    final text = await memory_analytics.briefing(config.repoRoot);
    final response = request.response;
    response.headers.contentType =
        ContentType('text', 'markdown', charset: 'utf-8');
    response.write(text);
    return response.close();
  }
  if (path.startsWith('/api/')) {
    return _json(request, {'error': 'not found'}, status: HttpStatus.notFound);
  }
  return _serveStatic(config, request);
}

Future<void> _serveStatic(AppboxdConfig config, HttpRequest request) async {
  if (request.method != 'GET' && request.method != 'HEAD') {
    return _json(request, {'error': 'method not allowed'}, status: HttpStatus.methodNotAllowed);
  }
  final root = p.canonicalize(config.webRoot);
  var rel = request.uri.path;
  // Strip leading slash, decode, and normalize — then refuse anything that
  // escapes the web root.
  if (rel.startsWith('/')) rel = rel.substring(1);
  final resolved = p.normalize(p.join(root, Uri.decodeComponent(rel)));
  if (!p.isWithin(root, resolved) && resolved != root) {
    return _json(request, {'error': 'forbidden'}, status: HttpStatus.forbidden);
  }

  var file = File(resolved);
  final type = file.statSync().type;
  if (type == FileSystemEntityType.directory) {
    file = File(p.join(resolved, 'index.html'));
  }
  if (!file.existsSync()) {
    return _json(request, {'error': 'not found'}, status: HttpStatus.notFound);
  }

  final response = request.response;
  response.headers.contentType = _contentTypeFor(file.path);
  response.headers.contentLength = file.lengthSync();
  if (request.method == 'GET') {
    await response.addStream(file.openRead());
  }
  await response.close();
}

ContentType _contentTypeFor(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.html':
      return ContentType.html;
    case '.css':
      return ContentType('text', 'css', charset: 'utf-8');
    case '.js':
    case '.mjs':
      return ContentType('text', 'javascript', charset: 'utf-8');
    case '.json':
      return ContentType.json;
    case '.png':
      return ContentType('image', 'png');
    case '.svg':
      return ContentType('image', 'svg+xml');
    case '.ico':
      return ContentType('image', 'x-icon');
    case '.wasm':
      return ContentType('application', 'wasm');
    case '.woff2':
      return ContentType('font', 'woff2');
    case '.md':
      return ContentType('text', 'markdown', charset: 'utf-8');
    case '.map':
    case '.txt':
      return ContentType.text;
    default:
      return ContentType.binary;
  }
}

Future<void> _json(HttpRequest request, Map<String, Object?> body,
    {int status = HttpStatus.ok}) async {
  final response = request.response;
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}
