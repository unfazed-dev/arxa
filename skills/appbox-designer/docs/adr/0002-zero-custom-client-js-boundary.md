# Zero custom client-side JS boundary

"No JS" scopes to the client rendering stack — htmx + CSS replaces React; the server is Node. Permitted in Artifacts: htmx 2.0.10 core plus Allowlisted official extensions (preload, head-support, sse; client-side-templates allowed but unrecommended — it inverts the HDA architecture), all vendored locally with SRI. Banned: `<script>` blocks, `hx-on:*`, `js:`-prefixed `hx-vals`/`hx-headers`, `[expr]` trigger filters. Enforcement is mechanical, not honor-system: `<meta name="htmx-config">` sets `allowEval:false` + `allowScriptTags:false` (banned features fail inert), plus a lint rule over generated HTML. Considered and rejected: htmx-core-only (loses preload snappiness and head merging), permitting `hx-on` (hand-written JS by another name, unprovable cleanliness).

**Amendment (2026-07) — the canvas island.** ONE named first-party exception: `assets/vendor/canvas.js`, a dependency-free pan/zoom module (~70 LOC) scoped to the design-canvas widget (`.dv-stage` / `.dv-rungs`). Shape: the "island" from htmx's hypermedia-friendly-scripting essay — view-state-only (zoom/pan never sync to the server), no globals, no framework, no build step; the same pattern as htmx's official SortableJS example. It lives in `runtime/vendor/` (the allowlist), ships in the starter, and loads `defer` from `base.html`; no SRI (first-party, not tracked by `fetch.mjs`/`manifest.json`). It is the ONLY first-party script an artifact may carry — everything else about the boundary stands unchanged. Research basis: continuous cursor-anchored zoom, drag-pan and drag-drop are impossible declaratively (htmx can hear `wheel`/`pointermove` but can only answer with HTTP requests), so the choice was this bounded island or no Figma-style canvas at all.

**Amendment (2026-07, canvas redesign) — inspect.js and drag.js islands.** Two
further named first-party exceptions, same island shape as canvas.js:
`assets/vendor/drag.js` (gesture island: marquee selection, free tile drag, rail
resize — pointer-based, view-state syncs to the server only on commit) and
`assets/vendor/inspect.js` (element-inspect island: hover outlines and
click-to-pin on `[data-el]` elements, conditionally included in stub renders
when the `inspect` server param is on). Both are dependency-free IIFEs, no
globals, no build step, re-arm on `htmx.onLoad`. The boundary otherwise stands
unchanged: three named islands total (canvas.js, drag.js, inspect.js), each
with a documented ceiling.

**Amendment (2026-07-31) — the media islands.** The island registry grows
from three to a first-class, two-tier architecture. Tier one, third-party
declarative web components, vendored and SRI-pinned via
`vendor/manifest.json`: `<model-viewer>` (GLB 3D), `<dotlottie-wc>`
(dotLottie; its WASM is pinned to the vendored copy by
`dotlottie_island.js`), `<lottie-player>` (Lottie JSON), plus the runtimes
the tier-two islands drive (`rive.js` canvas-single, `three.module.min.js`
+ `three.core.min.js`). Tier two, first-party data-attribute init islands,
same shape as canvas.js (no SRI, no globals, re-arm on `htmx:load`):
`dotlottie_island.js`, `rive_island.js` (state-machine inputs rendered as
buttons), `three_island.js` (one demo scene, rotate/wireframe toggles),
`game_island.js` (playable canvas game). The boundary otherwise stands
unchanged: no ad-hoc client JS, no inline scripts, enforcement is still
`allowEval:false` + the vendor-path lint. A new runtime enters only as a
new named, vendored, documented island amending this ADR.

**Amendment (2026-08-01) — the map island.** One more pair, same two-tier
shape. Tier one: Leaflet 1.9.4 (`leaflet/leaflet.js` + `leaflet/leaflet.css`,
vendored with SRI; its marker/layers sprites ride along unpinned under
`leaflet/images/`, referenced relative by the CSS — never a fetched
subresource with an integrity attribute). Tier two: `map_island.js`, the
data-attribute init island (`[data-map]` with lat/lng/zoom/marker/tiles
attributes; defaults to OSM tiles with the ToS-required attribution, marker
sprites pinned to the vendored images dir, re-arms on `htmx:load`, no-ops
when `L` is absent). Leaflet is the design-time visual mirror of kit/maps
(flutter_map); OSM tiles need no key, so prototypes stay credential-free.
The boundary otherwise stands unchanged.

**Amendment (2026-08-02) — the flow-walk island.** One first-party island, no
vendored runtime: `flowwalk.js`, alongside `inspect.js` and for the same
structural reason. The viewer's flows lens renders a flow as a row of screen
tiles; walking it means tapping the element an edge names (Continue on the auth
screen) and watching the row's ACTIVE tile advance to the screen that edge
points at. The tap happens inside a tile's iframe — a separate document — and
the row lives in the parent. No markup crosses that boundary, so without an
island the flows lens can only be walked from the parent-side tile chrome,
which is not the interaction being asked for.

Shape: armed only on the tile that is the current step, by the presence of a
`walk` query param carrying the complete parent viewer URL to advance to (so
the island never encodes the viewer's param list, and adding a viewer param
cannot silently break it). On a click it matches the target against the edge's
`element` when authored, else fuzzy-matches the edge's prose `trigger`;
an unmatched click falls through to normal behaviour rather than guessing. A
match calls `preventDefault()` — the in-frame navigation is suppressed on
purpose, because the tile must keep showing the screen it is labelled with
while only the row moves — then hands the URL to the parent's htmx
(`window.parent.htmx.ajax`, exactly as `inspect.js` does). No parent htmx (a
stub opened standalone) is a silent no-op, not a throw.

This is a genuine widening of the boundary: the flows lens was previously
specified as a non-navigable projection, with navigability living only in the
proto lens. `DESIGN-ARCHITECTURE.md` §"The output triad" is amended to match.
Enforcement is unchanged: `allowEval:false`, no inline scripts, and the island
lives in the vendored island directory rather than the design artifact — the
zero-custom-client-JS lint over `designs/appbox-studio` still passes clean.

**Amendment (2026-08-02, second) — the explode island.** One first-party
island, no vendored runtime: `explode.js`. It is the fifth named island and the
FIRST that runs in the PARENT document and reads a CHILD's DOM; every previous
island either stayed in its own document (`inspect.js`, `flowwalk.js`) or
touched only parent-owned nodes (`canvas.js`, `drag.js`). That inversion is why
it needs its own amendment rather than riding on the inspect one.

Why it cannot be server-rendered — the load-bearing fact, discovered by reading
a partial rather than assuming. The views lens now renders one row per screen
with two columns: the screen, and the same screen exploded into its widgets.
The widget inventory comes from `data-el`, and **those values are
templated**:

```
home.html      data-el="card:{{ t('portalo.cat.' ~ pair[0]) }}"   {% for %} over 4 pairs
_tabbar.html   data-el="tab:{{ t('portalo.tab.' ~ suffix) }}"     pulled in by {% include %}
```

Parsing the authored source yields one entry reading literally
`card:{{ t('portalo.cat.' ~ pair[0]) }}` where the screen shows four resolved
names, and misses the tab bar entirely because it lives in a second file. A
static extractor would have to evaluate loops, resolve i18n and follow
includes — i.e. be nunjucks. The only resolved copy of the inventory is the
rendered document, and the stub iframe is same-origin, so the parent reads
`iframe.contentDocument.querySelectorAll('[data-el]')` directly: no
postMessage, no child-side counterpart, nothing added to the stub.

Shape: dependency-free IIFE, no globals, no build step, re-arms on `htmx:load`,
binds one `load` listener per frame and guards against rebinding. It never
writes to the server and never navigates. Truth is split deliberately — name,
role, style, motion and function come from the rendered node's own
`data-inspect-*`; **box size is read on click only**, because it does not exist
until layout and pre-rendering it would be a fabrication; `fires` (which flow
edge an element takes) and `kit` come from the SERVER as `data-joins` /
`data-l-*` attributes, because flows.json and the registry are not in the DOM.
Element→edge matching reuses `flowwalk.js`'s exact rule — authored `element`
join first, fuzzy `trigger` second, **no match rather than a guess** — so the
two lenses cannot disagree about what a tap does.

Note it writes inline `style.outline` into the stub document to flash an
element rather than toggling a class, so the stub ships no CSS for a
parent-side island. The boundary otherwise stands: five named islands
(`canvas.js`, `drag.js`, `inspect.js`, `flowwalk.js`, `explode.js`),
`allowEval:false`, no inline scripts, and the zero-custom-client-JS lint over
`designs/appbox-studio` still passes clean.

**Not an amendment (2026-08-02) — the inspector pane (D16).** Recorded here
because the absence of an amendment is itself a decision someone will re-open,
and the reasoning should not have to be reconstructed.

The inspector pane adds a fourth activity-panel view (`/design/inspector`)
showing the element the user is hovering or has locked. That is new UI with new
state — hover, lock, unlock — and it would be reasonable to assume new client
JS, hence a sixth island. It needs none, so the island count stays at five.

Why it needs none: every piece of state it has already crosses the wire.
`inspect.js` (island 3, already amended in) is what observes the DOM inside the
stub iframe; it reports hover and click to the parent through the existing
channel, and the pane is rendered SERVER-SIDE from `d.inspectorHover` /
`d.inspectorLock` in the session. The pane is Nunjucks and htmx like every other
panel: an `hx-get` swaps it, `hx-post` unlocks it. Nothing in it observes,
measures or animates, which is the whole test for whether an island is
unavoidable (the canvas needed one because cursor-anchored zoom cannot be
expressed as an HTTP request; a pane that displays session state can).

The behavioural rule the pane encodes — **locked wins**: while a lock is held a
hover changes nothing, and unlocking promotes the locked element into the hover
slot — is also server-side, in `design_facade.js`. It is worth naming because it
was got wrong once: recording hovers while locked meant an element merely
brushed past on the way to the unlock button became the thing displayed after
unlocking, discarding the element the user had deliberately locked.

So: five named islands, unchanged. Adding a panel is not adding an island, and
the boundary only moves when something genuinely cannot be said in hypermedia.
