# dsh client slot registry — full enumeration

Sources (all primary, installed tree; `~/.dsh/profiles/node_modules/@deepseek-ai/` symlinks into
`~/.npm/_npx/1e7f6d9597241db0/node_modules/@deepseek-ai/`):

- `dsh-cordis-client-runner/lib/client.js:2119-3510` — `//#region lib/types/client/slot-catalog.js`,
  `const CLIENT_SLOT_API = [...]`, **42 entries**, "Every slot the shipped web bundle declares, sorted by key."
- `dsh-cordis-client-runner/lib/client.js:1306-1326` — the `slots` **service** catalog entry (`register` / `inject` contract).
- `dsh-client-ui-slots/README.md`, `dsh-client-ui-slots/lib/index.js`, `dsh-client-ui-slots/lib/types/index.d.ts` — the pure core.
- `dsh-client-ui-conversation/lib/client.js` — the render sites.

Machine-readable dump of all 42 records: `./slots.json` (same directory as this file).

### Completeness — verified, not assumed

"Every slot the shipped web bundle declares" is the catalog's self-description, so I checked it
against the actual render sites across **all** packages rather than trusting the blurb:

```
grep -rhoE 'renderSlot(Chain)?\("[^"]+"' */lib/client.js | grep -oE '"[^"]+"' | tr -d '"' | sort -u
comm -23 rendered.txt catalogued.txt      # rendered but NOT in the catalog
```

**Result: empty.** 41 distinct slot names are dispatched across the 10 packages containing
`renderSlot` (runtime, ui-conversation, ui-cordis, ui-layout, ui-settings-general,
ui-settings-plugins, ui-sidebar, ui-tool, ui-workspace, cordis-client-runner); every one is in the
catalog. A second sweep over `name: "…"` strings in `slots.register` calls likewise found no
uncatalogued slot.

The single catalogued-but-not-`renderSlot`ed key is `root`, which is expected: it is rendered by a
*separate* ctx-level entry, `ctx.slots.renderSlot('root')`, which explicitly rejects every other key
— `dsh-client-runtime/lib/client.js:155`: ``ctx-level renderSlot only renders 'root' (got "${key}");
child slots render through the component props face``. The shell boot calls it after
`ctx.slots.install(createSlotRenderer())`, and an unregistered `root` renders a `data-slot-error`
div rather than a blank (`dsh-client-web-react/lib/index.js:715-722`).

So the enumeration below is complete for the installed bundle (`0.1.0-rc.7`).

---

## 0. PRIORITY ANSWER — the stream is extensible at the NODE level, closed at the PART level

The question "hardcoded switch or registry?" has **two different answers at two different depths**,
and conflating them is the trap. Both were verified by reading the code path, not the `doc:` strings.

| depth | mechanism | verdict |
|---|---|---|
| which component renders one message / flow node | `renderSlot(…, { entryKey: node.kind })` → registry `.find()` | **(b) REGISTRY — open** |
| which component renders one tool call inside a message | `renderSlot("tool.call.toolview", …)` → registry `.find()` | **(b) REGISTRY — open** |
| **which component renders one content block inside a message body** | **`switch (block.kind)`, hardcoded** | **(a) CLOSED SWITCH** |

### (b) The node level IS a registry — proof

Dispatch site, `dsh-client-ui-conversation/lib/client.js:5270`:
```js
children: renderSlot("conversation.chat.node", routedOwner, {
  entryKey: routedNode.kind,   // :5271
  hookContext: nodeKey,
  fallback: jsx(JsonBlock, { label: t("message.unknownSurface", …) })
})
```
Lookup implementation, `dsh-client-web-react/lib/index.js:666-668` — a real registry index, no switch:
```js
const entry = host.entriesOfSlot(slotKey).find((e) => e.options.key === opts?.entryKey);
if (!entry) return entries.some((e) => e.options.key === opts?.entryKey)
  ? deadCell()
  : jsx(Fragment, { children: opts?.fallback ?? null });
return guarded(entry, entryKeyOf(entry));
```
`entriesOfSlot` (`dsh-client-ui-slots/lib/index.js:180-195`) projects the registered entries to one
shadowing winner per cell (`kind === "keyed" ? entry.options.key : …`).

Same pattern one level down for tool cards — `dsh-client-ui-tool/lib/client.js:887`:
```js
children: [renderSlot("tool.call.toolview", owner, { entryKey: toolName, … })
```

**Third parties already use this.** Three packages outside ui-conversation own a message kind:
`dsh-client-ui-tool/lib/client.js:1603` (`key: "tool-call"`),
`dsh-client-ui-goal/lib/client.js:388` (`key: "command-input"`),
`dsh-client-ui-workflow-run/lib/client.js:459` (`key: "workflow-run"`). The ui-tool registration also
*declares its own child slot* in the same call (`children: { "tool.call.toolview": { kind: "keyed",
scope: "session" } }`), so an outside package can both occupy a message kind and open a new
extension point beneath it. This is not theoretical extensibility.

### (a) The part/block level is a CLOSED SWITCH — proof

`AssistantMarkdown`, `dsh-client-ui-conversation/lib/client.js:9059-9120`. It receives `blocks` and
walks them in a `for` loop with a hardcoded `switch` at **line 9071**:

```js
for (let i = 0; i < blocks.length; i++) {
  const block = blocks[i];
  if (block === void 0) continue;
  switch (block.kind) {                                    // :9071
    case "text":      rendered.push(jsx(MarkdownText, { text: block.text, streaming, … }, i)); break;
    case "reasoning": rendered.push(jsx(ReasoningRow,  { text: block.text, running: streaming && i === last, t }, i)); break;
    case "image": {   /* greedily groups adjacent images */ rendered.push(jsx(ImageGallery, { images: group, … }, start)); break; }
    case "tool-call": break;                               // skipped, handled by the node level
    default:          rendered.push(jsx(JsonBlock, { label: t("message.unknownBlock"), payload: block.block, … }, i));
  }
}
```

`grep -c renderSlot` over lines 9050-9130 returns **0**. No slot, no registry, no injection point is
consulted while walking a message's blocks. An unrecognized `block.kind` falls to `default` and is
dumped as a raw JSON block labelled `message.unknownBlock` — it degrades visibly, but there is no
way to claim it.

Corroborating, the same closed shape appears in two more places:
- User messages: `contentParts()`, `dsh-client-ui-conversation/lib/client.js:4942-4956` — an
  if/else chain on `b.type === "text"` / `b.type === "image"` with an `else rest.push(block)` bucket.
- Trajectory has its **own independent** `switch (block.kind)` at
  `dsh-client-ui-trajectory/lib/client.js:6594` and `:6959`, and contains **zero** `renderSlot` calls
  in the entire bundle.

### What this means for the design decision

- To add a **new content-block type** rendered inside an existing assistant message body: **not
  possible.** That is a closed switch in ui-conversation, duplicated in ui-trajectory. It requires an
  upstream change.
- To add **UI attached to a message** (a button in the action row, a panel under a turn): possible
  and additive — `conversation.chat.assistant-actions` (list) or `conversation.chat.turnTail` (chain).
- To **own how a whole message kind renders**: possible via `conversation.chat.node`, but all 15
  keys are occupied, so it is a takeover needing a lower `priority` (see §2).
- To render **arbitrary React in the thread area**: possible and unoccupied via `conversation.view`
  (list) — you own the whole stream, as Trajectory does.

### Secondary: does the keyed shape match `settings.plugin.item`?

**Yes — identical.** Both are `kind: "keyed"`, and every keyed slot takes the same options bag.
Real shipped call sites:

```js
// dsh-client-ui-settings-plugins/lib/client.js:1325
ctx.slots.register({ name: "settings.plugin.item",   key: SHELL_NS,      locale: NS, inject: () => bash.inject() }, BashCard)

// dsh-client-ui-tool/lib/client.js:1084
ctx.slots.register({ name: "tool.call.toolview",     key: "ask_user_question", locale: CONVERSATION_NS }, AskQuestionRow)

// dsh-client-ui-goal/lib/client.js:388
ctx.slots.register({ name: "conversation.chat.node", key: "command-input",     locale: NS }, GoalCommandInputView)
```

One correction to the question as posed: the shape is `{name, key}`, **not** `{name, id, key, order}`.
`id` and `order` are the **list**-kind fields and `key` is the **keyed**-kind field — they are
mutually exclusive per `KindOptions` (`dsh-client-ui-slots/lib/types/index.d.ts:378-402`). So a keyed
registration is `{name, key, priority?}` and a list registration is `{name, id, order?, label?, priority?}`.

Also note `locale:` — present in essentially every real call site (it puts the typed `t` seat on the
component props, `index.d.ts:65,428`) but **missing from the catalog's `registerOptions`**, which
lists only `id, order, label, key, select`. Treat the catalog's option list as incomplete.

So yes: building against `conversation.chat.node` / `tool.call.toolview` is the same proven
in-contract pattern as `settings.plugin.item`. Building a new *block type* is not.

---

## 1. Per-message slots — the seams that do exist

**Four slots render per-message or inside a message's body**, all declared by `client-ui-conversation`,
plus two more that render inside a message's tool card.

| slot | kind | additive? | render site |
|---|---|---|---|
| `conversation.chat.assistant-actions` | list | **ADDITIVE** | inside one finalized assistant message's IconActions row |
| `conversation.chat.node` | keyed | REPLACING per key | **the whole body of one flow node** |
| `conversation.chat.turnTail` | chain | single elected winner | inside the completed Turn node, before its IconActions |
| `conversation.chat.commandview` | keyed | REPLACING per key | one command row inside the chat flow |
| `tool.call.toolview` | keyed | REPLACING per key | one tool call's card inside a turn |
| `tool.view.cordis` | keyed | REPLACING per key | interactive region inside the latest `cordis_run` card |
| `conversation.view` | list | **ADDITIVE** | a whole view tab — you own and render the entire stream yourself (how Trajectory ships) |

A "flow node" is not always a message: the `conversation.chat.node` key domain also covers
`compaction`, `context`, `turn-error`, and `turn-tail`, which are flow structure rather than
messages. Per-*message* in the strict sense is `assistant-actions` (finalized assistant messages
only) and the `user` / `steering` / `assistant-step` keys of `chat.node`.

`conversation.view` is the escape hatch worth naming up front: registering a list entry there is
additive, needs no takeover, and gives you the whole scrolling area to render React into — at the
cost of reimplementing the message stream. `client-ui-trajectory` is the shipped proof it works.

**The one you want for "attach my React component to a message" is
`conversation.chat.assistant-actions`** — it is the only *additive* per-message seat, and its whole
documented purpose is exactly that: "contributors add per-message actions without importing the
conversation implementation."

### Proof of per-message dispatch

`dsh-client-ui-conversation/lib/client.js:5270` — inside the memoized flow-row component, one call per node:

```js
const node = useSession((snapshot) => snapshot.chat.nodes.get(nodeKey));   // :5240
...
return jsx("div", {
  className: ChatView_module_css.flowItem,
  "data-chat-anchor-key": routedNode.key,
  "data-chat-flow-kind": routedNode.kind,
  children: renderSlot("conversation.chat.node", routedOwner, {
    entryKey: routedNode.kind,      // :5271  <- keyed dispatch on the message kind
    hookContext: nodeKey,           // :5272  <- per-message hook identity
    fallback: jsx(JsonBlock, {...}) // unknown kinds degrade, never crash
  })
});
```

Other in-flow render sites in the same file:

- `:9267` `renderSlot("conversation.chat.commandview", ..., { entryKey: command.name ?? "" })`
- `:9322` `renderSlotChain("conversation.chat.turnTail", ...)`
- `:9333` `renderSlot("conversation.chat.assistant-actions", ...)`

Full list of `renderSlot` call sites in `dsh-client-ui-conversation/lib/client.js`:
`:3888` input.plan, `:3896` input.model, `:5270` chat.node, `:6879` hero.workspace, `:6894`
hero.agentPreset, `:6898` composer.bar, `:6911` input.overlay, `:6912` input.left, `:6913`
input.right, `:6914` composer.dock, `:6922` input.dock, `:6927` composer (chain), `:6943`
session.header, `:6946` session, `:7028` header.actions, `:7032` header.utilities, `:7077`
conversation.view, `:7200` details.tool, `:9267` chat.commandview, `:9322` chat.turnTail (chain),
`:9333` chat.assistant-actions.

---

## 2. The four slot KINDS — additive vs replacing, and ordering

From `dsh-client-ui-slots/lib/types/index.d.ts:378-402` (`KindOptions`) and
`lib/index.js:68-122` (the sort + occupancy check).

| kind | count | occupancy | register options |
|---|---|---|---|
| `single` | 19 | ONE occupant — the slot itself is the cell | `priority?` only |
| `list` | 16 | **ADDITIVE — many stack** | `id` (required), `order?`, `label?`, `priority?` |
| `keyed` | 5 | one occupant **per key**; unclaimed keys are additive | `key` (required), `priority?` |
| `chain` | 2 | selector election — exactly one winner renders | `select` (required), `priority?` |

### Ordering semantics

- **list** — `next.sort(...)` at `dsh-client-ui-slots/lib/index.js:122` sorts by
  `priority ?? 0` **then** `order ?? 0`, both ascending; ties keep registration (= plugin assembly) order.
  `order` defaults to 0. Owners can additionally filter with `only: '<id>'`
  (`RenderOpts.only`, `index.d.ts:194`) — that is how `conversation.view` renders one tab at a time.
- **chain** — entries tried at render time in ascending `priority` (default 0, lower tries first;
  ties keep registration order). First non-null `select(owner)` return elects that entry and arrives
  as the component's `matched` prop. All-null falls to the owner's `ChainRenderOpts.fallback`
  (`index.d.ts:214-222`). `select` MUST be pure — a function of owner props only.
- **keyed / single** — sorted by `priority` only; no positional ordering, the dispatch site picks.

### CORRECTION to the catalog's own registerOptions text

The catalog blurb says "Registering an already-occupied key replaces that occupant." That is the
plugin-facing simplification. The real contract in `SlotCore.register`
(`dsh-client-ui-slots/lib/types/index.d.ts:542-548`, enforced at `lib/index.js:68-84`) is:

> Entries sharing one cell (single — the slot itself; keyed — same `key`; list — same `id`) coexist
> at **distinct priorities**, sorted ascending, **the cell's lowest live entry renders**. A second
> registration at an occupied cell's **exact** priority (default 0) **throws**, naming the occupant.

So plain `{ key: 'user' }` against a shipped occupant **throws at load**, it does not silently
replace. To shadow shipped UI you must pass a *lower* `priority`. The thrown message is built at
`lib/index.js:69`: ``at priority ${priority} (registered by ${registrant}) — register at a different
priority to shadow it (lowest renders)``.

---

## 3. Registration API — exact shape

The `slots` cordis service (`dsh-cordis-client-runner/lib/client.js:1306-1326`) exposes two members.

```js
// canonical example, verbatim from every catalog entry's `example:` field
return {
  inject: ['slots'],
  apply(ctx) {
    ctx.slots.inject('conversation.chat.assistant-actions', () => ctx.slots.register(
      { name: 'conversation.chat.assistant-actions', id: 'my-entry', order: 100, label: 'My entry' },
      () => React.createElement('div', null, 'hello'),
    ))
  },
}
```

Per kind, the options bag second member changes:

- `single`: `{ name }`
- `list`: `{ name, id, order?, label? }`
- `keyed`: `{ name, key }`
- `chain`: `{ name, select: owner => matchOrNull }`

and every kind additionally accepts `priority?`, plus the universal `children?` (child-slot
declaration table), `store?` (store seat), `inject?` (business-face factory).

### `ctx.slots.inject(key, callback)`

Signature (`client.js:1314`): `inject(key: keyof SlotMap & string, callback: () => SlotInjectionEffect): () => void`

> "Install an effect for each **declaration lifetime** of a slot. The callback runs synchronously
> when the declaration already exists; otherwise it runs inside the declaring `register()` call
> after the declaration is committed. Collapse disposes the effect and a later declaration runs it
> again. Callback effects are synchronous disposers; iterable effects install transactionally and
> dispose in reverse order. The controller belongs to the caller's fiber, so plugin unload cancels a
> pending wait and removes any active contribution."

Returns an idempotent disposer. **`inject` is mandatory in practice for every chat slot**, because
`conversation.chat.*` is declared by an entry in `conversation.view`, which is declared by an entry
in `conversation.session`, … up to `root`. The slot literally does not exist until that ancestor
chain is mounted, so a bare `register` at plugin load would throw "undeclared slot". A generator
callback can `yield` several `register()` calls as one transaction (rollback on setup failure,
reverse-order teardown).

### `ctx.slots.register`

`declare readonly register: SlotCore['register']` — the typed face IS the core's register, both
overloads reused verbatim. The service layer adds: disposal through the caller's `ctx.effect` (fiber
unload = cascade), exclusive store-factory minting (`store: createXxxStore` → a per-entry handle),
the registrant diagnostics stamp, and store-instance lifecycle on the entry axis. It MUST stay a
prototype method — the cordis service proxy binds `this.ctx` to the *caller's* context at call time,
which is what routes per-plugin disposal.

### What `key` means

`key` is the **cell key of a `keyed` slot** — not a React key. "Your cell key: the entry renders
where the owner dispatches this exact key." For `conversation.chat.node` the dispatched value is
`ChatConversationViewNode.kind`; for `tool.call.toolview` it is the wire tool name; for
`conversation.chat.commandview` it is `command/run.name`. The `list` analogue is `id`
("a fresh id is added beside the shipped entries, while reusing a shipped id puts you in THAT cell").

---

## 4. Props a registered component receives — the four shares

`dsh-client-ui-slots/README.md` + `index.d.ts:186-190` (`PropsRuntime`). Composed props are the
**intersection of four shares**, checked at the `register` call site:

| share | type | source |
|---|---|---|
| runtime | `PropsRuntime<K>` | the `owner` object from the parent's `renderSlot` call site + the scope's standard kit + the global seat |
| child render | `PropsRenderSlots<S>` | the register call's `children` key set (a statically narrowed `renderSlot`) |
| store | `PropsStore<H>` | declared handle: `useStore` selector hook + draft-stripped `actions` |
| business | `I` | inferred from the `inject` factory's return |

### Standard kit by scope (identical within each scope across all 42 slots)

**`scope: 'session'` (21 slots, includes every `conversation.chat.*`)**
```
useSessions:   SnapshotSelectorHook<SessionListState>
useWorkspaces: SnapshotSelectorHook<WorkspaceListState>
useSession:    SnapshotSelectorHook<ConversationSnapshot>
sessionId:     SessionId
useProjection: UseProjection
useInput:      SnapshotSelectorHook<InputState>
inputActions:  InputActions
```

**`scope: 'session-maybe'` (2 slots: `conversation`, `conversation.composer.bar`)** — same seven
names, but `useSession`/`useInput` are `MaybeSnapshotSelectorHook` and `sessionId`/`inputActions`
are `| undefined`.

**`scope: 'root'` (19 slots)** — only `useSessions` and `useWorkspaces`.

Inject-factory params derive from the declaration (`InjectParams`): session slots get `sessionId`,
a declared store appends baked `actions`, nothing else — other data access lives in the apply
closure's `ctx`.

### Owner share for each per-message slot (the message data you can read)

**`conversation.chat.node`** — `ChatNodeOwnerProps`, plus `node: ChatNode<Kind>` merged in at the
render site (`client.js:5262-5265`, `routedOwner = { ...owner, node: routedNode }`):
```ts
export interface ChatNodeOwnerProps {
  selectedCallId?: CallId | undefined      // selected Tool call, when the details store names one
  cwd?: string | undefined                 // session workspace root
  openFile: (path: string) => void
  inspectCall: (callId: CallId) => void
  forkAt: (seq: number) => void
  loadImage: (attachment: ImageAttachmentRef) => Promise<string>
  fileMentions: (owner: TurnTailOwnerProps) => MarkdownFileMentions | undefined
}
```
Also carries `slotInject: ChatNodeTurnDataInjected` and `hookContext: string` (the node key).

**RESOLVED (was INFERRED).** The type name is source-only, but its runtime implementation is in the
bundle — `dsh-client-ui-conversation/lib/client.js:9470`:
```js
const CHAT_NODE_INJECT = { hooks: { turnData: ({ useSession }, nodeKey) => function useTurnData(key) {
  return useSession((snapshot) => {
    const location = snapshot.chat.nodes.get(nodeKey)?.location;
    return location?.kind === "turn" || location?.kind === "step" ? location.turn.data.get(key) : void 0;
  });
} } };
```
So a `conversation.chat.node` entry receives a `useTurnData(key)` hook that reads the owning Turn's
keyed data map off the snapshot, scoped to this node. Consumed at `:9130`
(`const tail = useTurnData("turn-tail")` inside `AssistantNodeView`). It is a **read-only data face,
not an extension point**.

**`conversation.chat.assistant-actions`** — the *only* message identity, nothing else:
```ts
export interface AssistantActionOwnerProps {
  messageId: MessageId   // stable identity carried from the `assistant/message` event
}
```
Doc note: "Only finalized messages reach this slot, so the id is always present." Getting from that
id to the message's content is **not documented** — see the INFERRED note in §8.

**`conversation.chat.turnTail`**:
```ts
export interface TurnTailOwnerProps {
  turn: TurnLocation                    // engine-owned closing Turn boundary
  seq: number                           // the closing assistant's seq — the tail's anchor
  openFile: (path: string) => void
}
```

**`conversation.chat.commandview`**:
```ts
export interface CommandRowOwnerProps {
  node: CommandNode                       // folded command lifecycle (run + optional done)
  compaction?: CompactionSummaryNode
}
```

**`tool.call.toolview`**:
```ts
export interface ToolCallOwnerProps {
  callId: string
  toolName: string
  block: ToolCallBlock                  // frozen running call or settled result node
  cwd?: string | undefined
  openFile: (path: string) => void
  inspect?: (() => void) | undefined
}
```

**`tool.view.cordis`**: `{ pluginId, packageId, pluginRunId }` (all readonly, branded ids).

---

## 5. Full slot table — all 42

`risk` = the catalog's `replaceRisk` field. `shadows-shipped-ui` means the cell already has a
shipped occupant. `declaredBy` decides which `ctx.slots.inject` wait you need.

### Conversation thread (session scope unless noted)

| slot | kind | risk | summary (trimmed) | declaredBy | occupants |
|---|---|---|---|---|---|
| `conversation` | single | shadows | "The whole center column, across both the no-session hero and a live conversation." (scope session-maybe) | entry in `root` (ui-layout) | ConversationRoot |
| `conversation.session` | single | shadows | "The entire body of one session: taking this seat means rendering that session's conversation yourself." | entry in `conversation` | ConversationSession |
| `conversation.session.header` | single | shadows | "The strip above the session's scrollport: title, view tabs, and the action row." | entry in `conversation` | ConversationSessionHeader |
| `conversation.session.header.actions` | list | none | "One button in the session header's action row — the additive way to put a per-session control beside the title without replacing the header." | entry in `…header` | agent-preset, job-list, subagent-catalog |
| `conversation.session.header.utilities` | list | none | "Right-aligned Session utilities kept outside the title-adjacent action group, so an optional utility cannot reorder session context or lineage." | entry in `…header` | session-log-download |
| `conversation.view` | list | none | "The conversation view ring: one list entry per view tab (chat here; trajectory/waterfall from ui-trajectory), rendered one-at-a-time by the session body via `only: <active id>`." | entry in `conversation.session` | ChatView id `chat`; TrajectoryView id `trajectory` |
| **`conversation.chat.node`** | keyed | shadows | "Final business node renderer, dispatched by `ChatConversationViewNode.kind`." | entry in `conversation.view` | 15 (see §6) |
| **`conversation.chat.turnTail`** | chain | none | "The completed Turn Node's extension chain, rendered before that Node's IconActions. Entries derive a match from the engine-owned Turn and closing seq before mounting, so presentation components never mount only to return null; an all-declined chain renders nothing." | entry in `conversation.chat.node` | ui-deliverables ProducedFiles |
| **`conversation.chat.assistant-actions`** | list | none | "Action strip attached to one finalized assistant message, rendered inside that message's IconActions row. The chat entry owns the render site and passes the addressed message identity; contributors add per-message actions without importing the conversation implementation. Entries render by ascending `order`." | entry in `conversation.chat.node` | ui-message-feedback MessageFeedbackActions id `feedback` |
| **`conversation.chat.commandview`** | keyed | none | "The chat view's per-command row hole: keyed dispatch on the command name (`command/run.name`…). The render site dispatches via `entryKey: name` with GenericCommandCard as the `fallback` — a slash command renders durably with zero registration, and a domain upgrades by registering one row component." | entry in `conversation.chat.node` | **none — key domain fully open** |
| `conversation.details.tool` | single | shadows | "The body of the details panel for the tool call the user selected — one occupant, so taking it means rendering every tool's output… A per-tool renderer belongs in the keyed `tool.call.toolview` seat instead; this one is the whole panel." | entry in `details` | ui-tool ToolDetails |

### Tool cards (inside the thread)

| slot | kind | risk | summary | declaredBy | occupants |
|---|---|---|---|---|---|
| `tool.call.toolview` | keyed | shadows | "Keyed atomic Tool call view, dispatched by the wire Tool name. Register with `key: '<tool name>'` to own how one tool's calls render inside a turn — the key domain is open… A key the shipped composition already covers is replaced, not shared; an unclaimed key falls back to the generic tool row, so registering is additive for your own tool and a takeover for a shipped one." | entry in `conversation.chat.node` (ui-tool) | 15 rows, keys: `ask_user_question bash cordis_define cordis_run cordis_stop cordis_undefine edit glob grep read skill todo_write web_fetch web_search write` |
| `tool.view.cordis` | keyed | none | "Interactive Package-owned region rendered inside the latest eligible `cordis_run` card in the conversation flow. Use it for controls and other UI the user can interact with. Dynamic Client code registers with `key: 'self'`; the Guard binds that key to the current Plugin and Package." | entry in `tool.call.toolview` (ui-cordis) | **none** |

### Composer / input

| slot | kind | risk | summary | occupants |
|---|---|---|---|---|
| `conversation.composer` | chain | none | "The composer takeover chain: entries are selector-routed replacements of the default InputBar." | ApprovalPanel; SubagentReadOnlyComposer; QuestionComposer |
| `conversation.composer.bar` | single | shadows | "The default composer body: a single slot rendered as the composer chain's fallback (a real entry, not a chain rider, so a takeover election hides rather than unmounts it and the textarea DOM survives)." (session-maybe) | InputBar |
| `conversation.composer.dock` | list | none | "The band under the composer card, inside the bar's width column — the seat for an ambient readout about the conversation (the shipped stats line lives here)." | StatsLine id `stats` |
| `conversation.input.dock` | list | none | "A full-width row of its own, stacked above the composer card — the seat for anything that needs a line to itself (queue rows, a todo strip, a goal bar)." | QueueDock `queue`; TodoDock `todo`; GoalDock `goal` |
| `conversation.input.left` | list | none | "The left end of the tool row INSIDE the composer card, after the resident chrome (access mode, plan, attach) — the seat for a small always-visible control." | **none** |
| `conversation.input.right` | list | none | "The right end of the same tool row, before the primary send button — the seat for a control the user reaches on the way to sending." | **none** |
| `conversation.input.overlay` | list | none | "The InputBar floating overlay anchor: MenuView (this package) and the popupSelect shell (ui-commands) contribute list entries; each reads its own store and renders null while closed." | PopupSelectView `command-popup`; MenuView `slash-menu` |
| `conversation.input.model` | single | shadows | "The named model-select seat at the right end of the composer tool row, left of the send button." | ModelSelect |
| `conversation.input.plan` | single | shadows | "The named plan-status seat in the composer tool row, immediately right of the access-mode control." | PlanChip |

### Hero (new-session screen, root scope)

`conversation.hero.workspace` (single, shadows) — the hero-phase Workspace picker hole ·
`conversation.hero.workspace.directoryFlow` (single, shadows; declared by the WorkspacePicker entry) ·
`conversation.hero.agentPreset` (single, shadows) — the agent-preset chip beside the workspace picker.

### Shell / sidebar / settings (all root scope)

| slot | kind | risk | summary |
|---|---|---|---|
| `root` | single | shadows | "The built-in render-tree root hole (seeded by SlotCore): the one slot the shell itself renders, and the ancestor of every other seat." declaredBy: the runtime itself, always present |
| `sidebar` | single | shadows | "The whole left column." |
| `details` | single | shadows | "The right details column, shown when the layout opens it." (session scope) |
| `shell.overlay` | list | none | "Frame-wide floating layer, above every column and outside their scroll containers." — **no occupants** |
| `sidebar.workspaces` | single | shadows | workspace/session browsing region |
| `sidebar.workspaces.directoryFlow` | single | shadows | directory-flow hole under the browsing region |
| `sidebar.settings` | single | shadows | the settings seat at the sidebar foot |
| `sidebar.footer.action` | list | none | "Optional actions beside Settings at the sidebar foot." — CordisPanel |
| `settings.trigger` | single | shadows | sidebar-foot trigger row content (icon + label) |
| `settings.header` | single | shadows | the panel title text seat |
| `settings.close` | single | shadows | the close button's visually-hidden label text |
| `settings.action` | list | none | actions in the content-column header before Close |
| `settings.section` | list | none | "One settings page per list entry." — 4 |
| `settings.general.item` | list | none | "One preference row inside the General section — the additive seat for a single setting that needs no page of its own." — 5 |
| `settings.plugins.tab` | list | none | "One page inside the Plugins settings section." — 2 |
| `settings.plugin.item` | keyed | none | "One plugin's card inside the plugin configuration section." — 3 |
| `settings.onboarding` | list | none | "Root-scoped onboarding steps contributed by settings features." — 2 |

---

## 6. `conversation.chat.node` key domain (the message kinds)

`keyDomain`: "fixed by the owner's key table `{ [Kind in ChatNodeKind]: { node: ChatNode<Kind> } }`" —
a **closed compile-time set**. Already taken (15 registrations, 15 keys):

| key | occupant |
|---|---|
| `user` | ui-conversation UserMessageNodeView |
| `steering` | ui-conversation UserMessageNodeView |
| `context` | ui-conversation ContextMessageNodeView |
| `assistant-step` | ui-conversation AssistantNodeView |
| `command` | ui-conversation CommandNodeView |
| `command-input` | **client-ui-goal** GoalCommandInputView |
| `compaction` | ui-conversation CompactionNodeView |
| `manual-compaction` | ui-conversation ManualCompactionNodeView |
| `model-retry` | ui-conversation RetryNodeView |
| `turn-error` | ui-conversation TurnErrorNodeView |
| `turn-max-tokens` | ui-conversation TurnMaxTokensNodeView |
| `turn-tail` | ui-conversation TurnTailNodeView |
| `tool-call` | **client-ui-tool** ToolCallTree |
| `workflow-run` | **client-ui-workflow-run** WorkflowRunPanel |
| `unknown` | ui-conversation UnknownNodeView |

Every key is occupied, so any `conversation.chat.node` registration is a takeover requiring a lower
`priority`. The precedent that a third-party package legitimately owns a kind is real:
`client-ui-goal`, `client-ui-tool`, and `client-ui-workflow-run` are separate packages holding
`command-input`, `tool-call`, and `workflow-run`.

---

## 7. Message list composition — does it consult a registry per message?

**Yes for the chat view; no for trajectory.**

- **`dsh-client-ui-conversation`** — the chat flow maps each node key to a memoized row component
  that calls `renderSlot("conversation.chat.node", …, { entryKey: node.kind, hookContext: nodeKey })`
  (`lib/client.js:5270`). So the registry is consulted **once per message**, and the dispatch key is
  the message kind. Nesting below that: the node entry declares `conversation.chat.turnTail`,
  `conversation.chat.assistant-actions`, and `conversation.chat.commandview` as its children; the
  `tool-call` node entry (owned by ui-tool) declares `tool.call.toolview`, which in turn declares
  `tool.view.cordis`.
- **`dsh-client-ui-trajectory`** — a whole alternative *view*, not a per-message hook. Its
  `package.json` describes it as a "pure-consumer plugin registering into the conversation ViewMap
  (no service)", and its README states it "registers target-specific Event Definitions, a Trajectory
  view builder, and **one tab in the conversation's `'conversation.view'` slot ring**." Its
  `lib/client.js` contains exactly one `slots.inject` + one `slots.register` pair. It renders its own
  virtualized ledger internally and declares **no child slots** — there is no per-record extension
  point in Trajectory.

---

## 8. Practical recipe (per-message React component)

Additive, no takeover, no throw. The module shape below is the catalog's own `example:` string
verbatim (a factory returning `{ inject, apply }`) with only the component body filled in:

```js
return {
  inject: ['slots'],
  apply(ctx) {
    ctx.slots.inject('conversation.chat.assistant-actions', () => ctx.slots.register(
      { name: 'conversation.chat.assistant-actions', id: 'my-badge', order: 50, label: 'My badge' },
      ({ messageId }) => React.createElement('button', { onClick: () => {/* … */} }, '★'),
    ))
  },
}
```

`label` accepts `string | (() => string)`; the thunk form is re-read on every projection, so
localized text follows the active locale without re-registering (`SlotLabel`, `index.d.ts:373`).

**INFERRED — how to get from `messageId` to message content.** The owner share hands you *only*
`messageId`. Reading the message body presumably goes through the standard kit's
`useSession(snapshot => …)`, by analogy with `conversation.chat.node`'s own row component, which does
`useSession((snapshot) => snapshot.chat.nodes.get(nodeKey))` at
`dsh-client-ui-conversation/lib/client.js:5240`. But that lookup is keyed by *node key*, not
`messageId`, and no shipped code or doc string demonstrates a `messageId` → content path. The one
occupant of this slot (`client-ui-message-feedback MessageFeedbackActions`) only needs the id to
submit feedback, so it does not settle the question. Verify against `ConversationSnapshot` before
relying on it.

If you need real estate *below* a completed turn rather than a button in its action row, use
`conversation.chat.turnTail` (chain) with a `select` that returns non-null only for the turns you
care about — but note only one chain entry wins, and `client-ui-deliverables ProducedFiles` is
already registered there.

If you need to own the full body of a message kind, that is `conversation.chat.node` with a lower
`priority` than the shipped occupant — flagged `replaceRisk: shadows-shipped-ui`.

---

## 9. Inferred / unverified

- `ChatNodeTurnDataInjected` — **no longer inferred**, resolved from its runtime implementation
  `CHAT_NODE_INJECT` at `dsh-client-ui-conversation/lib/client.js:9470`. See §4. (The *type name*
  still appears nowhere in shipped `.d.ts`; the *behaviour* is fully readable.)
- All `source:` paths in the catalog (e.g. `packages/client/ui-conversation/src/client/contract/slots.ts:78`)
  refer to the **upstream monorepo**, which is not present locally. Only the compiled bundles are
  installed; those paths are reported as-is from the catalog, not verified.
- The `dsh-client-ui-slots` and `dsh-cordis-client-runner` directories under
  `~/.dsh/profiles/node_modules/@deepseek-ai/` are **symlinks** into
  `~/.npm/_npx/1e7f6d9597241db0/node_modules/@deepseek-ai/`. Package version: `0.1.0-rc.7`.
