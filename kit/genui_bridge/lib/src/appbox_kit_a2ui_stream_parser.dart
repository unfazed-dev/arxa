import 'dart:async';
import 'dart:convert';

import 'appbox_kit_a2ui_message.dart';

/// One event from an [AppBoxKitA2uiStreamParser]: a parsed message, a chunk of prose,
/// or a malformed attempted message.
sealed class AppBoxKitA2uiStreamEvent {
  const AppBoxKitA2uiStreamEvent();
}

/// A complete, structurally valid [AppBoxKitA2uiMessage] parsed from the stream.
final class AppBoxKitA2uiMessageEvent extends AppBoxKitA2uiStreamEvent {
  const AppBoxKitA2uiMessageEvent(this.message);

  /// The parsed message (already structurally valid; catalog validation is
  /// the bridge's job, not the parser's).
  final AppBoxKitA2uiMessage message;
}

/// Non-message text the model emitted alongside (or instead of) A2UI.
final class AppBoxKitA2uiTextEvent extends AppBoxKitA2uiStreamEvent {
  const AppBoxKitA2uiTextEvent(this.text);

  /// The prose chunk, with `<a2ui_message>` protocol tags stripped.
  final String text;
}

/// A payload that looked like an A2UI message but failed to parse.
///
/// Emitted (never thrown) so a consumer can feed [raw] + [error] into a
/// repair loop without try/catch plumbing around the stream.
final class AppBoxKitA2uiErrorEvent extends AppBoxKitA2uiStreamEvent {
  const AppBoxKitA2uiErrorEvent(this.error, this.raw);

  /// What went wrong (typically an [AppBoxKitA2uiFormatException] or
  /// [FormatException] from `jsonDecode`).
  final Object error;

  /// The raw payload text that failed.
  final String raw;
}

/// Incrementally parses a stream of LLM text chunks into [AppBoxKitA2uiStreamEvent]s.
///
/// Mirrors the extraction semantics of genui's `A2uiParserTransformer`
/// (https://github.com/flutter/genui/blob/main/packages/genui/lib/src/transport/a2ui_parser_transformer.dart):
///
/// - ```` ```json ```` fenced blocks are extracted first;
/// - otherwise a balanced `{...}` object is matched (string- and
///   escape-aware), so messages split across any chunk boundary assemble;
/// - whitespace between two messages (the JSONL separator) is dropped;
/// - anything else is prose and surfaces as [AppBoxKitA2uiTextEvent].
///
/// Deliberate divergences, because this parser feeds a repair loop rather
/// than a renderer (genui falls back to plain text in both cases):
///
/// - a fenced JSON block that fails `jsonDecode` is an [AppBoxKitA2uiErrorEvent];
/// - a trailing partial `{...` when the input closes is an [AppBoxKitA2uiErrorEvent]
///   (truncated message) instead of text.
class AppBoxKitA2uiStreamParser extends StreamTransformerBase<String, AppBoxKitA2uiStreamEvent> {
  const AppBoxKitA2uiStreamParser();

  @override
  Stream<AppBoxKitA2uiStreamEvent> bind(Stream<String> stream) =>
      _A2uiParserStream(stream).stream;
}

class _A2uiParserStream {
  _A2uiParserStream(Stream<String> input) {
    _controller = StreamController<AppBoxKitA2uiStreamEvent>(
      onListen: () {
        _subscription = input.listen(
          _onData,
          onError: _controller.addError,
          onDone: _onDone,
          cancelOnError: false,
        );
      },
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: () => _subscription?.cancel(),
    );
  }

  late final StreamController<AppBoxKitA2uiStreamEvent> _controller;
  StreamSubscription<String>? _subscription;
  String _buffer = '';

  /// Whitespace right after a message is a JSONL separator, not prose.
  bool _wasLastEventA2ui = false;

  Stream<AppBoxKitA2uiStreamEvent> get stream => _controller.stream;

  void _onData(String chunk) {
    _buffer += chunk;
    _processBuffer();
  }

  void _onDone() {
    final rest = _buffer;
    _buffer = '';
    if (rest.isEmpty || rest.trim().isEmpty) {
      // Nothing left, or a held JSONL separator.
      _controller.close();
      return;
    }
    if (rest.contains('{')) {
      // Stream ended mid-message: truncated A2UI, repairable.
      _controller.add(AppBoxKitA2uiErrorEvent(
        const FormatException('stream ended with an incomplete JSON message'),
        rest,
      ));
    } else {
      _emitText(rest);
    }
    _controller.close();
  }

  void _processBuffer() {
    while (_buffer.isNotEmpty) {
      // 1. A fenced ```json block, if one is complete in the buffer.
      final markdownMatch = _findMarkdownJson(_buffer);
      if (markdownMatch != null) {
        _emitBefore(markdownMatch.start);
        _emitPayload(markdownMatch.content);
        _buffer = _buffer.substring(markdownMatch.end);
        continue;
      }

      // 2. A balanced JSON object at the buffer start.
      final jsonMatch = _findBalancedJson(_buffer);
      if (jsonMatch != null) {
        _emitPayload(jsonMatch.content);
        _buffer = _buffer.substring(jsonMatch.end);
        continue;
      }

      // 3. No complete payload: emit prose, or wait for more data.
      final markdownStart = _buffer.indexOf('```');
      final braceStart = _buffer.indexOf('{');
      var firstPotentialStart = -1;
      if (markdownStart != -1 && braceStart != -1) {
        firstPotentialStart =
            markdownStart < braceStart ? markdownStart : braceStart;
      } else if (markdownStart != -1) {
        firstPotentialStart = markdownStart;
      } else if (braceStart != -1) {
        firstPotentialStart = braceStart;
      }

      if (firstPotentialStart == -1) {
        if (_wasLastEventA2ui && _buffer.trim().isEmpty) {
          // Possible JSONL separator; hold until more data or onDone.
          break;
        }
        _emitText(_buffer);
        _buffer = '';
        break;
      }
      if (firstPotentialStart > 0) {
        final prefix = _buffer.substring(0, firstPotentialStart);
        if (_wasLastEventA2ui && prefix.trim().isEmpty) {
          _buffer = _buffer.substring(firstPotentialStart);
          continue; // JSONL separator.
        }
        _emitText(prefix);
        _buffer = _buffer.substring(firstPotentialStart);
        continue; // Buffer now starts at a potential payload: try to extract
        // it immediately rather than waiting for the next chunk.
      }
      // Buffer starts with an incomplete payload; wait for more data.
      break;
    }
  }

  void _emitBefore(int index) {
    if (index > 0) _emitText(_buffer.substring(0, index));
  }

  void _emitText(String text) {
    _wasLastEventA2ui = false;
    final clean =
        text.replaceAll('<a2ui_message>', '').replaceAll('</a2ui_message>', '');
    if (clean.isNotEmpty) _controller.add(AppBoxKitA2uiTextEvent(clean));
  }

  void _emitPayload(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (e) {
      // Fenced-but-invalid JSON, or a balanced-but-invalid object: an
      // attempted A2UI message either way — surface for repair.
      _controller.add(AppBoxKitA2uiErrorEvent(e, content));
      _wasLastEventA2ui = false;
      return;
    }
    if (decoded is Map<String, dynamic>) {
      _emitOne(decoded, content);
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) _emitOne(item, content);
      }
    }
    // JSON scalars are ignored: they cannot carry an A2UI message.
  }

  /// Top-level keys that mark a JSON object as an attempted A2UI message.
  /// Includes `version` (a malformed-but-versioned payload still counts) and
  /// the v0.8 verb aliases the message model accepts.
  static const _a2uiMessageKeys = {
    'version',
    'createSurface',
    'updateComponents',
    'surfaceUpdate',
    'updateDataModel',
    'dataModelUpdate',
    'deleteSurface',
  };

  void _emitOne(Map<String, dynamic> json, String raw) {
    try {
      _controller.add(AppBoxKitA2uiMessageEvent(AppBoxKitA2uiMessage.fromJson(json)));
      _wasLastEventA2ui = true;
    } on AppBoxKitA2uiFormatException catch (e) {
      if (json.keys.any(_a2uiMessageKeys.contains)) {
        _controller.add(AppBoxKitA2uiErrorEvent(e, raw));
      } else {
        // Some other JSON object the model happened to emit; not A2UI.
        _controller.add(AppBoxKitA2uiTextEvent(jsonEncode(json)));
      }
      _wasLastEventA2ui = false;
    }
  }

  static final _markdownJson = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');

  static _Match? _findMarkdownJson(String text) {
    final match = _markdownJson.firstMatch(text);
    if (match == null) return null;
    return _Match(match.start, match.end, match.group(1) ?? '');
  }

  static _Match? _findBalancedJson(String input) {
    if (!input.startsWith('{')) return null;
    var balance = 0;
    var inString = false;
    var isEscaped = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (isEscaped) {
        isEscaped = false;
        continue;
      }
      if (char == '\\') {
        isEscaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (char == '{') balance++;
        if (char == '}') {
          balance--;
          if (balance == 0) return _Match(0, i + 1, input.substring(0, i + 1));
        }
      }
    }
    return null;
  }
}

class _Match {
  _Match(this.start, this.end, this.content);

  final int start;
  final int end;

  /// The payload text to decode (fence contents, or the balanced object);
  /// also what an [AppBoxKitA2uiErrorEvent] reports as its raw payload.
  final String content;
}
