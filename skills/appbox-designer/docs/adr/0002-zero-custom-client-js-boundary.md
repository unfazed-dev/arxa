# Zero custom client-side JS boundary

"No JS" scopes to the client rendering stack — htmx + CSS replaces React; the server is Node. Permitted in Artifacts: htmx 2.0.10 core plus Allowlisted official extensions (preload, head-support, sse; client-side-templates allowed but unrecommended — it inverts the HDA architecture), all vendored locally with SRI. Banned: `<script>` blocks, `hx-on:*`, `js:`-prefixed `hx-vals`/`hx-headers`, `[expr]` trigger filters. Enforcement is mechanical, not honor-system: `<meta name="htmx-config">` sets `allowEval:false` + `allowScriptTags:false` (banned features fail inert), plus a lint rule over generated HTML. Considered and rejected: htmx-core-only (loses preload snappiness and head merging), permitting `hx-on` (hand-written JS by another name, unprovable cleanliness).

**Amendment (2026-07) — the canvas island.** ONE named first-party exception: `assets/vendor/canvas.js`, a dependency-free pan/zoom module (~70 LOC) scoped to the design-canvas component (`.dv-stage` / `.dv-rungs`). Shape: the "island" from htmx's hypermedia-friendly-scripting essay — view-state-only (zoom/pan never sync to the server), no globals, no framework, no build step; the same pattern as htmx's official SortableJS example. It lives in `runtime/vendor/` (the allowlist), ships in the starter, and loads `defer` from `base.html`; no SRI (first-party, not tracked by `fetch.mjs`/`manifest.json`). It is the ONLY first-party script an artifact may carry — everything else about the boundary stands unchanged. Research basis: continuous cursor-anchored zoom, drag-pan and drag-drop are impossible declaratively (htmx can hear `wheel`/`pointermove` but can only answer with HTTP requests), so the choice was this bounded island or no Figma-style canvas at all.

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
