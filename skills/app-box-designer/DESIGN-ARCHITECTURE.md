# DESIGN-ARCHITECTURE

> **The authored layer** — `registry.json`, `surfaceId`, `app.routes.js`
> and `tabRoots` — is specified in
> [`references/app-architecture.md`](references/app-architecture.md). This
> file remains the binding contract for the data spine and the motion
> vocabulary; that file adds the layers the app_box pipeline consumes.


Version: 1.0.0
Date: 2026-07-24

This is the contract for how an Artifact built by this skill organizes data, state, and motion. It exists independently of any single Artifact — a Surface, a route, a fixture must all be traceable back to one of the sections below. Where the current reference app (`examples/hello-hda/`) does not yet instantiate a layer described here, that layer is specified as required target structure: new Artifacts must conform to it from creation, not retrofit it later.

## The data spine

Every piece of state an Artifact renders travels through five stages, in order:

1. **Seed** — a per-table SSOT (JSON or YAML) checked into the Artifact, one file per domain concept, hand-authored once.
2. **Fixture generation** — a small script turns seed into the on-disk shape a Model actually consumes. This repo has no generator today; new Artifacts add one under `models/<domain>_model/generate.mjs` (or equivalent) rather than hand-editing generated files.
3. **Model** — `models/<domain>_model/` holds the generated fixture plus the shape/schema comment describing it. Nothing under `models/` is hand-edited; it is always regenerated from seed.
4. **Services** — `services/repositories/*_repository.mjs` read Models and expose them as plain data. `services/facades/*_facade.mjs` compose one or more repositories into the shape a ViewModel actually wants.
5. **ViewModel → View** — a `*_viewmodel.js` calls facades only (never repositories directly), builds render context, and hands it to its co-located `*_view.html` (Nunjucks) for a full page or Named Fragment render.

Each stage only talks to its immediate neighbor. A View never reaches past its ViewModel; a ViewModel never reaches past a Facade.

## Registry canon

This medium currently has no Surface registry — `app.routes.js` is a route table (`[method, path, handler]`), not an inventory, and it mixes real Surfaces with non-page endpoints (form posts, poll targets, OOB fragments). The contract requires a separate registry, one entry per Surface, with exactly four fields:

- `id` — stable identifier, derived from the Surface's own path: `<shell>/<surface>` (e.g. `main/prefs`).
- `label` — human-readable name for nav/breadcrumb use.
- `surface` — nullable. Holds the render target (`ui/views/<shell>_shell/<surface>_view.html`) for a real page; `null` for entries that represent state (a toast, a dialog, an overlay) with no independent URL of its own.
- `roles` — array, required even when every Surface is open to everyone (`['*']` is a valid, explicit value, not an omission).

This medium historically shipped without a `surface` field; the contract now requires it on every entry — omit it only by setting it to `null`, never by leaving it out. Realize the registry server-side as a plain JS/JSON module (e.g. `registry.mjs` alongside `app.routes.js`), not a browser global — there is no client runtime to hold it. A route may reference a registry `id` as an extra field on its table row; the registry does not replace the route table, it indexes the subset of routes that are Surfaces.

## Services split

- `services/repositories/*_repository.mjs` — one per domain concept, read-only access to a Model's fixture. No facade logic, no request context.
- `services/facades/*_facade.mjs` — compose repositories, apply request-scoped logic (persona, filters, pagination), return exactly what a ViewModel needs.
- A loose service that fits neither role (e.g. a stateless formatter) lives at `services/` root, not inside either subfolder.

ViewModels import facades. They do not import repositories. If a ViewModel needs raw Model data with no composition, that is a signal the facade is trivial, not a license to skip it.

## Viewmodels

A ViewModel is its own artifact, not a section of a View. `*_viewmodel.js` co-located with `*_view.html` exports:

- context builders — pure functions producing the object a full-page or fragment render needs.
- handlers — `(c, h)` functions bound to routes, calling facades and using the `h.*` response helpers (`h.form`, `h.refresh`, `h.noContent`, OOB helpers) to decide full-page vs. Named-Fragment vs. no-content response, keyed off `HX-Request`.

A ViewModel never renders a template string itself and never touches a repository — both are boundary violations.

## Shared components (views)

A UI pattern that appears on two surfaces is extracted, never copied. The moment a second surface needs a rail, a card, a timeline bar, a shell nav, a composer, a viewer — it moves to a shared partial under `ui/common/` as a parameterized macro, and both surfaces call it. Three near-identical implementations of the same widget is the most expensive drift this medium allows: each copy silently diverges (the rail that pauses differently, the scrollbar that tints differently) and the scaffold downstream inherits the divergence.

- `ui/common/` owns cross-surface macros: shell chrome (nav, timeline), the rail (top bar, card shell, composer), the design viewer, primitives.
- Per-surface views keep only what is genuinely theirs: the card's domain content, the canvas artifact's body.
- Parameters travel through the macro's context (e.g. a `base` path prefix); session state stays namespaced per tab in the facade.
- The same rule applies to CSS: shared component styles live in the artifact's main stylesheet, not duplicated across per-surface CSS files. Scrollbars always blend (transparent track, theme-ink thumb) — see the starter's `app.css`.

## Motion vocabulary

No JS animation engine exists in this medium. Motion is realized entirely as CSS transitions/animations driven by htmx's swap-lifecycle classes and native browser primitives (View Transitions, Popover, `<details>`). Motion is the one channel that survives the pipeline freeze gate untouched — tokens and vocabulary below live in-artifact and are not subject to freeze.

Timing tokens (defined once, in a `:root` block shipped with the Artifact):

| Token | Value |
|---|---|
| `--motion-fast` | 150ms |
| `--motion-med` | 250ms |
| `--motion-slow` | 400ms |
| `--motion-vt` | 240ms |
| `--motion-ease` | `cubic-bezier(.2, .6, .2, 1)` |
| `--toast-ttl` | 5s |

Named vocabulary — the closed set. A Surface's own design-system doc may override one of these under its own `## Motion` heading, and only on deviation; absent an override, these apply globally.

| Name | Mechanism | Token(s) |
|---|---|---|
| `swap` | default content transition: outgoing content gets `.htmx-swapping` (opacity → 0), incoming gets `.htmx-added` (fade-in) | `--motion-fast` out, `--motion-med` in, `--motion-ease` |
| `traverse` | boosted navigation between Surfaces, same-document View Transition root crossfade (`::view-transition-old/new(root)`), zero JS via `globalViewTransitions: true` | `--motion-vt`, `--motion-ease` |
| `spotlight` | shared-element continuity across a `traverse`, element tagged with a stable `view-transition-name` | `--motion-vt`, `--motion-ease` |
| `reveal` | overlay/dialog open-close via Popover API, `@starting-style` + `transition-behavior: allow-discrete` on `opacity`/`translate`/`display`/`overlay`, plus `::backdrop` | `--motion-med`, `--motion-ease` |
| `disclose` | accordion expand/collapse, `<details>` content sized via `grid-template-rows: 0fr → 1fr` (or `interpolate-size: allow-keywords` where supported) | `--motion-med`, `--motion-ease` |
| `notify` | toast enter/exit, OOB-swapped node animates in then animates out and leaves the DOM after `--toast-ttl`, removal itself driven by the next server-issued swap | `--motion-med` in, `--motion-slow` out, `--toast-ttl` delay |
| `pending` | busy/loading state: `.htmx-request` toggles on the triggering element, `.htmx-indicator` children fade in, `.indicator-spin` rotates a spinner; skeleton shimmer for first-paint loads | `--motion-fast` |

All seven are gated inside `@media (prefers-reduced-motion: no-preference)`; reduced-motion users get the end-state instantly with no animated path. No eighth name gets added without deprecating one of these — the vocabulary stays closed so a Surface's motion is always describable as "which of the seven."

## Fixtures & provenance

A fixture's *shape* is medium-ergonomic and may differ from its seed row (a persona-keyed projection, a denormalized join for template convenience) — that is allowed. What is not allowed is a fixture with no seed behind it. Every file under `models/<domain>_model/` traces to exactly one seed table; if it can't be traced, it isn't a fixture, it's a stray file and should be deleted or promoted to seed. Hand-editing a generated fixture is a bug, not a shortcut — edit the seed and regenerate.

## Pipeline profile (optional overlay)

Everything above stands alone: a plain Artifact built from this contract needs no external pipeline to be complete, correct, or servable. This section is opt-in for callers that want to drive Artifact generation from an external orchestrator (FSM-style pipeline, multi-stage generator, or similar).

- The producer emits its output — seed, generated fixtures, registry, ViewModels, motion tokens — entirely in-artifact. A pipeline consumer builds from that output alone; it never reaches back into producer internals.
- Pipeline-specific metadata (stage IDs, gate names, freeze markers) is additive: it may be attached alongside registry entries or seed files as sibling metadata, never woven into the four required registry fields or the Model/Service/ViewModel boundary above.
- If no pipeline is present, this section does not apply and nothing in the core contract changes.
