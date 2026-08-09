# Zero custom client-side JS boundary

"No JS" scopes to the client rendering stack — htmx + CSS replaces React; the server is Node. Permitted in Artifacts: htmx 2.0.10 core plus Allowlisted official extensions (preload, head-support, sse; client-side-templates allowed but unrecommended — it inverts the HDA architecture), all vendored locally with SRI. Banned: `<script>` blocks, `hx-on:*`, `js:`-prefixed `hx-vals`/`hx-headers`, `[expr]` trigger filters. Enforcement is mechanical, not honor-system: `<meta name="htmx-config">` sets `allowEval:false` + `allowScriptTags:false` (banned features fail inert), plus a lint rule over generated HTML. Considered and rejected: htmx-core-only (loses preload snappiness and head merging), permitting `hx-on` (hand-written JS by another name, unprovable cleanliness).

**Amendment (2026-07) — the canvas island.** ONE named first-party exception: `assets/vendor/canvas.js`, a dependency-free pan/zoom module (~70 LOC) scoped to the design-canvas widget (`.dv-stage` / `.dv-rungs`). Shape: the "island" from htmx's hypermedia-friendly-scripting essay — view-state-only (zoom/pan never sync to the server), no globals, no framework, no build step; the same pattern as htmx's official SortableJS example. It lives in `runtime/vendor/` (the allowlist), ships in the starter, and loads `defer` from `base.html`; no SRI (first-party, not tracked by `fetch.mjs`/`manifest.json`). It is the ONLY first-party script an artifact may carry — everything else about the boundary stands unchanged. Research basis: continuous cursor-anchored zoom, drag-pan and drag-drop are impossible declaratively (htmx can hear `wheel`/`pointermove` but can only answer with HTTP requests), so the choice was this bounded island or no Figma-style canvas at all.
Charter extension (2026-08): interact-in-place — canvas.js wires capture-phase
`click`/`submit` cancellation into same-origin `still=1` stub documents (never
`inspect=1` ones), so canvas tiles take taps/scroll natively while navigation
stays inert. Parent-side wiring only; the stubs themselves remain script-free.

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
structural reason. The viewer's flows lens renders a flow as a row of view
tiles; walking it means tapping the element an edge names (Continue on the auth
view) and watching the row's ACTIVE tile advance to the view that edge
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
purpose, because the tile must keep showing the view it is labelled with
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
a partial rather than assuming. The views lens now renders one row per view
with two columns: the view, and the same view exploded into its widgets.
The widget inventory comes from `data-el`, and **those values are
templated**:

```
home.html      data-el="card:{{ t('portalo.cat.' ~ pair[0]) }}"   {% for %} over 4 pairs
_tabbar.html   data-el="tab:{{ t('portalo.tab.' ~ suffix) }}"     pulled in by {% include %}
```

Parsing the authored source yields one entry reading literally
`card:{{ t('portalo.cat.' ~ pair[0]) }}` where the view shows four resolved
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

**Amendment (2026-08-04) — strip-sync joins the canvas island's charter.** The
views-lens filmstrip now syncs both ways with the canvas viewport: scrolling
marks the view whose center is nearest the viewport center with `.on`
(accent) on BOTH the tile and its thumb and keeps that thumb in the strip's
view; clicking a thumb smooth-centers its tile. This is canvas view-state —
scroll-position observation and programmatic scrolling, the same faculties the
island already owns — so it lives in `canvas.js` (island 1), not a sixth
island. It passes the unavoidability test the inspector pane failed: which
view currently occupies the viewport center exists only in the client's
scroll geometry, changes per frame, and cannot be expressed as an HTTP request
any more than cursor-anchored zoom could. View-state-only stands: nothing
syncs to the server. The DOM contract is deliberately thin — a thumb's `href`
is the fragment id of its tile (`#dvt-views--<id>`), which also gives the
JS-off fallback for free (native fragment scroll; hx-boost skips local
anchors). Thumb click previously toggled pin-to-context; pinning lives on the
tile hover toolbar, where it remains. Island count: five, unchanged.

**Amendment (2026-08-04, second) — widget-manager selection joins the explode
island's charter.** The views lens's components column becomes the widget
manager: clicking a row now ALSO posts the selection to the server
(`POST /design/widget/select`, parent-side `htmx.ajax` — the exact channel
inspect.js already owns) and swaps a SERVER-RENDERED property editor fragment
into the row's view slot (`.dv-wedit`). The island contributes only the
gesture and the swap; identity crossing the wire is the static `data-el` kind
prefix (the piece that survives templating and names the source element — the
widget's definition), and every property value, every k-scale step, and every
write-through edit (`/design/widget/attr` → the project's surface source via
`/__project_write`) is server-side. This passes the same test strip-sync
passed: which rendered row was clicked exists only in the client, but nothing
else moved client-side. Editor controls are plain htmx (`hx-post` chips);
the k scale is enforced by the facade (400 on off-scale values, never a
clamp). Island count: five, unchanged.

**Amendment (2026-08-04, third) — edit arming and resize handles join the
canvas and drag charters.** The widget manager becomes editable ON the canvas,
and no sixth island is created: the two gestures land in the two islands that
already own their surfaces. `canvas.js` (which already wires every tile frame)
gains ARMING — while the canvas carries `data-wedit-armed`, a click inside a
tile selects the widget under the pointer instead of reaching the app under
design, posting the same `/design/widget/select` with the same static `data-el`
kind prefix the explode column posts. `drag.js` (which already owns pointer
gestures) gains the eight resize handles over the selected widget. Both pass
the unavoidability test: which element is under the pointer inside a
same-origin frame, and the rendered rect to hang handles on, exist only in the
client's layout and cannot be expressed as an HTTP request. Island count:
five, unchanged.

Three decisions are load-bearing and were nearly got wrong:

*Arming is explicit, not inferred.* A click on a tile has exactly two possible
readings — "use the app" or "select this widget" — and they are mutually
exclusive. Rather than overload a modifier key, the mode is a toggle in the
viewer toolbar with a real `aria-pressed` button, and the armed listener runs
first with `stopImmediatePropagation` (not `stopPropagation`: the
interact-in-place handlers are registered on the SAME node in the SAME phase,
where stopPropagation would not have stopped them). Arming is session state,
so a viewer morph cannot silently disarm mid-edit; armed-ness is read at CLICK
time rather than captured at wire time, because the per-frame wiring guards run
once while arming flips many times.

*Handles express a MODE, never a measurement.* The Auto Layout contract has no
size-bearing attribute — there is no `data-w`/`data-h`, only
`[data-resize-x|y] = hug|fill|fixed`. A drag therefore cannot commit a pixel
figure without inventing a second vocabulary, and forking the contract to make
a gesture feel familiar is a bad trade (ADR-0006). The gesture expresses
intent instead: drag outward → `fill`, drag inward → `hug`, under the dead
zone → nothing. `fixed` is deliberately unreachable by drag, because it means
"keep the size you have", which is what the user already sees, so no direction
honestly denotes it; it stays an explicit chip. Handles commit through the
EXISTING `/design/widget/attr`, so the facade's one value table remains the
single enforcement point — a handle cannot write a value a chip could not.

*Selection is re-derived from the server, never remembered by the client.* A
committed edit rewrites the source, the watcher reloads the frame ~200ms
later, and anything the client marked on the old node dies with the old
document. So the canvas carries the server's selection (`data-wedit-sel`) and
drag.js re-finds the node and re-places the handles on every scan — the same
discipline strip-sync already uses for the filmstrip's current mark. The
selection outline is set as an INLINE style, because the stub document carries
none of the studio's stylesheets and a class would name a rule that does not
exist there (explode.js reaches inside the same way).

*Known gap, recorded rather than papered over.* No stylesheet loaded by a
canvas tile currently implements the Auto Layout contract, so these attributes
are written through correctly and render no visible change. The rules live
only in `starter-partials/widgets/widgets.css` (installed into scaffolded
projects); the tile document links `app/theme/appshell/media.css` and never
`widgets.css`; the studio's same-named `assets/css/widgets.css` is an
unrelated chrome stylesheet; and the worker's project overlay serves HTML,
ARB and JSON but no CSS. This predates the increment — it applies equally to
the `data-pad`/`data-gap` chips already shipped. It is not fixed here because
every available fix either forks the contract into a second copy or changes
what scaffolded projects link, and neither is a decision to make in passing.
See `docs/plans/increment-3-edit-arming-resize-handles.md`.

**Amendment (2026-08-05) — the explode island retires with the components
container.** The view reveal-drawer plan (D2) removed the views lens's
components container — the element list, the per-view edit composer and the
plan sidecar — and `explode.js` existed only to fill that column, so the
island and its script tag are deleted, not replaced. Its selection charter had
already moved: armed canvas clicks post `/design/widget/select` from
`canvas.js`, the drawer Tools strip posts the same route from plain htmx, and
the widget editor now mounts in the drawer's `.dv-tools-wedit` — which is also
where `drag.js`'s resize-handle commits now target their swaps (the old
`#dv-wedit-<screen>` slot is gone). The client-side element inventory it
proved necessary is not lost: the drawer's Tools/Logic tabs derive theirs
server-side from `widget_repository` over the same `data-el` kind prefixes.
Island count: four (`canvas.js`, `drag.js`, `inspect.js`, `flowwalk.js`),
`allowEval:false`, no inline scripts, lint unchanged.
