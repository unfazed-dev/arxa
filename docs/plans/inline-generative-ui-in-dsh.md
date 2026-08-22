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

16b. **Two neighbours worth naming, because they split the problem the way
    this plan does.**
    - **AG-UI** (https://github.com/ag-ui-protocol/ag-ui, docs at
      docs.ag-ui.com) — an **event-stream** protocol, no iframe anywhere:
      typed events drive the host's *own* native components. That is the right
      model for **first-party** tools, which are not untrusted and do not need
      containment.
    - **A2UI** (https://a2ui.org — Google, Apache 2.0, v0.9.1 current, v1.0
      candidate; verified first-hand) — a **declarative** spec answering
      "how can agents safely send rich UI across trust boundaries": the agent
      emits JSON naming components from a **pre-approved catalogue**, the
      client renders them with its own widgets, MIME
      `application/a2ui+json`. Explicitly *not* executable code, so there is no
      sandbox surface at all. Its JSON is deliberately **flat and streaming**
      so an LLM can build a UI incrementally rather than having to emit perfect
      JSON in one shot. Reference renderers exist for Angular, Flutter, Lit and
      Markdown — the Flutter one is of independent interest to appbox.

16c. **The synthesis: one lookup path, two renderers.** These are not
    competing choices to pick between, they are the two ends of a trust axis,
    and dsh's keyed toolview can host both:
    - **first-party arxa tools** → JSON → our own vetted React components,
      **no iframe** (AG-UI's model, A2UI's payload shape);
    - **third-party MCP App servers** → HTML → sandboxed iframe (decision 18).

    The constraint this puts on Stage 2 — and it costs nothing to honour now —
    is that the tool→UI **metadata shape** stays MCP-Apps-compatible, so the
    second renderer later drops into the *same* lookup rather than arriving as
    a second protocol bolted alongside the first.

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

    **Borrow A2UI's payload shape rather than inventing a dialect** (decision
    16b): components named from a pre-approved catalogue, flat streaming JSON
    so a half-emitted payload renders progressively instead of waiting on one
    perfect blob. Keep the tool→UI metadata MCP-Apps-compatible per decision
    16c. Both are free now, and they are the difference between Stage 4 being
    an addition and being a rewrite.

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

## G. Build log — stages 1–3 shipped 2026-08-22

30. **Shipped as `arxa-studio/plugins/gen-ui` (commit `6a753b8`).** One
    package, both halves. Host registers the `gen_ui` tool and the
    `/arxa-gen-ui` RPC channel; browser registers `tool.call.toolview` with
    `key: 'gen_ui'` and the five catalogue renderers. Wired as profile row 9
    and a `file:` dep in `bin/arxa.mjs`. `plugins/gen-ui/selftest.mjs` — 10
    assertions, all passing — covers schema compilation, envelope canonicality,
    catalogue rejection, and the RPC verbs.

31. **Corrections found by building, recorded so they are not re-derived.**
    - An RPC channel is **one URL path segment** — `/^\/[A-Za-z0-9._~-]+$/`,
      with `/api` reserved (`dsh-client-connection/lib/index.js:203,331`).
      `arxa/gen-ui` fails the profile at boot; `/arxa-gen-ui` is correct.
    - The wire form is `POST {channel}/{endpoint}` with a JSON envelope whose
      **`method` must equal the endpoint** (`rpcFetchHandler`, `:275-300`).
      The endpoint is in the path, not the body.
    - `inputActions` is **not** among a toolview's props. The session standard
      kit for this scope is exactly `useSession`, `sessionId`, `useProjection`
      (`dsh-client-runtime/lib/types/client/index.d.ts:64-90`); an earlier note
      claiming otherwise was wrong. A toolview cannot drive the composer, which
      is why the `Choice` card records rather than sends.
    - The durable payload seam is **`output.presentationMeta`**, which lands on
      `ToolResultNode.meta`. `output.render` feeds the model, not the UI —
      rendering from `content` would have re-parsed model-facing prose.

32. **Verified against the running server**, not just unit-stubbed: bundle
    served 200 with the keyed registration and all five renderers; `select`
    then `state` round-trips over the real channel; an unknown endpoint and
    bad args return clean errors.

    **Decision 24's claim tested at the real origin, not merely read in the
    source.** `Host: arxa.studio.localhost:7891` → **200**; bare
    `arxa.studio.localhost`, `localhost:7891` and `127.0.0.1:7891` → 200;
    `evil.example.com` → **403**. So the widened classifier does carry this
    channel at the name the browser actually sends, and the fence still
    refuses everything else.

32b. **The durability chain traced end to end**, because all of stage 2 rests
    on one hop: `output.presentationMeta` is projected **only when
    `exec.parent === undefined`** (`dsh-tools/lib/index.js:3417-3424`) → lands
    as `meta` on the `tool/result` event → `rootResult` reads
    `meta: match.event.data.meta` into `ToolResultNode.meta`
    (`dsh-client-ui-conversation/lib/client.js` ~:8349). The sub-call
    projection (`childResult`, ~:8381) sets **no meta at all** — so the
    "direct top-level calls" caveat in the type doc is literal. The browser
    half therefore falls back to rebuilding the surface from
    `block.call.argsRaw`, which the sub-call projection *does* populate;
    without that, a `gen_ui` dispatched as a sub-call would render an empty
    card while its running state looked correct.

32c. **Not verified: the React actually rendering.** Every stage-2 check above
    is host-side or a read of the served bytes; no component in `client.js`
    has executed in a browser. Two things to watch on first open:
    `RendererHost` invokes each renderer as a plain function, so `Choice`'s and
    `RungLadder`'s hooks attach to `RendererHost`'s fiber — fine while the
    component type per id is stable, and the running→settled transition
    (args-derived → meta-derived components) is exactly where it would not be.

33. **Streaming, settled by evidence.** A toolview **cannot** stream arguments:
    it does not exist until the model has finished emitting the call. So there
    is no partial-JSON renderer in the thread and none should be added. The
    running card instead draws from the complete `argsRaw`, which makes the
    surface appear before `execute` settles. Live *during-run* updates, if ever
    needed, come from `useProjection` (whole-value, never a delta — fine for
    coarse progress, wrong for token-level text) or from `subCalls`.

## G2. Stage 4 shipped 2026-08-22 — arxa is an MCP Apps host

40. **Shipped as `arxa-studio/plugins/mcp-apps` (commit `edd4fe1`),
    disabled by default.** Host half opens its own read-only MCP connection,
    discovers tools carrying `_meta.ui.resourceUri`, reads their `ui://`
    templates, and exposes them plus an audited `tools/call` proxy over
    `/arxa-mcp-apps`. Browser half renders each template in a sandboxed iframe
    and speaks JSON-RPC 2.0 over `postMessage`.

41. **Sibling, not a patch — and this forced the shape.** Decision 16 said the
    gap was small; building it showed it also dictates a **two-row** install.
    dsh's `dsh-mcp-client` is what registers the server's tools with the model
    and it drops `_meta` at the boundary, so it can never carry UI. Forking it
    is barred and load-time patching a React path was already rejected. So
    `arxa-mcp-apps` connects to the SAME server a second time purely to
    discover UI. **Both rows are required, and `serverName` must match** —
    the qualified name dsh builds (`mcp__<serverName>__<rawName>`) IS the slot
    key the renderer claims, so a mismatch silently renders nothing.

42. **Verified against a real MCP server, not a mock.**
    `plugins/mcp-apps/testserver.mjs` is a working MCP App server (a counter
    widget that calls back through `tools/call`), and `selftest.mjs` drives
    the host half against it over real stdio — 6 assertions, all passing:
    `_meta` survives, the `ui://` resource reads back, discovery
    **discriminates** (only the UI-declaring tool is claimed; the plain one is
    not), the CSP is deny-by-default, and the proxy refuses a tool the server
    never advertised. Then run live in the studio with both rows enabled:
    `mcp__arxatest__show_counter` discovered, template HTML served, and a live
    `tools/call` proxy returning `counter is 7`. The rows were restored to
    commented-out afterwards so a demo server does not permanently occupy the
    model's tool list.

43. **Isolation as built.** `sandbox="allow-scripts"` with **no**
    `allow-same-origin` (verified absent from the served bundle's code), a
    `srcdoc` opaque origin, and a CSP `<meta>` built **host-side** from the
    resource's declared metadata and injected into the template — a template
    cannot widen its own policy, and declaring one domain does not unlock the
    others. Single iframe, not the double-iframe sandbox proxy: that defends
    multi-tenant hosts, which this is not (decision 18 stands).

44. **Deliberately not wired: `ui/message` and `ui/update-model-context`.**
    Only `ui/initialize`, `ui/notifications/size-changed` and `tools/call` are
    answered; everything else gets a JSON-RPC error. Injecting a synthetic user
    turn from a widget click is the conflation decision 15 warns about, and it
    would need a composer seam a toolview does not have (see decision 31).

45. **Also untested in a browser** — same standing caveat as 32c. The
    postMessage bridge, the size-change clamp (80–720px) and the
    stream-identity guard have not executed. Enable the two rows and call
    `show_counter` to exercise them.

## H. The design panel — answered, and it is a build not a wire-up

34. **Can the design panel host generative UI? Yes, trivially** — it is our own
    React in `shell.overlay`; the same catalogue renderers drop straight in.

35. **Can it be live-streaming per rung? Not today, and the blocker is in
    appbox, not arxa.** `appbox design serve` has **no server→browser push
    channel of any kind** — verified absence, not an unchecked assumption: no
    `text/event-stream`, no `EventSource`, no `WebSocketTransformer` anywhere
    in `appboxd/lib` outside `cdp.dart` and `lens/` (which talk to Chrome, not
    to a client). Reload is server-side only: a file watcher
    (`design_server.dart:891-906`) debounces 200 ms into `_scheduleReload()`
    (`:867-875`) and re-imports the artifact modules cache-busted in the same
    Chrome tab (`worker.dart:799-811`). **The browser is never told.** The
    panel's "remount on demand" is not a limitation of the panel — it is the
    only mechanism that exists.

36. **Nor is there per-rung rendering.** One document per route; the client
    sizes it. Rungs are a client/capture-side concept. And every generator is
    produce-whole-then-return — there is no incremental emit path.

37. **The cheapest real fix, priced.** Add `GET /__events` to
    `design_server.dart`: a broadcast `StreamController` fanned to held-open
    `text/event-stream` responses, firing `reloaded` when
    `_reloadAndRefreshRoutes()` completes (`:885-889`). ~50 lines of Dart, no
    existing scaffolding to reuse. The panel then listens and re-navigates each
    rung iframe. **Mandatory detail:** a remount fired right after a write
    usually lands inside the 3800 ms reload grace window
    (`_kReloadGrace`, `:224`) and gets **HTTP 503** with the "reloading" page —
    so the panel must retry the 503 (~1 s backoff, up to ~4 s) or it will flash
    an error surface at the user on every save. Generation stays batch; the
    user perceives "live" because all rungs refresh together.

38. **Seams that already work, to build on rather than around:**
    `POST /__project_write` (`design_server.dart:381`, impl `:734`) is a
    working, path-traversal-safe single-file write whose watcher triggers the
    reload — this is the write half of the awaited `design patch` verb, which
    is therefore a thin CLI wrapper, not new infrastructure.
    `GET /__routes` (`:407`) gives the live route table after each reload.
    The `--json` ready-record (`:1041-1047`) makes spawn-and-wait deterministic.
    Per-rung view files (`*_view.mobile.tsx` / `.tablet.tsx` / `.desktop.tsx`)
    already give "generate per rung" an authoring shape.
    **Hazard:** shutdown stops every instance serving the same artifact
    (pidfile registry, `:992-996`) — a panel that spawns servers must scope by
    artifact + port.

39. **`kit/genui_bridge` already implements A2UI v0.9 in Dart** — envelope
    (`appbox_kit_a2ui_message.dart`, version pinned `v0.9`), a chunk-boundary-safe
    incremental parser tested down to one byte at a time, and OpenAI/Anthropic
    SSE adapters. It has **zero dependents**: nothing in `appboxd` imports it,
    and it lives in the `kit/` layer aimed at *generated Flutter apps rendering
    gen-UI at runtime*, not at the designer producing a design. Reusing it for
    the panel is a real port, not a wire-up — but it is why stage 2's payload
    was pinned to the same `v0.9` envelope: one vocabulary, already spoken on
    both sides.

## F. Open questions for ratification

27. Which three components seed the Stage 2 catalogue? (Proposed: viewport
    ladder, choice/confirm row, structured diff.)
28. Does arxa want Stage 4 at all, or is standards-compatibility a distraction
    from the appbox/lens work? Stage 4 is the largest and the only one with an
    upstream dependency.
29. Layer B's `store?: H` seat on `register` was not investigated; it is
    page-lifetime, not disk, so it does not change decision 9 — but it may
    simplify sharing one handle across many cards.

## G3. Build log — the design-server SSE and the guard it needed (commit `7c790b7b`)

Answers decision 38's "~50 lines of Dart" estimate. It was ~50 lines of stream
and ~230 lines of guard, because the stream could not be added honestly
without the guard: `/__events` is the design server's first deliberately
cross-origin endpoint, and opening it meant looking at what was already open.

46. **What was already open, proven not asserted.** A worktree at `e7ab16f5`
    was served on port 4332 and sent the attack any web page in any tab could
    send — a CORS *simple request* (`Content-Type: text/plain`, so no
    preflight ever asks the server's permission):

        POST /__project_write   Origin: https://evil.example
        -> 200 {"ok":true,"path":"PWNED.js"}

    The file landed in `~/.appbox/projects/portalo/` (deleted immediately
    after; the proof was run against a scratch artifact but `__project_write`
    is confined to the *project* dir, which is the live one). `GET /__projects`
    with `Host: evil.example.com` also answered 200 — the DNS-rebinding path.
    `_handleProjectWrite` decodes JSON regardless of content type, which is
    what makes the no-preflight form work. The written file is later imported
    by the worker.

47. **`appboxd/lib/design_server/browser_trust.dart`** — three layers, in the
    order a request meets them:
    * **Host allowlist**, every request, `421` on a miss. Loopback names
      (`localhost`, `127.0.0.0/8`, `::1`, and `*.localhost` per RFC 6761),
      the bound host, and `--trusted-host`. This is the CVE-2025-66414 defense
      (MCP TypeScript SDK, Dec 2025, fixed in `@modelcontextprotocol/sdk`
      1.24.0 — same shape, same server class).
    * **Fetch-metadata / Origin check**, `403`, on every state-changing method
      AND every `/__*` path whatever the method (the resource-isolation policy
      from OWASP's XS-Leaks sheet — `GET /__projects` enumerates ~/.appbox and
      has no business answering a cross-site page). Artifact files and the
      design's own GET routes stay unguarded so the panel iframe and a
      hand-typed `http://127.0.0.1:4319/` need zero configuration.
    * **CORS echo** of the one matched origin, `Vary: Origin`, never `*`, and
      `Access-Control-Allow-Credentials` never set at all.

48. **The port is compared for Origin and ignored for Host, deliberately.**
    Host: a rebinding attacker controls the *name*, never the port — the
    request already arrived on our socket — and an allowlist that treats
    `localhost` and `localhost:4319` as different names is mlflow #22095,
    where valid clients were rejected over a header form and the "fix" people
    reach for is disabling the check. Origin: `http://localhost:8888` is
    somebody else's dev server, and treating it as ours would make any local
    tool that renders untrusted HTML a springboard into this one.

49. **The fail-open is a decision, recorded in the code as one.** A request
    carrying neither `Sec-Fetch-Site` nor `Origin` is allowed. Both are
    forbidden header names — page JavaScript cannot set or remove them, and
    every browser since 2023 sends `Sec-Fetch-Site` — so "neither" means "not
    a browser", and a browser is the whole threat model on a loopback socket.
    The callers in that category are the CLI, the probe suite, lens and curl.
    OWASP says do not fail open on absent fetch metadata; that is written for
    a public server, where "no browser headers" means a scripted attacker. A
    token here would break every shipped caller to defend against local code
    that already has the filesystem.

50. **`GET /__events`**, answered ahead of everything that can touch the
    worker. It needs no worker, so it must not queue behind the reload gate —
    which dissolves decision 38's "the panel must retry the 503 inside the
    3800ms grace": there is no 503 to retry. `retry: 500` in the stream lets
    EventSource's own reconnect do the work, so no retry loop was written on
    either side. Frames go out only after `_routeTable` re-registers, so a
    subscriber that remounts on the signal cannot land in the 404 window that
    ordering exists to close.

51. **Two things about Dart's `HttpResponse` that a stream lives or dies on.**
    `bufferOutput = false` is mandatory: the default buffers until the buffer
    fills or the response closes, neither of which an event stream ever does,
    so the connection opens, stays open, and delivers nothing. And a dead peer
    is only surfaced as an error on `done` **by a write** — an idle held-open
    response never notices the client left. So the heartbeat is also the
    reaper, and `eventHeartbeat` had to become injectable (20s default, 150ms
    in the test) or the departed-subscriber test would sit through it. Found
    by the test failing, not by reading.

52. **Verified.** 68 tests in `design_server_test.dart` (was 59) plus 30 in the
    new `browser_trust_test.dart`, and the process exits — a live
    `Timer.periodic` would have kept the VM alive. Live against a real server
    on 4331: a real file save pushed `event: reload / {"generation":1}` to a
    real cross-origin subscriber; `Host: evil.example.com` -> 421; the
    cross-site `__project_write` -> 403 with no file on disk; an
    un-allowlisted origin -> 403; `GET /`, `GET /__routes` and a cross-site
    iframe GET all still 200. `appbox design probe all` -> 10/16, and the
    discriminator is that the serve log recorded **zero** refusals: the six
    failures are unfinished spike work ("BLOCKED: no emitted tree") and
    inspector probes expecting a different project fixture, none of them the
    guard.

53. **The panel half** (`arxa-studio` `c1eae9f`): `arxa-design-panel` opens an
    EventSource on `<url>/__events` while the dock is open and bumps the
    iframe key on `reload`. This is cross-origin — the panel is served from
    `arxa.studio.localhost`, the design server from `127.0.0.1` — so the
    design server must be started with
    `--trusted-origin http://arxa.studio.localhost:7891`. Without it the
    subscription is refused, a dot in the toolbar goes grey with the flag in
    its tooltip, and ⟳ still works. Deliberately NOT default-allowlisted:
    hardcoding a product's origin into the engine is the wrong direction, and
    "any loopback origin" would readmit the springboard of decision 48.

54. **Untested in a browser** — no EventSource has actually run. The wire is
    proven with a raw `http.request` carrying the same headers a browser
    sends, which covers the server, but `es.onerror`/`onopen` and the remount
    have not executed. Open the panel against a server started with the
    `--trusted-origin` above and save a file.

55. **Amendment to 53 — the flag is no longer per-serve.** 53's clause "the
    design server must be started with `--trusted-origin …`" is struck; the
    rest of 53 stands, including the refusal to hardcode arxa's origin into
    the engine. `appbox design serve` now also reads
    `~/.appbox/trusted-origins` (one origin per line, `#` comments,
    `92b869ac`), and `bin/arxa.mjs` registers its own origin there at boot
    (`arxa-studio` `7ce8562`). The engine still knows nothing about arxa — it
    reads a file; arxa writes to it. Machine-scoped, because "this laptop's
    studio may subscribe" is a fact about the laptop, not about whichever
    client repo the design happens to live in — which is also why it is NOT
    in `config/appbox.config.json`, the pipeline's SSOT.
    * A line that does not parse as `scheme://host` is dropped and named on
      stderr. Left in, it would pass `normalizeOrigin`'s raw fallback, match
      nothing, and be indistinguishable from "the flag didn't work".
    * arxa registers only `http://arxa.studio.localhost:PORT`, never the bare
      `arxa.studio:PORT` its trust args also declare. `.localhost` is reserved
      to loopback (RFC 6761) so nobody can be served from it; `arxa.studio` is
      a real public domain, and trusting it would hand `/__*` to whoever
      answers that name.
    * The read happens in `designServe`, not in `BrowserTrust`'s constructor,
      so the 34 pure guard tests never touch the operator's home.
    * The file is read ONCE, at boot, and that is the right scope for an
      allowlist — but it means a studio that later comes up on a different
      port writes a new line that the already-running design servers never
      see. Symptom: a grey dot with no explanation. Restart the design
      server; do not make the guard re-read on every request.
    * A hand-written entry survives arxa's boot without duplicating —
      verified, since arxa's dedupe compares `line.split('#')[0].trim()` and
      that is the one place hand-written and code-written state meet.

56. **Restarted and smoke-tested (2026-08-22).** Both long-running servers
    were killed and restarted from their own cwds and argv — suczka-studio
    :4319 (`clients/normal_is_boring`) and energize-landing :4320
    (`clients/energize`, `--json`, whose stdout stayed one clean JSON line;
    the wildcard warning correctly goes to stderr and does not fire on a
    loopback bind). No orphaned Chromes: the SIGTERM handlers reaped their
    own trees. 11 checks per server, 22/22 green, **with no `--trusted-origin`
    on either command line** — which is what proves the file is doing the
    work: panel subscription 200 with the origin echoed, a real new file
    pushing `event: reload`, `Host: evil.example.com` -> 421, cross-site
    `__project_write` -> 403, un-allowlisted origin -> 403, and CLI/iframe
    paths still 200. Zero stray files.
    * The reload is triggered by CREATING a file, not `touch`ing one: macOS
      FSEvents can swallow a bare mtime bump, and a false negative there
      would read as a broken stream.

57. **The iframe never worked, and no test could have caught it.** Every
    cross-origin iframe of `appbox design serve` was refused — the design panel
    and the `gen_ui` RungLadder alike, both blank. The header doing it,
    `X-Frame-Options: SAMEORIGIN`, appears in no source file in this repo:
    `dart:io` puts it in `HttpServer.defaultResponseHeaders` by its own
    default. Grep cannot find it and a Dart test asserting response headers
    would have had to know to look.
    * The smoke test in decision 56 asserted `iframe GET from panel -> 200`
      and passed while every real iframe was refused. `X-Frame-Options` is
      enforced on the frame-embedding path ONLY: a `fetch()` carrying
      `Sec-Fetch-Dest: iframe` is not an iframe, so the server answers 200 and
      the header is never evaluated. The check could not fail for the reason
      that mattered — the same shape as the PASS-means-did-not-run family.

58. **X-Frame-Options is removed, not narrowed, and CSP `frame-ancestors`
    takes over in the same change.** The header has no allowlist form:
    `ALLOW-FROM` is obsolete and modern browsers ignore the whole header when
    they see it (MDN). So the only options are "keep refusing everyone" or
    "remove it". Removing it ALONE would let any page on the web frame the
    design server, which is why the CSP is not garnish — it is what preserves
    the posture. `frame-ancestors` is Baseline since 2018 and header-only
    (it is ignored in a `<meta>`).
    * The allowlist mirrors `originAllowed`: one operator lever
      (`~/.appbox/trusted-origins` + `--trusted-origin`) now governs both who
      may call us and who may frame us.
    * Set on `defaultResponseHeaders` at the bind site, not in `_handle`, so a
      route that returns early cannot ship a document without the policy.

59. **The test is a browser framing a real server, and it is a PAIR.**
    `design_server_framing_test.dart` drives Chrome over CDP: an allowlisted
    parent must frame the design server, an un-allowlisted parent must still
    be refused. Neither half is meaningful alone — the first proves the bug is
    fixed, the second proves the protection was not simply deleted to make the
    first pass. Verified failing before the fix (child title came back as
    `127.0.0.1`, Chrome's error-page title) and passing after.

60. **A cross-SITE iframe is out-of-process and invisible to
    `Page.getFrameTree`.** Live verification against the real pair first read
    as "no frame created, no error logged", which looked like a second bug. It
    was the instrument: `arxa.studio.localhost` and `127.0.0.1` are different
    sites, so the child became an OOPIF that the parent session's frame tree
    does not list. A same-origin control iframe in the same page proved the
    instrument sound, and `Page.captureScreenshot` proved the design renders.
    The in-repo test does not hit this because both its origins are
    `127.0.0.1` on different ports — same site, same process.
    * The negative case is what confirmed the CSP is live: framing from
      `http://127.0.0.1:7891` (not allowlisted) fails with
      `ERR_BLOCKED_BY_RESPONSE` and a console entry quoting this exact
      `frame-ancestors` directive.

61. **pnpm copies `file:` plugins into the profile; it does not symlink
    them.** `~/.arxa/dsh/profiles/arxa/node_modules/arxa-design-panel` resolves
    into `.pnpm/…`, a hard copy. Editing `plugins/design-panel/lib/client.js`
    changes nothing in a running studio until `pnpm install --dir <profile>`
    re-copies it — and arxa's boot only auto-installs when a plugin directory
    is MISSING, so an edited-but-present plugin is silently stale.

62. **gen-ui was never broken; its RungLadder's sandbox was.** After the
    framing fix the design panel worked and the thread still looked dead, which
    read as a gen-ui failure. Driving the real session under CDP showed the
    opposite: `GenUiToolView` mounts, the keyed toolview resolves on a SUB-call
    (`…:code:2`), and the card renders its title, Heading, Text, rung buttons
    and ⟳. Only the iframe was black.
    * Code mode is not the defect. The model reaches `gen_ui` through
      `run_code`, so the visible call is `run_code` and `gen_ui` is a sub-call —
      but `ToolCallBranch` renders "one root Tool call and its recursive
      children through the same atomic keyed dispatch", and `childResult` sets
      `call.argsRaw` from the sub-call's arguments. Both halves already worked.
      `agent-presets: default: code` was NOT changed.

63. **A sandbox without `allow-same-origin` gives an OPAQUE origin, which no
    server-rendered page survives.** The RungLadder framed with
    `sandbox="allow-scripts allow-forms"`, so the design artifact booted with an
    origin that fails the same-origin policy against itself: its own fetches,
    cookies and storage all denied. That is the user's second console error —
    "Unsafe attempt to load URL … Domains, protocols and ports must match" —
    which is NOT an X-Frame-Options consequence and was still live after
    decision 58. Proven by an A/B in one page: no sandbox renders, the current
    sandbox is black, `+ allow-same-origin` renders.
    * The earlier probe that "cleared" this error framed with a PLAIN iframe, so
      it never exercised the sandbox and could not have reproduced it. A probe
      that does not reproduce the reported conditions is not evidence of a fix.

64. **Decision 19 is amended, not reversed: the grant is conditional on the
    target being a foreign host.** "allow-same-origin would silently mean no
    sandbox at all" is true only when the frame is same-origin with the embedder
    — MDN scopes the escape exactly that way. Since `url` arrives in
    model-supplied tool args, the model could aim it at the studio's own origin
    and get precisely that escape, so `sandboxFor(url, selfHref)` grants
    `allow-same-origin` only for an `http(s)` URL on a different **hostname**,
    and fails closed otherwise.
    * Hostname, not origin: cookies ignore the port, so
      `arxa.studio.localhost:9999` is a different origin but could still read
      the studio's cookies.
    * Relative URLs are parsed against the page (`/admin` must resolve to US),
      and `data:`/`javascript:`/`file:` are rejected before any comparison —
      their origin is the string `"null"`, which a naive difference check would
      have GRANTED.
    * The rule lives in `catalog.js` (importable, tested) and is mirrored in
      `client.js` (which cannot be imported — it is a `__ModuleLoader__`
      factory). `selftest.mjs` runs ONE 15-row table against both copies, so
      drift fails the suite; verified by mutating the client copy's `hostname`
      back to `origin` and watching it go red.

65. **Scrollbars in a preview are harness, not design — and only the SERVER can
    remove them.** The bars showing in the ladder's mobile/tablet rungs and in
    the design panel belong to the framed document's own inner scrollers (the
    artifact's carousels and overflow panes), which is cross-origin: neither
    consumer can reach its stylesheets. So `appbox design serve` injects
    `*{scrollbar-width:none}` + `*::-webkit-scrollbar{width:0;height:0}` into
    full HTML documents, alongside the islands-eager loader it already injects.
    Scrolling is untouched; only the bar is hidden.
    * Gated on `Sec-Fetch-Dest: iframe`, so opening the same URL in a tab keeps
      its scrollbars. That header is a FORBIDDEN header name — page script
      cannot set or strip it — and the browser sends `iframe` only for the
      frame's own navigation, never its sub-resources, so it lands on exactly
      one response.
    * The design panel's own dock scroller is a separate, second bar and OURS;
      it gets `scrollbarWidth: 'none'` in the panel.

66. **A forbidden header cannot be forged, which also defeats the obvious
    test.** The first verification tried `Network.setExtraHTTPHeaders` with
    `Sec-Fetch-Dest: iframe` on a direct navigation — Chrome ignores the
    override (that is precisely why the signal is trustworthy), so the probe
    reported "not injected" and looked like a bug in the fix. The proof has to
    be a REAL frame.
    * It reads only because parent and child are both `127.0.0.1`: same SITE,
      so the child stays in-process and `evaluateInFrame` reaches it. The live
      pair (`arxa.studio.localhost` -> `127.0.0.1`) is cross-site, and its child
      is an OOPIF this session cannot see — see decision 60.
    * Verified by mutation: pointing the header check at a value nothing sends
      makes the test fail with "the framed navigation did not receive the
      style", so the assertion is not vacuous.
    * Headless Chrome renders OVERLAY scrollbars, so a screenshot can never
      show this difference either way. Computed `scrollbar-width` inside the
      frame is the machine-independent check.

67. **Streaming, re-measured — and decision 33's stated reason was the second
    blocker, not the first.** Session `e0b1b8ce` recorded six tool calls. Every
    one arrived as exactly **one** `tool-call-delta` chunk — 1149, 2875, 275,
    1466, 1509 and 1503 bytes, each with a **0 ms span**. dsh's accumulator
    (`argsRaw: base.argsRaw + chunk.argumentsDelta`, ui-conversation
    `updateChunk`) is correct and simply never receives a second delta: the
    provider ships the whole tool-call payload atomically. So a partial-JSON
    renderer would have exactly one state to render. Decision 33 reached the
    right conclusion; the first-order reason is upstream of the toolview.

68. **Two independent blockers, so "get the provider to stream" is not a fix.**
    Even given streamed arguments, `hasVisibleContent` returns `false` for
    `tool-call` blocks (ui-conversation), so a half-built call draws nothing in
    the thread, and the toolview still mounts from the completed `tool/call`
    node. Both would have to change together. Neither is worth it against the
    measured latency: in that session reasoning ran 13.2s→18.4s, the arguments
    landed at 26.23s, and the card dispatched at 26.267s — **37 ms** after the
    call. The wait users feel is thinking time; nothing inside gen-ui moves it.

69. **What ships instead: an accent outline glow on a surface still filling in.**
    Not a placeholder during reasoning — no card exists then (see 68). The
    window that IS real is the iframe boot: a RungLadder frames a live
    `appbox design serve`, which takes seconds. The frame box glows until its
    iframe fires `load`, and the whole card glows until the call settles. The
    ring is a masked `conic-gradient` swept by an `@property`-registered angle
    — a plain custom property is a *string* to the animation engine and would
    jump 0→360 rather than travel, which is a silent visual failure, so the
    registration is asserted in `selftest.mjs`. Verified in real Chrome: the
    sweep moved 142.02°→217.02° in 500 ms (=360°/2.4s, matching the
    declaration) and the ring paints on the border with the interior untouched.
    Load state is keyed by frame identity, not a boolean — switching rung
    remounts the iframe but not the component, so a boolean would latch true
    and the next frame would never glow. 20 s ceiling so a server that dies
    mid-boot does not glow forever.

70. **Decision 23 reversed: the catalogue is nine, not five — and the reason is
    that provider-independence beat fidelity.** The operator's ruling settled
    it: "the gen ui streaming feature must work regardless of the LLM." Token-
    level streaming is a *per-provider* property (measured: prose streams in
    1045 deltas across 74 coalesced rows, tool arguments in exactly one — see
    `streaming-generative-ui-research.md`), so building on it would ship a
    feature that silently degrades when the model changes. Disqualified as the
    mechanism, whatever a provider test would have shown. Added `Card`,
    `Button`, `Icon`, `Image`. Not speculative growth: a declared skeleton is
    not expressible without a container and something to put in it.

71. **The surface is a graph now, and the size signal comes from the author.**
    `Card.children` names sibling ids — A2UI's own `Map<String, Component>`
    shape, since the flat list cannot nest. Four ways this goes wrong, all
    validated host-side before the browser sees it: a dangling id, a card
    containing itself, a cycle across two cards (every individual reference is
    valid; only walking the graph finds it, and the renderer would recurse
    forever), and two cards claiming one child (which would draw it twice and
    give one componentId two selection records). `claimedChildren` is mirrored
    in both halves under the existing two-list contract, with one table run
    against both so they cannot drift.

72. **What actually fills in, and why it is honest on any model.** The wait
    that remains after the arguments land is in *rendering*, not generation:
    an `Image` fetching bytes, a `RungLadder` booting a live server. Those
    slots are reserved at their declared `height` and swapped when ready, so
    the surface never jumps — the reserved box IS "an outline of that size".
    Per the skeleton research, the pending dress is withheld for
    `PENDING_AFTER_MS = 400`: a treatment shown for a 200ms load flashes and
    reads as a glitch, which is exactly why the first glow was never visible.

73. **Decision 32c's caveat is closed for these paths.** `selftest.mjs` now
    runs the browser half's component functions for real in Node against a
    React stub — 19 checks. It proves a Card's children render exactly once
    (mutation: drop the top-level filter and the child draws twice), that an
    unloaded Image reserves its Slot (mutation: collapse it and the check
    fails), and that a dangling id draws a note. Not a browser: no layout, no
    CSS. But the components execute, which they never had before.

74. **One framed document serves every rung; switching a rung is a resize, not
    a navigation.** The iframe key carried the rung label (`epoch:url:label`),
    so every mobile/tablet/desktop click unmounted the element and mounted a
    new one — a full page load of the framed app, discarding the operator's
    scroll position to show the SAME document at a different width. `width`
    and `height` are plain attributes and the fit is a CSS `transform: scale`,
    none of which require navigation, so the key is now `epoch:url` in both
    the `gen_ui` RungLadder and the design-panel dock. `epoch` stays because
    ⟳ and the SSE `reload` frame genuinely do need a remount.

    Per-rung scroll memory was considered and rejected: it needs one mounted
    iframe per rung, i.e. three live app instances, three SSE subscriptions
    and three hot-reload storms, to remember a number the browser already
    keeps for the single document. `selftest.mjs` pins the invariant in both
    files (mutation-tested: restore the rung to either key and the check
    fails), because "the key should identify the rung" is exactly the kind of
    tidy-looking change a future reader makes.

75. **`frame-ancestors` cannot express a bracketed IPv6 literal, so the
    design server stopped emitting one.** CSP3 §2.3.1 defines
    `host-char = ALPHA / DIGIT / "-"` and `ancestor-source` admits only
    `scheme-source`, `host-source` and `'self'` — there is no production a
    `[::1]` can match. Chrome logged "does not support the source expression"
    once per document load and dropped the token; the spec's own note adds
    that only `127.0.0.1` ever matches a URL by address, so the entry had
    never done anything but generate console noise. `'self'` already covers a
    document actually served over `[::1]`. Removing it is behaviour
    preserving by construction: the browser was already discarding it.

    Verified end to end rather than by unit test alone — a throwaway server
    from the freshly AOT-compiled binary on port 4399 emitted
    `frame-ancestors 'self' http://127.0.0.1:4399 http://localhost:4399
    http://arxa.studio.localhost:7891`, confirming both that the token is
    gone and that `~/.appbox/trusted-origins` still supplies the studio, so a
    restart cannot silently un-frame the panel.

76. **An operator-supplied IPv6 origin is deliberately NOT filtered out of
    the header.** Filtering it would trade a loud failure for a silent one:
    today the browser names the exact offending token in the console, which
    tells the operator precisely what to fix, whereas dropping it server-side
    would leave them with framing that simply does not work and nothing that
    says why. That is the failure shape `readTrustedOriginsFile` already
    calls the worst an allowlist can have. `browser_trust_test.dart` asserts
    the pass-through so nobody "hardens" it into silence.

    Note for future debugging: `.build/appbox` is an AOT binary. A Dart change
    needs a recompile, and the `appbox` wrapper does that automatically only
    when invoked as `appbox` — relaunching the raw `.build/appbox` path
    re-execs the old image and the fix appears not to work.
