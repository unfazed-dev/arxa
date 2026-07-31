/// Flutter VM service client (ports probe-runner _flutter/flutter_vm/
/// flutter_attach/flutter_shot/flutter_tree/flutter_eval/
/// flutter_semantics/flutter_diag). Raw dart:io WebSocket JSON-RPC —
/// same protocol shape as CDP, no vm_service dependency.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LensVmException implements Exception {
  LensVmException(this.message);
  final String message;
  @override
  String toString() => 'LensVmException: $message';
}

/// Extract a VM service URI from tool output. Handles the interactive
/// form ('The Dart VM service is listening on http://…/') and the
/// --machine JSON event form.
String? parseVmServiceUri(String text) {
  final plain = RegExp(r'https?://\S+?/\S*/').firstMatch(text);
  if (plain != null && text.contains('VM service')) return plain.group(0);
  for (final line in const LineSplitter().convert(text)) {
    if (!line.startsWith('{')) continue;
    try {
      final ev = jsonDecode(line) as Map;
      if (ev['event'] == 'app.debugPort') {
        return (ev['params'] as Map)['wsUri'] as String?;
      }
    } catch (_) {/* not a json line */}
  }
  return null;
}

class FlutterVm {
  FlutterVm._(this._ws);
  final WebSocket _ws;
  var _id = 0;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _sub;

  /// VM service stream events (Extension, Debug, Isolate, …).
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Connect to a VM service URI in http(s) or ws(s) form. DDS proxy
  /// URIs (flutter run default) work unchanged. Begins listening
  /// immediately; [start] is a safe no-op afterwards.
  static Future<FlutterVm> connect(String uri) async {
    var ws = uri;
    if (ws.startsWith('http://')) ws = 'ws://${ws.substring(7)}';
    if (ws.startsWith('https://')) ws = 'wss://${ws.substring(8)}';
    if (!ws.endsWith('/ws')) {
      ws = '${ws.endsWith('/') ? ws : '$ws/'}ws';
    }
    final socket = await WebSocket.connect(ws);
    final vm = FlutterVm._(socket);
    vm._listen();
    return vm;
  }

  void _listen() {
    if (_sub != null) return;
    _sub = _ws.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final id = msg['id'];
      if (id != null && _pending.containsKey(id)) {
        _pending.remove(id)!.complete(msg);
      } else {
        _events.add(msg);
      }
    });
  }

  /// Start listening (idempotent; connect() already does this).
  void start() => _listen();

  /// Generic JSON-RPC call. Throws LensVmException on a protocol error.
  Future<Map<String, dynamic>> rpc(String method,
      [Map<String, dynamic>? params]) {
    final id = ++_id;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ws.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    }));
    return c.future.timeout(const Duration(seconds: 30), onTimeout: () {
      _pending.remove(id);
      throw LensVmException('VM service timeout on $method');
    }).then((msg) {
      final err = msg['error'];
      if (err != null) {
        throw LensVmException('$method: ${(err as Map)['message']}');
      }
      return (msg['result'] as Map?)?.cast<String, dynamic>() ?? {};
    });
  }

  Future<String> mainIsolateId() async {
    final vm = await rpc('getVM');
    final isolates = vm['isolates'] as List?;
    if (isolates == null || isolates.isEmpty) {
      throw LensVmException('no isolates — is a Flutter app attached?');
    }
    return (isolates.first as Map)['id'] as String;
  }

  /// Call a service extension (ext.flutter.*) against an isolate.
  Future<Map<String, dynamic>> callServiceExtension(String method,
      {String? isolateId, Map<String, dynamic>? args}) async {
    return rpc(method, {
      'isolateId': isolateId ?? await mainIsolateId(),
      'args': ?args,
    });
  }

  /// ext.flutter.screenshot (debug/profile builds only) -> PNG bytes.
  Future<List<int>> screenshot() async {
    final r = await callServiceExtension('ext.flutter.screenshot');
    final b64 = r['screenshot'] as String?;
    if (b64 == null) {
      throw LensVmException('ext.flutter.screenshot unavailable — '
          'release build or pre-2.x Flutter? (extension exists in '
          'debug/profile only)');
    }
    return base64Decode(b64);
  }

  Future<String> dumpRenderTree() async =>
      (await callServiceExtension('ext.flutter.debugDumpRenderTree'))['value'] as String;
  Future<String> dumpWidgetTree() async =>
      (await callServiceExtension('ext.flutter.debugDumpApp'))['value'] as String;
  Future<String> dumpSemanticsTree() async =>
      (await callServiceExtension('ext.flutter.debugDumpSemanticsTreeInTraversalOrder'))['value'] as String;

  /// Toggle a boolean debug extension (debugPaint, repaintRainbow,
  /// performanceOverlay, …).
  Future<void> setFlag(String ext, bool enabled) =>
      callServiceExtension(ext, args: {'enabled': '$enabled'});

  /// Evaluate a Dart expression in the isolate's root library
  /// (probe-runner's VMLib path).
  Future<dynamic> evalDart(String expression) async {
    final isolate = await mainIsolateId();
    final iso = await rpc('getIsolate', {'isolateId': isolate});
    final rootLib = ((iso['rootLib'] ?? iso['libraries']?[0]) as Map)['id'];
    final r = await rpc('evaluate', {
      'isolateId': isolate,
      'targetId': rootLib,
      'expression': expression,
    });
    return r['valueAsString'] ?? r;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _events.close();
    await _ws.close();
  }
}
