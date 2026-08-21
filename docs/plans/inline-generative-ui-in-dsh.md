# Inline generative UI in the dsh conversation thread — research and plan 2026-08-22

**Status:** research complete, decisions proposed (not yet ratified by the user).
Sibling of [arxa-harness-and-distribution.md](arxa-harness-and-distribution.md);
this plan lands in `arxa-studio` as a new plugin, under the same
depend-don't-fork law (decision 2 of that plan — no dsh fork, ever).

**Evidence:** five research passes on 2026-08-21/22 — three reading the
installed dsh tree (`~/.dsh/profiles/node_modules/@deepseek-ai/`, v0.1.0-rc.7),
two on the public web. Full reports are committed alongside this plan in
[`implementation/inline-gen-ui-evidence/`](implementation/inline-gen-ui-evidence/)
— `research-slots.md` (+ `slots.json`, the machine-readable dump of all 42
slots), `research-tool-ui.md`, `research-host-api.md`, `research-protocols.md`,
`research-sandboxing.md`. They carry the source URLs and the file:line refs
behind every decision below.
Advisor consulted before synthesis; its framing question ("keyed registry or
hardcoded switch?") drove the investigation and is answered in section B.

---

## A. Scope

1. **The ask:** an agent's work should be able to render as a **live,
   interactive component inside the conversation thread** — not a wall of
   text, not a side panel. For arxa specifically, the motivating cases are
   design/lens output (a viewport ladder, a diff of a widget tree, a
   pick-one-of-these choice) that today degrade to prose or force a jump to
   the design panel.

2. **Out of scope here:** the existing `arxa-design-panel` overlay (that is a
   dock, not inline), and any change to appbox engine verbs. This plan covers
   the *harness rendering seam* only.

---

## B. What dsh actually provides — the seam is real

The load-bearing question was whether the message stream is extensible or a
closed switch. **It is extensible, by a typed keyed-slot registry.** Verified
at the dispatch site, not from doc strings.

3. **`ctx.slots` is the whole extension model.** 42 slots ship in
   `0.1.0-rc.7`, catalogued in
   `dsh-cordis-client-runner/lib/client.js:2119-3510`. A completeness sweep
   (every `renderSlot(...)` call across all 10 rendering packages, diffed
   against the catalogue) found **zero uncatalogued slots** — the catalogue is
   the true contract.

4. **Per-message dispatch is keyed on the node kind**, one `renderSlot` call
   per node inside the memoised flow row —
   `dsh-client-ui-conversation/lib/client.js:5270`:

   ```js
   renderSlot("conversation.chat.node", routedOwner, {
     entryKey: routedNode.kind,    // keyed dispatch
     hookContext: nodeKey,         // per-message hook identity
     fallback: jsx(JsonBlock, {…}) // unknown kinds degrade, never crash
   })
   ```

5. **The four seats that matter**, of the 42:

   | slot | kind | notes |
   |---|---|---|
   | `tool.call.toolview` | keyed by **wire tool name** | one tool's card inside a turn. **The seat.** |
   | `conversation.chat.node` | keyed by node kind | the entire body of one flow node |
   | `conversation.chat.assistant-actions` | **additive** | the only additive per-message seat (action icons) |
   | `tool.view.cordis` | keyed `self` | interactive region in a *live* `cordis_run` card |

6. **Three layers decide how a tool call renders.** Conflating them is the
   main hazard, so they are named separately throughout this plan:

   | | who authors | expressive ceiling | durable? |
   |---|---|---|---|
   | **A. Host present** — `ToolDefinition.presentCall`/`presentResult` | tool author | fixed 6-arm vocabulary (generic/terminal/diff/search/read/web) | yes |
   | **B. Client toolview** — `tool.call.toolview` | client plugin, build time | arbitrary React | **yes** |
   | **C. Dynamic package** — `cordis_define` + `tool.view.cordis` | **the agent, at runtime** | arbitrary React + host RPC | **no** |

7. **Registration shape** — identical to the `settings.plugin.item` card
   already shipped in `arxa-design-panel`, so this is in-contract for us:

   ```js
   ctx.slots.inject('tool.call.toolview', () => ctx.slots.register(
     { name: 'tool.call.toolview', key: '<wire tool name>' },
     Component,
   ))
   ```

   Key domain is open: a typo simply never renders. An unclaimed key falls back
   to the generic tool row, so registering for **our own** tool is purely
   additive; registering for a shipped key (`bash`, `edit`, …) is a takeover
   (`replaceRisk: "shadows-shipped-ui"`) and is **not** proposed here.

8. **Durability — the axis that decides the design.** Tool calls and results
   are session events in the JSONL log, replayed through the conversation
   projection on load. A layer-B toolview is a **pure function of the persisted
   block**, so it re-renders identically forever. Layer C does not: the
   region shows only while `reading === "running"`, and only on the **latest**
   card per `(pluginId, packageId)` — older cards render "superseded"
   (`dsh-client-ui-cordis/lib/client.js:488,495`). Layer C is a **live control
   panel**, not a durable artifact.

9. **Renderer-local `useState` is never persisted.** Durable state must live in
   the tool result payload (`content` / `structuredContent`). A custom view
   must also handle `block.call === null` — the paired call can fall outside a
   truncated window.

10. **Interactivity, and the real back-channel.** Layer B's owner props carry
    no RPC handle by design ("the view stays a pure function of what the turn
    already knows"); sanctioned interactions are `openFile`, `inspect`,
    `inputActions` (drive the composer) and the session snapshot hooks. But
    **`ctx.connection.rpc.handle(channel, handler, { authority })`** is a
    generic, plugin-usable, codegen-free RPC registry
    (`dsh-client-connection/lib/types/rpc.d.ts:15-23`), with
    `ctx.connection.rpc.call(channel, endpoint, payload)` on the browser side.
    It is **not mentioned in any README** — found in the shipped types.
    `authority` is `'trusted-host' | 'loopback'`, which meshes with the
    loopback-classifier patch arxa already carries.

11. **Two more host facts.** `ctx.webServer.register({ kind: 'prefix', path })`
    lets a plugin serve its own routes (needed for an iframe origin);
    `ctx.connection.api.*` is **closed** — a plugin cannot add namespaces
    there, which is why decision 10's channel matters.

12. **Explicit negatives, recorded so nobody re-derives them.**
    `dsh-agent-tool-presentation` is agent-plane (which tool form the *model*
    sees), not UI. `dsh-client-ui-deliverables` / `-goal` / `-plan` / `-jobs` /
    `-subagent` register **no** toolview — they are docks on other slots, so
    "deliverables" is not an artifact store we can reuse. `tool.view.cordis`
    has **zero shipped occupants** — there is no working layer-C example to
    copy, only a 6-line catalogue stub.

---

## C. What the industry settled on — MCP Apps

13. **MCP Apps (SEP-1865) is the standard, and it is Final.** Verified
    first-hand against
    `modelcontextprotocol.io/seps/1865-…` (Status: **Final**, Extensions
    Track, created 2025-11-21). It absorbed the community MCP-UI project
    (Postman, Hugging Face, Shopify, Goose, ElevenLabs) plus lessons from
    OpenAI's Apps SDK, and shipped as MCP's **first official extension**;
    the 2026-07-28 core revision makes extensions first-class with MCP Apps
    as a flagship. (An adopter list circulates with the announcement; it is
    secondary sourcing and no decision here leans on it. The **spec status** is
    what this plan rests on, and that was verified first-hand.)

14. **Its shape, in one paragraph.** A server publishes a UI resource under
    `ui://` with MIME `text/html;profile=mcp-app`; a tool points at it via
    `_meta.ui.resourceUri`. The host can enumerate, review and cache every
    template *before* any tool runs. At render time the host puts the HTML in
    a sandboxed iframe and opens **JSON-RPC 2.0 over `postMessage`** — so every
    UI-initiated action is auditable exactly like a model-initiated tool call.
    v1 is **raw HTML only**; external-URL and remote-DOM content types are
    explicitly deferred.

15. **Three distinct feedback channels — do not conflate them.** This is the
    design lesson worth importing wholesale:
    `tools/call` (the widget invokes a real tool — gated and validated like any
    other), `ui/message` (submits a real new **user turn**), and
    `ui/update-model-context` (silent, out-of-band, no visible turn). Treating
    "user clicked a button" as a synthetic user message is precisely what
    corrupts transcript replay later.

16. **dsh is not an MCP Apps host, and the gap is small and specific.**
    `dsh-mcp-client` (MCP SDK `^1.12.0`) maps remote tools onto `defineTool` at
    `dsh-mcp-client/lib/index.js:158` — passing `tool.name`, `tool.description`,
    `tool.inputSchema`, `tool.outputSchema` and nothing else — and preserves
    `structuredContent` on the way back (`:262`, `:270`). But it **drops `_meta`
    entirely** and never lists or reads resources (grepped: no `_meta`, no
    `readResource`, no `resourceUri` anywhere in `lib/index.js`). No dsh bundle
    mentions `ui://` or `mcp-app`. So MCP Apps support is a **bridge
    extension**, not a rewrite.

---

## D. Isolation — what is proportionate

17. **For arxa today (localhost, single user, trusted operator): the
    component-catalogue approach for the majority of surfaces.** Validated JSON
    from the tool result rendered by *our own vetted React components* needs no
    iframe at all — there is no executable content to contain. It is also the
    only approach that streams cleanly and replays deterministically.

18. **Reserve iframe sandboxing for the genuine arbitrary-code case** (live
    preview of model-authored HTML/JS). Then: a **single** sandboxed iframe,
    `sandbox="allow-scripts"` **without** `allow-same-origin`, strict CSP
    (`default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline';
    img-src data:; connect-src 'none'`). The double-iframe "sandbox proxy" MCP
    Apps specifies is for multi-tenant hosts and is **not** needed yet.

19. **`allow-scripts` + `allow-same-origin` on same-origin content silently
    means no sandbox at all.** The single most common real-world mistake in
    this area; called out by MDN and web.dev. Written down here so it cannot be
    reintroduced by a well-meaning "it wasn't working so I added the flag".

20. **A capability bridge is invisible to CSP.** Claude Desktop's Cowork
    artifacts demonstrate it in production: `connect-src 'none'` blocks network
    exfiltration but not the injected IPC object. Any bridge we expose must be
    a narrow, logged, explicit method allowlist — never a generic "call
    anything". Same lesson applies to `host.call` in layer C, whose own guard
    doc is blunt: *"API discipline, not a security boundary"* — a dynamic
    package is as trusted as the process that accepted it.

21. **Shared origin across trust boundaries is a covert channel** (all Cowork
    artifacts share one origin, hence one `localStorage`). Irrelevant at one
    user; the first thing to fix if arxa ever serves more than one.

---

## E. The plan — four stages, each shippable alone

22. **Stage 1 — present-only, zero client code.** Give the arxa tool an
    `output.schema` and implement `presentCall`/`presentResult` so it rides the
    shipped `GenericToolCard`. Durable, replay-safe, no bundle. This is the
    floor: worth doing regardless of everything below, and it is what renders
    if the client plugin is ever absent.

23. **Stage 2 — the real seat: an `arxa-gen-ui` client plugin registering
    `tool.call.toolview` keyed to our own tool.** Renders a **fixed catalogue
    of vetted React components** selected and parameterised by the JSON the
    host tool put in `structuredContent`. Durable by construction (pure
    function of the persisted block). Handle `block.call === null`. Start the
    catalogue at three components, driven by real arxa need — a viewport
    ladder, a choice/confirm row, a structured diff — not a speculative
    framework.

24. **Stage 3 — interaction, over an explicit channel.** Host half calls
    `ctx.connection.rpc.handle('arxa/gen-ui', handler, { authority: 'loopback' })`;
    the component calls `ctx.connection.rpc.call(...)`.

    **`'loopback'` is correct, and it works only because arxa already patches
    the classifier — verified, not assumed.** `authority: 'loopback'` resolves
    to an empty trusted-host list (`dsh-client-connection/lib/index.js:243`,
    and `:237` for the intercept path), which funnels into
    `isLoopbackHostname(hostUrl.hostname)` at `:189`. That is **the same
    predicate at `:100-101`** which `arxa-studio/bin/loopback-localhost-patch.mjs`
    widens to accept `*.localhost`. So under `arxa.studio.localhost:7891` a
    `'loopback'` channel is reachable in arxa and would 403 on stock dsh. Two
    consequences to hold: the patch is now load-bearing for a **second**
    feature, so its fail-loud needle check must never be softened; and if that
    patch is ever retired, this channel must move to `'trusted-host'` in the
    same change.

    Adopt MCP Apps'
    three-way split verbatim (decision 15): a real tool call, a real user turn,
    or a silent context update — chosen per action, never blurred. Every
    handler method is an allowlisted verb (decision 20).

25. **Stage 4 — become an MCP Apps host.** Extend the MCP bridge to (a) keep
    `_meta` on bridged tools, (b) read `ui://` resources, and (c) register one
    generic toolview per UI-declaring MCP tool that renders the HTML in the
    sandboxed iframe of decision 18 with the JSON-RPC-over-postMessage bridge.
    Payoff: **any** MCP App server works in arxa, with no arxa-specific code —
    and arxa gets standards credit rather than a bespoke dialect. Sequenced
    last because it is the only stage with an external moving target.

26. **Not proposed: layer C (`cordis_define`).** It is the only path where the
    *agent itself* authors the component, which is seductive and is the literal
    reading of "generative UI". It is rejected for the durable case on
    evidence: ephemeral by design (decision 8), zero shipped examples, no JSX,
    and arbitrary code execution in the client. Revisit **only** for a genuine
    live control panel bound to a running job — where its lifetime is a feature
    rather than a defect.

---

## F. Open questions for ratification

27. Which three components seed the Stage 2 catalogue? (Proposed: viewport
    ladder, choice/confirm row, structured diff.)
28. Does arxa want Stage 4 at all, or is standards-compatibility a distraction
    from the appbox/lens work? Stage 4 is the largest and the only one with an
    upstream dependency.
29. Layer B's `store?: H` seat on `register` was not investigated; it is
    page-lifetime, not disk, so it does not change decision 9 — but it may
    simplify sharing one handle across many cards.
