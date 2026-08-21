# appbox design pipeline — research for the arxa design panel

Repo: `/Volumes/developer_ssd/Developer/totem_labs/app-box` (read-only investigation, nothing modified).
Date: 2026-08-22. Every claim below carries a `file:line`. Claims I could not verify from
primary source are marked **INFERRED**.

**Bottom line up front:** the design server is a Dart HTTP server that renders one HTML
document per route, on demand, by dispatching through artifact JS running in a headless
Chrome tab over CDP. It has **no server→browser push channel of any kind** and **no
per-rung rendering** — rungs are a client-side/capture-side concept. Generation is
batch: an artifact is authored as files on disk, and the server renders whatever is on
disk at request time. So *live UI streamed per rung as it is produced* is **not
supported today**; §7 lists the exact seams you would build it on.

---

## 1. `appbox design serve` — what it is

### Command chain

| stage | file:line |
|---|---|
| top-level CLI verb `design` | `appboxd/bin/appbox.dart:88` |
| `design` subcommand dispatcher `designMain` | `appboxd/lib/design_cli.dart:78` |
| `case 'serve'` | `appboxd/lib/design_cli.dart:103` |
| server implementation | `appboxd/lib/design_server.dart` (1420 lines) |
| CDP worker bridge | `appboxd/lib/design_server/worker.dart` (1382 lines) |

Invocation used throughout the repo:
`dart run appboxd/bin/appbox.dart design serve <artifact-dir|design-name> [--port N] [--host H] [--json] [--no-watch]`
(example at `appboxd/lib/probes/probe_base.dart:217`).

### Port

- Default **4319**, overridable by the `PORT` env var, then `--port`:
  `appboxd/lib/design_server.dart:151-153` (`Platform.environment['PORT'] != null ? … : 4319`).
- `--port` parsing: `design_server.dart:166-173`. `--port 0` asks the OS for a free port
  (`design_server.dart:293`, `:325`).
- Binds **127.0.0.1** by default; `--host 0.0.0.0` exists for phone previews and announces
  itself on stdout (`skills/appbox-designer/runtime/README.md`, Commands section).
- The *ejected* Hono app defaults to **4399**, not 4319 — different thing, don't confuse
  them (`appboxd/lib/design_cli.dart` usage block; `appboxd/test/design_tools_test.dart:1379`).

### Ready-record and exit codes — you will spawn this process

`--json` prints exactly one line **after the socket is listening** (not merely spawned):

```json
{"url":"http://127.0.0.1:52953/","port":52953,"host":"127.0.0.1","pid":40311,"artifact":"/…/designs/appbox-app"}
```

Built at `appboxd/lib/design_server.dart:1041-1047` — note it registers and reports the
**bound** port, so with `--port 0` the reported port is the real one. Failures go to
stderr as plain text with an empty stdout, so a parsed ready-record is never ambiguous.

Exit codes (`design_server.dart:32-36`, usage at `:963`):

| code | meaning |
|---|---|
| 0 | ok |
| 64 | bad usage |
| 66 | no such artifact |
| 69 | port already in use (`design_server.dart:1023`) |
| 70 | other |
| 77 | not allowed to bind host:port (`design_server.dart:1028`) |

`serve` accepts a **path or a bare design name** — `appbox-app` resolves to
`designs/appbox-app`.

**Process-registry hazard for a panel that spawns servers:** Ctrl+C / shutdown stops
*every instance serving the same artifact*, tracked as pidfiles
(`registerServeInstance`, `design_server.dart:1041`). This was a real bug — one ^C used to
SIGTERM every design server on the machine because the predicate was a constant
(`appboxd/test/serve_scope_test.dart:1-5`). Scoping is now artifact + port
(`design_server.dart:992-996`, guarded on `a.port != 0`).

### What it serves

Not a static build, not Flutter web, not a template engine in the usual sense. It serves
**server-rendered HTML per route**, produced by executing the artifact's own ES modules:

- Dart owns HTTP, routing, sessions, prefs, timers, hot reload, pidfiles.
- The artifact's JS (`app.routes.js`, `*_viewmodel.js`, `*.tsx` views) executes in a
  **headless-Chrome tab driven over CDP** — the "worker".
  Header comment: `appboxd/lib/design_server.dart:1-19`; worker rationale:
  `appboxd/lib/design_server/worker.dart:1-14`.
- History: this is a port of the retired Node runtime `skills/appbox-designer/runtime/serve.mjs`
  (archived under `archives/tooling-pre-dart/`). Stated at
  `skills/appbox-designer/runtime/README.md` ("The server is the Dart design server now",
  2026-07-31, commit 4f9c458). **Do not go looking for `serve.mjs` — it is gone.** What
  remains in `runtime/` is `vendor/` (SRI-pinned client libs) and `ladder.json`.

### Internal HTTP endpoints (the panel's real API surface)

All in `appboxd/lib/design_server.dart`:

| endpoint | line | purpose |
|---|---|---|
| `GET /__routes` | `:407` | `{"routes":[{"method":"GET","path":"/design"}, …]}` — the live route table |
| `GET /__projects` | `:419` | read-only project listing |
| `POST /__project_use` | `:445` | switch the overlaid project |
| `POST /__project_write` | `:381`, impl `:734` | **write one file inside the live-read project**; path-traversal rejected; triggers the project watcher → hot reload |
| `GET /__worker_page` | `:365` | the worker tab's own page |
| `GET /__worker_assets/*` | `:370` | worker-side assets (`islands_eager.js` etc.) |
| `POST /prefs/lang`, `/prefs/*` | `:~800` | locale/pref cookies |

`GET /__routes` is the one to poll if the panel wants to know what surfaces exist.

### The other `design` verbs (complete list)

From `appboxd/lib/design_cli.dart:89-117` and the usage block at `:42-77`:

`commission` · `lint` · `check-ladder` · `check-wiring` · `pseudolocalize` ·
`vendor-fetch` · `doctor` · `serve` · `eject` · `ds-check` · `record-asset` ·
`ds-import` · `selftest` · `probe`

### `design patch` — DOES NOT EXIST (verified negative)

- Absent from the `switch` in `appboxd/lib/design_cli.dart:89-117` and from the usage block.
- The only `patch` verbs in the repo are shorebird OTA (`appboxd/lib/deploy.dart:207`, `:569`).
- It is **desired, not built**, and named as a prerequisite in exactly one place:
  `docs/plans/arxa-harness-and-distribution.md:216` ("never freeform DOM/CSS writes …
  the engine `design patch` verb"), `:511`, `:522` ("Drag overlay stays deferred until
  `design patch` exists").
- The same plan at `:511-522` records that the arxa design panel **viewer was built
  2026-08-21** (commit `9f48fa37`) with iframe + rungs + URL field + remount button, and
  that the drag overlay is deliberately deferred behind this missing verb.

**The seam a `design patch` would be built on already exists**: `POST /__project_write`
(`design_server.dart:734`). It is a confined single-file write into the live-read project,
name-validated, traversal-rejected, and the project watcher hot-reloads the worker on its
own afterwards. See §7.

---

## 2. Live reload — the single most important answer

**Transport: none. There is no push channel. Reload is server-side only; the browser
learns nothing and must re-request.**

### What actually happens

1. `Directory(dir).watch(recursive: true)` on the artifact dir — `design_server.dart:891-895`.
   A second watcher on the overlaid project dir — `:904-906`. Disabled by `--no-watch`
   (`:180-181`, `:348-350`). If the platform doesn't support watching, hot reload is
   silently disabled (`:898`).
2. Events debounce 200 ms into `_scheduleReload()` — `design_server.dart:867-875`.
3. `_reloadAndRefreshRoutes()` calls `_worker.reload()` then re-registers the route table
   — `design_server.dart:885-889`. Refreshing routes *after* the reload settles is
   deliberate: renaming a route used to hot-reload the view but leave the route dead
   (`:877-884`).
4. `JsWorker.reload()` re-imports the artifact modules **cache-busted in the same Chrome
   tab** — `worker.dart:799-811`. Reload coalescing: an in-flight reload sets
   `_reloadQueued` rather than stacking (`worker.dart:784-805`) because one
   `POST /__project_write` writing two files produces two watcher events.
5. A request that arrives **while a reload is in flight** waits on
   `JsWorker.reloadInFlight` up to `_kReloadGrace` = **3800 ms**
   (`design_server.dart:224`, wait at `:655-664`). On timeout the server answers
   **HTTP 503** with the `errorSurface.reloading` page: *"The design server is reloading
   after a file change. Try again in a moment."* (`design_server.dart:73-79`).
   Measured reload cost: ~850 ms typical, 948 ms slowest observed (`:219-224`).

### Consequences for the panel — read this before writing code

- **The browser is never told anything changed.** The iframe shows stale HTML until the
  panel re-navigates or the user clicks something. The existing arxa panel's
  "remount the iframe on demand" is not a limitation of the panel — it is the *only*
  mechanism available. The claim in the panel's docs that "live reload comes from the
  design server itself" is **true only for the server's own render**, not for the
  connected browser.
- **Any auto-remount must tolerate a 503.** A remount fired right after a file write
  will very often land inside the 3800 ms reload window and render the
  `errorSurface.reloading` page. Retry the 503 (a short backoff, ~1 s, up to ~4 s) or the
  panel will flash an error surface at the user on every save.
- htmx 4xx/5xx are retargeted into `#toasts` by the artifact's own config
  (`design_server.dart:87`, `:522`, `:536`) — that is artifact-side behavior, not a
  reload signal.

### Negative evidence (this is a verified absence, not an unchecked assumption)

- No `text/event-stream`, `EventSource`, `WebSocketTransformer`, or HTTP upgrade handling
  anywhere in `appboxd/lib` outside `cdp.dart` and `lens/`, which use WebSocket to talk to
  **Chrome**, not to a design-panel client. The only `WebSocketException` reference is
  error classification at `worker.dart:733`. (Scoped to the design server's own request
  path — `gateway.dart:216` does do SSE, but that is the `appbox serve` LLM gateway, a
  different process and verb entirely; see §4.)
- No `EventSource` / `WebSocket` / `location.reload` / `setInterval` in any worker asset:
  `appboxd/lib/design_server/worker_assets/{islands_eager.js,worker_shim.js,worker_page.html,fs_shim.js}`.
- No `hx-ext` / `sse-connect` / `ws-connect` / `hx-trigger="every …"` in any artifact
  (`designs/`, `kit/`, `skills/appbox-designer/examples/`).
- **One nuance worth knowing:** `hx-sse.min.js` and `sse.js` **are vendored** in
  `skills/appbox-designer/runtime/vendor/`. They are unused, and the artifacts' own
  `base.tsx` records why: *"support extensions are gone — hx-ext does not exist in v4"*
  (`designs/appbox-studio/ui/common/base.tsx:79`, same line in `appbox-studio-v2`). So an
  SSE client library sits on disk but the htmx version in use cannot mount it as an
  extension. **INFERRED:** adding SSE would mean a first-party island under ADR-0009
  rather than an htmx extension.

---

## 3. Rungs and viewports

### `rung` IS a first-class engine concept

Ratified vocabulary, deliberately kept. `docs/plans/rung-to-viewport-sweep.md` is
**CLOSED — decision 2026-08-09: keep `rung`** (option C). The rename to `viewport` was
rejected because `viewport` already means *the window* ("viewport lock") and the rename
would make the rung the ladder. Doctrine: *viewport ladder → rungs are positions on it*.

### The authoritative ladder

**`skills/appbox-designer/runtime/ladder.json`** is the runtime contract:

| rung | width | height | window size class |
|---|---|---|---|
| `compact` | 390 | 844 | compact |
| `medium` | 744 | 1133 | medium |
| `expanded` | 1280 | **832** | expanded |

`boundaries: [600, 840]`. Widths sit *inside* Material 3 window size classes, never on a
boundary, so a frozen render lands unambiguously in one class.

Doctrine doc: `skills/appbox-designer/references/viewport-ladder.md` — same table, and it
states heights "pair with the widths (390×844, 744×1133, 1280×832) but are far less
load-bearing — surfaces scroll; classes branch on width alone."

`appbox design check-ladder` (pure core `checkLadderFromInputs` at
`appboxd/lib/design_tools.dart:560-613`, CLI wrapper `designCheckLadder` at `:616-645`)
cross-checks **exactly these two files** and nothing else: every config rung
must appear in the doc table with the same width, every doc rung must exist in the config,
and no rung may sit on a class boundary.

### The 1280×800 vs 1280×832 discrepancy — resolved

`config/appbox.config.json:4-8` carries a *different* map under a *different* vocabulary:

```json
"viewports": { "mobile": {390,844}, "tablet": {744,1133}, "desktop": {1280,800} }
```

**`ladder.json` wins.** `check-ladder` never reads `config/appbox.config.json`, so this
file is outside the drift check and its 800 is unpoliced. Use **1280×832** — it is the
value in the runtime contract, the doctrine doc, the lens's hardcoded fallback ladder
(`appboxd/lib/lens_cli.dart:825-829`: `_Rung('compact',390,844)`,
`_Rung('medium',744,1133)`, `_Rung('expanded',1280,832)`), the recorded evidence goldens
(`designs/appbox-studio/evidence/tsx-vs-master/README.md:18-29`), and the rungs the arxa
panel already ships (`docs/plans/arxa-harness-and-distribution.md:511`). Treat the
`mobile/tablet/desktop` names as the legacy vocabulary and `compact/medium/expanded` as
the current one.

### Which rungs are ACTIVE is derived, never chosen

Resolution order (`appboxd/lib/lens_cli.dart:831-865`):
`--rungs` flag > `$APPBOX_LADDER` env > the artifact's `_d_meta.json` `.ladder` key >
all rungs in `ladder.json`. `ladder.json`'s own `_note` says: *"Which rungs are ACTIVE for
a project is derived from its targets — do not edit this file to select rungs."*

### Does the server render per rung? **No.** (verified negative)

`grep -n "queryParameters|'vp'|viewport|rung|width|height" appboxd/lib/design_server.dart`
returns exactly four lines, and none of them is a size parameter:

- `:109` — the literal `<meta name="viewport" content="width=device-width, initial-scale=1">`
  in the error-page template.
- `:558`, `:623`, `:790` — `req.uri.queryParameters`, used **only** for locale negotiation
  (`lang`), never for dimensions.

The same grep for `viewport|rung|'vp'` over `appboxd/lib/design_server/worker.dart` returns
**nothing**. So neither the HTTP layer nor the render worker has any concept of a rung or a
viewport size.

The server serves **one document per route**; the *client* sizes it. Rungs materialize in
three other places:

1. **The lens** — `appbox lens shoot <url> --rungs=compact,medium,expanded`
   (`appboxd/lib/lens_cli.dart:35`, loop at `:933`) drives `CdpSession.setViewport` per
   rung and screenshots each. This is capture-time, one navigation per rung.
2. **The artifact's own viewer** — `designs/appbox-studio/ui/common/integration_viewer.md`
   describes a `vp` query param (`mobile|tablet|desktop`, default mobile) and a per-screen
   `s.tile {vp,width,height}`. That is a *feature of that one design artifact's viewer
   surface*, authored in its views — not a server capability, and it uses the legacy
   vocabulary.
3. **Responsive view files** — a surface is authored as
   `main_shell_view.mobile.tsx` / `.tablet.tsx` / `.desktop.tsx` plus a dispatching
   `main_shell_view.tsx` (see `skills/appbox-designer/examples/hello-hda/ui/views/main_shell/`).
   The per-rung variants are **files on disk**, selected at render time by the view's own
   logic — so per-rung output is authored, not parameterized by the server.

**Consequence for the panel:** three iframes at true pixel size against the same origin is
exactly right and is the only available approach. Each rung is an independent HTTP
request; there is no way to ask the server for "the compact render" specifically.

---

## 4. What generates the UI — the pipeline

### Stages (skill chain)

`appbox-orchestrator` (Ø) → `appbox-story-mapper` / `appbox-moodboarder` (0, optional) →
`appbox-intake` (1) → **`appbox-designer` (2)** → `appbox-scaffolder` (3) →
`appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9);
cross-cutting `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10).
FSM phases: `appboxd/lib/phases.dart`. Map: `docs/appbox-system-map.md`,
`docs/research/pipeline-map.md` §1.

### Intermediate formats

| artifact | what it is |
|---|---|
| `intake/registry.json` | the **only authoring surface** — the view registry (ids, routes, tiles) |
| `intake/flows.json` | the flows SSOT — `{from, to, trigger}` edges over registry ids |
| `_d_meta.json` | per-project asset/DS/ladder binding (`design_tools.dart:2886-3030`, `metaFile` const at `:2897`) |
| `structure.json` | the **FROZEN** output of stage 2, threading an optional top-level `flows` array; the scaffolder's only input |
| `*.tsx` views + `*_viewmodel.js` + fixtures | the artifact itself — MVVM, ES modules |

The designer skill's own words: the artifact is "three switchable lenses over one view
registry" — **prototype** (wired nav over each entry's `route`), **flows** (edge graph),
**views** (tile inventory) — never three separate artifacts
(`skills/appbox-designer/SKILL.md`, "The output triad"; binding contract in
`skills/appbox-designer/DESIGN-ARCHITECTURE.md`).

The design viewer **live-reads AND edits `intake/flows.json` directly — never a copy**
(SKILL.md, Pipeline position). That edit path is `POST /__project_write`.

### Render pipeline at serve time (the hot path)

`appboxd/lib/design_server/worker.dart:1-14` and `:395-410`:

1. At boot and on every hot reload, Dart scans the artifact's `.tsx` view inventory.
2. `generateRenderTsx(artifactDir, {projectDir})` (`appboxd/lib/design_tools.dart:2305`)
   synthesizes a `render.tsx` module that imports every view.
3. A browser-compatible `icon.tsx` is generated (reads `globalThis.__icons` instead of
   `node:fs`).
4. **esbuild** bundles it all into one self-contained ESM file
   (`design_tools.dart:2076-2110`; pinned invocation `_esbuildCmd` at `:1767-1774` —
   prefers the skill's lockfile-pinned binary, falls back to `npx --yes esbuild@0.25.12`,
   never a floating `npx esbuild`).
5. The bundle is injected into Chrome as a **blob URL**; `__boot` dynamically imports it.
6. Each HTTP request → `JsWorker.dispatch(...)` (`worker.dart:658-704`) runs the artifact's
   viewmodel layer in the tab and returns a `WorkerResponse` (HTML). Dart writes it out.
7. Failure modes are graceful: a TSX syntax error leaves `bundleError` set and every route
   answers 500 + toast while it stands (`worker.dart:316-330`, `:621-624`); a viewmodel
   exception is a 500, never a crashed server; a tab that lost `globalThis.__dispatch`
   self-heals by rebooting (`worker.dart:704-746`, `:926`).

An in-memory prefetch built by scanning the artifact dir backs the render path with **sync
lookups only** — refreshed on hot reload (`worker.dart:133-134`).

### Where an LLM plugs in today

**Nowhere in the design-serve render path.** There is no LLM call anywhere in
`design_server.dart`, `worker.dart`, or `design_tools.dart`. Design artifacts are authored
by an **agent using the `appbox-designer` skill** — an agent writing `.tsx`/`.js`/`.json`
files to disk with ordinary file tools. The server then renders whatever is on disk. The
LLM is *upstream of the filesystem*, not inside the server.

Two LLM-shaped things exist elsewhere in the engine, neither wired to design serve:

1. **The loopback gateway** — `appboxd/lib/gateway.dart`, mounted by
   `appboxd/lib/server.dart:12-22` under `appbox serve` (a *different* verb,
   `appboxd/bin/appbox.dart:115`). Serves `/llm/v1/chat/completions` (OpenAI shape) and
   `/llm/v1/messages` (Anthropic shape), routed through `config/model-fabric.json`
   (`gateway.dart:75`, `:111-115`, `:121-126`). It **does support streaming**, but as
   *pass-through only*: `_streamUpstream` (`gateway.dart:216`) refuses to stream when the
   client shape and upstream protocol differ (`:224-232`) — translated calls must set
   `stream=false`. Token-scoped by tier with usage recording.
2. **`kit/genui_bridge/`** — see §6. Exists, tested, **zero dependents**.

---

## 5. Streaming / incremental emit — batch only

**Nothing in the design pipeline emits progress events or partial output.**

Verified absence of `Stream<…>` / `StreamController` / `yield` / `progress` / `onProgress`
in: `design_server.dart`, `design_server/worker.dart`, `emit_htmx.dart`,
`emit_structure.dart`, `emit_stage.dart`, `scaffold.dart`, `blueprint.dart`,
`synthesize.dart`, `generate_view.dart`. All returned empty.

Every emit verb (`appbox emit story-map|scaffold|structure|htmx|playground|synthesize|blueprint|…`,
dispatched at `appboxd/bin/appbox.dart:656-712`) is produce-whole-artifact-then-return.
`emit_htmx.dart` even spawns a **node** producer and waits for a ready line
(`emit_htmx.dart:244-313`) before capturing — the most batch-shaped thing in the repo.

The only streaming machinery in the whole repo is (a) the LLM gateway's SSE pass-through
(`gateway.dart:216`) and (b) `kit/genui_bridge` (§6). Neither touches design serve.

---

## 6. `kit/genui_bridge` — the A2UI streaming path exists but is UNWIRED

This is the most consequential finding for the parent question, and the easiest to
misread, so state it precisely.

**What exists** (`kit/genui_bridge/`, a Flutter/Dart package `appbox_kit_genui_bridge`):

| file | what |
|---|---|
| `lib/src/appbox_kit_chat_stream.dart` | `abstract class AppBoxKitChatStream { Stream<String> complete(List<AppBoxKitChatMessage>, {AppBoxKitJsonSchema? schema}); }` — the one provider-agnostic abstraction |
| `lib/src/adapters/appbox_kit_openai_chat_stream.dart` | `POST {baseUrl}/v1/chat/completions`; also covers Ollama / llama.cpp / vLLM via `baseUrl` |
| `lib/src/adapters/appbox_kit_anthropic_chat_stream.dart` | `POST {baseUrl}/v1/messages` |
| `lib/src/appbox_kit_sse_transport.dart` | injectable SSE HTTP layer (how tests assert request shapes without network) |
| `lib/src/appbox_kit_a2ui_stream_parser.dart` | **incrementally parses LLM text chunks into UI messages** |
| `lib/src/appbox_kit_a2ui_message.dart` | A2UI envelope, protocol version pinned `v0.9` |
| `lib/src/appbox_kit_json_schema.dart` | bounded validator + `AppBoxKitSchemaError` for repair loops |

The parser (`appbox_kit_a2ui_stream_parser.dart:44-70`) mirrors flutter/genui's
`A2uiParserTransformer`: extracts ```` ```json ```` fences first, else matches a balanced
`{...}` (string- and escape-aware) **so messages split across any chunk boundary
assemble**; JSONL whitespace dropped; prose surfaces as `AppBoxKitA2uiTextEvent`; malformed
payloads become `AppBoxKitA2uiErrorEvent` (emitted, never thrown) so a consumer can feed
`raw` + `error` into a repair loop. Tests cover chunk-boundary splits down to one byte at
a time (`kit/genui_bridge/test/appbox_kit_a2ui_stream_parser_test.dart:16-100`).

**What does NOT exist — the critical part:**

- `grep -rln "appbox_kit_genui_bridge" --include=pubspec.yaml` over the whole repo returns
  **only `kit/genui_bridge/pubspec.yaml` itself**. Zero dependents.
- `grep -rn "genui_bridge|GenuiBridge|AppBoxKitA2ui|a2ui"` over `appboxd/lib` and
  `appboxd/bin` returns **nothing**. The engine does not import it.
- The design server has **no A2UI path** of any kind.

It lives in the **`kit/` layer — runtime libraries for generated Flutter apps**, i.e. the
capability is aimed at *a built app rendering generative UI at runtime*, not at *the
designer producing a design*. Reusing it for the design panel means lifting a Flutter-kit
package into the Dart engine and into a browser-facing HTML path — a real port, not a wire-up.

Related reading (intent, not implementation):
`docs/plans/inline-generative-ui-in-dsh.md` (dated 2026-08-22 — today; about rendering
generative UI *inside the dsh conversation thread* via dsh's `ctx.slots` keyed-slot
registry, a different target than the design panel),
`docs/research/flutter-genui.md`, `kit/genui_bridge/assets/a2ui/PROVENANCE.md`.

---

## 7. Answering the goal question

> *Can arxa designer generate live UI per rung, streamed into the panel as it is produced?*

**Not today.** Four independent gaps, in order of how much work each represents:

| # | gap | evidence |
|---|---|---|
| 1 | **No server→browser push.** Nothing tells a connected iframe that anything changed. | §2 |
| 2 | **No per-rung server render.** One document per route; the client sizes it. No rung or viewport parameter exists in the HTTP layer or the worker. | §3 |
| 3 | **No incremental emit.** Every generator is produce-whole-then-return. | §5 |
| 4 | **A2UI streaming machinery is unwired and in the `kit/` layer.** | §6 |

### The seams that already work — build on these

1. **`POST /__project_write`** (`design_server.dart:381`, impl `:734`) is a *working,
   confined, path-traversal-safe single-file write* into the live-read project, and the
   project watcher hot-reloads the worker automatically afterwards
   (`:904-906` → `:867` → `:885`). This is the write half of `design patch` and it exists
   today. A generator that writes a `.tsx` view here gets a re-render for free.
2. **`GET /__routes`** (`:407`) gives the panel the live route table after each reload —
   use it to discover new surfaces without guessing.
3. **The `--json` ready-record** (`:1041-1047`) makes spawn-and-wait deterministic.
4. **Per-rung view files** (`*_view.mobile.tsx` / `.tablet.tsx` / `.desktop.tsx`) mean
   "generate per rung" already has an authoring shape — write three files, not one
   parameterized render.
5. **`appbox lens shoot --rungs=…`** (`lens_cli.dart:35`, `:933`) already does the
   per-rung capture loop if the panel wants images rather than live iframes.

### Cheapest path to "streamed live UI" — **INFERRED** (design suggestion, not repo fact)

The smallest change that produces the requested behavior is **not** streaming HTML. It is:

1. Add an SSE endpoint to `design_server.dart` (e.g. `GET /__events`) that fires a
   `reloaded` event when `_reloadAndRefreshRoutes()` completes (`:885-889`) — a
   `StreamController` broadcast fanned to held-open `text/event-stream` responses. ~50
   lines; there is no existing scaffolding to reuse.
2. The panel listens and re-navigates each rung iframe on `reloaded`, **with 503 retry**
   (§2). The user perceives live per-rung UI because all three rungs refresh together.
3. Generation stays batch: the agent writes files (via `__project_write` or directly), the
   watcher fires, the worker rebundles, the event fans out. Streaming *token-by-token* UI
   would additionally require the A2UI port from §6 and a render path that accepts partial
   component trees — substantially larger, and nothing in the current architecture
   anticipates it.

The `design patch` verb the arxa plan is waiting on
(`docs/plans/arxa-harness-and-distribution.md:216,511,522`) is a thin CLI wrapper over
seam 1, not new infrastructure.

---

## 8. The agent-facing skills

### `skills/appbox-designer/` (stage 2)

Layout: `SKILL.md`, `DESIGN-ARCHITECTURE.md` (binding contract), `DESIGNER_playbook.mdx`,
`system-prompt.md`, `docs/adr/0001-0009`, `references/` (13 files), `built-in-skills/`
(18 task recipes: wireframe, hi-fi-design, interactive-prototype, mobile-prototype,
import-from-figma/github/html, productionize, …), `examples/hello-hda/` (a complete
reference artifact — read this first to understand artifact shape),
`starter-partials/`, `runtime/` (now only `vendor/` + `ladder.json` + `eject/` + `kit-facades/`).

Governing files, which the skill says **win over any prose elsewhere in it**:
- `references/showcase-anatomy.md` — `kit/showcase_app/lib` is *the structure contract,
  not an example*: folder layout, the `<app>_<feature>_` naming law, the five-file
  per-surface split, barrels, the two-tier widget placement law, the **closed 15-kind
  widget vocabulary**, mandatory `///` frontmatter.
- `references/delta-runs.md` — where input comes from and what may be touched.

How it invokes the engine: `appbox design commission <app-dir>` first (§0 of the skill —
compiles brief + direction + selected scored moodboard refs into `design/commission.md`;
a missing or stale commission means **STOP**), then authoring, then
`appbox design serve` to preview, `appbox design lint` / `check-wiring` / `check-ladder`
to validate, and the freeze emits `structure.json`. Output must be **structurally
isomorphic to `kit/showcase_app/lib`** so the scaffolder transliterates rather than
interprets.

### `skills/appbox-lens/` (cross-cutting stage 8)

Three files only: `SKILL.md`, `capability-map.md`, `LENS_playbook.mdx`. It is a **Dart
library first** — `appboxd/lib/lens.dart` over `appboxd/lib/cdp.dart`, with
`appboxd/lib/lens/{a11y,crawl,daemon,dom,motion,net,ocr,pixels,skeleton,states,tokens}.dart`
and `appboxd/lib/lens_cli.dart`.

Every invocation launches **its own headless Chrome** (`--headless=new`, throwaway temp
profile, ephemeral port), so parallel capture needs no port/profile juggling and the
user's browser is never touched. **Console/page errors always fail the lens**, regardless
of pixel match.

Verb table (`skills/appbox-lens/SKILL.md`): `shot`/`compare` → `captureGolden`/`compareGolden(byte|pixel|ssim)`;
`open`/`emu`/`scroll` → `CdpSession.navigateAndSettle`/`setViewport`/`screenshot(fullPage:)`;
`console` → `consoleErrors`/`pageErrors`; `click`/`key`/`hover`/`type`;
`tokens` → `extractTokens`; `dom`/`a11y`/`net`; `anim`/`flipbook`/`record`/`burst`;
`skeleton`/`skeleton-diff`/`states`; `shoot` → the per-rung ladder pass.

Standing doctrine in both skills: **for anything regarding appbox, appbox's own tools come
first**; if a verb is missing, extend `appboxd/lib/lens.dart` / `cdp.dart` — never reach
for `archives/tooling-pre-dart/`.

---

## Appendix — quick file index for the implementer

| concern | file |
|---|---|
| serve entrypoint / HTTP / routing / watcher | `appboxd/lib/design_server.dart` |
| CDP worker, esbuild bundling, dispatch, reload | `appboxd/lib/design_server/worker.dart` |
| `design` subcommand dispatch | `appboxd/lib/design_cli.dart` |
| `generateRenderTsx`, check-ladder, `_d_meta.json`, eject | `appboxd/lib/design_tools.dart` |
| l10n / ARB parsing for the server | `appboxd/lib/design_server/l10n.dart` |
| worker-side JS assets | `appboxd/lib/design_server/worker_assets/` |
| rung ladder (authoritative) | `skills/appbox-designer/runtime/ladder.json` |
| rung doctrine | `skills/appbox-designer/references/viewport-ladder.md` |
| legacy viewport map (do not use for rungs) | `config/appbox.config.json:3-8` |
| per-rung capture | `appboxd/lib/lens_cli.dart:813-975` |
| LLM gateway (separate `appbox serve` verb) | `appboxd/lib/gateway.dart`, `appboxd/lib/server.dart` |
| A2UI streaming (unwired, `kit/` layer) | `kit/genui_bridge/lib/src/` |
| arxa panel intent + the missing `design patch` | `docs/plans/arxa-harness-and-distribution.md:216,511,522` |
| server behavior contract (15 behaviors) | `appboxd/test/design_server_test.dart` |
| multi-server / pidfile scoping contract | `appboxd/test/serve_scope_test.dart` |
