# genui_bridge

The provider- and model-agnostic reliability core for making **any LLM** emit
valid [A2UI](https://github.com/google/A2UI) v0.9 JSON messages — the wire
format Flutter's [`genui`](https://pub.dev/packages/genui) package (0.10.1)
renders. Pure Dart: zero Flutter imports, zero plugin dependencies, so a
`dart:io` daemon can import it.

Reliability does **not** depend on any provider's structured-output mode
(those differ and move). The loop is:

```
catalog schemas in the system prompt
  → streamed incremental parse
  → validate every message against the catalog schema
  → bounded repair (re-ask with the validation error, n ≤ 2)
  → only valid messages leave the bridge
```

## The `ChatStream` contract

The one abstraction every provider lives behind:

```dart
abstract class ChatStream {
  Stream<String> complete(List<ChatMessage> messages, {JsonSchema? schema});
}
```

- `messages` — conversation turns (`ChatMessage.system/.user/.assistant`).
- `schema` — an *optional acceleration hint* an adapter may map to a
  provider-native mode. Callers must validate output regardless; the bridge
  does. (The OpenAI adapter maps it to `response_format`; the Anthropic
  adapter ignores it — that API has no response-schema mode that preserves
  plain text streaming.)

Nothing in the interface names a provider or a model. Two adapters ship:

| Adapter | Endpoint | Covers |
| --- | --- | --- |
| `OpenAIChatStream` | `POST {baseUrl}/v1/chat/completions` | OpenAI, and Ollama / llama.cpp / vLLM via `baseUrl` (e.g. `http://localhost:11434`) |
| `AnthropicChatStream` | `POST {baseUrl}/v1/messages` | Anthropic messages API |

Both are thin HTTP over `dart:io` + `dart:convert` only. Auth is an injected
header per request (`Bearer` / `x-api-key`) — nothing is stored. The HTTP
layer is a `SseTransport` function you can inject, which is how the tests
assert request shapes without network.

## Usage (how appboxd uses it)

```dart
import 'package:genui_bridge/genui_bridge.dart';

final chat = OpenAIChatStream(
  model: 'qwen3:8b',
  baseUrl: Uri.parse('http://localhost:11434'), // no apiKey — local server
);

final bridge = GenuiBridge(
  chat: chat,
  catalogId: 'appbox.dev:catalog',
  catalog: {
    'StageCard': {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'component': {'const': 'StageCard'},
        'title': {'type': 'string'},
        'status': {'type': 'string', 'enum': ['pending', 'running', 'done']},
      },
      'required': ['id', 'component', 'title', 'status'],
    },
    // …one schema per catalog component type. Runtime input, flattened —
    // see the validator ceiling below.
  },
);

try {
  final turn = await bridge.generate([
    const ChatMessage.user('show me the build pipeline status'),
  ]);
  // Only valid messages ever get here. Forward the canonical JSONL to the
  // Flutter client, whose genui A2uiTransportAdapter.addChunk() consumes it:
  final jsonl = turn.toJsonl();
} on GenuiBridgeFailure catch (f) {
  // Still invalid after 1 + maxRepairs attempts: f.errors, f.lastRawOutput.
}
```

What you get, in layers (each usable on its own):

- **`A2uiMessage` model** — parse/serialize the four v0.9 verbs
  (`createSurface`, `updateComponents`, `updateDataModel`, `deleteSurface`).
  Read-tolerant of the rename-in-flight (`surfaceUpdate`/`dataModelUpdate`
  accepted as aliases), canonical v0.9 on write. Strict on
  `version == 'v0.9'`, because that is what genui's `a2ui_core` accepts.
- **`A2uiStreamParser`** — `StreamTransformer<String, A2uiStreamEvent>` that
  assembles messages split across arbitrary chunk boundaries (fenced blocks,
  balanced-brace objects, JSONL separators), passes prose through as
  `A2uiTextEvent`, and surfaces malformed/truncated payloads as
  `A2uiErrorEvent`s instead of throwing.
- **`GenuiBridge`** — prompt → parse → catalog validation → bounded repair,
  per turn. An attempt that mixes valid and invalid messages is discarded
  whole; a turn's messages are only emitted once every one validates.
- **`lib/testing.dart`** — `FakeChatStream` (script queues + call recording)
  for testing your own bridge consumer without network.

## Version pinning

Pinned to **A2UI v0.9**, the protocol genui 0.10.1's `a2ui_core` accepts on
the wire. The canonical spec schema this package is checked against lives in
`assets/a2ui/` with full provenance (source URLs, spec version, fetch date,
and the known spec↔code disagreements). A2UI is pre-1.0 and renames are
expected — the alias seam in `A2uiMessage.fromJson` is the single place to
absorb the next one.

## kimitail ceilings (deliberate simplifications)

- **`JsonSchemaValidator` is a subset validator.** It checks `type`
  (incl. multi-type lists), `properties`, `required`,
  `additionalProperties: false`, `items`, `enum`, `const`, `minItems`,
  `minLength`, `minimum`/`maximum` — and ignores everything else
  (`$ref`/`$defs`, `allOf`/`oneOf`/`anyOf`, `pattern`, `format`). Flatten
  refs and unions before supplying catalog schemas. *Add when:* a catalog
  needs union types or shared refs — then depend on a real JSON Schema
  package.
- **`generate` buffers each attempt** and returns the validated batch
  (`Future<A2uiTurn>`); there is no progressive emission of a partial batch.
  *Add when:* a latency profile shows time-to-first-surface matters — emit
  per-message after validation, keep repair batch-scoped.
- **No provider-native structured-output reliance and no tool-use forcing.**
  `schema` is a hint, not a guarantee. *Add when:* a specific provider
  pairing proves measurably more reliable with tool-forced output — behind
  the same `ChatStream` interface, per adapter.
- **No auth/credential management, no retries/timeouts on the HTTP layer, no
  token counting.** Those belong to the embedding daemon, which owns the
  `SseTransport` seam and can wrap it.
- **v0.8's `beginRendering` is not aliased** (its body shape differs from
  `createSurface`); pre-v0.9 envelopes without `version: "v0.9"` are
  rejected. *Add when:* a producer genuinely speaks v0.8 — map it at the
  edge, not here.
