import 'dart:convert';

import '../arxa_kit_chat_stream.dart';
import '../arxa_kit_json_schema.dart';
import '../arxa_kit_sse_transport.dart';

/// Per-provider wire policy for [ArxaKitOpenAIChatStream]: which `response_format`
/// a schema hint maps to.
enum ArxaKitOpenAIParamPolicy {
  /// OpenAI and the local servers: `{"type": "json_schema", "json_schema": …}`.
  fullJsonSchema,

  /// Providers documenting `json_object` only (Kimi / api.moonshot.ai):
  /// `{"type": "json_object"}` plus the schema spelled out in a system
  /// message — their documented idiom.
  jsonObjectOnly,
}

/// [ArxaKitChatStream] over the OpenAI chat-completions API — also covers Ollama,
/// llama.cpp, vLLM and any other OpenAI-compatible server via [baseUrl].
///
/// Wire shape (verified against https://platform.openai.com/docs/api-reference/chat/create,
/// 2026-07-28): `POST {baseUrl}/v1/chat/completions` with
/// `{model, messages, stream: true}`; the SSE stream emits
/// `data: {"choices":[{"delta":{"content":"..."}}]}` chunks and terminates
/// with `data: [DONE]`.
class ArxaKitOpenAIChatStream implements ArxaKitChatStream {
  /// [apiKey] may be null for local servers that ignore auth; [baseUrl]
  /// defaults to OpenAI — point it at `http://localhost:11434` for Ollama or
  /// `http://localhost:8080` for llama.cpp. Auth is injected per request;
  /// nothing is persisted by this package.
  ///
  /// [paramPolicy] selects how a [ArxaKitChatStream.complete] schema hint is sent:
  /// the default works for OpenAI and the local servers; use
  /// [ArxaKitOpenAIParamPolicy.jsonObjectOnly] for providers like Kimi
  /// (api.moonshot.ai) that reject `json_schema` and document
  /// `{"type": "json_object"}` plus the schema in a system message instead.
  ArxaKitOpenAIChatStream({
    required this.model,
    this.apiKey,
    Uri? baseUrl,
    ArxaKitSseTransport? transport,
    this.extraHeaders = const {},
    this.paramPolicy = ArxaKitOpenAIParamPolicy.fullJsonSchema,
  })  : baseUrl = baseUrl ?? _defaultBaseUrl,
        _transport = transport ?? arxaKitHttpPostStream;

  static final _defaultBaseUrl = Uri.parse('https://api.openai.com');

  /// The provider's model identifier (e.g. `gpt-4o-mini`, `qwen3:8b`).
  final String model;

  /// Bearer token; omitted from headers when null (local servers).
  final String? apiKey;

  /// Scheme/host[/base-path] of an OpenAI-compatible server.
  final Uri baseUrl;

  /// Extra headers merged into every request (after auth, so they win).
  final Map<String, String> extraHeaders;

  /// How a schema hint is put on the wire; see the constructor docs.
  final ArxaKitOpenAIParamPolicy paramPolicy;

  final ArxaKitSseTransport _transport;

  @override
  Stream<String> complete(List<ArxaKitChatMessage> messages,
      {ArxaKitJsonSchema? schema}) async* {
    final schemaInPrompt =
        schema != null && paramPolicy == ArxaKitOpenAIParamPolicy.jsonObjectOnly;
    final body = <String, Object?>{
      'model': model,
      'stream': true,
      'messages': [
        for (final m in messages) {'role': m.role.name, 'content': m.content},
        // jsonObjectOnly providers (Kimi) learn the shape from the prompt —
        // their documented idiom — since the wire param carries no schema.
        if (schemaInPrompt)
          {
            'role': 'system',
            'content':
                'Respond with a single JSON object matching this JSON schema: '
                    '${jsonEncode(schema)}',
          },
      ],
      // Optional acceleration only: when the caller supplies a schema, ask
      // the provider for schema-guided JSON. The bridge validates output
      // regardless, so providers that ignore or reject this are fine.
      if (schema != null)
        'response_format': switch (paramPolicy) {
          ArxaKitOpenAIParamPolicy.fullJsonSchema => {
              'type': 'json_schema',
              'json_schema': {'name': 'a2ui_message', 'schema': schema},
            },
          ArxaKitOpenAIParamPolicy.jsonObjectOnly => {'type': 'json_object'},
        },
    };
    final headers = <String, String>{
      if (apiKey != null) 'authorization': 'Bearer $apiKey',
      ...extraHeaders,
    };
    final uri = _resolve(baseUrl, '/v1/chat/completions');

    await for (final payload
        in arxaKitSplitSseEvents(_transport(uri, headers, body))) {
      if (payload == '[DONE]') return;
      final Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        continue; // Heartbeats / non-JSON events: skip.
      }
      if (decoded is! Map<String, dynamic>) continue;
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        throw ArxaKitChatStreamException(
          'provider error: ${error['message'] ?? payload}',
          body: payload,
        );
      }
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final delta = first['delta'];
          if (delta is Map<String, dynamic>) {
            final content = delta['content'];
            if (content is String) yield content;
          }
        }
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
