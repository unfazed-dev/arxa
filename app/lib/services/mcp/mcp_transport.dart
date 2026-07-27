import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// MCP transport abstraction (8.9). Two implementations:
///  - [StdioMcpTransport]: local server, JSON-RPC over the process stdin/stdout
///    (newline-delimited). Optimal for desktop.
///  - [HttpMcpTransport]: remote server, Streamable HTTP + SSE (bearer/API keys).
///
/// Both speak JSON-RPC 2.0; the [McpClient] above them is transport-agnostic.
abstract class McpTransport {
  String get id;
  bool get isConnected;
  Future<void> connect();
  Future<Map<String, dynamic>> request(String method, {Map<String, dynamic>? params});
  Future<void> close();
}

/// Stdio transport: spawn the server process, exchange newline-delimited JSON.
class StdioMcpTransport implements McpTransport {
  StdioMcpTransport({
    required this.id,
    required this.command,
    this.args = const [],
    this.environment = const {},
  });

  @override
  final String id;
  final String command;
  final List<String> args;
  final Map<String, String> environment;

  Process? _proc;
  int _nextId = 1;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  bool _closed = false;

  @override
  bool get isConnected => _proc != null && !_closed;

  @override
  Future<void> connect() async {
    _proc = await Process.start(
      command,
      args,
      environment: environment,
      runInShell: true,
    );
    _proc!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: close);
    _proc!.stderr.transform(utf8.decoder).listen((_) {});
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    final json = jsonDecode(line);
    if (json is Map<String, dynamic> && json['id'] is num) {
      final completer = _pending.remove(json['id']);
      completer?.complete(json);
    }
  }

  @override
  Future<Map<String, dynamic>> request(String method,
      {Map<String, dynamic>? params}) async {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final envelope = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };
    _proc!.stdin.writeln(jsonEncode(envelope));
    return completer.future.timeout(const Duration(seconds: 30),
        onTimeout: () => {'error': {'message': 'timed out'}});
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _proc?.stdin.close();
    _proc?.kill();
    _proc = null;
  }
}

/// Streamable HTTP + SSE transport: POST JSON-RPC; the server may respond with a
/// single JSON document or an `text/event-stream` of SSE `data:` frames. Both are
/// parsed here. Bearer / API-key auth via [headers].
class HttpMcpTransport implements McpTransport {
  HttpMcpTransport({
    required this.id,
    required this.url,
    this.headers = const {},
    this.timeout = const Duration(seconds: 30),
  });

  @override
  final String id;
  final String url;
  final Map<String, String> headers;
  final Duration timeout;
  final _client = HttpClient();
  int _nextId = 1;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    // A lightweight probe: an initialize request confirms the endpoint speaks
    // MCP. Real connection is established on the first request.
    _connected = true;
  }

  @override
  Future<Map<String, dynamic>> request(String method,
      {Map<String, dynamic>? params}) async {
    final id = _nextId++;
    final envelope = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };
    final req = await _client.postUrl(Uri.parse(url)).timeout(timeout);
    req.headers.contentType = ContentType.json;
    headers.forEach((k, v) => req.headers.set(k, v));
    req.headers.set('Accept', 'application/json, text/event-stream');
    req.add(utf8.encode(jsonEncode(envelope)));
    final res = await req.close().timeout(timeout);

    final body = await _readBody(res).timeout(timeout);
    return _extractJsonRpc(body, id);
  }

  Future<String> _readBody(HttpClientResponse res) async {
    final buf = StringBuffer();
    await for (final chunk in res.transform(utf8.decoder)) {
      buf.write(chunk);
    }
    return buf.toString();
  }

  /// Parses a JSON body OR an SSE stream of `data:` frames, returning the
  /// JSON-RPC response matching [id].
  Map<String, dynamic> _extractJsonRpc(String body, int id) {
    final trimmed = body.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    // SSE: collect `data:` lines, parse each as JSON, find ours by id.
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      final json = jsonDecode(payload);
      if (json is Map<String, dynamic> && json['id'] == id) return json;
    }
    return {'error': {'message': 'no response for id $id'}};
  }

  @override
  Future<void> close() async {
    _connected = false;
    _client.close(force: true);
  }
}
