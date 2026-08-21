# dsh: tool-call rendering and the generative-UI seam

Source of truth: `~/.dsh/profiles/node_modules/@deepseek-ai/` (v0.1.0-rc.7). All
package dirs are **symlinks** into `~/.npm/_npx/1e7f6d9597241db0/node_modules/@deepseek-ai/`
— `grep -r .` silently returns nothing; use glob paths (`*/lib/...`) or `grep -R`.

Two path conventions appear below and must not be confused:
- **Installed-bundle refs** — `package/lib/client.js:LINE`. Verified by reading the file.
- **Repo refs** — `packages/client/ui-tool/src/client/contract/slots.ts:23`. These come
  from the harness's own slot catalog `source:` fields. NOT installed paths; not verified.

The `.d.ts` files under `lib/types/**` are shipped and are the authoritative contract.
Prefer them over the minified-ish bundles.

---

## 0. Executive answer

There is **no registry keyed by tool name that takes a "tool renderer"** in the
React-component-registry sense you might expect. There is something better and more
general: a **typed slot registry** (`ctx.slots`), and tool views are one *keyed* slot on
it — `tool.call.toolview`, keyed by the wire tool name. A client plugin registers a React
component for a tool name in one call.

There are **four distinct paths** that decide how a tool call renders, and conflating them
is the main hazard. Note that C1 and C2 are both agent-authored at runtime but differ
enormously in lifetime:

| Path | Who writes it | Slot | What it can express | Custom React? |
|---|---|---|---|---|
| **A. Host render intent** — `ToolDefinition.presentCall` / `presentResult` | the tool author (host plane) | — | a fixed tagged vocabulary: generic / terminal / diff / search / read / web | No |
| **B. Shipped client toolview** | a client plugin (build-time, in a bundle) | `tool.call.toolview` | arbitrary React | Yes |
| **C1. Dynamic package toolview** | the **agent, at runtime** (`cordis_define`) | `tool.call.toolview` | arbitrary React, evaluated from source | Yes |
| **C2. Dynamic package control panel** | the **agent, at runtime** (`cordis_define`) | `tool.view.cordis` | arbitrary React + `host.call` RPC | Yes |

The literal "agent calls a tool, the tool's result renders as an interactive component"
story is **C1**, not C2. A dynamically defined package's browser half may register into
`tool.call.toolview` exactly as a shipped plugin does — this is not a loophole, it is the
documented purpose of the shipped slot catalog (§7). C1 renders on **every** call of that
tool name, including scroll-back. C2 is a narrower thing: a live control panel that shows
only while a plugin run is `running` (§6).

Both C1 and C2 are bounded by the same page-session lifetime: a browser refresh unloads
every dynamic package by design, so agent-authored renderers vanish until the next
`cordis_run`, while the tool calls themselves persist and fall back to shipped rendering.

---

## 1. Is there a registry of tool renderers keyed by tool name?

**Yes.** It is the keyed slot `tool.call.toolview` on the `slots` service.

Declaration (`dsh-client-ui-tool/lib/types/client/contract/slots.d.ts:5-25`; repo ref
`packages/client/ui-tool/src/client/contract/slots.ts:23`):

```ts
declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface SlotMap {
    'tool.call.toolview': {
      kind: 'keyed'
      scope: 'session'
      owner: ToolCallOwnerProps
    }
  }
}
```

The shipped doc comment on it states the semantics exactly:

> Keyed atomic Tool call view, dispatched by the wire Tool name. Register with
> `key: '<tool name>'` to own how one tool's calls render inside a turn — the key domain
> is open (any wire tool name, including a tool your own package registered), so there is
> no compile-time key set to pick from and **a typo simply never renders**.
>
> A key the shipped composition already covers is **replaced, not shared**; an unclaimed
> key falls back to the generic tool row, so registering is additive for your own tool and
> a takeover for a shipped one.

### Exact call shape

```js
// canonical minimal form, from the harness's own slot catalog `example` field
{
  inject: ['slots'],
  apply(ctx) {
    ctx.slots.inject('tool.call.toolview', () => ctx.slots.register(
      { name: 'tool.call.toolview', key: '<one key the owner dispatches>' },
      () => React.createElement('div', null, 'hello'),
    ))
  },
}
```

A real shipped one — `dsh-client-ui-tool/lib/client.js:1259-1264`:

```js
ctx.slots.inject("tool.call.toolview", () => ctx.slots.register({
  name: "tool.call.toolview",
  key: "bash",
  locale: CONVERSATION_NS
}, BashRow));
```

Two keys from one plugin use a generator (`dsh-client-ui-tool/lib/client.js:1310-1321`):

```js
ctx.slots.inject("tool.call.toolview", function* () {
  yield ctx.slots.register({ name: "tool.call.toolview", key: "edit",  locale: CONVERSATION_NS }, FileMutationRow);
  yield ctx.slots.register({ name: "tool.call.toolview", key: "write", locale: CONVERSATION_NS }, FileMutationRow);
});
```

### API notes

- `register(options, Component)` — 2-arg. Overloads at
  `dsh-client-ui-slots/lib/types/index.d.ts:562` and `:575` (the second takes an `inject`
  face). Declared on class `SlotCore` (`:513`).
- `ctx.slots.inject('<slotname>', factory)` wraps the register so it re-runs across the
  declaring entry's activation/reload lifetimes. `tool.call.toolview` is *declared by* an
  entry in `conversation.chat.node`, so it only exists while ui-tool's `ToolCallTree` is
  mounted. Registering without `ctx.slots.inject` is a lifetime bug.
- Disposal rides `ctx.effect` inside `slots.register` — no manual teardown.
- `priority?: number` (`dsh-client-ui-slots/lib/types/index.d.ts:378-380`) is the cell
  shadowing rank: ascending, default 0, **lowest renders**. Same key + same priority
  **throws**. This is how a plugin takes over a shipped key deterministically.
- `locale?: N` puts a typed `t` translate seat on the props; rendering without an
  installed locale face fails loud.
- `registrant?: string` is a diagnostics label.

### Registering the tool itself is separate

`tool.call.toolview` only registers the *view*. The tool is registered host-side on
`ctx.tools`. The two are joined only by the string key. Nothing enforces that a view's key
corresponds to a real tool — an unmatched key is silently inert.

---

## 2. What props does a tool renderer receive?

Owner props (`dsh-client-ui-tool/lib/types/client/contract/slots.d.ts:26-41`):

```ts
export interface ToolCallOwnerProps {
  callId: string                      // stable across running and settled forms
  toolName: string                    // wire tool name = the keyed dispatch value
  block: ToolCallBlock                // frozen running call OR settled result node
  cwd?: string | undefined            // session workspace root, for relative summaries
  openFile: (path: string) => void    // open a tool argument path through the Host
  inspect?: (() => void) | undefined  // jump to this call in the trajectory view
}
```

Full props = `PropsRuntime<'tool.call.toolview'>`, which is the four-share intersection
(`dsh-client-ui-slots/lib/types/index.d.ts:190`, `:358`): owner props + key props +
slot-inject face + scope standard props + global standard props (+ `t` if `locale` declared).

Because scope is `'session'`, every toolview additionally receives these **standard props**
(verbatim from the slot catalog, `dsh-cordis-client-runner/lib/client.js:3440-3447`):

```
useSessions:   SnapshotSelectorHook<SessionListState>
useWorkspaces: SnapshotSelectorHook<WorkspaceListState>
useSession:    SnapshotSelectorHook<ConversationSnapshot>
sessionId:     SessionId
useProjection: UseProjection
useInput:      SnapshotSelectorHook<InputState>
inputActions:  InputActions
```

`inputActions` is notable: a toolview can drive the composer. See §4.

### `block` — status, args, result

`ToolCallBlock = RunningToolCall | ToolResultNode`
(`dsh-client-runtime/lib/types/client/sessions/conversation.d.ts:276`).

**Status is by shape, not by a status field.** Discriminate with `'kind' in block` — a
settled `ToolResultNode` has `kind: 'tool-result'`; a `RunningToolCall` has no `kind`.
The harness documents this explicitly in the `conversation.details.tool` catalog entry:
"branch on `'kind' in block`". So the state machine is:

| State | Detection |
|---|---|
| running | `!('kind' in block)` |
| done | `block.kind === 'tool-result' && !block.isError` |
| error | `block.kind === 'tool-result' && block.isError` |

There is no separate "pending" state at this slot — the view mounts when the `tool/call`
event lands, i.e. already dispatched.

`RunningToolCall` (`conversation.d.ts:262-275`): `callId`, `name`, `argsRaw`, `turn`,
`step`, `time`, `callView`, `subCalls`.

`ToolResultNode` (`conversation.d.ts:161-189`): `kind`, `seq`, `time`, `callId`,
`call: { name, argsRaw } | null`, `callTime`, `content: readonly ContentBlock[]`,
`isError`, `error?: { name, code }`, `meta?: unknown`, `callView`, `resultView`, `subCalls`.

**Arguments: complete, not streaming.** `argsRaw` is a **JSON string** (not a parsed
object; call sites do `JSON.parse(call.argsRaw)`, e.g.
`dsh-client-ui-conversation/lib/client.js:5727`). It is assigned whole from the `tool/call`
session event at `dsh-client-ui-conversation/lib/client.js:8337`:

```js
argsRaw: match.event.data.arguments,
```

Partial-argument streaming **does exist** but on a different surface: the assistant's
in-flight block accumulates `base.argsRaw + chunk.argumentsDelta` on a `tool-call-delta`
chunk (`dsh-client-ui-conversation/lib/client.js:7326-7332`). That feeds `PartialAssistant`
/ `AssistantBlock`, which is the streaming assistant message — **not** `tool.call.toolview`.
A toolview never sees half-parsed args.

**Result: structured, not string-only.** `content` is `readonly ContentBlock[]` (text /
image / etc.), plus `meta?: unknown` for arbitrary structured payload, plus the
`resultView` render intent (below). Sub-calls nest recursively via `subCalls`, and the
tree renders them — `ToolCallBranch` at `dsh-client-ui-tool/lib/client.js:896`.

### `callView` / `resultView` — host-declared render intent

Both nodes carry a host-computed render intent, `null` meaning "generic JSON card". These
are the layer-A vocabulary, defined in `dsh-tools/lib/types/presentation.d.ts`:

- `ToolCallView = GenericCallView | TerminalCallView | DiffCallView` (`:41`)
- `ToolResultView = GenericResultView | TerminalResultView | DiffResultView | SearchResultView | ReadResultView | WebResultView` (`:130`)

Declared by the tool author via `ToolDefinition.presentCall` / `presentResult`. The
vocabulary is deliberately provider-neutral so "UI bridges map it without special-casing
tool names". Supporting types: `ToolCallKind` (`read|edit|delete|move|search|execute|fetch|other`),
`FileLocation {path, line?}` for editor follow-along, `FileDiff {path, oldText|null, newText}`,
`ReadFileLine {number, text}`.

Wired onto the node at `dsh-client-ui-conversation/lib/client.js:8341` and `:8362`:
```js
callView:   match.view?.for === "call"   ? match.view.view : null,
resultView: match.view?.for === "result" ? match.view.view : null,
```

**This is the cheapest win in the whole system:** a host tool that implements
`presentCall`/`presentResult` gets a rich terminal/diff/read/search/web card with **zero**
client-side code, because the fallback card already renders all six. See §3.

---

## 3. Fallback / default renderer

**Yes** — `GenericToolCard`. Dispatch site, `dsh-client-ui-tool/lib/client.js:888-892`:

```js
renderSlot("tool.call.toolview", owner, {
  entryKey: toolName,
  fallback: (0, react_jsx_runtime.jsx)(GenericToolCard, { ...owner, t })
})
```

`GenericToolCard` (`dsh-client-ui-tool/lib/client.js:811`) is **not** a dumb code block. It
builds every card model and lets whichever one matched render:

```js
const model    = toolRowModel(toolName, block, cwd);
const terminal = terminalCardModel(block, cwd);
const read     = readCardModel(block, cwd);
const diff     = diffCardModel(block);
const search   = searchCardModel(block);
const web      = webCardModel(block);
```

then hands them to the shared `ToolRow` chrome (icon, title, summary, collapsible body,
output section, error summary, file-path link, expansion state). Card models live at
`dsh-client-ui-tool/lib/types/client/tool/models/{terminal,read,diff,search,web}-card-model.d.ts`.

So the fallback ladder is: **keyed toolview → GenericToolCard driven by the host's
`callView`/`resultView` → plain generic row with pretty-printed JSON args.**

Icon selection falls back through `TOOL_VARIANTS`
(`dsh-client-ui-tool/lib/client.js:31+`), a known-tool-name → variant table
(`bash|pwsh→bash`, `read|web_fetch→read`, `web_search|grep|glob→search`, `write→write`,
`edit→edit`, default `others`). Its doc comment records the precedence rule: `cordis_define`
is deliberately absent because a keyed hit **replaces** the generic row, so an entry would
be unreachable.

---

## 4. Can a tool renderer be interactive?

**Layer B (`tool.call.toolview`) — interactive, but deliberately narrowly.**

The slot's own doc states the constraint:

> The owner passes the call's identity, its frozen running-or-settled node, and the
> expansion state, **so the view stays a pure function of what the turn already knows.**

`block` is described as "frozen". There is no connection/RPC handle in `ToolCallOwnerProps`.
The sanctioned interactions are the two owner callbacks — `openFile(path)` and `inspect()` —
plus, from the session standard props, `inputActions` (drive the composer) and the
`useSession` / `useProjection` / `useInput` snapshot hooks (read live state).

`inputActions` is stronger than it looks. Verified shape
(`dsh-client-ui-conversation/lib/types/client/input/contract.d.ts:65-76`):

```ts
export interface InputActions {
  setDraft(text: string): void
  addImages(ids: readonly DraftAttachmentId[]): boolean
  removeImage(id: DraftAttachmentId): void
  pruneImages(ids: readonly DraftAttachmentId[]): void
  submit(): void          // "Enter submission (adjudication / claim transaction / default sink inside)"
}
```

`setDraft(...)` + `submit()` is a genuine **button → new agent turn** loop: a toolview
button can compose a message and send it without any user keystroke. That is the sanctioned
callback path for layer B, and for many "interactive generative UI" designs it is
sufficient — the widget talks back to the *agent* rather than to a host function.

So layer B interactivity is real (open files, jump to trajectory, drive and submit the
composer) but it is **not** a general call-back-to-a-host-function channel. A shipped
example of a genuinely interactive row is `AskQuestionRow` for `ask_user_question`
(`dsh-client-ui-tool/lib/client.js:1082-1086`).

Nothing *mechanically* stops a build-time client plugin from closing over its `apply(ctx)`
and reaching `ctx.remote.*` (the typed client Remote namespaces from `dsh-api-remotes`) —
that is ordinary JS closure capture. `dsh-client-ui-cordis` does exactly this shape,
passing a service-backed `inject` face into its registration
(`dsh-client-ui-cordis/lib/client.js:1378-1398`). So the "pure function" line is **API
discipline, not enforcement**. INFERRED, but strongly supported by the ui-cordis precedent.

**Layer C (`tool.view.cordis`) — explicitly interactive, with a host RPC channel.**

This is the purpose-built seat. Catalog entry (`dsh-cordis-client-runner/lib/client.js:3479-3485`;
repo ref `packages/extensions/ui-cordis/src/client/slots.ts:31`):

> Interactive Package-owned region rendered inside the latest eligible `cordis_run` card in
> the conversation flow. **Use it for controls and other UI the user can interact with.**
> Dynamic Client code registers with `key: 'self'`; the Guard binds that key to the current
> Plugin and Package.

Owner props: `{ pluginId, packageId, pluginRunId }` — plus the same seven session standard
props. Dynamic browser-half code runs as an async function body whose **parameters are its
entire symbol surface** (`dsh-cordis-client-runner/lib/types/client/evaluator.d.ts:1-7`).
Exact surface (`dsh-cordis-client-runner/lib/client.js:3534-3563`):

```
ctx     — restricted Cordis Context:
            ctx.get(name): unknown | undefined
            ctx.on(name, listener): () => void
            ctx.provide(name, value): () => void
            ctx.effect(callback, label?): () => void
React   — React.createElement / useState / useEffect   (no JSX transform)
host    — host.call(method: string, args?: JsonValue): Promise<JsonValue>
styles  — styles.insert(css: string): () => void       (auto-removed on unload)
```

**`host.call` is the answer to "can a button click call back to the host":** it is a
package-private JSON RPC from the client half to that same package's host half. Ambient
globals (`setTimeout`, `fetch`, `require`, …) are shadowed by parameters that throw
teaching redirects (`DYNAMIC_CLIENT_REDIRECTS`).

The guard (`dsh-cordis-client-runner/lib/types/client/guard.d.ts`) whitelists lifecycle-safe
verbs, withholds framework internals, denies `Context`-valued returns, pins `theme`
overrides to the package id, and ledgers every slot registration with an auto-allocated
unique shadowing priority. Its own doc is blunt about the threat model:

> This is **API discipline, not a security boundary**: a dynamic package's code is as
> trusted as the host process that accepted its definition.

Treat `cordis_define` as arbitrary code execution in the client, because it is.

---

## 5. Existing built-in rich renderers (the copyable examples)

Complete occupant list of `tool.call.toolview`, from the catalog
(`dsh-cordis-client-runner/lib/client.js:3453-3470`) and confirmed against each bundle:

| Key(s) | Component | Package | Registration |
|---|---|---|---|
| `bash` | `BashRow` | ui-tool | `client.js:1259-1264` |
| `edit`, `write` | `FileMutationRow` | ui-tool | `client.js:1310-1321` |
| `read` | `ReadRow` | ui-tool | `client.js:1363-1367` |
| `grep`, `glob` | `SearchRow` | ui-tool | `client.js:1416-1426` |
| `todo_write` | `TodoRow` | ui-tool | `client.js:1528-1532` |
| `web_search`, `web_fetch` | `WebRow` | ui-tool | `client.js:1578-1588` |
| `ask_user_question` | `AskQuestionRow` | ui-tool | `client.js:1082-1086` |
| `skill` | `SkillRow` | ui-skill | `client.js:227-230` |
| `cordis_define` | `CordisDefineRow` | ui-cordis | `client.js:1372-1377` |
| `cordis_run` | `CordisRunRow` | ui-cordis | `client.js:1378-1399` |
| `cordis_stop`, `cordis_undefine` | `CordisActionRow` | ui-cordis | `client.js:1400-1411` |

Taken keys, verbatim from the catalog's `keyDomain`: `ask_user_question, bash,
cordis_define, cordis_run, cordis_stop, cordis_undefine, edit, glob, grep, read, skill,
todo_write, web_fetch, web_search, write`. `replaceRisk: "shadows-shipped-ui"`.

**Best models to copy:**
- **Simplest** — `BashRow`: one `register`, delegates to shared `ToolRow` chrome.
- **Two keys, one component** — `FileMutationRow` (the generator form).
- **Interactive** — `AskQuestionRow`, and `CordisRunRow` for the full treatment
  (service-backed `inject` face, `useEffect`, child-slot declaration).
- **Rich content** — `GenericToolCard`, which shows how to consume all six card models.

Rich UI that exists **today**: terminal card (cwd-headed, live output), inline diff card,
syntax-highlighted line-numbered read card, search results card, web card, todo/plan strip,
and the nested sub-call tree. Diff and terminal rendering are driven by the host's
`presentCall`/`presentResult`, not hardcoded per tool name.

### Explicit negatives

- **`dsh-agent-tool-presentation` is NOT tool UI.** Despite the name, it is agent-plane:
  `ctx.tools.presentAs('native' | 'code' | 'both')` selects which *form of tool the model
  sees* (native tool-calling vs Code Mode). Nothing to do with rendering.
  (`dsh-agent-tool-presentation/lib/index.js`, whole file, 51 lines.)
- **`dsh-client-ui-deliverables`, `dsh-client-ui-goal`, `dsh-client-ui-plan`,
  `dsh-client-ui-jobs`, `dsh-client-ui-subagent` register NO `tool.call.toolview` entry.**
  A grep across all `*/lib/*.js` for `tool.call.toolview` returns only ui-tool, ui-skill,
  ui-cordis, cordis-client-runner (catalog data), and client-connection. Those packages are
  panels/docks on other slots, not tool views.
- **`plan-summary` is not a plan UI.** It is a pure derivation helper for the `todo_write`
  row's one-line summary — counts plus active-item text
  (`dsh-client-ui-tool/lib/types/client/tool/toolviews/plan-summary.d.ts`,
  used at `client.js:1482`).
- **`tool.view.cordis` has `occupants: []`** — no shipped component uses it. There is no
  working in-repo example of layer C to copy; only the catalog's 6-line `example` stub.

---

## 6. Persistence and re-render on reload

**Tool calls and results: yes, fully persisted and re-rendered.** They are session events
(`tool/call`, `tool/result`, plus `tool/code` for sub-calls) in the JSONL session log
(`dsh-session-persistence-jsonl`), replayed through the conversation projection into
`ConversationNode`s on load. `ToolResultNode` carries `seq`/`time` and is part of the
durable `ConversationNode` union (`conversation.d.ts:260`). A registered toolview
re-renders identically after reload — it is a pure function of `block`.

Caveat: window truncation. `ToolResultNode.call` is `null` when the paired `tool/call` fell
outside the loaded window (the card head then shows `callId`), and `callTime` is likewise
`null`. A custom view must handle `block.call === null`.

**Layer B renderer state: not persisted.** A toolview is an ordinary React component; local
`useState` is lost on reload. Durable state must live in the tool's own result payload
(`content` / `meta`). The slot system also offers a `store?: H` seat on `register`
(`dsh-client-ui-slots/lib/types/index.d.ts`, `BaseOptions`) — a shared apply-constructed
handle or a per-entry factory. INFERRED that it is page-lifetime rather than disk-backed;
its persistence semantics were not investigated, so do not rely on this either way.

**Layer C1 (dynamic package → `tool.call.toolview`): renders on every call, but dies with
the page.** Two separate lifetimes matter and are easy to conflate:

1. *Within a page session*, the registration is ordinary. Dynamic packages "ride the exact
   machinery static plugins do (activation gating on inject, fiber-effect cleanup, status
   projection)" (`dsh-cordis-client-runner/lib/client.js:358-363`). So a C1 registration
   renders **every** call of that tool name in the transcript, including scroll-back and
   calls that happened *before* the package loaded — it is a keyed dispatch, not tied to
   the `cordis_run` card that created it. Unload = loader entry removal, and "fiber
   disposal cascades slot entries and facade effects" (`:361-363`), triggered by
   `retract(pluginId, pluginRunId)` (`runtime.d.ts:201`) on a stop or undefine.

2. *Across a refresh*, it is gone — deliberately
   (`dsh-cordis-client-runner/lib/client.js:3911-3915`):

   > Nothing loads on activation: this page holds no dynamic package until a dispatch
   > arrives, and a dispatch only follows a model `cordis_run` or a user pressing a card's
   > start control. **A refresh therefore starts clean by design** — host process memory
   > still holds the definition, the page simply does not run it until asked again.

   `isLoaded` is documented as "page-local truth, never the host's 'it is running'"
   (`:463-465`). After reload the tool calls still render — via the shipped keyed view or
   `GenericToolCard` — but the agent-authored view is absent until another `cordis_run`.

**Layer C2 (`tool.view.cordis`): far more ephemeral — run-bound and latest-card-only.**

`tool.view.cordis` renders only while the plugin run is live. From `CordisRunRow`
(`dsh-client-ui-cordis/lib/client.js:495`):

```js
const showBusiness = reading === "running" && key !== null;
```

`reading` resolves through a precedence chain (`client.js:491`):
`removed → superseded → awaiting-approval → failed → cordisVisibleStatus(...) → idle`.
And supersession (`client.js:488`):

```js
const superseded = pointer !== void 0 && pointer.callId !== callId && pointer.seq >= (card.seq ?? -1);
```

Consequences:
1. Only the **latest** `cordis_run` card for a given `(pluginId, packageId)` shows the UI;
   older cards render a "superseded" message instead.
2. The UI shows **only** while status is `running`. Once the run settles, the region is
   replaced by a status label.

So `tool.view.cordis` is a **live control panel bound to an active plugin run**, not
durable inline generative UI. Scrolling back through history will not show a working
widget from an earlier turn — and unlike C1, it does not even render other calls of the
same tool while the package is loaded.

On reload it does not come back on its own: per the load-engine doc above, a refresh loads
no dynamic package until a new `cordis_run` dispatch. (This corrects an earlier inference
that a still-running host half would re-register automatically; the page is the gate, not
the host's run status.)

---

## 7. Recommended path for "generative UI inline in the thread"

Ranked by durability, which is the axis that actually differentiates them:

1. **Implement `presentCall`/`presentResult` on your host tool.** Zero client code, rides
   the shipped `GenericToolCard`, fully durable, survives reload. Ceiling is the six-card
   vocabulary. Do this first regardless of what else you do.

2. **Ship a client plugin registering `tool.call.toolview` with `key: '<your tool>'`.**
   Arbitrary React, fully durable (pure function of the persisted `block`), interactive
   within the sanctioned surface (`openFile`, `inspect`, `inputActions`, snapshot hooks).
   Requires a build-time package in the composition. **This is the right answer for a tool
   you own and want to look good permanently.** Put structured payload in the result's
   `meta`, render from it.

3. **`cordis_define` + `tool.view.cordis` with `key: 'self'`.** The only path where the
   *agent itself* authors the component at runtime, and the only one with `host.call` RPC.
   Genuinely interactive. But: ephemeral (running-run only, latest card only), no shipped
   example, `React.createElement` with no JSX, and it is arbitrary code execution in the
   client. Right for a live control panel; wrong for a durable artifact in the transcript.

A durable-plus-interactive combination would be #2 for the persistent rendering, with the
component reading structured state the host tool wrote into `meta` — reserving #3 for
genuinely live control surfaces.

---

## 8. Verification status

**Verified by reading shipped files:** the `tool.call.toolview` declaration and its owner
props; the `register`/`inject` call shape and all 15 built-in key registrations; the
`GenericToolCard` fallback dispatch at `client.js:888`; `ToolCallBlock` / `RunningToolCall`
/ `ToolResultNode` field-by-field; `argsRaw` assigned whole from the `tool/call` event at
`ui-conversation/lib/client.js:8337`; the separate streaming accumulator at `:7326-7332`;
the `presentation.d.ts` view vocabulary; the `showBusiness` / `superseded` predicates at
`ui-cordis/lib/client.js:488,495`; the closure symbol surface at
`cordis-client-runner/lib/client.js:3534-3563`; the guard's whitelist doc.

**From the harness's own slot catalog (shipped data, not independently re-derived):** the
standard-props list, `keyDomain`, `occupants`, `replaceRisk`, and all `source:` repo paths.

**INFERRED, flagged in place:** that a layer-B toolview can reach `ctx.remote.*` by closure
capture (§4); that a still-running dynamic package re-registers its control panel on reload
(§6).

**Not investigated:** the `store?: H` seat's full semantics; `dsh-client-ui-trajectory`'s
separate tool rendering (`trajectory-tool-definition.d.ts`) — it is a distinct table/timeline
surface with its own definitions and does not use `tool.call.toolview`; `ToolEventView`;
`conversation.details.tool` beyond its documented single-occupant contract.
