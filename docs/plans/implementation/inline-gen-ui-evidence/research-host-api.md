# dsh host plugin API — capability survey for interactive generative UI

Source of truth: `~/.dsh/profiles/node_modules/@deepseek-ai/` at version `0.1.0-rc.7`.

**Layout correction that matters for every ref below.** Packages do NOT ship
`lib/index.js` + `lib/client.js` alongside `lib/*.d.ts`. The runtime is a rolled-up
`lib/index.js` (host) and `lib/client.js` (browser); the *types* live under
`lib/types/**/*.d.ts` per the `exports` map. So the authoritative shape refs are
`<pkg>/lib/types/<file>.d.ts:LINE` and the implementation refs are
`<pkg>/lib/index.js:LINE` / `lib/client.js:LINE`.

Every claim below cites a path+line grepped in this session. Anything not directly
observed is tagged **INFERRED**.

---

## Headline

**A tool result cannot become a live component.** The renderable vocabulary is a
closed 6-arm union with no custom/component/html arm, and tool presenters are
required to be *pure and replayable*. There is no escape hatch at the tool seam.

**But the plugin CAN build interactive generative UI**, by a different decomposition:

| Need | Mechanism | Verdict |
|---|---|---|
| Model calls a tool | `ctx.tools.register(defineTool({...}))` | yes |
| Tool returns structured JSON to the *model* | `output.schema` + `render` | yes, JSON only |
| That JSON reaches the *browser* | `presentationMeta` **only** — `value` is stripped from durable events | yes, top-level calls only |
| That JSON renders as a live component | client plugin registers a conversation node | yes, **client-side**, not via tool result |
| Component calls back into host | `ctx.connection.rpc.handle()` + `rpc.call()` | **yes — no codegen needed** |
| Host pushes to browser unsolicited | `ctx.remote.$on` | **no** for plugin-defined events (closed allowlist) |
| Plugin serves its own HTTP routes | `ctx.webServer.register()` | yes |

The load-bearing discovery is **`ctx.connection.rpc.handle()`** (Q3). It is a generic,
plugin-usable, codegen-free custom RPC channel that completely bypasses the closed
`RpcMethodMap`. No README documents the *host registration* side; I found it in
`dsh-client-connection/lib/types/rpc.d.ts` and confirmed it in `lib/index.js`. The
`dsh-api-gateway` README does show the calling side, `ctx.connection.rpc.call('/api',
endpoint, ...)`, which is how Typert itself rides this same machinery.

---

## Q1 — Tool definition, and the allowed shape of a return value

### `defineTool` exact signature

`@deepseek-ai/dsh-tools`, exported from `lib/index.js`, typed at
`dsh-tools/lib/types/schema.d.ts:178-231` (`DefineToolOptions`) and
`schema.d.ts:239` (the function).

```ts
export declare function defineTool<
  const S extends ParameterSchemaSpec,
  const O extends ValueSchemaSpec
>(options: DefineToolOptions<S, O>): ToolDefinition;

export interface DefineToolOptions<S, O> {
  readonly name: string;                       // :180
  readonly description: string;                // :182
  readonly parameters: S;                      // :184
  readonly output: {                           // :186  — MANDATORY
    readonly schema: O;                                              // :188
    render(args: InferArgs<S>, value: InferValue<O>): ContentBlock[]; // :190
    presentationMeta?(args, value): JsonValue;                       // :192
  };
  readonly timeoutMs?: number;                 // :195
  isConcurrencySafe?(args): boolean;           // :201
  execute(args: InferArgs<S>, exec: ToolRunContext): Promise<InferValue<O>>; // :208
  finalizeContent?(exec, result): ContentBlock[] | undefined;        // :217
  presentCall?(args): ToolCallView | undefined;                      // :223
  presentResult?(args, result: ToolResult): ToolResultView | undefined; // :230
}
```

Registration: `ctx.tools.register(definition): () => void`. Scope is the calling
context's fiber — a plain plugin context registers globally, an `agent.ctx`
registers for that agent alone (shadowing a same-named global tool).

### Which validator?

**Not zod, and not raw JSON Schema by default.** It is a bespoke DSL the package
calls `ValueSchemaSpec` / `ParameterSchemaSpec`
(`dsh-tools/lib/types/schema.d.ts`, compiled by `parameterSchemaSpecToJsonSchema`
and `valueSchemaSpecToJsonSchema`, both exported at `lib/types/index.d.ts:14`).
Supported node types: `string`, `number`, `integer`, `boolean`, `null`, `array`,
`object`, an author-only `json`, and exact-one `oneOf`.

Raw JSON Schema is accepted but only over an *enforced subset*
(`assertSupportedJsonSchema`, `assertObjectJsonSchema`, `JsonSchemaError` —
`lib/types/index.d.ts:15`). zod (`@deepseek-ai/schemastery`) is used for the
*settings* plane, not for tool parameters.

Argument validation happens before `execute`; violations become `ToolArgsError`
(`INVALID_ARGS`) on the normal error-result path rather than throwing.

### Return value — the actual answer

**A tool body returns a canonical JSON value, not a string.**
`execute` returns `Promise<InferValue<O>>` where `O` is the declared `output.schema`.
So structured/JSON return **is supported and in fact mandatory** — `output` is a
required field and a registration with a missing or unsupported output declaration
fails at register time.

The registry then snapshots, validates, and **freezes** that canonical value before
rendering (`ToolExecutionSuccess.value: JsonValue`,
`dsh-tools/lib/types/index.d.ts:392`).

`output.render(args, value)` projects the frozen JSON into the **model-facing**
`ContentBlock[]`. That is the model's view, not the UI's.

### Typed content parts / resources / attachments / MIME

`ContentBlock` is defined at `dsh-llm/lib/types/types.d.ts:79-89`:

```ts
export interface ContentBlockMap {   // :79  — merge-extensible
  'text':        TextBlock;          // :80  { type:'text';      text: string }          (:39-42)
  'reasoning':   ReasoningBlock;     // :81  { type:'reasoning'; text: string }          (:44-47)
  'image':       ImageBlock;         // :82  { type:'image'; attachment: ImageAttachmentRef } (:54-58)
  'tool-call':   ToolCallBlock;      // :83                                              (:60-67)
  'tool-result': ToolResultBlock;    // :84  { toolCallId; content: ContentBlock[]; isError? } (:69-74)
}
export type ContentBlock = ContentBlockMap[ContentBlockType];  // :89
```

- **Attachments: yes, for images only.** `ImageBlock.attachment` is an
  `ImageAttachmentRef` — "immutable bytes and intrinsic display metadata owned by
  the attachment service" (`types.d.ts:56`). See `@deepseek-ai/dsh-attachment` /
  `dsh-attachment-local`.
- **MIME-typed payloads / generic resources: NO.** There is no MCP-style
  `resource` arm, no `mimeType` field, no blob arm.
- **Merge-extensible: technically yes, practically no.** `ContentBlockMap` is an
  `interface`, so a plugin can add an arm by declaration merging. The doc comment
  at `types.d.ts:76-77` states the constraint plainly: *"New core blocks must land
  with adapter, UI, and compaction support."* Adding a type entry buys nothing at
  runtime — nothing renders it. Treat as a fork-only path.
- Note `types.d.ts:49-52`: production adapters declare **text-only output**, so
  assistant-side images are forward-compat only.

### The UI-facing view — the hard negative

`presentResult` returns `ToolResultView`, a **closed union**
(`dsh-tools/lib/types/presentation.d.ts:130`):

```ts
export type ToolResultView =
  | GenericResultView   // :135  card:'generic'  { title?, content?: ContentBlock[] }
  | TerminalResultView  // :151  card:'terminal' { output?, exitCode?, signal? }
  | DiffResultView      // :171  card:'diff'     { diffs }
  | SearchResultView    // :249  card:'search'   (matches | paths arms, :200 / :221)
  | ReadResultView      // :262  card:'read'     { path, offset, lines, totalLines, lang? }
  | WebResultView;      // :326  card:'web'      (search | fetch arms, :333 / :351)
```

`ToolCallView` is likewise closed at `presentation.d.ts:41` (generic | terminal | diff).

Both are `type` aliases, **not** merge-extensible interface maps — so unlike
`ContentBlockMap`, a plugin cannot even declaration-merge a new card. There is
**no `custom`, `component`, `html`, `iframe`, or `react` arm**.

The richest available payload is `GenericResultView.content?: ContentBlock[]`
(`presentation.d.ts:143`) — "UI-facing result content, reformatted from the
model-facing result." Still just text/image blocks.

### The one structured channel to the UI — `presentationMeta`, and it is the ONLY one

`output.presentationMeta?(args, value): JsonValue` (`schema.d.ts:192`) —
*"Pure replayable presentation metadata for direct top-level calls."*

**This is not merely the intended path; it is the only path.** The canonical value
your tool returns from `execute` does **not** reach the browser.
`ToolExecutionSuccess.value` is annotated at `dsh-tools/lib/types/index.d.ts:391`:
*"Execution-local canonical value; **deliberately omitted from durable events**."*

Traced end to end:

1. `dsh-tools/lib/index.js:3417-3424` — the registry projects it:
   ```js
   if (exec.parent === void 0 && tool.output.presentationMeta !== void 0) {   // :3417
       projected = tool.output.presentationMeta(exec.arguments, value);        // :3420
       meta = snapshotProjection(tool.name, "presentationMeta", projected);    // :3424
   ```
2. It lands on the result as `ToolExecutionSuccess.meta?: JsonValue`
   (`lib/types/index.d.ts:395`).
3. The browser receives it as `ToolResultNode.meta?: unknown`
   (`dsh-client-runtime/lib/types/client/sessions/conversation.d.ts:180`).

**Two constraints that will bite:**

- **Top-level calls only.** The `exec.parent === void 0` guard at `:3417` means
  `presentationMeta` is skipped entirely for nested Code Mode sub-calls. A tool
  invoked from inside `run_code` ships no meta. If your generative-UI tool can be
  called that way, it renders with nothing.
- **It is typed `unknown` on the client.** No generated types cross the boundary;
  the client plugin must validate the shape itself.

Corroborating evidence that this is the sanctioned pattern: the read-card fixture
comment at `dsh-client-connection/lib/client.js:6574-6580` says its structured window
is *"authored inline exactly as the tool would project it through
`presentationMeta`"* — i.e. the shipped `read` tool uses `presentationMeta` to
produce the structured `card: 'read'` view.

**Purity is a hard constraint, and it is the design's whole point.**
`presentCall` / `presentResult` / `presentationMeta` are all specified pure, and
`index.d.ts:160` says the runtime calls them *"during live streaming AND a session-log
replay, so it must depend"* only on its inputs. `finalizeContent` "must be
synchronous and total". A presenter therefore cannot hold component state, open a
socket, or close over a live handle. Interactivity has to live on the client side
of the wire, reading `presentationMeta` — never inside the tool.

---

## Q2 — Streaming from a tool: **clear negative**

**A tool cannot emit progress or partial output while running.** No callback, no
async generator, no event.

- `execute` returns a `Promise` (`schema.d.ts:208`), not an `AsyncIterable`.
- `ToolRunContext` (`dsh-tools/lib/types/index.d.ts:283-300`) extends
  `ToolExecution` and adds exactly **two** methods, neither of which emits:
  - `deferContext(context: UserMessage): void` — `:290`. Queues a context that the
    agent loop appends **after** `tool/result`. Explicitly *"never injects
    immediately."*
  - `concludeTurn(): void` — `:299`. Marks a successful result terminal for the turn.
- A grep for `progress|partial|stream|emit(` across all of
  `dsh-tools/lib/types/*.d.ts` returns three hits, all prose in comments — no API.
- The full cordis event vocabulary (`index.d.ts:24-95`) is:
  `tools/pre-execute` (:38, waterfall), `tools/execute` (:49, waterfall),
  `tools/post-execute` (:61, waterfall), `tools/code-dispatch-log` (:75, waterfall),
  `tools/result` (:83, emit), `tools/change` (:93, emit).
  Every one is either an interception point or terminal. **None is mid-flight
  progress from the tool body.**

What the client sees mid-flight is therefore only the **pending card** —
`presentCall(args)` rendered from arguments alone, with no update until the call
settles. Title, `kind`, `cwd`, `locations` — that is the entire mid-flight budget.

The nearest thing to progress in the whole system is Code Mode's per-sub-call
session events, `tool/code-dispatch-start` and `tool/code-dispatch` (declared
`dsh-tools/lib/types/types.d.ts:36` and `:21-55`), which let a UI show live running
state for each nested dispatch inside one `run_code` call. That is the harness
emitting on the tool's behalf, not a surface the tool can drive.

**Workaround (INFERRED, not observed in any shipped plugin):** a long-running tool
can push progress out-of-band over its own `ctx.connection.rpc` channel (Q3) and
have the client component poll or long-poll it, keying on `callId`. The tool result
stays a single terminal value; the liveness rides the plugin's own channel. This is
consistent with every constraint I verified but I found no precedent for it.

---

## Q3 — Custom RPC: **yes, via `ctx.connection.rpc.handle()`**

### The negative first: you cannot add to `ctx.connection.api.*`

`ctx.connection.api.<namespace>.<method>()` is the **closed** apiproxy contract
(`@deepseek-ai/dsh-host-apiproxy`, `src/api/`). Its README's own deferred-work
section states: *"An unknown method fails loud at envelope parse rather than getting
a not-implemented code."* `RpcMethodMap` is a fixed union; a plugin cannot extend it.
The one advertised extension point on that plane is the **settings** domain —
`settings.describe` serves every registered namespace, so a plugin distributed
outside the repo becomes browser-configurable with no change to the proxy. That is
config, not arbitrary RPC.

### The affirmative: a generic channel registry

`@deepseek-ai/dsh-client-connection` provides `ctx.connection` on the **host** side
(`lib/types/rpc-host.d.ts:5-10` merges `Context.connection: HostConnectionHandle`)
carrying a generic RPC registry, fully typed at `lib/types/rpc.d.ts`:

```ts
export type ConnectionRpcAuthority = 'trusted-host' | 'loopback';        // :4
export interface ConnectionRpcHandlerOptions { readonly authority: ConnectionRpcAuthority } // :6-9
export type ConnectionRpcHandler =
  (endpoint: string, payload: unknown, signal: AbortSignal) => Promise<RpcResult<unknown>>; // :11
export type ConnectionRpcEndpointMatcher = (endpoint: string) => boolean; // :13

export interface HostConnectionRpc {                                      // :15
  handle(channel: string,
         handler: ConnectionRpcHandler,
         options: ConnectionRpcHandlerOptions): () => Promise<void>;      // :23
  intercept(channel: '/api',
            matches: ConnectionRpcEndpointMatcher,
            handler: ConnectionRpcHandler,
            options: ConnectionRpcHandlerOptions): () => Promise<void>;   // :32
}
```

Browser side — **verified present on the real (non-fixture) client `ctx.connection`**:

- contract `lib/types/rpc.d.ts:40-50`; factory `lib/types/client/rpc.d.ts:7`;
  implementation `lib/client.js:10088-10089`.
- The client plugin's `apply(ctx)` builds the handle with
  `const rpc = fixtureClient?.rpc ?? createWebConnectionRpc()` (`lib/client.js:10147`
  — the fixture is used only when the page URL carries `?fixture`, `:10145`),
  puts `rpc` on the handle at `:10172` alongside `api` / `isLoopback` /
  `hostDescription` / `start`, and provides it as
  **`ctx.provide("connection", handle)` at `lib/client.js:10195`.**
- Caveat worth knowing: `ConnectionController`
  (`lib/types/client/connection.d.ts:38`) is an internal stream-loop class and does
  **not** carry `rpc` — it is not `ctx.connection`. The README's summary of
  `ctx.connection` also predates/omits `rpc`. Trust `client.js:10160-10195`.

```ts
export interface ClientConnectionRpc {
  call(channel: string, endpoint: string,
       payload: unknown, signal?: AbortSignal): Promise<RpcResult<unknown>>; // :49
}
```

**Exact call shape.** Host:

```ts
ctx.connection.rpc.handle('/myplugin', async (endpoint, payload, signal) => {
  if (endpoint === 'widget/click') return { ok: true, value: {/* ... */} }
  return { ok: false, error: { code: 'internal', details: {} } }
}, { authority: 'loopback' })
```

Browser:

```ts
const res = await ctx.connection.rpc.call('/myplugin', 'widget/click', { id })
if (res.ok) use(res.value)
```

`RpcResult<T>` is `{ ok: true; value: T } | { ok: false; error: RpcError }`
(`dsh-host-apiproxy/lib/types/api/rpc.d.ts:189-195`). Handlers **never throw**
business errors — they return the error branch. `transportError()` (`:203`) folds a
thrown value into it with code `'internal'`.

### Implementation and lifecycle

`HostConnectionService.register` at `dsh-client-connection/lib/index.js:241-258`:
`handle()` mounts a **real webserver prefix route at the channel path**
(`{ kind: 'prefix', path: channel }`, `:245-247`), wrapped in the trust check at
`:249-253`, and returns via `owner.effect(...)` (`:257`) so the registration is
owned by the calling cordis fiber and withdrawn on unload. `get rpc()` at `:219-224`
closes over the calling context as `owner`.

### Auth / permission fence — read this before designing

1. **`authority` is inverted from intuition.** At `lib/index.js:243`:
   `const trustedHosts = options.authority === "loopback" ? [] : this.trustedHosts`.
   `'loopback'` is the **stricter** setting (empty extra-authority list, loopback
   only); `'trusted-host'` additionally admits the deployment's configured
   `trustedHosts`. For an inline-UI callback, use `'loopback'`.
2. Every request hits `isTrustedApiRequest` (`src/api-request-trust.ts`) before the
   handler: `Host` must be a loopback authority or match a `trustedHosts` entry
   (DNS-rebinding defense — `Host` is the one header rebinding cannot forge); when
   browser markers are present, `Origin` must equal the Host authority and an
   explicit `sec-fetch-site: cross-site` is refused. Failures answer plain **403
   before any RPC dispatch** (`lib/index.js:249-252`).
3. **`PRIVILEGED_METHODS` does not apply to plugin channels.** The pinned privileged
   set (`host.pickDirectory`, `host.openPath`, the whole `settings.*` /
   `credentials.*` configuration plane, `agentPreset.read/copy/openDocument/remove`)
   is enforced on the `/api` route only. A plugin channel is fenced by its own
   `authority` and nothing else — **the plugin owns its own authorization.**
4. **`intercept()` is effectively unavailable to third-party plugins.**
   `registerInterceptor` (`lib/index.js:259-272`) hard-rejects any channel but
   `/api` (`:260`) and throws `"shared RPC channel ... already has an interceptor"`
   if one exists (`:267`). In the shipped web composition the **Typert Gateway
   already claims it** (`dsh-api-gateway` README: *"The Host entry registers a
   trusted-host interceptor on Connection's shared `/api` FetchHandler"*).
   Use `handle()` with your own channel.

### The other custom-RPC path: Typert — and why to avoid it

`@deepseek-ai/dsh-api-gateway` provides `ctx.typertGateway` (host) and `ctx.remote`
(client). A business Service extends `TypertRemoteService`, marks methods `@Remote` /
`@RemoteScope`, and the client mounts a generated contribution with
`ctx.remote.$mount(contribution)` (`dsh-typert-protocol/lib/types/types.d.ts:193`),
after which calls go out as `ctx.remote.<namespace>.<method>(...)` over
`ctx.connection.rpc.call('/api', endpoint, ...)`.

**Three blockers for a third-party plugin:**

1. **`@deepseek-ai/dsh-typert-generator` is NOT INSTALLED.** Verified absent from
   `~/.dsh/profiles/node_modules/@deepseek-ai/`. It does the build-time TypeScript
   analysis that emits the descriptors.
2. The gateway README's deferred work states: *"Only strict generated contributions
   can mount on the Client face. SRC markers have no Client codec or type
   projection."* SRC (the no-codegen dev fallback) works host-side but **cannot
   reach the browser**. `$mount` rejects "descriptors without strict generated codecs
   ... before methods become callable."
3. Discovery is via a `"./typert"` package export; only five installed packages have
   one (`dsh-commands`, `dsh-cordis-host-runner`, `dsh-goal`,
   `dsh-host-plugin-inventory`, `dsh-message-feedback`).

**Recommendation: use `ctx.connection.rpc.handle()`.** It needs no codegen, no
generator package, no manifest — and it is what Typert itself sits on.

---

## Q4 — Server→client push: **effectively no for a plugin**

There are two downlinks and one subscription API, and none of them is open to
plugin-defined events.

### Transport

`/api/events.mux` and `/api/events.host`, each a WebSocket upgrade,
**downlink-only** — *"the client sends no application data over these sockets"*
(`dsh-client-connection` README). Host-side carrier at
`lib/types/websocket-downlink.d.ts:1-24`. Ordinary GETs to these paths return
**426 with no SSE fallback**; the SSE codec serves only the in-process carrier.
Readiness requires both sockets open **and** the `host.describe` HTTP call to
succeed; if either socket ends, the connection generation fails and rebuilds both.

### Subscription API

`dsh-typert-protocol/lib/types/types.d.ts:202`:

```ts
$on<Event extends TypertRemoteEvent>(event: Event, listener: Events[Event]): () => void;
```

`$dispatch(event, args)` (`:214`) is the **carrier's** half — the client owning the
host frame sink hands decoded frames over. A consumer subscribes and never calls it.
Each subscription belongs to the calling fiber and disappears with it; delivery is
one-way, in registration order, and a throwing listener is logged and isolated.

### The fence — a hardcoded array

Legal `$on` keys are exactly `API_REMOTE_FORWARDED_EVENTS`, a literal array at
**`dsh-api-remotes/lib/index.js:18-30`**:

```
agent-preset/selected, commands/change, credentials/updated,
cordis/request-run, cordis/request-run-resolved,
cordis/dynamic-package, cordis/dynamic-retract,
cordis/inspect-query, cordis/inspect-query-resolved,
llm/adapters-updated, settings/document-updated
```

Eleven entries. The README is explicit: *"Forwarding one more event is an entry in
that array and nothing else."* **A plugin cannot add its own event without patching
`dsh-api-remotes`.** The host face additionally asserts the list against
`TypertForwardableEvent`, rejecting any name that is not a declared event, that binds
an AgentScope, or whose shape is not one-way.

Also from the gateway's deferred work: forwarded events reach `$on` verbatim —
*"no payload projection or redaction, no Scope-bound subscription, and **no replay
after a reconnect**."*

### Two interesting escapes

- **`cordis/dynamic-package` and `cordis/dynamic-retract` ARE on the allowlist.**
  These are generic cordis lifecycle events. **INFERRED:** a plugin that can cause
  one to fire gets a push to every browser subscriber. I did not verify their payload
  shape or whether a plugin can emit them meaningfully — worth a look if push is a
  hard requirement.
- **Polling over your own channel.** Since `ctx.connection.rpc.handle()` gives you an
  arbitrary HTTP route, the practical push substitute is client-driven polling or
  long-polling on that channel. **INFERRED**, but it needs no core patch. A raw
  WebSocket via `ctx.webServer.registerUpgrade()` (Q6) is the other option.

---

## Q5 — "deliverables": **not an artifact store.** Clear negative.

`@deepseek-ai/dsh-client-ui-deliverables`, described in its own `package.json` as
*"Produced-files turn tail and clickable final-response file references for Web"*.

**The host half is 24 lines and stores nothing.** `lib/index.js:1-24`: it has
`inject = ["systemPrompt"]` (`:9`) and its entire `apply(ctx)` (`:16-21`) registers
one system-prompt section, `"ui:deliverable-file-references"`, order 190, whose text
(`:11`) is:

> "When you successfully create or modify files, mention the primary outputs in your
> final response. To make those and any other changed-file references clickable in
> Web, format them as Markdown inline code using the exact file-tool path, or a
> basename when unique among the files changed in that turn."

That is the whole host contribution. No storage, no service, no `ctx.deliverables`.
A repo-wide grep for `deliverable` matches nothing outside this one package.

**The client half derives a file list from tool render intents.** From
`lib/types/client/turn-deliverables.d.ts` — *"Client-only and model-free: the
vocabulary is the mutation tools' own follow-along `locations`, never the closing
prose"* (`:1-5`):

- `DeliverablesTurnData { readonly produced: readonly ProducedPath[] }` (`:14-16`),
  merged into `ConversationTurnDataMap` under key `deliverables` (`:17-22`).
- `producedForClosing(data, seq?)` (`:47`), `selectProducedFiles(owner)` (`:53`),
  `deliverablesDefinition: ConversationNodeDefinition<DeliverablesState>` (`:55`).
- The recognition rule (`:27-46`): *"A mutation is recognized by render intent, not
  by tool name — a diff card, or a generic card whose `kind` is `edit`."* Reads
  contribute nothing, deletes contribute nothing, failed calls contribute nothing;
  paths keep first-seen order and dedupe.

**It can hold: file paths. Nothing else.** It is a turn-tail chip list of files your
tools touched. It is **not** the artifact primitive.

### What it did reveal — the actual generative-UI seam

`deliverablesDefinition` is a `ConversationNodeDefinition`, and `ConversationTurnDataMap`
is a **merge-extensible interface**. Both come from
`@deepseek-ai/dsh-client-runtime/client`, exported at
`dsh-client-runtime/lib/types/client/index.d.ts:16`, defined in
`lib/types/client/contract/conversation.d.ts`. The surrounding vocabulary —
`ConversationNodeContext`, `ConversationMatch`, `ConversationPublication`,
`ConversationViewBuilder`, `ConversationViewDefinition`, `ChatConversationViewNode`,
plus `lib/types/client/slots.d.ts` — is how a client plugin injects its own nodes
into the conversation timeline, and `TurnTailOwnerProps` from
`dsh-client-ui-conversation/client` is how it claims the turn tail.

**This is where interactive inline UI actually lives.** `dsh-client-ui-deliverables`
is a working end-to-end example of the pattern at minimum scale: host registers a
prompt section, client registers a conversation node definition that reads tool
render intents and renders a component. Swap "reads `locations`" for "reads
`presentationMeta`" and add `ctx.connection.rpc.call` on click, and that is the
architecture.

I did not survey the conversation-node API in depth — it is client-side and the
`dsh-slots` / `dsh-tools-ui` agents own that surface. Flagging the entry point.

---

## Q6 — Serving plugin assets: bundles are fixed, but you can add routes

### How `/plugins/<id>/client.js` is served

Owned by `@deepseek-ai/dsh-client-modules` (**not** the webserver, which
*"knows no harness concepts and serves no files"*).

Host half, `dsh-client-modules/lib/index.js:158-160`:

```js
ctx.effect(() => ctx.webServer.register({
  kind: "prefix",
  path: "/plugins",
  ...
```

The node half scans enabled Loader entries for packages declaring `dsh.client` in
`package.json`, resolves each `exports["./client"]`, hashes the built bundle into the
boot graph (`window.__DSH_BOOT__`), and serves it with its source map. Path handling
at `lib/index.js:321-326` shows the prefix `"/plugins/"` and that it serves exactly
two things — the client bundle and its `.map`:

```js
const prefix = "/plugins/";                                               // :321
const isSourceMap = pathname.startsWith(prefix) && pathname.endsWith(mapSuffix); // :324
const clientPath = pathname.startsWith(prefix) && pathname.endsWith(suffix)
  ? this.clientPath(pathname.slice(9, -suffix.length)) : void 0;          // :326
```

**So `/plugins` will not serve arbitrary static files.** It is a bundle route, not a
static directory.

Bundles are lazy CJS: executing a bundle only *registers* a factory
(`window.__ModuleLoader__.load({id, factory})`); module body side effects including
CSS injection run at materialization, not at script execution. `<id>/client` and the
bare id resolve to the same exports.

### Serving your own files or routes — yes

`@deepseek-ai/dsh-host-webserver` provides `ctx.webServer`:

- **`register(route)`** — a named `exact` or `prefix` HTTP route. Returns a disposer.
  A duplicate path **throws** (route patterns are a composition-level contract).
- **`registerUpgrade(route)`** — an upgrade route for an exact pathname. **This is
  how you would run your own WebSocket** for the push that Q4 denies you.
  Unmatched upgrades are closed; the upgrade handler owns the protocol handshake and
  connection contents.
- **`registerFallback(handler)`** — single-owner, already taken by
  `dsh-host-frontend-static`. A second registration throws. Not available to you.
- **`tapIndex(transform)`** — adds an index.html transform; `applyIndexTaps(html)`
  runs them in order on every index response. This is the seam for injecting a tag
  into the shell document.
- `ctx.webServer.port` / `.host` are readable composition-time facts.

Match order is fixed: **exact over the whole table, then longest prefix, then
fallback.** Upgrades match exactly only.

Binding: `host` accepts only `127.0.0.1` (default) or `0.0.0.0` (deliberate network
exposure). Serves browsers only — **Electron loads dist over `file://` and carries
fetch over an IPC bridge.**

### If inline UI must iframe something

Register a prefix route with `ctx.webServer.register({ kind: 'prefix', path: '/my-plugin-assets', handler })`
and serve from it. **Two cautions:**

1. **A raw `ctx.webServer` route has NO trust fence.** The `/api` browser-trust fence
   lives in the connection plugin, not the webserver. `ctx.connection.rpc.handle()`
   gets you the fence for free (`lib/index.js:249-253`); a bare `webServer.register`
   does not. Serve only non-sensitive assets there, or replicate the check.
2. **The Electron carrier will not see it** — `file://` + IPC, no HTTP origin.
   An iframe-based design is web-only. **INFERRED** from the README's statement that
   Electron loads dist over `file://`; I did not read the Electron carrier.

---

## Recommended architecture

1. **Host:** `ctx.tools.register(defineTool({...}))`. Declare the component's full
   initial state in `output.schema`, then **project it through `presentationMeta`** —
   the canonical `value` is stripped from durable events, so meta is the only way it
   reaches the browser. Keep the tool out of Code Mode reach, or accept that nested
   calls ship no meta (`lib/index.js:3417`).
2. **Host:** `ctx.connection.rpc.handle('/my-plugin', handler, { authority: 'loopback' })`
   for the interaction callbacks. Enforce your own authorization inside the handler —
   nothing else will.
3. **Client:** a `dsh.client` bundle registering a `ConversationNodeDefinition` that
   matches your tool's results and renders the live component. The node reads
   `ToolResultNode` (`dsh-client-runtime/lib/types/client/sessions/conversation.d.ts:161-187`),
   whose three payload-bearing fields are `meta?: unknown` (`:180` — your
   `presentationMeta`, validate it yourself), `content: readonly ContentBlock[]`
   (`:174`), and `resultView: ToolResultView | null` (`:184`, the closed card union).
   Interactions call `ctx.connection.rpc.call('/my-plugin', endpoint, payload)`.
4. **Do not** expect streaming, a rich tool-result card, an artifact store, or
   plugin-defined server push. Poll your own channel, or run your own WebSocket via
   `registerUpgrade`.

The clean split: the **tool** produces frozen, replayable JSON; the **client node**
owns all liveness; the **plugin RPC channel** carries every interaction. This is the
same decomposition `dsh-client-ui-deliverables` uses, and it is what the purity
constraints on the presenters are pushing you toward.

---

## Verification notes

**Verified by direct file read this session** — all `defineTool` / `ToolDefinition` /
`ToolRunContext` / `ToolResultView` / `ContentBlock` / `ToolResultNode` shapes and
line numbers; the absence of any progress API in `dsh-tools`; the
`presentationMeta` → `result.meta` → `ToolResultNode.meta` chain and its
top-level-only guard; the `HostConnectionRpc` / `ClientConnectionRpc` **type**
contracts plus the **host** implementation (`lib/index.js:219-272`) and the **client**
provisioning (`lib/client.js:10147, 10172, 10195`);
`API_REMOTE_FORWARDED_EVENTS` contents; the deliverables host half in full; the
`/plugins` prefix registration; the absence of `dsh-typert-generator`.

Not read: the body of `createWebConnectionRpc`'s transport (`lib/client.js:10089+`)
beyond its signature, and `snapshotProjection`'s failure behavior.

**From README prose, not code** — the webserver method list, the browser-trust fence
details, the `/api` privileged method set, Typert's strict-vs-SRC client restriction,
the Electron `file://` carrier. These are the packages' own docs and were internally
consistent, but I did not confirm each against implementation.

**Tagged INFERRED above** — the out-of-band progress workaround, the
`cordis/dynamic-package` push escape, polling as a push substitute, and the Electron
iframe caveat.

**Not investigated** — the conversation-node client API in depth (client-side; owned
by the `dsh-slots` / `dsh-tools-ui` agents), `dsh-attachment` internals,
`dsh-user-questions` / `/api/respond` as an interactive precedent (the apiproxy
README notes its pending-interaction table "handles questions only" and has no
approval entries, so it is a fenced special case rather than a general seam).

**Hygiene** — the shared ctx FTS index returned results from other agents' sessions
(Unsplash API docs, a `layout-types-root` module). Nothing from those was used here.
