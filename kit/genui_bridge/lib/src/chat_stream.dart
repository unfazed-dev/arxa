import 'json_schema.dart';

/// The role of a [ChatMessage] in a conversation.
enum ChatRole { system, user, assistant }

/// One conversation turn handed to a [ChatStream].
class ChatMessage {
  const ChatMessage(this.role, this.content);

  const ChatMessage.system(String content) : this(ChatRole.system, content);
  const ChatMessage.user(String content) : this(ChatRole.user, content);
  const ChatMessage.assistant(String content)
      : this(ChatRole.assistant, content);

  final ChatRole role;
  final String content;

  @override
  String toString() => 'ChatMessage(${role.name}, ${content.length} chars)';
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
abstract class ChatStream {
  /// Streams the completion for [messages] as raw text chunks.
  ///
  /// Errors (HTTP failures, provider error events) are delivered on the
  /// returned stream's error channel as [ChatStreamException] where possible.
  Stream<String> complete(List<ChatMessage> messages, {JsonSchema? schema});
}

/// A provider call failed: non-200 HTTP status, a provider error event, or a
/// transport-level failure.
class ChatStreamException implements Exception {
  const ChatStreamException(this.message, {this.statusCode, this.body});

  final String message;

  /// HTTP status code, when the failure came from an HTTP response.
  final int? statusCode;

  /// Response body (or provider error payload), when available.
  final String? body;

  @override
  String toString() => 'ChatStreamException($statusCode): $message'
      '${body == null ? '' : ' — $body'}';
}
