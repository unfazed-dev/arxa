# Is idiomorph the right default swap strategy for a DOM-state-preserving htmx 2.x app?

Research date: 2026-08-02. Anchored to 2025-2026 sources; older sources flagged.

## TL;DR

Yes, with conditions. Idiomorph is the correct default *inside the coarse container* that holds the iframes/details/scroll regions — but only if every tile in the loop gets a **stable, server-rendered `id`**, and the iframe itself is either (a) never re-rendered with a changed `src` in the fragment, or (b) explicitly guarded with an idiomorph callback so a spurious/reformatted-but-same `src` doesn't trigger a reload. Idiomorph does not replace the need to **narrow swap targets** — for the 20-iframe container, the two fixes are complementary, not either/or. Confidence: 🔥 for wiring/mechanics (official docs + source), 🌡️ for the iframe-survives-untouched claim (strong indirect evidence + one direct GitHub issue, no first-party "we tested this" doc), ❄️ for performance-at-20-iframes and htmx-4 forward-compat claims (single secondary source, no benchmark).

---

## 1. Current status of idiomorph

- Latest release: **v0.7.4** (2025-09-29), per [github.com/bigskysoftware/idiomorph/releases](https://github.com/bigskysoftware/idiomorph/releases). CHANGELOG confirms the same date and lists a perf fix for focus-preservation checking and a bug fix for elements with attributes literally named `name="id"`. Prior releases: 0.7.3 (2025-03-05), 0.7.2 (2025-02-20), 0.7.1 (2025-02-13).
- Repo: [github.com/bigskysoftware/idiomorph](https://github.com/bigskysoftware/idiomorph), ~1.1k stars, 54 forks, actively maintained — day-to-day commits currently come from `@botandrose` and `@MichaelWest22`, under the `bigskysoftware` GitHub org (Carson Gross's org, the htmx author). htmx's own extensions page states idiomorph "was created by the htmx team" and lists it under **Core Extensions** — i.e., officially supported by the htmx team, not a random community extension. [htmx.org/extensions/](https://htmx.org/extensions/)
- For **htmx 2.x** (your target), idiomorph ships as a **separate extension**, not bundled: you load `idiomorph-ext.min.js` after `htmx.min.js` and opt in with `hx-ext="morph"`. [htmx.org/extensions/idiomorph/](https://htmx.org/extensions/idiomorph/)
- Forward-looking note (2026, not your version but worth flagging): per InfoWorld's April 2026 feature ["HTMX 4.0: Hypermedia finds a new gear"](https://www.infoworld.com/article/4150864/htmx-4-0-hypermedia-finds-a-new-gear.html), htmx 4.0 — a Fetch-API-based rewrite, still led by Carson Gross — bundles idiomorph into core and enables morphing "basically for free," adding first-class controls (`hx-morph-skip`, `hx-morph-skip-children`, `htmx.config.morphSkip`) that don't exist in the 2.x extension. This is a single secondary source (journalism, not the htmx changelog) — treat the specific attribute names as ❄️ until confirmed against htmx.org docs when you're ready to consider a migration. It does, however, corroborate that idiomorph is the direction the htmx team has bet on, for what that's worth to a "will this be maintained" judgment.
- Idiomorph has also been adopted outside the htmx ecosystem: 37Signals adopted it for **Turbo 8** in place of morphdom (README quotes Jorge Manrubia of 37Signals: "we started with morphdom, but eventually switched to idiomorph as we found it way more suitable... at least as fast"), and it's referenced as the merge engine behind Datastar. This is the strongest signal of real-world production hardening — Turbo 8/Turbo Frames' morphing is exercised at Basecamp/HEY scale.

## 2. Exact wiring

Load order and activation, straight from the official extension docs ([htmx.org/extensions/idiomorph/](https://htmx.org/extensions/idiomorph/)):

```html
<head>
  <script src="https://cdn.jsdelivr.net/npm/htmx.org@2.0.10/dist/htmx.min.js"></script>
  <script src="https://unpkg.com/idiomorph@0.7.4/dist/idiomorph-ext.min.js"></script>
</head>
<body hx-ext="morph">
```

Swap-attribute syntax, from the idiomorph README's htmx section:

- `hx-swap="morph"` — morph the outerHTML of the target (default form)
- `hx-swap="morph:outerHTML"` — same, explicit
- `hx-swap="morph:innerHTML"` — morph only the target's children, leaving the target element itself untouched
- `hx-swap="morph:<js-expr>"` — `<expr>` is any JS expression evaluated and passed as the config object to `Idiomorph.morph()`, e.g. `hx-swap="morph:{ignoreActiveValue:true}"`

**Global default**: `hx-swap` with no value falls back to `htmx.config.defaultSwapStyle` (default `innerHTML`) — this is a *global* htmx config key, and nothing in the docs suggests you can set `defaultSwapStyle` to `morph` and have it work without also registering the extension via `hx-ext`. In practice you set `hx-ext="morph"` on `<body>` (inherited by all descendants) and then either set `hx-swap="morph"` per-element or wrap it in a helper/template partial. There is no first-party single global switch that turns *all* unspecified `hx-swap` into morph mode — you still opt in per swap. [htmx.org/attributes/hx-swap/](https://htmx.org/attributes/hx-swap/)

Composability with View Transitions: `transition:true` is an independent *modifier*, `morph`/`morph:innerHTML` is the *strategy* — combine in one attribute: `hx-swap="morph:innerHTML transition:true"`. See §5 for caveats.

## 3. Does morphing preserve an `<iframe>` without reloading it? (load-bearing question)

**Mechanism, confirmed from source/README**: Idiomorph matches elements by building an **id-set** per node (the union of the node's own `id` plus every `id` found among its descendants), then merges the old node in place when id-sets intersect. Matched nodes are never removed-and-recreated; only their **attributes** are updated (added/removed/changed) to match the new node, in place, via `beforeAttributeUpdated`-gated attribute mutation. This is architecturally different from full-subtree replacement (`outerHTML` swap), where the browser tears down and rebuilds the DOM subtree, forcing every `<iframe>` inside it to reload its `src` from scratch (iframes reload whenever they are removed from the document and re-inserted, or whenever their `src` attribute is set/changed — this is standard iframe/browser behavior, not htmx-specific).

- The idiomorph README's own headline demonstration is literally an iframe (embedding a YouTube video) that keeps playing across a morph, specifically because morphdom (idiomorph's ancestor) *can't* tell the video's ancestor div should be discarded rather than morphed, while idiomorph's id-set approach gets it right and the "iframe element is never re-created and `src` is never touched." [github.com/bigskysoftware/idiomorph](https://github.com/bigskysoftware/idiomorph) (README + linked demo)
- 37Signals' Turbo 8 adoption note makes the same claim independently, from the consumer side.
- **Negative-case primary evidence** (the strongest confirmation, because it shows the *other* approach failing): [`bigskysoftware/htmx` issue #695, "hx-preserve does not work with iframes and input elements"](https://github.com/bigskysoftware/htmx/issues/695) (filed 2021, still referenced from `hx-preserve` docs today) — a user replaced a `<div hx-preserve>` spinner with an iframe and the iframe reloaded on every htmx-triggered swap, because `hx-preserve` clones by id but does not stop the browser from re-parsing the DOM subtree the way morphing does. htmx's own `hx-preserve` docs now explicitly say: *"Some elements cannot unfortunately be preserved properly, such as `<input type="text">`... iframes or certain types of videos. To tackle some of these cases we recommend the [morphdom extension]... which does a more elaborate DOM reconciliation."* [htmx.org/attributes/hx-preserve/](https://htmx.org/attributes/hx-preserve/) — Note: the doc still says "morphdom extension," which is stale/inconsistent wording (that extension is a separate, less-maintained community extension in `bigskysoftware/htmx-extensions`); idiomorph is the actively maintained, htmx-team-endorsed answer to the same problem and is what you should actually use. This is a documentation inconsistency worth flagging, not a recommendation to use morphdom.

**If the iframe's `src` DOES change** in the new fragment: idiomorph will update the `src` attribute in place (attribute-level diff, via `beforeAttributeUpdated`), and the browser will treat that exactly like any programmatic `src` mutation — **it reloads**, same as it would without morphing. Morphing does not suppress a genuine `src` change; it only avoids reload when the src is byte-identical and the node is matched (so no unnecessary reload, but no magic "diff the iframe's internal navigation" either). This is inference from the documented attribute-diffing mechanism plus standard iframe semantics, not a dedicated idiomorph test case I could find — flag as 🌡️.

**Practical guard for your case**: if your fragment regenerates the iframe tag with `src="...&t=<timestamp>"` or similar cache-busting query strings, or if attribute ordering/whitespace differs between renders in a way your templating engine treats as a "change," you'll get spurious reloads. Use idiomorph's `beforeAttributeUpdated(attributeName, node, mutationType)` callback (returns `false` to block the update) to explicitly guard `src` on iframe nodes, or ensure your server renders iframe `src` deterministically/unchanged across re-renders of the same iframe.

## 4. `id` requirements — how id-set matching works

From the idiomorph README ("id sets") and corroborated by [Radan Skorić's two-part deep dive](https://radan.dev/articles/turbo-morphing-deep-dive-idiomorph) (community, Turbo-focused but algorithm-identical to the htmx extension, since Turbo 8 vendors idiomorph directly):

- **Every element with an `id`** gets entered into a per-morph **id map** (built via `querySelectorAll('[id]')` over both old and new trees before diffing starts).
- Idiomorph computes an **id-set** per element = its own id (if any) plus the ids of *all descendants*. Two elements are considered a match candidate if their id-sets intersect — this is the key improvement over morphdom/nanomorph, which only look at a sibling's own `id`, not its children's ids, and therefore mis-match or lose state when structure shifts by one wrapper level.
- **Elements without an `id`** are matched by a soft/positional heuristic among siblings (tag name + position), which is fine for stable, non-reorderable content but is exactly where morph "guesses wrong" on reordered lists — this is the practical risk for your tile-reorder feature.
- **Practical authoring rule for your loop-of-tiles templates**: give every tile (and every stateful child inside it — iframe, `<details>`, scroll container) a **stable, content-derived `id`** that survives reordering (e.g. `id="tile-{{ record_id }}"`, not `id="tile-{{ loop.index }}"`). Index-based ids will misattribute state when the reorder button changes ordering, because idiomorph will match "tile 3" in old to "tile 3" in new even though they're semantically different tiles now. Since your explicit use case is a "reorder button," this is not a minor footnote — it is the central authoring constraint.
- Idiomorph also exposes `im-preserve="true"` and `im-re-append="true"` attributes, but per the README these are documented specifically under **head-tag merging** control (forcing/blocking script re-evaluation, preserving stylesheet links not present in the new head). It's unclear from the docs whether `im-preserve` is honored on body-content nodes as well as head nodes — treat that scope claim as ❄️ and verify empirically before relying on it outside `<head>`; for body-level "always keep this exact node regardless of new content," the documented, supported mechanism is the `beforeNodeRemoved`/`beforeNodeMorphed` callbacks, not `im-preserve`.

## 5. Known failure modes and gotchas

- **Web Components / custom elements don't survive `morph:outerHTML`**: [idiomorph issue #57](https://github.com/bigskysoftware/idiomorph/issues/57) — a custom element's `disconnectedCallback`/`connectedCallback` never fire during a morph (because the DOM node is preserved, not removed+re-added), so any web component with side effects tied to those lifecycle callbacks silently breaks, while a plain `outerHTML` swap works fine. If your design tool or the HTML it generates for end users embeds third-party web-component widgets, this is a direct hazard — audit for any such widgets before defaulting to morph.
- **`<details open>` and other ephemeral DOM state not represented as attributes on the server-rendered HTML get clobbered**: [issue #58](https://github.com/bigskysoftware/idiomorph/issues/58) and [issue #7](https://github.com/bigskysoftware/idiomorph/issues/7) — if the server's HTML for a `<details>` never includes `open`, but the user opened it client-side, a naive attribute-diff can still remove the client-added `open` attribute during morph, because idiomorph diffs "what's on the DOM now" against "what the server rendered" and the server didn't render `open`. This directly affects your "open `<details>` menus must survive" requirement — the safe pattern is either (a) don't let the server response omit state it doesn't own (echo current `open` state back, if knowable), or (b) use `beforeAttributeUpdated` to skip the `open` attribute specifically, or (c) mark the `<details>` node itself for skip via a callback.
- **Focus/selection state**: v0.7.1 added an on-by-default `restoreFocus` option specifically because older browsers lose focus/selection when a focused element's ancestor is moved during DOM mutation, even when the element itself is preserved — this was a real, needed fix, meaning pre-0.7.1 versions had a known focus-loss bug class. Make sure you're pinned to ≥0.7.1 (ideally 0.7.4).
- **`<script>` tags**: outside of `<head>`, I found no first-party documentation of how idiomorph treats `<script>` tags encountered in body content during a morph (re-execute vs. leave inert) — this is a documentation gap, not a confirmed behavior; flag ❄️ and test directly if your fragments include inline `<script>`.
- **Performance on large fragments**: community discussion (compressed web-search summary, not a citable single URL) reports morph cost scales with **id density** — pages/fragments with many `[id]` elements make the id-map build and id-set intersection more expensive; the same discussion's practical mitigations mirror the standard htmx advice regardless of morph: narrow swap targets, reduce id count inside large repeated fragments, or use `morph:<expr>` to pass an `ignoreActiveValue`-style config per swap. No official benchmark numbers found for a 20-iframe / large-tile-grid scenario — treat any specific perf claim here as ❄️ and benchmark your own fragment size.
- **View Transitions**: `transition:true` and `morph` compose in principle (`hx-swap="morph:innerHTML transition:true"`), but because morphing *intentionally* keeps DOM nodes in place rather than replacing them, elements that are morphed rather than added/removed don't produce the old/new snapshot pairs the View Transitions API needs to animate — only elements that are added, removed, or change `view-transition-name` actually animate. In other words: morph and view-transitions are not mutually exclusive, but you get transition animation only where content is structurally added/removed, not where it's attribute-diffed in place. This is useful for your case (you don't want a transition animation replaying inside the iframe pane anyway) but means don't expect morph+transition to give you element-level "fade the changed tile" animations for tiles that merely got attribute updates.

## 6. Alternatives and when NOT to morph

| Approach | What it does | Iframe-safe? | Fit for your case |
|---|---|---|---|
| **`hx-preserve`** | Clones an element by `id` across a swap, keeping the *same node* untouched | No — [confirmed broken for iframes/inputs, issue #695](https://github.com/bigskysoftware/htmx/issues/695); htmx's own docs disclaim iframe support | Insufficient alone; use for isolated single elements (e.g. one video player), not for a whole container of iframes/details/scroll regions |
| **idiomorph (`hx-ext="morph"`)** | Full-tree attribute-level diff/merge by id-set | Yes, if ided correctly and `src` doesn't spuriously change | Best fit for the coarse container itself |
| **Alpine's morph plugin** (`@alpinejs/morph`) | Same idea as idiomorph but Alpine-state-aware — preserves Alpine component state (`x-data`) across a morph, used via the `alpine-morph` htmx extension when Alpine components get swapped wholesale | Same DOM-preservation properties as idiomorph for plain elements (Alpine's morph is itself built to interoperate, and htmx's community extensions list documents `alpine-morph` specifically for retaining Alpine state on swap) | Only relevant if you also use Alpine.js for client state inside tiles; otherwise idiomorph alone covers you |
| **`morphdom`** | The original id-only DOM diffing lib idiomorph was built to improve on | Weaker — matches only on a node's own id, not its descendants' ids, so it silently gets structural changes around iframes wrong unless *every relevant ancestor* also has an id (per idiomorph's own README example) | Not recommended as a new choice in 2025-2026; superseded by idiomorph even by its own comparison, and largely abandoned relative to idiomorph's cadence |
| **Turbo/Hotwire's `data-turbo-permanent` and Turbo 8 morphing** | Turbo 8 vendors idiomorph directly for full-page/frame morphing; separately, `data-turbo-permanent` is Turbo's older, hx-preserve-equivalent mechanism | Turbo's morphing has the same iframe-preservation properties as idiomorph (it's the same algorithm); not directly usable from htmx, but validates the approach at Basecamp/HEY production scale | Not applicable directly (different framework) but its adoption is strong external validation of idiomorph specifically for the DOM-preservation problem you're solving |
| **Narrowing swap targets** | Instead of one coarse container swap, target only the specific tile/button/menu that changed, using precise `hx-target` + out-of-band swaps (`hx-swap-oob`, `hx-select-oob`) for anything else that must update | Sidesteps the whole problem — untouched iframes are never in the swap path at all | **The complementary fix, not a substitute.** Community guidance is consistent: prefer a smaller, precise target with OOB swaps for secondary regions; reserve morph for genuinely large state-holding subtrees you can't easily decompose. For a pin-toggle or reorder that only changes one tile's class/position, a narrow OOB-based swap is simpler and cheaper than morphing the entire 20-iframe container on every interaction — morphing is a *fallback* for the tool-generated / large-fragment cases where narrowing isn't practical, not a reason to stop narrowing where you can. |

**When practitioners say NOT to morph** (recurring theme across the official extension notes, `hx-preserve` docs, and the community discussion synthesized above): don't morph subtrees dominated by web components/custom elements with lifecycle side effects (§5); don't morph as a substitute for precise targeting when a small, well-scoped `hx-target` + OOB swap would do the same job more cheaply; don't rely on morph to preserve state that the server-rendered HTML doesn't itself represent as an attribute (the `<details open>` problem) without an explicit callback guard.

## Recommendation for this app

1. Add `hx-ext="morph"` at a root level (e.g. `<body>`) and switch the coarse container's swap from `outerHTml` to `hx-swap="morph:innerHTML"` (innerHTML variant, since you want to morph the container's contents, not replace the container element itself — matters less here but is the more conservative choice).
2. Audit every template that renders inside that container (tiles, iframes, `<details>`) and ensure **every** stateful node has a stable, record-derived `id` — this is non-negotiable for your reorder feature to morph correctly, not just a nicety.
3. Add a `beforeAttributeUpdated` guard (or ensure deterministic rendering) so a re-rendered iframe's `src` attribute is never spuriously different between renders — this is the single biggest risk to "no reload."
4. Add a callback or explicit server-side omission handling for `<details open>` state, since morph will fight you on ephemeral state the server doesn't echo back.
5. Apply the *same* reusable pattern (`hx-ext="morph"` + stable ids) to HTML the tool generates for end users — the wiring is identical; the only extra work is the id-authoring discipline in whatever templates/generators produce that output.
6. Do not treat morph as license to stop narrowing swap targets — for simple single-tile interactions (a pin toggle), a scoped OOB swap is still cheaper and simpler than re-morphing the whole container; use morph specifically where you can't decompose the target (the reorder case, or bulk regenerated content).

## Confidence and weakest claims

- 🔥 Wiring/syntax (`hx-ext="morph"`, `morph`/`morph:outerHTML`/`morph:innerHTML`/`morph:<expr>`), id-set matching mechanism, maintainer status, release cadence — all directly from official docs/README/CHANGELOG.
- 🌡️ "Iframe survives untouched, no reload" — strong indirect evidence (README's own flagship demo, Turbo adoption, the negative-case issue #695 for `hx-preserve`) but no dedicated first-party idiomorph test/doc titled exactly "iframes are safe." Verify empirically in your app before shipping.
- 🌡️ Behavior when iframe `src` genuinely changes — inferred from documented attribute-diff mechanism + standard browser iframe semantics, not a dedicated idiomorph doc/test.
- ❄️ Performance at scale (20 iframes / large tile grids) — no benchmark found; community claims about id-density cost are from compressed/aggregated web search summaries, not a single citable primary source.
- ❄️ `im-preserve` attribute scope (head-only vs. also body) — README only documents it under head-merging; unverified for general body nodes.
- ❄️ htmx 4.0 specifics (`hx-morph-skip` etc.) — single secondary (journalism) source; not your current version, included only as forward context.
- ❄️ `<script>` tag re-execution behavior during body-content morphs — no first-party documentation found; must be tested directly.

## Sources

- https://github.com/bigskysoftware/idiomorph (README, id-set explanation, Turbo testimonial, callbacks table)
- https://github.com/bigskysoftware/idiomorph/releases (version history)
- https://github.com/bigskysoftware/idiomorph/blob/main/CHANGELOG.md
- https://github.com/bigskysoftware/idiomorph/issues/57 (web components don't survive morph:outerHTML)
- https://github.com/bigskysoftware/idiomorph/issues/58 (preserve attribute values / details open)
- https://github.com/bigskysoftware/idiomorph/issues/27 (preserve input value if no attr change)
- https://github.com/bigskysoftware/idiomorph/issues/7 (ignore specified attributes/elements from morph)
- https://github.com/bigskysoftware/htmx/issues/695 (hx-preserve does not work with iframes and input elements)
- https://htmx.org/extensions/ (core vs. community extensions, idiomorph "created by the htmx team")
- https://htmx.org/extensions/idiomorph/ (installation, activation)
- https://htmx.org/attributes/hx-swap/ (hx-swap syntax, defaultSwapStyle, transition modifier)
- https://htmx.org/attributes/hx-preserve/ (iframe caveat, morphdom-extension recommendation)
- https://www.infoworld.com/article/4150864/htmx-4-0-hypermedia-finds-a-new-gear.html (htmx 4.0, idiomorph bundled into core, Apr 2026)
- https://radan.dev/articles/turbo-morphing-deep-dive-idiomorph (community deep dive on idiomorph's id-map algorithm, Turbo 8 context)
- https://alpinejs.dev/plugins/morph (Alpine morph plugin, state preservation across swaps)
- https://github.com/bigskysoftware/htmx-extensions (community extensions repo, includes alpine-morph, morphdom-swap)
