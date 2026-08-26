import 'arxa_kit_json_schema.dart';

/// The role of a [ArxaKitChatMessage] in a conversation.
enum ArxaKitChatRole { system, user, assistant }

/// One conversation turn handed to a [ArxaKitChatStream].
class ArxaKitChatMessage {
  const ArxaKitChatMessage(this.role, this.content);

  const ArxaKitChatMessage.system(String content) : this(ArxaKitChatRole.system, content);
  const ArxaKitChatMessage.user(String content) : this(ArxaKitChatRole.user, content);
  const ArxaKitChatMessage.assistant(String content)
      : this(ArxaKitChatRole.assistant, content);

  final ArxaKitChatRole role;
  final String content;

  @override
  String toString() => 'ArxaKitChatMessage(${role.name}, ${content.length} chars)';
}

/// The one abstraction every LLM provider lives behind.
///
/// Implementations stream the assistant's reply as raw text chunks for a
/// conversation. Reliability never depends on a provider's structured-output
/// mode: [schema] is only an *optional acceleration hint* an adapter may map
/// to a provider-native mode (e.g. OpenAI `response_format`) — callers must
/// treat its use as best-effort and validate the output regardless.
///
/// Nothing in this interface names a provider or a model.
abstract class ArxaKitChatStream {
  /// Streams the completion for [messages] as raw text chunks.
  ///
  /// Errors (HTTP failures, provider error events) are delivered on the
  /// returned stream's error channel as [ArxaKitChatStreamException] where possible.
  Stream<String> complete(List<ArxaKitChatMessage> messages, {ArxaKitJsonSchema? schema});
}

/// A provider call failed: non-200 HTTP status, a provider error event, or a
/// transport-level failure.
class ArxaKitChatStreamException implements Exception {
  const ArxaKitChatStreamException(this.message, {this.statusCode, this.body});

  final String message;

  /// HTTP status code, when the failure came from an HTTP response.
  final int? statusCode;

  /// Response body (or provider error payload), when available.
  final String? body;

  @override
  String toString() => 'ArxaKitChatStreamException($statusCode): $message'
      '${body == null ? '' : ' — $body'}';
}
