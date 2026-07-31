import 'dart:convert';

import '../chat_stream.dart';
import '../json_schema.dart';
import '../sse_transport.dart';

/// [ChatStream] over the Anthropic messages API.
///
/// Wire shape (verified against https://docs.anthropic.com/en/api/messages-streaming,
/// 2026-07-28): `POST {baseUrl}/v1/messages` with
/// `{model, max_tokens, system?, messages, stream: true}` and headers
/// `x-api-key` + `anthropic-version`. The SSE stream runs
/// `message_start → content_block_* → message_delta → message_stop`; text
/// arrives in `content_block_delta` events as
/// `{"delta": {"type": "text_delta", "text": "..."}}`.
class AnthropicChatStream implements ChatStream {
  /// Auth is injected per request via the `x-api-key` header; nothing is
  /// persisted by this package.
  AnthropicChatStream({
    required this.model,
    required this.apiKey,
    Uri? baseUrl,
    SseTransport? transport,
    this.maxTokens = 8192,
    this.anthropicVersion = '2023-06-01',
    this.extraHeaders = const {},
  })  : baseUrl = baseUrl ?? _defaultBaseUrl,
        _transport = transport ?? httpPostStream;

  static final _defaultBaseUrl = Uri.parse('https://api.anthropic.com');

  /// The provider's model identifier (e.g. `claude-sonnet-4-5`).
  final String model;

  /// Sent as the `x-api-key` header on every request.
  final String apiKey;

  /// Scheme/host[/base-path] of an Anthropic-compatible server.
  final Uri baseUrl;

  /// `max_tokens` request parameter — required by this API.
  final int maxTokens;

  /// `anthropic-version` header value.
  final String anthropicVersion;

  /// Extra headers merged into every request (after auth, so they win).
  final Map<String, String> extraHeaders;

  final SseTransport _transport;

  @override
  Stream<String> complete(List<ChatMessage> messages,
      {JsonSchema? schema}) async* {
    // Anthropic takes the system prompt as a top-level parameter, not a
    // message; system turns are concatenated in order.
    final system = [
      for (final m in messages)
        if (m.role == ChatRole.system) m.content,
    ].join('\n\n');
    final body = <String, Object?>{
      'model': model,
      'max_tokens': maxTokens,
      'stream': true,
      if (system.isNotEmpty) 'system': system,
      'messages': [
        for (final m in messages)
          if (m.role != ChatRole.system)
            {'role': m.role.name, 'content': m.content},
      ],
    };
    // Note: `schema` is accepted by the interface but intentionally unused —
    // this API has no response-schema mode that preserves plain text
    // streaming (tool-forcing would change the response shape). Validation +
    // repair in the bridge is the reliability mechanism.
    final headers = <String, String>{
      'x-api-key': apiKey,
      'anthropic-version': anthropicVersion,
      ...extraHeaders,
    };
    final uri = _resolve(baseUrl, '/v1/messages');

    await for (final payload
        in splitSseEvents(_transport(uri, headers, body))) {
      final Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;
      // Unknown event types are ignored, per the API's versioning policy.
      switch (decoded['type']) {
        case 'content_block_delta':
          final delta = decoded['delta'];
          if (delta is Map<String, dynamic> &&
              delta['type'] == 'text_delta' &&
              delta['text'] is String) {
            yield delta['text'] as String;
          }
        case 'error':
          final error = decoded['error'];
          throw ChatStreamException(
            'provider error: '
            '${error is Map<String, dynamic> ? error['message'] : payload}',
            body: payload,
          );
        case 'message_stop':
          return;
      }
    }
  }

  static Uri _resolve(Uri base, String path) {
    final baseText = base.toString();
    final trimmed = baseText.endsWith('/')
        ? baseText.substring(0, baseText.length - 1)
        : baseText;
    return Uri.parse('$trimmed$path');
  }
}
