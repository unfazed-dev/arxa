# Streaming tool args & progressive toolviews in dsh v0.1.0-rc.7

Root: `~/.dsh/profiles/node_modules/@deepseek-ai/` (abbreviated `@` below).
Types under `lib/types/**/*.d.ts` are authoritative; `lib/client.js` is the browser bundle.

## Verdict

**Streaming ARGS into a toolview: NO.** A toolview does not exist until the args are
complete. The partial-arg text is reachable from React (`snapshot.partial.blocks` via
`useSession`), but the shipped UI explicitly drops it, and the `tool.call.toolview` slot is
not mounted during the streaming window.

**Live updates DURING the run: YES, and it ships in production.** A tool body can append
session events from inside `execute` (`exec.agent.session.append(...)`), and two independent
paths carry that to a mounted toolview:

1. **`subCalls`** — the `tool/code-dispatch-start` / `tool/code-dispatch` pair, folded into
   the running block's `subCalls` array. Zero new client code.
2. **`useProjection`** — the session-projection subsystem, a generic key-addressed live push
   channel delivered as a standard prop to every session-scope slot. `@dsh-tool-todo` is a
   working end-to-end template: it appends from inside `execute` and folds that into a
   projection its own key owns.

Caveat that shapes what is feasible: the projection contract is **whole-value, never a
delta**, so every progress tick re-transmits the entire payload. Good for coarse increments
(steps completing, a growing list, a percentage). Bad for token-level text streaming.

---

## 1. `ToolCallOwnerProps` and the `block` union

### Owner props — `@dsh-client-ui-tool/lib/types/client/contract/slots.d.ts:28-41`

```ts
export interface ToolCallOwnerProps {
    callId: string;                        // :30  stable across running and settled
    toolName: string;                      // :32  wire name = keyed dispatch value
    block: ToolCallBlock;                  // :34  frozen running-or-settled node
    cwd?: string | undefined;              // :36  session workspace root
    openFile: (path: string) => void;      // :38  open an arg path through the Host
    inspect?: (() => void) | undefined;    // :40  trajectory view, when available
}
```

Note: **no expansion-state field**, despite the slot doc comment at `:17` saying the owner
passes "the expansion state (see ToolCallOwnerProps)". Expansion is view-local: `BashRow` owns
its own `useState(false)` at `@dsh-client-ui-tool/lib/client.js:1151`, and the comment at
`:1143-1144` describes this as "ToolRow's unified expand interaction, **replicated locally per
the registrant posture**" — i.e. deliberate, not an oversight. Either way, **a custom toolview
must own its own expansion state; it will not be handed one.**

### The full composed props are wider than the owner props

`ToolCallViewProps = PropsRuntime<'tool.call.toolview'>` (`slots.d.ts:43`), and
`PropsRuntime` (`@dsh-client-ui-slots/lib/types/index.d.ts:190`) composes:

```
OwnerOf<K> & KeyPropsOf<K, EntryKey> & SlotInjectFace<...>
  & (scope 'session' ? SessionStandardProps : ...) & GlobalStandardProps
```

`ui-slots` declares those standard-kit interfaces EMPTY (`:162-177`, zero-dependency layer);
`@dsh-client-runtime/lib/types/client/index.d.ts:64-90` merges the real members:

| Prop | Type | Source |
|---|---|---|
| `useSession` | `SnapshotSelectorHook<ConversationSnapshot>` | index.d.ts:71 |
| `sessionId` | `SessionId` (framework-resolved; owners never pass it) | index.d.ts:73 |
| `useProjection` | `UseProjection` | index.d.ts:75 |
| `useSessions` | `SnapshotSelectorHook<SessionListState>` | index.d.ts:87 |
| `useWorkspaces` | `SnapshotSelectorHook<WorkspaceListState>` | index.d.ts:89 |

Confirmed empirically: `BashRow({ toolName, block, sessionId, useSessions, inspect, t })` at
`@dsh-client-ui-tool/lib/client.js:1146` destructures `sessionId` and `useSessions`, neither of
which is in `ToolCallOwnerProps`.

**`t` is NOT in `ToolCallViewProps`.** [INFERRED] It arrives because the registration passes
`locale: CONVERSATION_NS` (`client.js:1263`). Contrast `ToolTreeProps`, which declares
`PropsLocale<'conversation'>` explicitly (`slots.d.ts:45`). So `t` is a registration-time
opt-in, not part of the declared slot props.

### The `block` union — `@dsh-client-runtime/lib/types/client/sessions/conversation.d.ts:276`

```ts
export type ToolCallBlock = RunningToolCall | ToolResultNode;
```

**`RunningToolCall`** (`:262-274`) — "In-flight tool card material: tool/call seen,
tool/result not yet."

| Field | Type |
|---|---|
| `callId` | `string` |
| `name` | `string` |
| `argsRaw` | `string` |
| `turn` | `number` |
| `step` | `number` |
| `time` | `number` (unix ms of the `tool/call` event) |
| `callView` | `ToolCallView \| null` (host render intent; null = generic JSON card) |
| `subCalls` | `readonly ToolCallBlock[]` (child calls, dispatch order) |

**`ToolResultNode`** (`:161-187`) — a settled result paired with its call head.

| Field | Type |
|---|---|
| `kind` | `'tool-result'` |
| `seq` | `number` |
| `time` | `number` |
| `callId` | `string` |
| `call` | `{ name: string; argsRaw: string } \| null` — null when window truncation left the call outside |
| `callTime` | `number \| null` — call event time, for row duration |
| `content` | `readonly ContentBlock[]` |
| `isError` | `boolean` |
| `error?` | `{ name: string; code: string }` |
| `meta?` | `unknown` — tool-private presentation payload |
| `callView` | `ToolCallView \| null` |
| `resultView` | `ToolResultView \| null` |
| `subCalls` | `readonly ToolCallBlock[]` |

### What distinguishes running from settled at the type level

**The presence of the `kind` field.** `ToolResultNode` has `kind: 'tool-result'`;
`RunningToolCall` has no `kind` at all. So the discriminant is asymmetric — you cannot
`switch (block.kind)`. Use the shipped guards
(`@dsh-client-ui-conversation/lib/types/client/contract/chat-nodes.d.ts`):

```ts
isSettledTool(block): block is Extract<ToolCallBlock, { kind: 'tool-result' }>   // :59
isRunningTool(block): block is RunningToolCall                                    // :67
```

Secondary tell: only the settled arm has `seq` / `content` / `isError`; only the running arm
has `turn` / `step` at the top level. Note `argsRaw` moves: top-level on running,
nested under `call.argsRaw` (nullable) on settled.

---

## 2. Partial arguments — the toolview never sees them

### What the accumulator at `:7326-7332` actually accumulates

`@dsh-client-ui-conversation/lib/client.js:7320-7333`, inside the **assistant-message** chunk
reducer (a `switch (chunk.type)` over `assistant/chunk` stream deltas, `:7300`):

```js
case "tool-call-delta": {                                     // :7320
    const previous = blocks[chunk.index];
    const base = previous?.kind === "tool-call" ? previous : {
        kind: "tool-call", callId: "", name: "", argsRaw: ""   // :7322-7327
    };
    blocks[chunk.index] = {
        kind: "tool-call",
        callId: base.callId || String(chunk.id),
        name: chunk.name ?? base.name,
        argsRaw: base.argsRaw + chunk.argumentsDelta           // :7332  <-- the accumulation
    };
    break;
}
```

**Where it lands:** in an `AssistantBlock` of `kind: 'tool-call'`
(`conversation.d.ts:39-43` — `{ kind, callId, name, argsRaw }`), inside
`PartialAssistant.blocks` (`conversation.d.ts:291-295`), surfaced as
`ConversationSnapshot.partial` (`:382`).

### Why the toolview cannot see it

The tool node is a **separate** conversation-node definition
(`client.js:8326`, `//#region lib/types/client/conversation-nodes/tool.js`). Its
`RunningToolCall` is minted only when the durable `tool/call` event lands:

```js
function rootCall(match) {                                     // :8332
    if (match.event.type !== "tool/call") throw new Error("tool-call start requires tool/call");
    return { callId: ..., name: ..., argsRaw: match.event.data.arguments, ... };  // :8337
}
```

`match.event.data.arguments` is the complete raw JSON string — `SessionEventMap['tool/call']`
at `@dsh-session/lib/types/types.d.ts:286-292` documents it as "the raw `arguments` JSON string
exactly as the model produced it (unparsed)". A `tool/call` event is only appended once the
model finished emitting the call. **There is no code path that writes a partial `argsRaw` into
a `RunningToolCall`.** The toolview does not exist during the streaming window.

### Is it reachable from a toolview component?

Not *internal* to the conversation package — `snapshot.partial.blocks` is on the public
`ConversationSnapshot`, and every session-scope slot gets `useSession`. A component could
legitimately write:

```ts
const streamingArgs = useSession(s =>
  s.partial?.blocks.find(b => b.kind === 'tool-call' && b.callId === callId)?.argsRaw);
```

But inside a **toolview** this always reads `undefined`: the toolview mounts on `tool/call`,
which is exactly when `partial` stops carrying that block. To render streaming args you would
need a slot that is already mounted during assistant streaming (the assistant chat node, or a
turn-scoped outlet) — not `tool.call.toolview`.

### The shipped UI drops streaming tool-call blocks entirely

Two independent places:

- `hasVisibleContent` (`client.js:7276-7281`): `if (block.kind === "tool-call") return false;`
  — a partial whose only content is a streaming tool call counts as having no visible content,
  so the row stays `hidden` (`:7350`).
- `AssistantMarkdown` (`client.js:9059`): the render switch has `case "tool-call": break;`
  at `:9104` — rendered as nothing. And the early bail at `:9066`
  (`blocks.some(b => b.kind !== "tool-call")`) returns `null` for a tool-call-only,
  non-streaming partial.

**Plain statement: toolviews only ever see complete args. Progressive rendering of the
model's argument text is not available at the `tool.call.toolview` slot, and no shipped
component renders it anywhere.** A plugin could render it from `snapshot.partial.blocks` via a
different, already-mounted slot — that is unproven but type-legal. [INFERRED]

---

## 3. Streaming tool OUTPUT during a run

### The clean negative first

- **No progress frame on the wire.** `MuxFrame`
  (`@dsh-host-apiproxy/lib/types/api/events.d.ts:66-145`) enumerates every push:
  `session/event`, `session/subscribed`, `approval/requested`, `approval/resolved`,
  `question/requested`, `question/resolved`, `session/queue`, `session/jobs`,
  `session/projection`, `stream/error`. There is no `tool/progress`, no partial-result frame.
- **`BashRow` shows no live output.** It is a pure function of `block`
  (`@dsh-client-ui-tool/lib/client.js:1146-1148`): `toolRowModel(toolName, block)` and
  `terminalCardModel(block, cwd)`. While running, `block` is a `RunningToolCall` whose only
  payload is `argsRaw` — the command. So a running bash card shows the command, a
  `StateDot`, and `t("bash.running")` (`:1127-1135`). Live stdout appears only when
  `tool/result` lands.
- **Background bash output is model-polled, not pushed.** `renderProcessRead`
  (`@dsh-tool-bash/lib/types/render.d.ts:20-30`) shapes "the `job_output` **delta the model
  sees**" — the model calls `job_output` again; the UI is not streamed.

**So the terminal card is not the existence proof. It has no live-output mechanism.**

### Existence proof A — `subCalls` (zero client code, ships today)

`@dsh-tools/lib/types/types.d.ts:21-53` declaration-merges two events into `SessionEventMap`:

```ts
'tool/code-dispatch-start': CodeDispatchStartEventData;  // :36
'tool/code-dispatch':       CodeDispatchEventData;        // :52
```

with payloads at `:9-20`:
```ts
CodeDispatchStartEventData { rootCallId, parentCallId, subCallId, name, arguments }
CodeDispatchEventData extends it { isError, content }
```

The doc comment at `:30-34` is explicit: *"Appended when the scheduler actually starts the
call (not at submission) … Log-only … **UIs use it for live per-sub-call running state** and
pair it with `tool/code-dispatch` by `subCallId`."* And at `:47-50`: *"Appended **inside the
parent `run_code`'s execution**"* — i.e. mid-run, while the outer tool is still executing.

Client fold — `@dsh-client-ui-conversation/lib/client.js:8431-8462`:

```js
function updateDispatch(state, match) {                        // :8431
    if (event.type !== "tool/code-dispatch-start" && event.type !== "tool/code-dispatch") return state;
    ...
    if (event.type === "tool/code-dispatch-start") {
        children.set(parentCallId, [...siblings, childCall(match, data)]);   // :8442
        ...
    }
    // settle: replace the child in place with childResult(...)              // :8452-8454
}
```

`childCall` (`:8367-8378`) mints a `RunningToolCall`; `childResult` (`:8379-8396`) replaces it
with a `ToolResultNode`. `projectBlock` (`:8463`) then rebuilds the tree, returning
`{...block, subCalls: children.map(...)}` — a **new object identity up to the root** on every
sub-dispatch event. Cycle/depth guards: `acceptsEdge` (`:8403`) and `MAX_DEPTH = 256`
(`:8327`).

Net effect: while a `run_code` call is still running, its toolview's `block.subCalls` grows
and mutates live, and the toolview re-renders each time. **This is the copyable pattern for
live-updating tool UI.**

### Existence proof B — session projections (`useProjection`), the general mechanism

Wire frame — `@dsh-host-apiproxy/lib/types/api/events.d.ts:136-141`:

```ts
{ type: 'session/projection'; sessionId: SessionId; key: string; value: unknown; seq: number }
```

Doc at `:128-135`: *"One projection unit's finished value changed … Live push state, never
logged — replay recomputes on the host … Clients keep one generic per-session value store
under **higher-seq-wins**."*

Client store — `@dsh-client-runtime/lib/types/client/sessions/projection-store.d.ts`:
`ProjectionValueStore` (`:49`) with `faceOf(key)` (`:62`, identity-stable per key, "always
defined — absence is an `undefined` snapshot, **so a component may subscribe before the key
ever carries a value**"), `apply(key, value, seq)` (`:88`), `seed(baseline)` (`:97`),
`truncate(lastSeq)` (`:107`).

Hook seat — same file `:23-26`:

```ts
export type UseProjection = {
    <K extends keyof SessionProjectionMap & string>(key: K): SessionProjectionMap[K] | undefined;
    <K extends ..., S>(key: K, selector: (v: SessionProjectionMap[K] | undefined) => S,
                      eq?: (a: S, b: S) => boolean): S;
};
```

Delivered to **every session-scope slot**, including `tool.call.toolview`, via
`SessionStandardProps.useProjection` (`@dsh-client-runtime/lib/types/client/index.d.ts:75`).
`undefined` uniformly means capability absent. The renderer resolves it through
`SessionMaybeProvideInfo.projections.faceOf(key)`
(`@dsh-client-ui-slots/lib/types/renderer.d.ts:79-81`) — an **open key space**, bound per
resolved key rather than per static roster member.

Host side — `@dsh-session-projection/lib/types/index.d.ts`:

```ts
export interface ProjectionDefinition<K extends keyof SessionProjectionMap, S> {
    key: K;                                    // :39
    schema: ZodType<SessionProjectionMap[K]>;  // :41  validates before it leaves the host
    init(): S;                                 // :46
    apply(state: S, event: SessionEvent): S;   // :55  pure, SYNCHRONOUS
    view(state: S): SessionProjectionMap[K];   // :61  whole current value
    stateVersion: number;                      // :68  cache-invalidation version
}
ctx.sessionProjections.register(definition): () => void   // :137, effect on the calling fiber
```

Constraints that matter (`:29-35`, `:13-15`):
- All three functions MUST be synchronous; `state` MUST be plain JSON.
- `apply` MUST return the **same state reference** for events it does not care about —
  `Object.is` equality produces zero downstream work.
- **Whole-value event rule (load-bearing):** *"a state-carrying log event MUST carry the
  complete post-change state, never a bare delta."*
- Register under `ctx.inject(['sessionProjections'], …)` so headless assemblies are unaffected.
- The key must be declare-merged into `SessionProjectionMap`
  (`@dsh-session-projection/lib/types/types.d.ts:16` — an empty, merge-extensible interface).

### The load-bearing enabler: a tool body CAN append session events mid-execution

`Agent.session: Session` is public and readonly
(`@dsh-agent/lib/types/runtime-types.d.ts:66`), and a tool body reaches it through
`exec.agent`.

**Proof 1 — a tool body appends from inside `execute`.** `@dsh-tool-todo/lib/index.js:169-172`:

```js
execute(args, exec) {
    const todos = toTodoList(args.todos, allowParallel);
    if (!exec.agent) throw new Error("todo_write requires an owning agent session");
    exec.agent.session.append("todo/write", { todos });      // :172
    ...
}
```

**Proof 2 — repeated appends DURING a long-running call.**
`@dsh-tool-workflow/lib/index.js`. The `run_workflow` execute body:

```js
async execute(args, exec) {                                   // :231
    const parent = exec.agent;
    const run = ctx.workflowEngine.start({...});              // :234
    const recordsRun = exec.parent === void 0;
    if (recordsRun) recorder.start(parent.session, run);      // :242  seeds `active`
    ...
    result = await run.result;                                // :249  <-- suspended here
    ...
    } finally {
        if (recordsRun) recorder.finish(run.id, result.stopReason);   // :264
    } finally {
        if (recordsRun) recorder.abandon(run.id);             // :267  clears `active`
    }
}
```

While execute is suspended at `:249`, the recorder's cordis listeners
`ctx.on("workflow/agent-start", …)` (`:49`) and `ctx.on("workflow/agent-end", …)` (`:60`)
append `tool-workflow/agent-start` / `agent-end` to that session — once per workflow member.
The append can *only* happen inside the execute window: the listeners look the session up via
`active.get(info.id)` (`:50`, `:61`) and return early when absent, and `active` is populated
only between `recorder.start` (`:242`) and `recorder.abandon` (`:267`), both inside execute.

These four event types are declare-merged at `@dsh-tool-workflow/lib/types/types.d.ts:33-55`,
which is also the real proof that plugin-merged event types are appendable — stronger than the
`SessionEventType` doc comment at `@dsh-session/lib/types/types.d.ts:355-356`.

Defensive posture worth copying (`@dsh-tool-workflow/lib/index.js:39-48`): every append is
try/caught, and a failure disables durable recording rather than failing the tool. Also,
`Session.append` runtime-validates event data with `isJsonValue`
(`@dsh-session/lib/types/types.d.ts:296-299`) — a non-serializable payload is rejected at the
source.

### The whole recipe, verified end-to-end in one shipped package

`@dsh-tool-todo` does all four steps:

1. **Merge the projection key** — `@dsh-tool-todo/lib/types/types.d.ts:12-21`:
   ```ts
   declare module '@deepseek-ai/dsh-session-projection/types' {
       interface SessionProjectionMap { todos: TodoItem[] | null; }
   }
   ```
2. **Register the unit** — `@dsh-tool-todo/lib/index.js:80-93`:
   ```js
   ctx.inject(["sessionProjections"], (projectionCtx) => {
       projectionCtx.sessionProjections.register({
           key: "todos",
           schema: todosProjectionSchema,
           init: () => null,
           apply: (state, event) => {
               if (event.type === "todo/write") return event.data.todos;   // :86
               if (event.type === "turn/start") return null;               // :87  reset per turn
               return state;                                              // :88  same ref = no work
           },
           view: (state) => state,
           stateVersion: 2
       });
   });
   ```
3. **Append from the tool body** — `:172` (above).
4. **Read in a component** — `useProjection('todos')`.

**Plugin-merged events do reach the projection drive.** `@dsh-plan-mode/lib/index.js:160-173`
switches its `apply` on `event.type === "plan/mode"` (`:169`, merged by dsh-plan-mode) and
`event.type === "command/run"` (`:161`, merged by dsh-commands) — neither is a core
`SessionEventMap` key. So step 1's custom event type folds normally.

Cost model: every tick carries the whole value through Zod validation, the wire, and a React
re-render. Coarse milestones are the intended grain. Note the `turn/start` reset at `:87` — a
useful idiom for progress state that should not survive into the next turn.

---

## 4. Re-render cadence — the memo does not block live updates

`ChatNodeSeat`, `@dsh-client-ui-conversation/lib/client.js:5239-5280`:

```js
const ChatNodeSeat = react.memo(function ChatNodeSeat({ nodeKey, ..., useSession, renderSlot, t }) {
    const node = useSession((snapshot) => snapshot.chat.nodes.get(nodeKey));   // :5240
    ...
    return <div ...>{renderSlot("conversation.chat.node", routedOwner, {
        entryKey: routedNode.kind, hookContext: nodeKey, fallback: ... })}</div>;  // :5270
});
```

The doc comment at `:5238` states the intent: *"Subscribe and dispatch one stable Context key
**without observing sibling Nodes**."*

**The `react.memo` is a sibling firewall, not an update blocker.** The seat holds its own
per-key `useSession` subscription (uSES). When the tool node's object identity changes, that
subscription fires and the seat re-renders regardless of whether its props changed. `projectBlock`
(`:8463-8470`) returns `{...block, subCalls: [...]}`, changing identity up to the root, so a
sub-dispatch event does reach the seat. The whole flow row does **not** re-render — only the
one seat whose key changed.

The memo's comparator matters only for the props it does receive (`selectedCallId`, `cwd`,
`openFile`, `inspectCall`, `forkAt`, `loadImage`, `fileMentions`), which are re-memoized at
`:5242-5259`.

Independently, the toolview itself receives `useSession` and `useProjection` and may open its
own subscriptions — those bypass the seat's memo entirely.

**Per-token updates:** not blocked by memoisation, but not *supplied* either. Cadence is
driven by committed session events (for `useSession`) or projection pushes (for
`useProjection`). Both are event-granular, not token-granular. The only token-granular stream
in the client is `assistant/chunk` → `PartialAssistant`, and per §2 it is not routed to
toolviews. [INFERRED: a per-token toolview would require a new host-side event appended per
token, which the whole-value projection rule makes expensive and the session log makes
durable — not the intended use.]

---

## 5. Host side — no progress callback exists

`DefineToolOptions` (`@dsh-tools/lib/types/schema.d.ts:178-231`) — full member list:
`name` (:180), `description` (:182), `parameters` (:184), `output { schema, render,
presentationMeta? }` (:186-193), `timeoutMs?` (:195), `isConcurrencySafe?` (:201),
`execute` (:208), `finalizeContent?` (:217), `presentCall?` (:223), `presentResult?` (:230).

**No `onProgress`, no `emit`, no `notify`, no partial-result sink.**

The execute signature (`schema.d.ts:208`, mirrored at `index.d.ts:119`):

```ts
execute(args: InferArgs<S>, exec: ToolRunContext): Promise<InferValue<NoInfer<O>>>;
```

`ToolRunContext` (`@dsh-tools/lib/types/index.d.ts:283-300`) adds exactly two methods:

```ts
export interface ToolRunContext extends ToolExecution {
    deferContext(context: UserMessage): void;   // :290  attach context to this result
    concludeTurn(): void;                       // :299  mark result terminal for the turn
}
```

Neither is a progress channel. `deferContext` is explicitly deferred — *"the loop appends it
only **after** the `tool/result`"* (`:280-281`).

Inherited shape — `ToolExecution` (`:260-265`) extends `ToolExecutionInput` (`:196-220`):

| Field | Type |
|---|---|
| `callId` | `CallId` |
| `rootCallId` | `CallId` (readonly, resolved for every root and nested execution) |
| `name` | `string` |
| `arguments` | `unknown` (losslessly JSON-serializable, deep-frozen) |
| `agent?` | `Agent` — **the escape hatch: `agent.session.append(...)`** |
| `parent?` | `ToolExecutionToken` |
| `signal` | `AbortSignal` (required caller-owned cancellation) |
| `token` | `ToolExecutionToken` (registry-assigned) |

So progress reporting is **not a first-class tool-runtime concept**. The supported route is
the session log: `exec.agent.session.append(type, wholeState)`, consumed either by a
projection unit or by a client-side conversation-node definition.

Adjacent hooks that are *not* progress channels (`index.d.ts:32-61`): `tools/pre-execute`,
`tools/execute` (around-dispatch wrapper), `tools/post-execute` — all fire at pipeline
boundaries, none mid-body.

---

## File reference index

| Concern | Path (under `@`) |
|---|---|
| Slot declaration + owner props | `dsh-client-ui-tool/lib/types/client/contract/slots.d.ts` |
| `ToolCallBlock` / `RunningToolCall` / `ToolResultNode` | `dsh-client-runtime/lib/types/client/sessions/conversation.d.ts` |
| `isRunningTool` / `isSettledTool` | `dsh-client-ui-conversation/lib/types/client/contract/chat-nodes.d.ts:59,67` |
| `PropsRuntime` composition | `dsh-client-ui-slots/lib/types/index.d.ts:190` |
| Standard-kit merge (`useSession`/`useProjection`) | `dsh-client-runtime/lib/types/client/index.d.ts:64-90` |
| `UseProjection` / `ProjectionValueStore` | `dsh-client-runtime/lib/types/client/sessions/projection-store.d.ts` |
| `ProjectionDefinition` / registry | `dsh-session-projection/lib/types/index.d.ts` |
| `SessionProjectionMap` (merge target) | `dsh-session-projection/lib/types/types.d.ts:16` |
| Wire frames (`MuxFrame`, `session/projection`) | `dsh-host-apiproxy/lib/types/api/events.d.ts` |
| `SessionEventMap` (core) | `dsh-session/lib/types/types.d.ts:223-354` |
| Sub-dispatch events | `dsh-tools/lib/types/types.d.ts` |
| `ToolRunContext` / `DefineToolOptions` | `dsh-tools/lib/types/index.d.ts:283`, `dsh-tools/lib/types/schema.d.ts:178` |
| Streaming accumulator | `dsh-client-ui-conversation/lib/client.js:7320-7333` |
| Tool node builder (`rootCall`) | `dsh-client-ui-conversation/lib/client.js:8332-8344` |
| Sub-dispatch fold (`updateDispatch`) | `dsh-client-ui-conversation/lib/client.js:8431-8462` |
| `ChatNodeSeat` memo | `dsh-client-ui-conversation/lib/client.js:5239-5280` |
| `AssistantMarkdown` (drops tool-call) | `dsh-client-ui-conversation/lib/client.js:9059-9111` |
| `BashRow` + registration | `dsh-client-ui-tool/lib/client.js:1146-1266` |
| Tool appending from `execute` | `dsh-tool-todo/lib/index.js:172` |
| Repeated appends during a run | `dsh-tool-workflow/lib/index.js:231-269` (execute) + `:37-88` (recorder) |
| Full recipe, end to end | `dsh-tool-todo/lib/types/types.d.ts:12-21` + `dsh-tool-todo/lib/index.js:80-93,172` |
| Plugin-merged event in a projection `apply` | `dsh-plan-mode/lib/index.js:160-173` |
