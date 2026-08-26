/// Test doubles for arxa_kit_genui_bridge.
///
/// Import in tests: `import 'package:arxa_kit_genui_bridge/arxa_kit_testing.dart';`
library;

import 'arxa_kit_genui_bridge.dart';

/// A [ArxaKitChatStream] whose responses are fully scripted, with every call
/// recorded for assertion.
///
/// Each scripted entry is consumed by one [complete] call, in order:
/// - [scriptText]: the response as a single chunk;
/// - [scriptChunks]: the response as streamed chunks (to exercise
///   split-across-chunk parsing);
/// - [scriptError]: the call fails with this error on the stream.
///
/// A call with no scripted entry left throws [StateError] — an unscripted
/// call is a test bug.
class FakeArxaKitChatStream implements ArxaKitChatStream {
  final List<_Scripted> _script = [];

  /// Every `messages` list received, in call order (including the system
  /// prompt a bridge prepended).
  final List<List<ArxaKitChatMessage>> calls = [];

  /// Every `schema` argument received, in call order.
  final List<ArxaKitJsonSchema?> schemas = [];

  /// Scripts a single-chunk response.
  void scriptText(String text) => _script.add(_Scripted.chunks([text]));

  /// Scripts a response delivered as multiple stream chunks.
  void scriptChunks(List<String> chunks) =>
      _script.add(_Scripted.chunks(chunks));

  /// Scripts a call whose stream fails with [error].
  void scriptError(Object error) => _script.add(_Scripted.error(error));

  /// The last message of the most recent call — where a bridge appends its
  /// repair instruction.
  ArxaKitChatMessage get lastMessage => calls.last.last;

  @override
  Stream<String> complete(List<ArxaKitChatMessage> messages, {ArxaKitJsonSchema? schema}) {
    calls.add(List.unmodifiable(messages));
    schemas.add(schema);
    if (_script.isEmpty) {
      throw StateError('FakeArxaKitChatStream: unscripted call #${calls.length}');
    }
    final next = _script.removeAt(0);
    return switch (next) {
      _Chunks(:final chunks) => Stream.fromIterable(chunks),
      _Error(:final error) => Stream.error(error),
    };
  }
}

sealed class _Scripted {
  const _Scripted();
  const factory _Scripted.chunks(List<String> chunks) = _Chunks;
  const factory _Scripted.error(Object error) = _Error;
}

final class _Chunks extends _Scripted {
  const _Chunks(this.chunks);
  final List<String> chunks;
}

final class _Error extends _Scripted {
  const _Error(this.error);
  final Object error;
}
