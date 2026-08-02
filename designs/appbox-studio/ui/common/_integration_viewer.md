# Integration — shared design viewer (ui/common/design_viewer.html)

The shared screen-stage component: three lenses over the shell's screen
registry, switched by server-side viewer state and swapped through
`#design-viewer`.

- `views` (default; legacy `mode=flow` aliases here) — every screen as a
  chromeless tile (`?embed=1`) at the CURRENT rung (`vp` param, default
  mobile; `s.tile` carries the per-screen width/height at that rung, falling
  back to the first authored rung), a flat wrapping grid in REGISTRY order.
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
  that rung); the active screen is picked from the composer tray's filmstrip
  (a thumb is a picker in proto — via `protoPicks` — a chat-context
  toggle in views/flows).

Files:

- `ui/common/design_viewer.html` — `designViewer(v)` macro (+ `protoStage`,
  `deviceChrome`).
- `ui/common/mini_panel.html` — the floating mini panel: ONE panel, the
  Controller, carrying the lens switch (`views` / `flows` / `proto`), the
  canvas undo/redo pair and the viewer
  fullscreen button (`data-action="viewer-fullscreen"`, implemented
  client-side by `runtime/vendor/canvas.js` — requestFullscreen on the
  enclosing `.design-viewer`; a `data-action="viewer-fullscreen-exit"` close
  button in `design_viewer.html` shows only under `:fullscreen`); the
  bar-right cluster carries the device rung icons (both modes) — divider —
  bg swatches (every mode). The screens filmstrip lives in the composer
  tray (`ui/common/composer.html`), not here.
- `assets/css/viewer.css` — flow canvas, mini panel, `.dv-proto*` + `.device`.

## The `v` contract (produced by the shell facade's `viewerFor`)

```js
{
  screens:  [{ id, label?, state?, chips?, viewports, inContext?, dim?,
               tone?, primaryWidth,
               tile: { vp, width, height },       // dims at the CURRENT rung
               inspecting?, inspectHref? }],
               // NOTE: no live/walk fields here. The views lens has no
               // interactive mode — without a row there is no flow to scope
               // nextEdge by, so the destination would be a guess. They are
               // added PER ROW by the flows builder below.
  flows:    [{ id, name, walking?, tiles: [...screens entries +
               conn?, live?, liveHref?, liveCloseHref?,
               advanceHref?, edge?, walkQs? }],
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
  protoPicks: { <screenId>: '/design/viewer?...&screen=<id>' } | null,
               // proto mode only — the composer tray's filmstrip turns its
               // thumbs into the active-screen picker with these hrefs
               // (the tray lives outside #design-viewer, in #panels).
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

## Wiring a shell

1. Facade: a `viewerFor` producing the contract above (see
   `services/facades/design_facade.js`), plus a `setViewer` that replaces the
   state keys in namespaced session state (`sessionData.<shell>.viewer`) —
   all keys authoritative, none sticky (see the rule above).
2. Viewmodel: whitelist the query params into `setViewer` — see
   `design/prototype/prototype_viewmodel.js` (`bg/inspect/mode/screen/vp`).
   Forgetting a param silently drops that control (the viewer
   renders, the toggle does nothing).
3. View: a `viewerSwap(c)` fragment macro rendering `dv.designViewer(c.viewer)`;
   the canvas block calls the same macro on full renders.
4. `ui/common/base.html` links `assets/css/viewer.css`.

Build evidence uses the same component with `static: true` (read-only
artboards, no drag/marquee/pins) and no `contextBase`.
