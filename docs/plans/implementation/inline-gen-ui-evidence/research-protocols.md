# Agent-generated interactive UI in a chat thread — state of the art (as of 2026-08-21)

Research for: a plugin for a self-hosted coding-agent harness (React web UI) where a tool call
should render a live interactive component in the message stream, not plain text.

All dates below are publication dates of the source, not "today." Anything from 2025 or earlier
is flagged explicitly as pre-2026 / possibly superseded.

---

## 1. MCP-UI → MCP Apps (the official Model Context Protocol UI extension)

**Status: standardized and shipping in production as of 2026-01-26; folded into the core MCP
spec's 2026-07-28 release as a first-class extension. This is the most mature, most-adopted
option in this survey.**

### History and naming
"MCP-UI" was an experimental community project (created by Ido Salomon and Liad Yosef,
maintained by "a dedicated community," adopters included Postman, Hugging Face, Shopify, Goose,
ElevenLabs). It proved out `ui://` resources, a bidirectional postMessage protocol, and three
content types (HTML, external URL, remote-DOM). On 2025-11-21 Anthropic proposed folding this
work — plus lessons from OpenAI's separately-built Apps SDK — into MCP itself as **SEP-1865:
"MCP Apps — Interactive User Interfaces for MCP."** SEP-1865 reached **Status: Final** on
2026-01-26 and is MCP's first official extension. `mcpui.dev` now brands itself
"MCP-UI → MCP Apps": the MCP-UI open-source packages are the reference client/server SDK that
implements the official spec; the project didn't go away, it became the SDK for the standard.
- SEP page: https://modelcontextprotocol.io/seps/1865-mcp-apps-interactive-user-interfaces-for-mcp
- Full spec text: https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/2026-01-26/apps.mdx
- Announcement: https://blog.modelcontextprotocol.io/posts/2026-01-26-mcp-apps/
- MCP-UI site: https://mcpui.dev/

### How it works
Two MCP primitives, nothing new invented:
1. **UI Resources** — server-hosted resources under the `ui://` URI scheme, MIME type
   `text/html;profile=mcp-app`. The **MVP deliberately supports only raw HTML** — external URLs
   and remote-DOM (both of which the pre-standard community MCP-UI supported) are explicitly
   *deferred*, not part of v1. Rationale given in the spec: HTML has the simplest, best-understood
   security model (a standard iframe sandbox) and is sufficient for observed use cases; multiple
   content types would bloat the MVP.
2. **Tools with UI metadata** — a tool declares `_meta.ui.resourceUri` pointing at a `ui://`
   resource. Hosts fetch and can pre-review/cache all UI templates *before* any tool runs
   (benefits called out in the spec: performance/preload, security review, template/data
   caching, auditability — resources are enumerable up front).

At runtime the host renders the HTML in a sandboxed iframe and opens a **JSON-RPC 2.0 channel
over `window.postMessage`** — the same base RPC MCP already uses everywhere else, so every
UI-initiated action is auditable/loggable exactly like a direct tool call. Lifecycle: the View
sends `ui/initialize` (declaring `appCapabilities`: whether it exposes its own tools,
`availableDisplayModes: ["inline","fullscreen","pip"]`), host acks, then either side can send
further JSON-RPC requests/notifications.

**Size negotiation**: for flexible (non-fixed) dimensions, the View sends
`ui/notifications/size-changed {width,height}` notifications; the SDK auto-emits these via a
debounced `ResizeObserver` when `autoResize` is on (default). The host resizes the iframe on
receipt.

**Action vocabulary** (from the pre-standard community SDK, carried forward as the client SDK's
typed action union — this is *not* itself part of the wire-level SEP-1865 JSON-RPC methods, it's
the ergonomic layer on top): `{type:'tool', payload:{toolName, params}}`,
`{type:'intent', payload:{intent, params}}`, `{type:'prompt', payload:{prompt}}`,
`{type:'notify', payload:{message}}`, `{type:'link', payload:{url}}`. A button click that fires
`tool`/`intent` routes through the host's normal tool-call consent/audit path — the UI cannot
call anything the model couldn't already call.
- https://workos.com/blog/mcp-ui-a-technical-deep-dive-into-interactive-agent-interfaces (2025-09-08 — describes the **pre-standard** 3-content-type version; useful for the event vocabulary, but its `UIResource.mimeType` union (`text/html | text/uri-list | application/vnd.mcp-ui.remote-dom`) is broader than what actually shipped in the Jan-2026 MVP)

### Security model
Defense in depth, spelled out in both the spec and the announcement:
- **Iframe sandboxing** with restricted permissions is mandatory.
- Recommended **double-iframe "sandbox proxy" architecture** for web hosts: an outer proxy
  iframe (different origin from the host, `allow-scripts allow-same-origin`) negotiates with the
  host over reserved messages (`ui/notifications/sandbox-proxy-ready`,
  `ui/notifications/sandbox-resource-ready`) and only then loads the untrusted HTML into an inner
  iframe with a CSP built from the resource's declared metadata.
- **CSP is constructed from resource `_meta.ui.csp`** (`connectDomains`, `resourceDomains`,
  `frameDomains`, `baseUriDomains`) and `_meta.ui.permissions` (camera/microphone/geolocation/
  clipboardWrite → maps to the iframe's `allow` attribute). If no CSP metadata is declared, the
  host MUST fall back to a fully restrictive default (`connect-src 'none'`, no external script/
  style/img domains). Hosts MUST NOT allow undeclared domains — they may only tighten, never
  loosen.
- **Pre-declared templates**: because HTML ships as a discoverable resource, hosts can
  content-review it before it ever renders, and log/audit every CSP config.
- **User consent**: hosts can require explicit approval for UI-initiated tool calls.

### Client / adopter support (as of the 2026-01-26 announcement, "more coming soon")
Named directly in the official MCP blog post: **Claude** (web + desktop), **Goose**,
**Visual Studio Code** (Insiders), **ChatGPT** (rolling out "starting this week"). Other sources
(secondary, not independently verified against a primary doc) additionally name **Postman**,
**MCPJam**, and **Archestra.AI** as hosts, and **Shopify, Hugging Face, ElevenLabs** as MCP-UI-era
server adopters. One secondary source (inkeep.com) claims 9 named Claude launch partners
(Amplitude, Asana, Box, Canva, Clay, Figma, Hex, monday.com, Slack) — this is **unverified**
against a primary Anthropic source and should be treated as reported-but-not-confirmed.
Example servers ship in the reference repo: 3D viz (three.js), maps, PDF viewer, system monitor
dashboard, sheet music. https://github.com/modelcontextprotocol/ext-apps/tree/main/examples

### The 2026-07-28 core MCP spec revision
This is the answer to "does Anthropic have its own documented extension surface, not a closed
feature": **yes — MCP Apps** is exactly that, and it graduated into the core protocol's biggest
revision to date. https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/
(RC blog; final ships same date per the post) describes MCP going **stateless at the protocol
layer** (handshake/session removed, works behind plain round-robin load balancers,
`tools/list` becomes cacheable via `ttlMs`), **"Extensions Become First-Class"** — MCP Apps and a
new Tasks extension (for long-running work) are the two flagship extensions of this release —
plus OAuth/OIDC-aligned authorization hardening, deprecation of roots/sampling/logging, and full
JSON Schema 2020-12 support for tool schemas. Net effect: UI-in-chat is not a side feature bolted
onto MCP, it is now one of the two things the "extensions" mechanism was built to carry.

### Claude Artifacts, specifically
Claude Artifacts (the side-panel code/HTML/React/SVG/Markdown live-preview feature) is a
separately-run, browser-sandboxed-iframe renderer — historically **not** a documented API surface
that arbitrary third parties can register against. What answers the "documented extension
surface" question for Claude specifically is that **Anthropic did not ship a parallel proprietary
artifacts API for third parties — it co-authored MCP Apps and shipped support for it directly
inside claude.ai/desktop conversations** (demoed with a color-picker MCP App running live in
Claude.ai in the announcement GIF). Third-party interactive UI in Claude goes through the same
open, multi-vendor MCP Apps contract everyone else uses, not a Claude-only mechanism.

---

## 2. AG-UI (Agent-User Interaction Protocol)

**Status: an open, company-led (CopilotKit) protocol, not a standards-body spec like SEP-1865.
Origin ~2025 (repo says released ~May 2025 / "early 2025" per secondary sources); wide adoption
inside the agent-*framework* ecosystem through 2026. Solves a different layer of the problem than
MCP Apps.**

- Docs: https://docs.ag-ui.com/introduction
- Repo (15.5k★, 1.4k forks as fetched 2026-08-21): https://github.com/ag-ui-protocol/ag-ui
- Canonical event enum: https://docs.ag-ui.com/sdk/js/core/events

### What it actually is
AG-UI explicitly positions itself as one leg of a three-protocol stack: **MCP** = agent↔tools/data,
**A2A** (Google-originated) = agent↔agent, **AG-UI** = agent↔user-facing-application. It is an
**event-streaming wire format**, not a rendering/sandboxing spec. An agent backend emits a stream
of typed events over any transport (SSE, WebSockets, webhooks — "loose event format matching" is
explicit design goal for interop), and the frontend app subscribes and reacts.

**Canonical `EventType` enum** (fetched from the current docs, larger than the "~16" figure quoted
in older secondary sources — reasoning events are a 2026 addition):
`TEXT_MESSAGE_START/CONTENT/END`, `TOOL_CALL_START/ARGS/END/RESULT`, `STATE_SNAPSHOT`,
`STATE_DELTA`, `MESSAGES_SNAPSHOT`, `ACTIVITY_SNAPSHOT/DELTA`, `RAW`, `CUSTOM`,
`RUN_STARTED/FINISHED/ERROR`, `STEP_STARTED/FINISHED`, `REASONING_START`,
`REASONING_MESSAGE_START/CONTENT/END/CHUNK`, `REASONING_END`, `REASONING_ENCRYPTED_VALUE`.
Streaming triads mirror each other: text messages are START→CONTENT(*)→END; tool calls are
START(name)→ARGS(streamed JSON fragments)→END→RESULT.

### Rendering model — the key contrast with MCP Apps
There is **no iframe and no HTML resource** in AG-UI's core model. "Generative UI" in the AG-UI/
CopilotKit world means: the agent's tool call (or `STATE_DELTA`) is a *signal* the frontend app —
which is first-party code the app's own developers wrote — interprets to render or update one of
**its own native React (or Angular/mobile) components**. CopilotKit ships this as
"tool-based generative UI" and "shared state" patterns. Because the rendering code is trusted,
first-party, and already living inside your app's bundle, there is no sandboxing story to design —
the security boundary is "don't let the agent call tools/render components you didn't author,"
handled at the app layer, not the protocol layer.

### Adoption (as fetched from the repo, 2026-08-21)
1st-party/"✅ Supported" framework integrations listed in-repo: **LangChain/LangGraph, CrewAI,
Microsoft Agent Framework, Google ADK, AWS Strands Agents, Mastra, Pydantic AI, Agno, LlamaIndex**.
Secondary sources (WebSearch summaries, not independently re-verified page-by-page) additionally
report: AWS added AG-UI support to **Amazon Bedrock AgentCore Runtime** (March 2026), Microsoft's
Agent Framework docs include AG-UI integration guidance, SDKs now span TypeScript/Python/Kotlin/
Java/Go, and 2026 additions include React Native support (renders to native mobile widgets, not a
webview) and full CrewAI compatibility (streamed reasoning, multimodal input, human-in-the-loop
interrupts, checkpointing).

### AG-UI vs A2UI (frequent confusion, addressed directly in AG-UI's own docs)
"A2UI is a generative UI specification... where AG-UI is the Agent↔User Interaction protocol."
They're complementary layers, not competitors — CopilotKit explicitly says it works with both
MCP-UI and A2UI. See §4 below for A2UI itself.

---

## 3. Anthropic's own direction — summary

Covered inline in §1: Anthropic's documented extension surface for UI-in-chat *is* MCP Apps
(SEP-1865, co-authored with OpenAI and MCP-UI's creators), now part of the core spec's biggest-ever
revision (2026-07-28). There is no separate/parallel proprietary Anthropic UI protocol to report on
— Claude Artifacts remains a same-origin, closed-to-third-parties renderer for content Claude
itself generates inline in a turn, while third-party interactive tool UI goes through MCP Apps.

---

## 4. Competing / adjacent approaches

### OpenAI Apps SDK / ChatGPT Apps
Now **converged with MCP Apps** rather than a separate rival: OpenAI's Nick Cooper is a named
SEP-1865 co-author, and the OpenAI blog quote in the MCP announcement calls Apps SDK a foundation
MCP Apps "builds upon." Architecture: a ChatGPT app = an MCP server + a bundled widget
(built via e.g. `esbuild --bundle --format=esm`) that the server inlines as the HTML resource,
rendered by ChatGPT in a sandboxed iframe — the same rawHTML-in-iframe shape MCP Apps
standardized. The widget talks back to the host via a `window.openai` bridge:
`callTool(name, args)` (invoke MCP tools directly from widget JS), `setWidgetState(state)`
(synchronous, persisted per-conversation, restored on revisit), `sendFollowUpMessage(text)`
(inject text back into the conversation as if from the user, resuming the model). Docs:
https://developers.openai.com/apps-sdk/ , https://developers.openai.com/apps-sdk/build/state-management
Maturity: production in ChatGPT since the MCP Apps launch window (Jan 2026); effectively an
implementation of the shared standard now, not a fork.

### A2UI (Google) — declarative generative UI
Google-originated, https://a2ui.org — a **declarative** spec: instead of shipping HTML/JS, a tool
returns a **JSON payload naming components from a predefined catalog**; the host renders those
natively (React, Flutter, Angular all cited) using its own design system — "write once, render
natively anywhere." Security model is capability-based: the client only ever instantiates
components it already trusts from its catalog, so there's no arbitrary-code-execution surface to
sandbox, but developers are limited to whatever's in the catalog (weak for bespoke/complex
client-side logic). Google/MCP Apps' co-creators published a joint post
(2026-06-17, https://developers.googleblog.com/a2ui-and-mcp-apps/) explicitly reconciling the two
rather than competing, with three worked integration patterns: (1) A2UI served directly over MCP
servers as an alternative to MCP Apps for simple structured UI, (2) an MCP App wrapped as a custom
A2UI component so it participates in A2UI's state-sync loop, (3) an A2UI rendering engine running
*inside* an MCP App's iframe. Google says it's "considering" a formal MCP extension for A2UI.
Maturity: early/actively-converging, not yet a settled independent competitor.

### Vercel AI SDK — Generative UI (`ai/rsc`, React Server Components)
The historical pioneer of "tool call → streamed UI component" (announced 2024-03-01,
https://vercel.com/blog/ai-sdk-3-generative-ui): a `streamUI`/`render` call maps specific tool
calls to React Server Components that stream from the Next.js server straight to the client — no
iframe, no sandbox, because the "server" rendering the component *is* your own app's backend.
**Important 2026 status change**: Vercel's own current docs state **"Development of AI SDK RSC is
currently paused."** The SDK now pushes **AI SDK UI** (client hooks like `useChat`/`useCompletion`
that stream structured tool-call data, left to the app to render as normal client components) plus
a new prebuilt component library ("AI Elements") and separate Workflows/Sandbox products added in
2026. Net: the RSC-streaming approach that originated "generative UI" as a term is not the pattern
Vercel is currently investing in.

### LangGraph / CopilotKit
CopilotKit is the company/framework behind AG-UI (see §2) — "the frontend stack for agents and
generative UI" — with first-class LangGraph integration (`CoAgents`) plus the same event/state-sync
model applied across many other agent frameworks. Not a separate protocol from AG-UI; it's
AG-UI's reference application layer (hooks, headless UI, human-in-the-loop primitives).

### Shopify remote-dom
https://github.com/Shopify/remote-dom — a general-purpose technique, **not chat-specific and not
a protocol**: a tree of DOM elements built in a sandboxed JS environment (worker or iframe) gets
mirrored into a host-environment DOM tree using the host's own components, avoiding iframe
rendering overhead entirely while still isolating untrusted code off the main thread. This was one
of the three content types the **pre-standard** community MCP-UI supported
(`application/vnd.mcp-ui.remote-dom`) but is **explicitly deferred, not in the official SEP-1865
MVP** (HTML-only for now). Best understood as a lower-level rendering primitive that a future MCP
Apps content-type extension could adopt, not a competing top-level spec.

### htmx / hypermedia-over-tools
Not a protocol — a **technique for authoring the rawHTML content inside an MCP App**, documented
in an independent developer's essay (2026-03-18):
https://htmx.org/essays/mcp-apps-hypermedia/. Uses Fixi (an htmx-adjacent micro-library) so DOM
updates happen via server-rendered HTML fragments returned from MCP tool calls (`fx-action` calls
a tool, `fx-target`/`fx-swap` splice the returned fragment into the DOM) rather than client-side
JS state management. Explicit rationale in the essay: the iframe can't talk directly to your
server and every interaction must cross the postMessage bridge, so minimizing client-side state
reduces the surface area for cross-boundary bugs. A legitimate pattern *within* MCP Apps, not an
alternative to it.

---

## 5. Comparison table

| Approach | Data shape returned by a tool | How it renders | Interaction → agent | Isolation model | Maturity (2026-08-21) |
|---|---|---|---|---|---|
| **MCP Apps** (formerly MCP-UI) | `ui://` resource, `text/html;profile=mcp-app` (HTML-only in MVP) | Sandboxed iframe (double-iframe "sandbox proxy" recommended) | JSON-RPC 2.0 over postMessage; typed `tool/intent/prompt/notify/link` actions route through host's normal tool-call consent path | Untrusted-by-default: iframe sandbox + per-resource CSP/permissions metadata, pre-declared/reviewable templates | **Final SEP (2026-01-26)**, folded into core MCP spec 2026-07-28. Shipping in Claude, ChatGPT, Goose, VS Code Insiders. Highest adoption/standardization of anything here. |
| **AG-UI** | Stream of typed JSON events (`TOOL_CALL_*`, `STATE_SNAPSHOT/DELTA`, etc.) over SSE/WebSocket/webhook | First-party native components (React/Angular/mobile) the app already owns, driven by state sync | Same event stream, bidirectional; app-defined | Trusted-by-design: no sandbox, because rendering code is first-party | Company-led open protocol (CopilotKit), origin ~2025; broad adoption across agent *frameworks* (LangGraph, CrewAI, MSFT Agent Framework, Google ADK, AWS Strands, Mastra, more) and AWS Bedrock AgentCore (Mar 2026). Not itself a chat-thread HTML renderer. |
| **A2UI** (Google) | JSON payload naming components from a predefined catalog | Host renders natively from its own catalog (React/Flutter/Angular) | Declared actions in the JSON; host-mediated | Capability-based: only catalog components ever instantiate, no arbitrary code | Newer; actively converging with MCP Apps via 3 named hybrid patterns (Google post 2026-06-17). Not yet an independent standard on its own footing. |
| **OpenAI Apps SDK** | Same `ui://`-shaped MCP resource + bundled widget JS | Sandboxed iframe | `window.openai.{callTool, setWidgetState, sendFollowUpMessage}` | Same as MCP Apps (co-authored the same SEP) | Converged into MCP Apps; production in ChatGPT since Jan 2026 launch. |
| **Vercel AI SDK RSC genUI** | React Server Component, streamed | Server-streamed RSC straight into your own Next.js client tree | Normal React event handlers → server actions | Trusted-by-design (your own backend) | Pioneer (Mar 2024); **development paused** per Vercel's current docs, superseded by AI SDK UI + AI Elements. |
| **remote-dom** (Shopify) | Mirrored DOM tree from a sandboxed worker/iframe | Host renders using its own components, no iframe compositing cost | Whatever events the remote tree emits | Sandboxed JS environment, no iframe overhead | Mature general-purpose library; used by pre-standard MCP-UI, **deferred from the official MCP Apps MVP**. |
| **htmx-over-tools** | HTML fragments returned by MCP tool calls | Server-rendered fragment swapped into the DOM (`fx-action`/`fx-swap`) | Ordinary tool call each interaction | Same as whatever MCP Apps iframe hosts it in | A technique/pattern inside MCP Apps, not a separate protocol; one essay (Mar 2026), niche. |

---

## 6. Opinionated read — what to imitate for a self-hosted coding-agent harness (React web UI)

**Imitate AG-UI's rendering model for the harness's own first-party tools; borrow MCP Apps'
resource-linkage and action vocabulary as the metadata shape, so the two paths can share one
lookup mechanism later.**

Reasoning: MCP Apps' entire security architecture (double-iframe sandbox proxy, per-resource CSP
construction, pre-declared/reviewable templates, restrictive default policy) exists to solve a
problem this harness mostly doesn't have — **rendering HTML authored by an untrusted third-party
MCP server you didn't write.** If the harness's tool-driven UI is coming from tools the harness
itself defines and ships (even if community-contributed, they're reviewed/built into the same
repo/plugin), that's the AG-UI situation: trusted, first-party rendering code already living in
your React bundle. Paying the iframe + postMessage-JSON-RPC + CSP-negotiation tax for that case is
pure overhead — and Google's own June-2026 A2UI post makes exactly this argument against
iframe-only architectures (aesthetic inconsistency, redundant scrollbars, perf/security cost) for
anything that doesn't strictly need it.

Concretely: define a small set of typed tool-result "render" events (tool name + typed payload,
optionally a state-delta stream for live updates) that the harness's React app matches against its
own component registry and renders natively — no iframe, no CSP, no sandbox proxy, full access to
the harness's existing design system. That's the AG-UI/CopilotKit shape, and it has the broadest,
most framework-agnostic 2026 adoption of anything surveyed here that isn't MCP Apps itself.

But don't throw away compatibility: give the tool-to-UI linkage the **same shape** MCP Apps uses
(`_meta.ui.resourceUri`-style metadata, `ui://`-style identifiers, the same
`tool/intent/prompt/notify/link` action taxonomy) even for natively-rendered components. That way,
the day the harness needs to host a genuinely untrusted plugin or a third-party MCP server's UI —
which, given the ecosystem's convergence, is increasingly likely to arrive already MCP-Apps-shaped
— it drops straight into a sandboxed-iframe renderer using the *same* lookup/metadata path, without
inventing a second, incompatible protocol from scratch. This mirrors exactly what Google did for
A2UI/MCP-Apps interop (Pattern 2: wrap an MCP App as a component inside the native-rendering
system) rather than picking one exclusively.

**Dead ends to avoid:**
- **Vercel AI SDK RSC generative UI** — the pattern that coined the term is now dev-paused by
  Vercel itself, and it's structurally coupled to Next.js server infrastructure that a self-hosted
  harness likely doesn't run.
- **Standardizing on remote-dom as the outer contract** — it's a legitimate, mature *technique*
  (and was in the pre-standard MCP-UI), but the ecosystem itself deferred it from the official MVP;
  treat it as an optimization to reach for later under an MCP-Apps-shaped resource, not the thing
  to build the whole plugin architecture around.
- **Committing fully to A2UI's fixed component catalog** — high lock-in for a harness that
  presumably wants to own its design system; take the "no-iframe, native-render" idea (which
  AG-UI already gives you, more framework-agnostically) rather than the specific Google spec.

---

## Sources (primary docs fetched and indexed)
- SEP-1865 spec text: https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/2026-01-26/apps.mdx
- SEP-1865 SEP page (Final): https://modelcontextprotocol.io/seps/1865-mcp-apps-interactive-user-interfaces-for-mcp
- MCP Apps announcement (2026-01-26): https://blog.modelcontextprotocol.io/posts/2026-01-26-mcp-apps/
- MCP core spec 2026-07-28 release: https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/
- MCP-UI site: https://mcpui.dev/
- AG-UI docs: https://docs.ag-ui.com/introduction , event reference: https://docs.ag-ui.com/sdk/js/core/events
- AG-UI repo: https://github.com/ag-ui-protocol/ag-ui
- OpenAI Apps SDK: https://developers.openai.com/apps-sdk/ , https://developers.openai.com/apps-sdk/build/state-management
- Google A2UI + MCP Apps: https://developers.googleblog.com/a2ui-and-mcp-apps/
- Vercel AI SDK 3.0 generative UI: https://vercel.com/blog/ai-sdk-3-generative-ui
- Shopify remote-dom: https://github.com/Shopify/remote-dom
- htmx MCP Apps hypermedia essay (2026-03-18): https://htmx.org/essays/mcp-apps-hypermedia/
- WorkOS MCP-UI technical deep dive (2025-09-08, pre-standard, flagged as such above): https://workos.com/blog/mcp-ui-a-technical-deep-dive-into-interactive-agent-interfaces
- CopilotKit "State of Agentic UI" (2025-12-02, pre-A2UI-post, framing largely confirmed by the later Google post): https://www.copilotkit.ai/blog/the-state-of-agentic-ui-comparing-ag-ui-mcp-ui-and-a2ui-protocols
