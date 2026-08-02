# htmx fragment/swap architecture for complex multi-panel apps

Research date: 2026-08-02. Scope: web research only (official htmx docs/essays + community/practitioner sources), no repo edits. Anchored to htmx 2.x (current stable) with forward notes on htmx 4.0 ("the Fetchening") where relevant.

Problem restated: a single "toggle pin on a tile" interaction currently does `hx-get` → `#panels` `outerHTML`, returning an 84 KB fragment that re-renders every panel (left, right, canvas, composer tray, timeline footer). App already has `hx-boost="true"` on `<body>`, `hx-sync="this:replace"`, `head-support` + `preload` extensions, `globalViewTransitions:true`, 68 `hx-target`s, 12 `hx-swap-oob`s.

---

## 1. Granularity principle — how big should a swap target be?

There is no single named "granularity pattern" from the core team; it's a stated tradeoff between two htmx design principles that pull in opposite directions:

- **Locality of Behaviour (LoB)** — "the behaviour of a unit of code should be as obvious as possible by looking only at that unit of code" ([htmx: Locality of Behaviour](https://htmx.org/essays/locality-of-behaviour/), Carson Gross, 2020). LoB favors *fewer, coarser* attributes/targets because spreading `hx-target`s across many small elements with inherited attributes makes behavior harder to trace ("spooky action at a distance").
- **Attribute inheritance vs. clarity** — the official [htmx quirks page](https://htmx.org/quirks/) explicitly documents this tension: inheriting `hx-target` from a parent keeps markup DRY, but "as the attributes get further away [from the] elements, you lose Locality of Behavior and it becomes more difficult to understand what an element is doing." Some teams disable inheritance entirely via `htmx.config.disableInheritance` to force every element to be locally legible — which pushes toward smaller, explicit targets.

**Practical decision rule synthesized from docs + practitioner sources:**
- Default swap strategy is `innerHTML` (not `outerHTML`) — many teams override the default to `outerHTML` only where it's actually needed, because `innerHTML` swaps are cheaper and don't require re-attaching the element's own id/attributes. Blanket `outerHTML` on a whole panel container, as in your `#panels` case, is the anti-pattern: it forces a full subtree re-render for what should be one attribute flip.
- Practitioner pattern seen in real dashboard code: **id-scoped targets per panel/section**, e.g. `hx-target="#{{name}}-content"` per widget, each independently `hx-get`-loadable with its own `hx-indicator`, rather than one shared container target. This is the same idea as component-level re-rendering in JS frameworks, done declaratively.
- Two named architectural approaches that operationalize "swap only the delta":
  - **`hx-swap-oob`** for updating several *disjoint* small regions from one response (see §2).
  - **Server-side "template fragments"** for rendering the *one* changed sub-view without duplicating templates (see §3).
- The line between "one big swap is simpler" and "swap only the delta": one big swap is acceptable when (a) the interaction legitimately changes most of what's on screen (navigation, filter-change re-rendering a whole list), or (b) the panel is small/cheap to regenerate. It stops being acceptable once payload size and re-render cost are dominated by *unchanged* content — which is exactly the failure mode described (84 KB to flip one boolean). At that point the fix is either narrowing the target (`hx-target` on the tile's own DOM node) or, if multiple regions genuinely need updating together, OOB swaps targeting only those regions.

Confidence: 🌡️ — the tension (LoB vs. DRY/inheritance) is directly documented; the specific "id-scoped per-panel target" pattern is practitioner-observed, not codified as an official named pattern.

---

## 2. Out-of-band swaps (`hx-swap-oob`) — accepted pattern and pitfalls

**Mechanism** ([htmx docs §out of band swaps](https://htmx.org/docs/#oob_swaps), [`hx-swap-oob` attribute](https://htmx.org/attributes/hx-swap-oob/)): a response can contain one element that's swapped into the request's `hx-target` normally, plus any number of additional top-level elements marked `hx-swap-oob="..."` that are swapped by matching their own `id` against an existing DOM element, regardless of where they appear in the response. `hx-swap-oob="true"`/`"outerHTML"` replaces the whole element; a swap-strategy value (`beforeend`, `afterbegin`, etc.) or a CSS-selector value routes to a different match target/strategy per fragment.

**Pitfalls and how practitioners keep it maintainable:**

- **Nested OOB collisions.** By default htmx processes *any* element with `hx-swap-oob` anywhere in the response, including nested inside the main swap target. This breaks reusable partials: a fragment that's sometimes rendered standalone (as an OOB update) and sometimes embedded inside a larger response gets silently stripped out when embedded, because it's still treated as an OOB instruction. Fix: set `htmx.config.allowNestedOobSwaps = false` (only top-level/adjacent elements are treated as OOB; nested `hx-swap-oob` attributes elsewhere are stripped and ignored) — or, more robustly, keep `hx-swap-oob` *out of* the reusable partial template and apply it only at the composition layer that assembles the multi-fragment response. ([GitHub discussion #3080](https://github.com/bigskysoftware/htmx/discussions/3080))
- **Ordering.** OOB swaps are processed *before* the main target swap, with OOB elements already stripped from the response by the time the main swap happens. Useful to know when a fragment appears to "vanish" from the main content — it was consumed as an OOB swap first.
- **ID collisions / determinism.** Since OOB matching is purely by `id`, every fragment needs a stable, deterministic id matching exactly one DOM node. Duplicate ids across panels (a realistic risk at 68 targets / 12 OOB swaps) will misroute swaps silently.
- **Non-standalone elements** (`<tr>`, `<td>`, `<tbody>`, `<li>`, etc., which the HTML spec doesn't allow to exist outside their parent structure) must be wrapped in a `<template>` tag in the OOB fragment; htmx unwraps it before swap.
- **OOB-only responses need a no-op main target** — if a response contains *only* OOB fragments, htmx still tries to swap "the rest" into the requesting element's `hx-target`; point that at an empty, otherwise-inert element to avoid clobbering something real.
- **`hx-select-oob`** ([docs](https://htmx.org/attributes/hx-select-oob/)) is the complementary primitive: instead of the *server* marking response fragments as OOB, the *client* declares "pull element with id X out of the response and swap it OOB" via `hx-select-oob="#alert"` (optionally `#alert:afterbegin` for a non-default strategy) alongside `hx-select` for the main content. This decouples the requesting element's markup from needing every possible OOB fragment pre-tagged server-side — useful when the same endpoint is called from different UI contexts that want different OOB behavior.
- **Swap-modifier support is inconsistent.** OOB swaps only reliably honor the base swap-strategy token; other `hx-swap` modifiers (`settle`, `delay`, and — notably — `transition`) are not consistently supported. `hx-swap-oob="outerHTML transition:true"` fails outright in htmx 2.x ([GitHub #1524](https://github.com/bigskysoftware/htmx/issues/1524); tracked more generally in [#2308](https://github.com/bigskysoftware/htmx/issues/2308)). Don't assume OOB fragments animate the same way primary swaps do.
- **Event asymmetry.** `htmx:beforeSwap` fires only for the main-target swap; `htmx:afterSwap` fires for the main swap *and* every OOB swap ([GitHub #2192](https://github.com/bigskysoftware/htmx/issues/2192)). Relevant if you're trying to hook lifecycle logic (e.g., re-initializing a JS island) uniformly across both.
- **Scale/maintainability.** The community explicitly flags that "you may end up with several disparate HTML elements to combine into a final result, and combining them can become an architectural challenge" — echoed by framework-integration requests (e.g. a Quarkus/Qute issue asking for first-class multi-fragment rendering support specifically to avoid hand-stitching OOB HTML: [quarkusio/quarkus#29247](https://github.com/quarkusio/quarkus/issues/29247)). The maintainable pattern that emerges: **compose OOB responses at one layer** (a "response assembler" that concatenates: primary fragment + N named OOB partials, each independently unit-testable), never inline `hx-swap-oob` markers deep inside shared partial templates.
- **Alternative for many simultaneous targets:** the community `multi-swap` extension (`htmx-ext-multi-swap`, part of [bigskysoftware/htmx-extensions](https://github.com/bigskysoftware/htmx-extensions)) lets one response swap N CSS-selected fragments with independent strategies without needing OOB id-matching semantics — worth evaluating at your 12-OOB scale, though it has its own rough edges (selectors after the first silently "not found" in some 2.0 combos — [extensions issue #72](https://github.com/bigskysoftware/htmx-extensions/issues/72); `afterSwap` not firing for multi-swap-replaced elements — [issue #2596](https://github.com/bigskysoftware/htmx/issues/2596); incompatible with `response-targets`).

Confidence: 🔥 — this section is grounded in official docs plus specific, verifiable GitHub issues.

---

## 3. Template organisation — one route, full page or any fragment, no duplication

**Named pattern: "Template Fragments."** Carson Gross's essay ([htmx: Template Fragments](https://htmx.org/essays/template-fragments/)) defines the problem directly: naively supporting partial rendering means splitting every partial out into its own template file (e.g. `archive-ui.html` included by `detail.html`), which multiplies files and, per Locality of Behaviour, makes it harder to see what a feature does by reducing everything to one file. "Template fragments" is the SSR-library feature that lets you render *part* of a single template file by name/block, without extracting it to a separate file. This is described as "relatively rare" among templating engines, which is why third-party add-ons exist:

- **jinja2-fragments** (Python/Jinja2, works with Flask/Starlette/FastAPI/Quart/Sanic/Litestar): `render_block(environment, "page.html.jinja2", "content", **ctx)` renders only the named `{% block content %}`; `render_blocks` (plural) renders multiple named blocks from the same template and concatenates them — the natural fit for building an OOB multi-fragment response from one file. Framework integrations expose this as a `block_name` kwarg on the normal `TemplateResponse`/`render()` call, so the *same* view function/route can render full page or fragment depending on the caller. (jinja2-fragments.readthedocs.io)
- **django-template-partials** (Django): defines `{% partialdef %}` / `{% partial %}` tags so a fragment is declared once inside the full-page template and rendered standalone via `render_block_to_string()` when needed — again, one file, one route, parametrized output. Practitioner guidance (spookylukey/django-htmx-patterns' `inline_partials.rst` vs `separate_partials.rst`, and the [BugBytes walkthrough](https://bugbytes.io/posts/rendering-template-fragments-with-django-template-partials/)) converges on: prefer the *inline partial* (fragment defined inside the full template) over physically separate partial files, specifically to reduce bandwidth/duplication and keep the permission/business logic that gates the fragment co-located with the fragment itself (a partial's authorization check can't be bypassed if it's inline to the block, vs. an included file that might be reachable from elsewhere).
- Equivalent tooling exists for MiniJinja and Askama (Rust). The underlying idea — named blocks in one template renderable in isolation — is the transferable concept regardless of stack; for a non-Python/Django server it means: pick (or write) a template engine wrapper that can render a named sub-block of a template file directly, rather than string-concatenating hand-written partial HTML.

**How the "full page vs. fragment" decision is made server-side:** htmx sends distinguishing request headers that a route/controller reads to decide what to render — this is the mechanism, not a named pattern, but it's the standard way people avoid route duplication:
- **`HX-Request: true`** — present on every htmx-initiated request; the most common branch condition ("if htmx request → render fragment; else → render full page with layout").
- **`HX-Target`** — the `id` of the target element for the request, letting one route serve *different* fragments depending on which UI region asked for it.
- **`HX-Trigger`** / **`HX-Trigger-Name`** — the id/name of the element that triggered the request, useful when several different triggers hit the same endpoint but expect different partials back.
- **`HX-Boosted`** — set specifically on boosted requests, distinct from ordinary htmx requests, useful if boosted navigation should still get a full-page render (see §4).
(All documented in [htmx docs — Request Headers / Response Headers](https://htmx.org/docs/#request-headers) — `HX-Request`, `HX-Target`, `HX-Trigger`, `HX-Trigger-Name`, `HX-Boosted`, `HX-Current-URL` are all sent on the request; `HX-Retarget`, `HX-Reswap`, `HX-Trigger` on the response let the server *override* the client's declared target/swap.)

**Synthesized recommendation for your app:** one template per panel-region, each internally decomposed into named fragments (candidate: one Jinja/Django/whatever-your-stack-uses block per tile, per composer-tray section, per timeline row-group). The pin-toggle route should render just the **tile fragment**, not the panel. If pinning a tile also needs to update a "pinned count" badge elsewhere and reorder a list, those become additional *named* OOB fragments from named blocks in their owning templates — composed by the response layer, not duplicated into the pin-toggle handler.

Confidence: 🔥 — official essay plus two independently-documented, actively maintained community libraries confirming the same pattern across two ecosystems.

---

## 4. `hx-boost` pitfalls — is body-level boost still good practice?

The official [htmx quirks page](https://htmx.org/quirks/) is candid about the costs of `hx-boost`. Key documented facts:

- `hx-boost` is sugar for: `hx-target` = body, `hx-get`/`hx-post` = the anchor/form's href/action, forced `hx-swap="innerHTML"`, `hx-push-url=true`.
- Boosting only swaps `<body>` **innerHTML**; anything relying on the new page's `<head>` (styles, scripts) is discarded, and global JS scope is *not* refreshed — this is exactly why your app also runs the `head-support` extension, which patches this specific gap by diffing/merging `<head>` content on boosted navigations.
- **Targeting `body` always forces an `innerHTML` swap "for historical reasons"** — you cannot change attributes on `<body>` itself via a boosted or targeted request. A real regression was reported where upgrading 1.9.12 → 2.0.1 caused boosted body-swaps to strip `<template>` elements from the DOM, silently breaking anything relying on a template-tag id as a fallback target ([GitHub #2776](https://github.com/bigskysoftware/htmx/issues/2776)).
- **State loss is the sharpest practical problem.** A body-level boost swap gives no hook for client-side state preservation — Alpine.js (and by extension any imperative JS state attached to the DOM) loses all component state and listeners on every boosted navigation unless manually re-initialized ([Alpine discussion #4485](https://github.com/alpinejs/alpine/discussions/4485)). The documented mitigation is **`hx-preserve`**, which exempts a marked container from replacement during any swap (not just boosted ones) — but it has known friction with certain element types (media players) and isn't a general fix.
- **Maintainer position is explicitly split.** In [htmx discussion #2041 — "Is hx-boost-ing the whole body a good practice?"](https://github.com/bigskysoftware/htmx/discussions/2041), core-team framing is pragmatic ("neither approach is inherently good or bad; boost was designed for both use cases"), but a competing, frequently-cited counter-view from within the same community is sharper: *ask whether you actually need to swap the whole page — if not, don't boost the body; use explicit `hx-get`/`hx-target` on the specific elements instead, trading a few more attributes for full control instead of "magic" that "can magically fail."* Some core contributors go further, arguing that because browsers have gotten faster at native navigation, `hx-boost` is increasingly an "odd one out" best avoided in new architecture.

**Answer for your app:** given you already have 68 explicit `hx-target`s, `hx-sync="this:replace"`, and OOB swaps doing fine-grained work, body-level `hx-boost="true"` is very likely fighting your own architecture rather than helping it — it exists as a convenience for plain-link/plain-form MPA navigation, not for a component-dense SPA-like shell. The 2026 community-leaning position is: **prefer explicit targeting for anything that isn't a top-level page navigation**; reserve `hx-boost` (if used at all) for actual full-page route changes, not for interactions within the multi-panel shell. This is consistent with what you're already doing for panel-level interactions (explicit targets) — the boost is arguably vestigial/risky at `<body>` scope given the state-loss and `<template>`-stripping issues above, especially combined with `globalViewTransitions` (see §6) and 12 OOB swaps in flight.

Confidence: 🌡️ — the documented facts (quirks page, discussion #2041, Alpine issue, #2776) are solid; the "2026 consensus leans away from body-boost" framing is a synthesis of a debate that the core team itself declines to resolve authoritatively — treat it as informed opinion, not settled doctrine.

---

## 5. "Islands" / HDA architecture for JS-driven components

**HDA (Hypermedia-Driven Application)** is the named architectural synthesis from the core team: "thesis: MPA, antithesis: SPA, synthesis: HDA" ([htmx: Hypermedia-Driven Applications](https://htmx.org/essays/hypermedia-driven-applications/), Carson Gross, 2022). Two constraints define it: (1) declarative HTML-embedded interactivity over imperative scripting, (2) server communication in terms of hypermedia (HTML), not JSON/RPC — preserving HATEOAS, unlike most SPAs.

**Islands are the sanctioned escape hatch when declarative HTML isn't enough**, laid out in [htmx: Hypermedia-Friendly Scripting](https://htmx.org/essays/hypermedia-friendly-scripting/) (Gross, 2022) as five rules: respect HATEOAS; client-side-only state is fine; use *events* to communicate between components; **use islands to isolate non-hypermedia components from the rest of the HDA**; optionally use inline scripting for genuinely local behavior.

Key mechanics relevant to your composer tray / canvas (the parts of your shell most likely to need real client-side interactivity — drag, multi-select, canvas rendering):

- **Isolation boundary test = state ownership.** Client-side-only, ephemeral UI state (hover, drag-in-progress, local selection) is fine to keep inside a JS island with no hypermedia exchange. The moment that state needs to be *persisted or reflected server-side* (e.g., a pin toggling), it should flow back out through a normal hypermedia exchange — i.e., the island fires a request or dispatches an event that a hypermedia control turns into a request, not a component managing its own server sync via fetch/JSON.
- **Events are the glue**, not shared JS state or prop-drilling: islands communicate outward via DOM events; a normal htmx-controlled element (an "outer hypermedia control") can listen for that event via `hx-trigger="eventName from:..."` and turn it into a request. This lets an island stay ignorant of hypermedia and lets the hypermedia layer stay ignorant of the island's internals.
- **Directionality**: it's much easier to embed a non-hypermedia island *inside* a larger HDA than to embed HDA behavior inside a JS-framework tree — informs where the "island" seam should sit (wrap the interactive widget, don't try to make the framework own the page shell).
- **Web Components as the island container** ([htmx: Web Components Work Great with htmx](https://htmx.org/essays/webcomponents-work-great/)) — a documented pattern: htmx keeps the server as source of truth for the hypermedia majority of the page; genuinely interactive pieces become standard custom elements, each self-initializing on `connectedCallback` (so they survive/re-initialize cleanly across swaps, unlike ad-hoc `addEventListener` wiring that gets orphaned when its container is replaced). One production write-up ([kore-nordmann.de](https://kore-nordmann.de/blog/htmx-and-web-components-instead-of-react.html)) reports ~20 vanilla web components covering the interactive islands of an otherwise-htmx app, explicitly citing longevity/maintainability (web standards over framework churn) as the reason. A parallel Lit-based write-up ([lorenstew.art](https://www.lorenstew.art/blog/eta-htmx-lit-stack)) frames Lit components as "islands of interactivity" that still carry `hx-*` attributes internally on their own buttons, i.e. the island isn't hypermedia-hostile — it still participates in the hypermedia model for anything that needs server sync.
- **Re-initialization concern (important for your swap-heavy shell):** because islands are DOM elements, they get destroyed and recreated whenever an ancestor is swapped (innerHTML/outerHTML). Web Components handle this cleanly via lifecycle callbacks; ad-hoc JS attached via imperative `document.querySelector`+listeners does not, and is the most common source of "my widget stopped working after a swap" bugs in htmx apps. This is a strong argument for standardizing islands as custom elements specifically *because* your shell does frequent fine-grained swapping — a component-lifecycle contract survives swaps that raw script blocks don't.

This maps directly onto "HTML their tool generates for end users": if the generated output itself needs interactive widgets, the same HDA/islands contract applies to *that* generated HTML too — keep interactive pieces as self-initializing custom elements wrapped around otherwise-plain, swap-safe hypermedia markup, rather than baking framework-specific mount code into generated output.

Confidence: 🔥 — this is the most authoritatively documented area (multiple first-party essays), corroborated by independent production write-ups reaching the same architecture from different stacks.

---

## 6. View Transitions (`globalViewTransitions:true`) interaction with fine-grained swaps/OOB

**Baseline mechanics** ([htmx docs — View Transitions](https://htmx.org/docs/#css_transitions), [`hx-swap` transition modifier](https://htmx.org/attributes/hx-swap/)): `htmx.config.globalViewTransitions = true` wraps *every* swap in `document.startViewTransition()`; per-swap `transition:true` on `hx-swap` opts a single swap in without the global flag; `htmx:beforeTransition` can be caught and `preventDefault()`-ed to fall back to a plain swap.

**Known friction points, verified against source/issues (not just blog claims):**

1. **OOB swaps don't reliably support the `transition` modifier.** `hx-swap-oob="outerHTML transition:true"` fails to swap at all in current htmx — the OOB code path only parses the base strategy token, not full `hx-swap` modifier syntax ([GitHub #1524](https://github.com/bigskysoftware/htmx/issues/1524)), and more generally OOB swaps don't honor most `hx-swap` modifiers (`settle`, `delay`, `transition`) — tracked as a real gap ([GitHub #2308](https://github.com/bigskysoftware/htmx/issues/2308)). With `globalViewTransitions:true` set app-wide (your case), the *main* target swap and any OOB swaps in the same response are not on equal footing with respect to transitions — worth explicit testing per-panel rather than assuming uniform behavior.
2. **Event asymmetry compounds this.** `htmx:beforeSwap` fires only for the main swap, `htmx:afterSwap` fires for main + all OOB swaps ([GitHub #2192](https://github.com/bigskysoftware/htmx/issues/2192)) — if you're trying to coordinate a single view transition spanning a main swap and its OOB siblings, the event model doesn't naturally give you one clean "everything is about to change" hook.
3. **Browser-level constraint (not htmx-specific, but load-bearing):** the View Transitions API itself supports only one active transition on the document at a time. Because `globalViewTransitions:true` triggers a `startViewTransition()` call *per htmx swap operation*, and a response with 12 OOB fragments plus a main swap is still processed as effectively one operation but multiple DOM mutations, rapid/overlapping htmx-triggered swaps (e.g., two panels updating in quick succession, or a swap firing while another's transition is still animating) risk transitions cancelling or visually stepping on each other. This risk is *architecturally inherent* to combining fine-grained/high-frequency swapping with a single global always-on transition flag — the more independently-triggerable targets you have (you have 68), the more likely two swaps' transitions overlap in time.
4. **Forward-looking, not yet shipped:** the core team's public roadmap essay ["The Fetchening"](https://htmx.org/essays/the-fetchening/) (htmx 4.0 preview) describes adding a *queue* for view transitions specifically so overlapping transitions complete sequentially instead of cancelling each other, plus a simplified OOB story. This is a **future-state fix, confirming the current-state problem** — i.e., the core team itself has identified "many simultaneous/overlapping view-transitioned swaps fight each other" as a real, known limitation of the current (2.x) implementation worth a breaking-version fix.

**Current guidance synthesized:** don't set `globalViewTransitions:true` as a blanket app-wide flag in a shell with dozens of independently-triggerable fine-grained targets and OOB swaps — that's exactly the combination the core team is redesigning for in 4.0 because it's currently fragile. Prefer scoping `transition:true` per-swap to the one or two regions where a visible transition is actually desired (e.g., the canvas or a modal), and let the rest swap plainly. If multiple regions must animate together, consolidate them into a single transitioned swap over a shared ancestor with per-element `view-transition-name` CSS, rather than relying on several independent `startViewTransition` calls (main + N OOB) to compose visually.

Confidence: 🌡️ — points 1–2 and 4 are directly sourced from official docs/issues/roadmap; point 3 (the "overlapping transitions fight" mechanism) is inferred from documented View Transitions API semantics plus the Fetchening essay's stated motivation, not from a single htmx-specific bug report reproducing exactly your 68-target scenario — this is the weakest claim in the report and should be validated empirically against your app before being treated as fact.

---

## Overall confidence: 🌡️

The architectural guidance (LoB vs. DRY tradeoff, template fragments, OOB composition discipline, islands/HDA) is well-grounded in first-party htmx essays plus corroborating independent implementations — high confidence. The `hx-boost` section is grounded in fact but its "should you still do this in 2026" conclusion is a synthesis of an explicitly unresolved core-team debate, not settled doctrine. The weakest claim in the whole report is the view-transitions §6 point 3 (overlapping/cancelling transitions at your specific 68-target, 12-OOB, `globalViewTransitions:true` scale) — it's inferred from API semantics and the Fetchening roadmap rather than directly observed in your app; recommend treating it as a hypothesis to test (trigger two independently-targeted swaps in quick succession with the view transitions devtools open) rather than an established fact before any remediation work is prioritized on it.

## Recommendations (synthesis, for the pin-toggle case specifically)

1. Stop targeting `#panels` `outerHTML` for a pin toggle. Target the tile's own element (`hx-target="this"` or `#tile-{id}`, `hx-swap="outerHTML"` on just that node).
2. If pinning must also update a badge/count and reorder a list, add those as 1–2 named OOB fragments composed at a response-assembly layer — not by re-rendering the owning panel.
3. Build fragments via a "template fragments" pattern (named block per tile/section in the owning template), so the pin-toggle route and the full-page route render from the same template file with no duplication — use `HX-Request`/`HX-Target` to decide fragment vs. full page server-side.
4. Reassess `hx-boost="true"` on `<body>` — likely unnecessary and possibly actively harmful (state loss, `<template>`-stripping precedent) given the app already does explicit fine-grained targeting everywhere else.
5. Set `htmx.config.allowNestedOobSwaps = false` given 12 existing OOB swaps, and audit for any partial reused both standalone and nested.
6. Scope `transition:true` per-region instead of `globalViewTransitions:true` app-wide; test overlapping-swap behavior explicitly given the OOB+transition gaps documented in #1524/#2308.
7. For genuinely interactive canvas/composer-tray widgets, standardize on Web Components as the island container so their lifecycle survives ancestor swaps — apply the same contract to HTML your tool generates for end users.

## Sources

- [htmx: Locality of Behaviour](https://htmx.org/essays/locality-of-behaviour/)
- [htmx quirks page](https://htmx.org/quirks/)
- [htmx docs — main documentation (AJAX, swapping, OOB, requests/responses, synchronization, view transitions)](https://htmx.org/docs/)
- [`hx-swap-oob` attribute](https://htmx.org/attributes/hx-swap-oob/)
- [`hx-select-oob` attribute](https://htmx.org/attributes/hx-select-oob/)
- [`hx-swap` attribute (transition modifier)](https://htmx.org/attributes/hx-swap/)
- [htmx: Template Fragments](https://htmx.org/essays/template-fragments/)
- [htmx: Hypermedia-Driven Applications](https://htmx.org/essays/hypermedia-driven-applications/)
- [htmx: Hypermedia-Friendly Scripting](https://htmx.org/essays/hypermedia-friendly-scripting/)
- [htmx: Web Components Work Great with htmx](https://htmx.org/essays/webcomponents-work-great/)
- [htmx: The Fetchening (4.0 preview)](https://htmx.org/essays/the-fetchening/)
- [htmx `response-targets` extension](https://htmx.org/extensions/response-targets/)
- [GitHub discussion #3080 — OOB swap behaviour / nested OOB](https://github.com/bigskysoftware/htmx/discussions/3080)
- [GitHub discussion #2041 — Is hx-boost-ing the whole body a good practice?](https://github.com/bigskysoftware/htmx/discussions/2041)
- [GitHub issue #2776 — hx-boost on body removing `<template>` elements](https://github.com/bigskysoftware/htmx/issues/2776)
- [GitHub issue #1524 — OOB swap + transition:true fails](https://github.com/bigskysoftware/htmx/issues/1524)
- [GitHub issue #2308 — hx-swap-oob should support all hx-swap modifiers](https://github.com/bigskysoftware/htmx/issues/2308)
- [GitHub issue #2192 — beforeSwap/afterSwap event asymmetry with OOB](https://github.com/bigskysoftware/htmx/issues/2192)
- [Alpine.js discussion #4485 — hx-boost breaking Alpine state](https://github.com/alpinejs/alpine/discussions/4485)
- [Ben Nadel — Using hx-preserve To Persist Elements Across Swaps](https://www.bennadel.com/blog/4790-using-hx-preserve-to-persist-elements-across-swaps-in-htmx.htm)
- [jinja2-fragments docs](https://jinja2-fragments.readthedocs.io/)
- [django-template-partials / BugBytes walkthrough](https://bugbytes.io/posts/rendering-template-fragments-with-django-template-partials/)
- [kore-nordmann.de — HTMX and Web Components Instead of React](https://kore-nordmann.de/blog/htmx-and-web-components-instead-of-react.html)
- [lorenstew.art — Eta, HTMX, and Lit stack](https://www.lorenstew.art/blog/eta-htmx-lit-stack)
- [bigskysoftware/htmx-extensions — multi-swap](https://github.com/bigskysoftware/htmx-extensions)
- [Quarkus/Qute issue #29247 — multi-fragment OOB rendering request](https://github.com/quarkusio/quarkus/issues/29247)
