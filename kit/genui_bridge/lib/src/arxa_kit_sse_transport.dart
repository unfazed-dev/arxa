import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'arxa_kit_chat_stream.dart';

/// The HTTP seam every streaming adapter talks through.
///
/// Posts [body] as JSON to [uri] with [headers] and yields the raw response
/// body as UTF-8 text chunks. Adapters own SSE framing and payload extraction
/// on top of this; tests inject a fake to assert the request shape and script
/// the response — no network, no mocking of `dart:io` types.
typedef ArxaKitSseTransport = Stream<String> Function(
  Uri uri,
  Map<String, String> headers,
  Map<String, Object?> body,
);

/// Default [ArxaKitSseTransport]: `dart:io` [HttpClient], nothing else.
///
/// Throws [ArxaKitChatStreamException] on non-200 responses (with the body captured
/// for diagnostics). The client is closed when the response stream ends.
Stream<String> arxaKitHttpPostStream(
  Uri uri,
  Map<String, String> headers,
  Map<String, Object?> body,
) async* {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    headers.forEach(request.headers.set);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      final errorBody = await utf8.decoder.bind(response).join();
      throw ArxaKitChatStreamException(
        'HTTP ${response.statusCode} from $uri',
        statusCode: response.statusCode,
        body: errorBody,
      );
    }
    yield* utf8.decoder.bind(response);
  } finally {
    client.close();
  }
}

/// Splits a raw SSE byte stream into event payloads.
///
/// Yields one string per complete SSE event: its `data:` lines joined with
/// `\n` per the SSE spec. `event:`/comment lines are dropped — both supported
/// providers embed the event type inside the JSON payload itself.
Stream<String> arxaKitSplitSseEvents(Stream<String> chunks) {
  return Stream<String>.eventTransformed(chunks, (sink) => _SseEventSink(sink));
}

class _SseEventSink implements EventSink<String> {
  _SseEventSink(this._out);

  final EventSink<String> _out;
  String _pending = '';
  List<String> _dataLines = [];

  void _addLine(String line) {
    if (line.isEmpty) {
      // Blank line: event boundary.
      if (_dataLines.isNotEmpty) {
        _out.add(_dataLines.join('\n'));
        _dataLines = [];
      }
      return;
    }
    if (line.startsWith('data:')) {
      var value = line.substring(5);
      if (value.startsWith(' ')) value = value.substring(1);
      _dataLines.add(value);
    }
    // `event:`, `id:`, `retry:` and comments are intentionally ignored.
  }

  @override
  void add(String chunk) {
    _pending += chunk;
    var start = 0;
    for (var i = 0; i < _pending.length; i++) {
      if (_pending[i] == '\n') {
        var line = _pending.substring(start, i);
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
        _addLine(line);
        start = i + 1;
      }
    }
    _pending = _pending.substring(start);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _out.addError(error, stackTrace);

  @override
  void close() {
    if (_pending.isNotEmpty) _addLine(_pending);
    if (_dataLines.isNotEmpty) _out.add(_dataLines.join('\n'));
    _out.close();
  }
}
