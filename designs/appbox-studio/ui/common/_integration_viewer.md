# Integration — shared design viewer (ui/common/design_viewer.html)

The shared screen-stage component: three lenses over the shell's screen
registry, switched by server-side viewer state and swapped through
`#design-viewer`.

- `views` (default; legacy `mode=flow` aliases here) — ONE ROW PER SCREEN in
  REGISTRY order, each row two columns: the chromeless tile (`?embed=1`) at the
  CURRENT rung (`vp` param, default mobile; `s.tile` carries the per-screen
  width/height at that rung, falling back to the first authored rung), and
  `.dv-explode` — that screen decomposed into its inspectable components.
  (It was a flat wrapping grid until 2026-08-02. It never actually wrapped:
  `.dv-flow-canvas .dv-zoom` (0,2,0) beat `.dv-zoom-views` (0,1,0) on
  `flex-direction`, so the computed value was `column` and every tile got its
  own line. The rule was deleted, not fixed.)
  The explode column's element list is filled CLIENT-SIDE by
  `runtime/vendor/explode.js`, and that is not a shortcut: `data-el` values are
  templated (`data-el="card:{{ t('portalo.cat.' ~ pair[0]) }}"` inside a
  `{% for %}`, tab bar via `{% include %}`), so the authored source has no
  resolved inventory to render from — only the rendered iframe does, and it is
  same-origin. The server supplies exactly what the DOM cannot know: `s.fires`
  (the flow edges this screen's elements take) and `s.kits`.
- `flows` — one dashed `.dv-flow-row` per project flow, tiles in edge-chain
  order with a `.dv-connector` (trigger label + line + arrowhead) between
  consecutive tiles. Flow edits WRITE the project's flows.json:
  `POST /design/flows/:flow/move/:screen` (form `dir` -1|1 from the toolbar
  nudge arrows, or `index` from drag.js's axis-locked row drag — the only
  tile drag left; X-axis locked inside the row, drop slot = count of sibling
  midpoints left of the drop x), `POST /design/flows/:flow/add/:screen`
  (views-lens add-to-flow menu, appends) and
  `POST /design/flows/:flow/remove/:screen` (stitches the chain). All three
  re-render `#panels` and record canvas undo entries replayed as file writes.
- `proto` — the wired-app preview: ONE screen live at a REAL rung size
  inside device chrome (phone / tablet / desktop window — `.device` in
  `assets/css/viewer.css`; ONE mobile chrome, no os dimension). The rung
  switches from the device icon buttons in the mini panel's bar-right
  cluster (present in ALL modes — in views/flows they re-render the tiles at
  that rung). Proto has NO active-screen picker: the filmstrip that used to
  serve as one is views-only now (see below), so proto renders the facade's
  default screen. `protoPicks` still ships the hrefs a new picker would use.

Files:

- `ui/common/design_viewer.html` — `designViewer(v)` macro (+ `protoStage`,
  `deviceChrome`).
- `ui/common/mini_panel.html` — the docked mini panel: **ONE ROW**, half the
  viewer's content width, centred. The Controller (lens switch `views` /
  `flows` / `proto`, the canvas undo/redo pair, the viewer fullscreen button
  — `data-action="viewer-fullscreen"`, implemented client-side by
  `runtime/vendor/canvas.js` as requestFullscreen on the enclosing
  `.design-viewer`; a `data-action="viewer-fullscreen-exit"` close button in
  `design_viewer.html` shows only under `:fullscreen`) and the bar-right
  cluster (device rung icons in both modes — divider — bg swatches in every
  mode) share that single flex line; cramped, it scrolls sideways rather than
  wrapping back into two rows.
- **The screens filmstrip is the viewer's RIGHT COLUMN, VIEWS LENS ONLY**
  (`design_viewer.html`, `.dv-vstrip`), fed by `v.filmstrip` at the composer
  tray's original thumb scale. Not an overlay: `.dv-flow` is a row flex and
  the rail is its last child, `flex: none; align-self: stretch` — so it takes
  real width off `.dv-flow-canvas` (which needs `min-width: 0` to give it up)
  and every `.dv-views-row`'s second column (`minmax(16rem, 1fr)`) narrows to
  absorb it. Full height of the rows, scrolling on its own Y axis, and outside
  the canvas's scroll box so it stays put while the canvas pans. Below ~1440px
  the explode column hits its 16rem floor and the canvas scrolls sideways
  instead — the rail is unaffected. The facade returns `null` for `flows` and
  `proto`, which also
  means **proto has no active-screen picker any more** (the strip was it);
  `protoPicks` still carries the hrefs if one is needed. A thumb toggles the
  pin (`#panels`). The composer tray (`ui/common/composer.html`)
  keeps its own copy ONLY on surfaces that have a composer and no viewer —
  today just freeze, which opts in with `stageContext`'s `composerStrip`.
  Two copies would be two sets of thumb iframes for the same screens.
- `assets/css/viewer.css` — flow canvas, mini panel, `.dv-proto*` + `.device`.

## The `v` contract (produced by the shell facade's `viewerFor`)

```js
{
  screens:  [{ id, label?, state?, chips?, viewports, inContext?, dim?,
               tone?, primaryWidth,
               tile: { vp, width, height },       // dims at the CURRENT rung
               inspecting?, inspectHref?,
               fires: [{ flow, flowName, to, trigger, element }],
               kits:  ['auth', 'payments', …] }],
               // NOTE: no live/walk fields here. The views lens has no
               // interactive mode — without a row there is no flow to scope
               // nextEdge by, so the destination would be a guess. They are
               // added PER ROW by the flows builder below.
               // `fires` is EVERY outgoing edge across every flow, unscoped and
               // plural on purpose: the explode column asks "what can this
               // screen's elements do", and nothing here picks a winner, so
               // nothing here can guess wrong. The island matches an element to
               // one of these by exact `element` then fuzzy `trigger` —
               // flowwalk.js's rule, so the two lenses cannot disagree.
               // NOTE: the element INVENTORY is deliberately absent — see the
               // views bullet above; it exists only in the rendered DOM.
  flows:    [{ id, name, walking?, tiles: [...screens entries +
               conn?, live?, liveHref?, liveCloseHref?,
               advanceHref?, edge?, walkQs?, handoffs? }],
               // handoffs = LAST TILE ONLY: [{ flow, flowName, to, trigger,
               //   href }] — the other flows that continue from this screen.
               //   Flows are joined by SHARED SCREEN IDS (portalo.home ends
               //   Onboarding and heads both Browse-and-buy and Account), so
               //   the hand-off needs no authored key and nothing can disagree
               //   with the ids. A list: picking one would be a guess.
               // flows lens rows; conn = trigger label to the NEXT tile.
               // walking   = this row is the one being walked
               // live      = this tile is the current step (interactive)
               // liveHref  = arm the walk here / liveCloseHref = stop
               // advanceHref = next step in THIS row (null on the last tile)
               // edge      = { to, trigger, element } — what fires the edge
               // walkQs    = extra stub query for the walked tile, carrying
               //             the parent url + matchers to the flowwalk island
  mode:     'views' | 'flows' | 'proto',  // default 'views'
  proto:    { active, vp, src },       // proto mode only
  vp:       'mobile' | 'tablet' | 'desktop',   // current rung (default mobile)
  inspect:  screen id | null,          // that tile's inspect island armed
  live:     screen id | null,          // that tile live + interactive.
                                       // CLAMPED to the flows lens in the
                                       // facade: a stale ?live= carried into
                                       // views used to paint an interactive
                                       // tile with no reachable close control.
  flow:     flow id | null,            // the row being walked (flows only)
  step:     screen id | null,          // position in that row; defaults to
                                       // the chain head when flow is set
  static:   bool,                      // build evidence: read-only canvas
  bg:       'canvas' | 'warm' | 'slate',
  base:     '/design/viewer',          // per-shell viewer route
  stubBase: '/build/screens/',         // iframe src prefix — every tile,
               // thumb and proto frame renders the STUB, always. The
               // app-under-design (Portalo) is design CONTENT served by
               // GET /build/screens/:surface (bespoke partials under
               // build/loop/portalo/), never a registry surface or a
               // live studio route.
  contextBase: '/design/chat/context/',// present where tiles pin as context
  miniPanel: { bar: { devices: [{ key, icon, active, href }] | null,
                      bgs: [{ value, active, href }] },
               controller: { modes, undo, redo } },
  filmstrip:  [{ id, label, tone, inContext, dim, src,
                 contextHref, active? }] | null,
               // every screen as a thumb, in the viewer's right-hand column
               // (.dv-vstrip). NON-NULL IN THE VIEWS LENS ONLY — null in
               // flows, in proto, and on viewers with no design context
               // (build loop's evidence viewer).
  protoPicks: { <screenId>: '/design/viewer?...&screen=<id>' } | null,
               // proto mode only. Nothing in #design-viewer reads these any
               // more (the strip that did is views-only now, so proto sits on
               // whatever screen the facade defaults to). Still exposed
               // because freeze's composer tray builds its own strip outside
               // #design-viewer, in #panels.
}
```

- Every viewer CONTROLLER action is `GET {{base}}?bg=&inspect=&live=&mode=&screen=&vp=`
  with `hx-target="#design-viewer" hx-swap="outerHTML"` — the route records
  the choice and re-renders the viewer fragment. Every control href echoes
  the WHOLE viewer state with defaults elided (`views`, `mobile`), so
  `setViewer` treats the state keys as authoritative — an absent key means
  "back to default", never "keep" (merging would strand every non-default:
  the canvas chip sends no `mode=`, so a merged `mode:'proto'` could never
  flip back). Flow edits are the exception: POSTs to the `/design/flows/…`
  endpoints above, swapping `#panels`.
- A `viewports` entry is a key (`'mobile'`) or an authored object
  `{ vp, width, height?, rung?, note?, shot? }`. Real rung sizes are
  390×844 / 744×1133 / 1280×800; devices render at true size — the proto
  stage pans when oversized, centers when it fits, never clamps.
- Proto iframe src: `{stubBase}{active}?vp={vp}&embed=1` — the
  `GET /build/screens/:surface` stub renderer. Canvas tiles use the same
  shape with `s.tile.vp` (`{stubBase}{s.id}?vp={tile.vp}&embed=1&still=1` —
  the live tile drops `still`, the inspected tile appends `&inspect=1`).

## The second arg: `designViewer(v, chrome)` — the two shell panels

The viewer renders three stacked panels inside `.design-viewer`: `.dv-topbar`,
the canvas, and `.dv-botbar` (which hosts the mini panel, docked — it used to
float, which is why `.dv-flow-canvas` carried `padding-bottom: 11rem` purely as
clearance; both are gone). All three are INSIDE `.design-viewer` because
`canvas.js` fullscreens that element — anything outside it disappears on
fullscreen, including the exit button, which would strand the user.

```js
chrome = { title, state, foot, actions: [{ key, icon, href, label, danger? }] }
```

`chrome` is **optional, and that is the mechanism, not an oversight.** The two
bars belong to the design shell, not to the viewer component — and the same
component renders build evidence with `static: true`. Evidence passes no
`chrome`, so it gets no title bar and no actions structurally, instead of
relying on a `static` guard on every individual control that someone would
eventually forget to add. Only `prototype_view.html` passes it.

`actions` is currently `[]`: shell-scoped actions have not been named, and
inventing plausible buttons is worse than an honest empty slot.

## Wiring a shell

1. Facade: a `viewerFor` producing the contract above (see
   `services/facades/design_facade.js`), plus a `setViewer` that replaces the
   state keys in namespaced session state (`sessionData.<shell>.viewer`) —
   all keys authoritative, none sticky (see the rule above).
2. Viewmodel: whitelist the query params into `setViewer` — see
   `design/prototype/prototype_viewmodel.js` (`bg/inspect/mode/screen/vp`).
   Forgetting a param silently drops that control (the viewer
   renders, the toggle does nothing).
3. View: ONE macro that builds the chrome and calls
   `dv.designViewer(c.viewer, chrome)` — see `stageViewer(c)` in
   `design/prototype/prototype_view.html`. Both the full render AND the
   `viewerSwap(c)` fragment must call that same macro, so the two paths
   cannot drift.

   This is a rule, not a style note. `design_viewer.html` guards the whole
   `.dv-topbar` (and `.dv-botbar-foot`) with `{% if chrome %}`, so a swap
   path that passes no chrome renders the viewer with no top panel and no
   foot line — and it never comes back without a full page reload. That
   shipped once: `viewerSwap` called `dv.designViewer(c.viewer)` with one
   argument while the full render passed chrome inline, so every mini-panel
   tab, viewport tab and lens switch silently destroyed the top panel.
4. `ui/common/base.html` links `assets/css/viewer.css`.

Build evidence uses the same component with `static: true` (read-only
artboards, no drag/marquee/pins) and no `contextBase`.
