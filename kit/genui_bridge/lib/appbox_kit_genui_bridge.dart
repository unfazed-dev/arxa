/// appbox_kit_genui_bridge — the provider- and model-agnostic reliability core for
/// making any LLM emit valid A2UI v0.9 JSON messages for Flutter's `genui`
/// package (0.10.1).
///
/// One abstraction — [AppBoxKitChatStream], `Stream<String> complete(messages, {schema})`
/// — with thin OpenAI-compatible and Anthropic adapters behind an
/// injectable HTTP seam. Reliability comes from the loop, not from any
/// provider's structured-output mode: catalog schemas in the system prompt →
/// incremental streamed parse → validate every message → bounded repair
/// (re-ask with the error, n ≤ 2) → only valid messages leave the bridge.
///
/// Pure Dart: no Flutter imports, no plugin dependencies — a dart:io daemon
/// can import it. See `appbox_kit_testing.dart` for the scriptable [FakeAppBoxKitChatStream].
library;

export 'src/appbox_kit_a2ui_message.dart';
export 'src/appbox_kit_a2ui_stream_parser.dart';
export 'src/adapters/appbox_kit_anthropic_chat_stream.dart';
export 'src/adapters/appbox_kit_openai_chat_stream.dart';
export 'src/appbox_kit_chat_stream.dart';
export 'src/appbox_kit_genui_bridge.dart';
export 'src/appbox_kit_json_schema.dart';
export 'src/appbox_kit_sse_transport.dart'
    show AppBoxKitSseTransport, appBoxKitHttpPostStream, appBoxKitSplitSseEvents;
