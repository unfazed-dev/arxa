/// genui_bridge — the provider- and model-agnostic reliability core for
/// making any LLM emit valid A2UI v0.9 JSON messages for Flutter's `genui`
/// package (0.10.1).
///
/// One abstraction — [ChatStream], `Stream<String> complete(messages, {schema})`
/// — with thin OpenAI-compatible and Anthropic adapters behind an
/// injectable HTTP seam. Reliability comes from the loop, not from any
/// provider's structured-output mode: catalog schemas in the system prompt →
/// incremental streamed parse → validate every message → bounded repair
/// (re-ask with the error, n ≤ 2) → only valid messages leave the bridge.
///
/// Pure Dart: no Flutter imports, no plugin dependencies — a dart:io daemon
/// can import it. See `testing.dart` for the scriptable [FakeChatStream].
library;

export 'src/a2ui_message.dart';
export 'src/a2ui_stream_parser.dart';
export 'src/adapters/anthropic_chat_stream.dart';
export 'src/adapters/openai_chat_stream.dart';
export 'src/chat_stream.dart';
export 'src/genui_bridge.dart';
export 'src/json_schema.dart';
export 'src/sse_transport.dart'
    show SseTransport, httpPostStream, splitSseEvents;
