# Flutter GenUI — research digest (2026-07-28)

Captured by web research against the live docs; sources linked inline.
Status flags: UNVERIFIED items were not confirmable from official pages.

## Identity & status

- Package: [`genui` on pub.dev](https://pub.dev/packages/genui), publisher
  `labs.flutter.dev` (official Flutter labs). Latest **0.10.1** (2026-07-20).
  Rapid cadence: 0.5.0 Nov 2025 → 0.10.1 Jul 2026. BSD-3-Clause.
  Repo: [github.com/flutter/genui](https://github.com/flutter/genui)
  (monorepo: `genui`, `genui_a2a`, `a2ui_core`, `genai_primitives`,
  `json_schema_builder`).
- README verbatim: **"Status: highly experimental — the API will change
  (sometimes drastically)"**. Underlying [A2UI protocol](https://github.com/google/A2UI)
  is v0.8 Public Preview; genui "currently supports A2UI v0.9". Pre-1.0, pin
  versions, expect renames (0.9→0.10 already renamed
  `CoreCatalogItems`→`BasicCatalogItems`; `genui_google_generative_ai`
  discontinued).
- SDK floor: Dart >=3.10, Flutter >=3.35.7.

## Architecture

LLM never emits code — it streams **A2UI JSON messages**; the client renders
them against a **developer-controlled widget catalog**. Key APIs (verbatim):

- `Conversation` — primary facade/entry point; owns history, emits
  `ConversationSurfaceAdded/Removed` events.
- `SurfaceController(catalogs: [...])` — runtime engine; processes
  `A2uiMessage`s, manages the `DataModel`.
- `Catalog` / `CatalogItem(name:, dataSchema:, widgetBuilder:)` — the widget
  vocabulary; schemas via `json_schema_builder` (`S.object(properties: …)`).
- `DataModel` — observable store; widgets bind via `DataContext`
  (`{path: …}` bindings); only dependents rebuild.
- `A2uiTransportAdapter` — implement `onSend`, feed LLM chunks to
  `addChunk()`; incremental parse. **Streaming is the native model.**
- `A2uiMessage` verbs: `createSurface`, `updateComponents`, `updateDataModel`,
  `deleteSurface` (docs site shows older `surfaceUpdate`/`dataModelUpdate` —
  churn).
- `Surface` widget renders a surface by ID.
- Loop: user input → `onSend` → LLM stream → `addChunk()` → messages →
  surface rebuilds → interactions update `DataModel`/fire actions → packed
  back into a `ChatMessage` to the LLM.
- Rendering is fully client-side; the server's only job is "produce A2UI
  JSON". Remote-agent topology: **`genui_a2a`** (`A2uiAgentConnector`,
  websocket/SSE).

## Catalog

- Ships `BasicCatalogItems.asCatalog()`: audio_player, button, card,
  check_box, choice_picker, column, date_time_input, divider, icon, image,
  list, modal, row, slider, tabs, text, text_field, video. **No charts, no
  tables** — a build-pipeline catalog is custom work.
- Custom items are first-class:
  `BasicCatalogItems.asCatalog().copyWith(newItems: […])`. Docs: "most
  production apps will want to define a custom catalog."
- Theming: catalog widgets are ordinary Flutter widgets — your `Theme.of`
  applies. (UNVERIFIED: dedicated theme hooks beyond that.)

## LLM backends

- **Backend-agnostic; Firebase/Gemini NOT required.** README: "Any Model:
  integrate with any LLM that can generate structured JSON output."
  Documented paths: Firebase AI Logic (happy path), A2A server via
  `genui_a2a`, or "build your own" (`onSend` + any streaming HTTP client —
  Ollama, llama.cpp, arxa).
- No official local-LLM adapter ships. (UNVERIFIED: third-party ones.)

## Platforms

`simple_chat` example has runners for android, ios, linux, macos, web,
windows. iOS/macOS need the `com.apple.security.network.client` entitlement.
Core `genui` pulls `audioplayers`, `video_player`, `url_launcher`,
`flutter_markdown_plus` — plugin weight even if media widgets go unused.

## Examples & docs

- [docs.flutter.dev/ai/genui](https://docs.flutter.dev/ai/genui/get-started) —
  overview, components, get-started, input & events.
- Repo `examples/`: `simple_chat` (default catalog, AI surfaces interleaved
  in the message list) and **`verdure` — Flutter client + Python A2A server
  over localhost: the exact topology arxa ↔ arxa would use.**
- Repo `dev_tools/`: `catalog_gallery`, `composer`.
- A2UI repo: protocol spec + Lit/Angular/React renderers.

## Fit for arxa

- arxa can be the A2UI server: call the LLM itself and relay chunks, or
  expose enough A2A for `A2uiAgentConnector` (verdure pattern). No cloud.
- We build: the domain catalog (stage cards, charts, gate prompts, log
  viewers — none ship), the LLM bridge, and the system-prompt engineering.
- The main risk is structured-output reliability of the chosen model, not
  the framework. genui is rendering infra, not an agent.
- Alternative worth naming: the A2UI verb set is four messages — a
  hand-rolled JSON→widget renderer over our fixed catalog is simple. genui
  buys the parser, `DataModel` binding, event loop, and protocol alignment;
  costs an experimental 0.x dep with media-plugin weight.

## Design-phase consequence

The htmx prototypes simulate GenUI honestly: chat thread + server-rendered
component cards appended via htmx = the A2UI createSurface/update flow with
the fixture→repository→facade→viewmodel spine standing in for catalog data
schemas. What the design proves (calm, one-thing-at-a-time composition)
transfers directly to a genui `Catalog`.

## Verified against 0.10.1 (spike, 2026-07-29)

Spike at `spikes/genui/` (untracked) ran the mock-transport topology for
real — macOS + web, local canned A2UI stream, basic + custom catalog:

- `flutter analyze` clean, 2 widget tests pass, `flutter build macos` ✓,
  `flutter build web` ✓ (wasm dry-run ok). Media-plugin weight does not
  break either build.
- Mock seam confirmed: `A2uiTransportAdapter(onSend:)` + `addChunk()` —
  **this is the arxa injection point**. 18-char mid-token chunks
  reassemble correctly; `SurfaceController` buffers updates for
  not-yet-created surfaces.
- Custom `CatalogItem` with `S.object` schema + `{path:}` DataModel binding
  works; action round-trip (`UserActionEvent` → `UiInteractionPart` packed
  into a `ChatMessage`) works.
- Wire protocol is enforced strictly: `"version":"v0.9"` mandatory, exactly
  four verbs; anything else throws `A2uiValidationError` — stale docs fail
  loudly, not silently.
- **Corrections to the digest above** (spike read the .pub-cache source):
  `BasicCatalogItems` already existed in 0.9.2 (the rename predates it);
  `Surface` takes a `SurfaceContext` from `controller.contextFor(id)`, not
  an id; `createSurface` does NOT nest components — flat `updateComponents`
  maps, root component must be `id:"root"`.
- Costs: ~65–70 extra transitive packages (audioplayers/video_player/
  url_launcher are compile-time deps even unused; `asNoAssetCatalog()`
  trims catalog items, not native deps); custom schemas need a direct
  `json_schema_builder` dep; arxa's macOS entitlements lack
  `com.apple.security.network.client` — required the day arxa is reached
  over HTTP, localhost included.
- Still unknown after spike: iOS/Android builds, `genui_a2a`/
  `A2uiAgentConnector`, real-LLM structured-output reliability (that last
  one is `genui_bridge`'s whole reason to exist).
