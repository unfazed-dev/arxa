import 'appbox_kit_json_schema.dart';

/// The role of a [AppBoxKitChatMessage] in a conversation.
enum AppBoxKitChatRole { system, user, assistant }

/// One conversation turn handed to a [AppBoxKitChatStream].
class AppBoxKitChatMessage {
  const AppBoxKitChatMessage(this.role, this.content);

  const AppBoxKitChatMessage.system(String content) : this(AppBoxKitChatRole.system, content);
  const AppBoxKitChatMessage.user(String content) : this(AppBoxKitChatRole.user, content);
  const AppBoxKitChatMessage.assistant(String content)
      : this(AppBoxKitChatRole.assistant, content);

  final AppBoxKitChatRole role;
  final String content;

  @override
  String toString() => 'AppBoxKitChatMessage(${role.name}, ${content.length} chars)';
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
abstract class AppBoxKitChatStream {
  /// Streams the completion for [messages] as raw text chunks.
  ///
  /// Errors (HTTP failures, provider error events) are delivered on the
  /// returned stream's error channel as [AppBoxKitChatStreamException] where possible.
  Stream<String> complete(List<AppBoxKitChatMessage> messages, {AppBoxKitJsonSchema? schema});
}

/// A provider call failed: non-200 HTTP status, a provider error event, or a
/// transport-level failure.
class AppBoxKitChatStreamException implements Exception {
  const AppBoxKitChatStreamException(this.message, {this.statusCode, this.body});

  final String message;

  /// HTTP status code, when the failure came from an HTTP response.
  final int? statusCode;

  /// Response body (or provider error payload), when available.
  final String? body;

  @override
  String toString() => 'AppBoxKitChatStreamException($statusCode): $message'
      '${body == null ? '' : ' — $body'}';
}
