# Integration — shared design viewer (ui/common/design_viewer.html)

The shared screen-stage component: two lenses over the shell's screen
registry, switched by server-side viewer state and swapped through
`#design-viewer`.

- `flow` (default) — every screen as a chromeless tile (`?embed=1`) at the
  CURRENT rung (`vp` param, default mobile; `s.tile` carries the per-screen
  width/height at that rung, falling back to the first authored rung),
  grouped by shell into block-flow rows. Tiles drag freely (drag.js); x/y is
  POSTed on drop (`/design/artboard/:id/layout`), a saved position renders
  the tile absolute, group-relative. CSS flow layout IS the auto-grid — no
  facade grid math. Saved layout is per-screen, shared across rungs.
- `proto` — the wired-app preview: ONE screen live at a REAL rung size
  inside device chrome (phone / tablet / desktop window — `.device` in
  `assets/css/viewer.css`; ONE mobile chrome, no os dimension). The rung
  switches from the device icon buttons in the mini panel's bar-right
  cluster (present in BOTH modes — in flow they re-render the tiles at that
  rung); the active screen is picked from the Screens mini panel (a
  thumb is a picker in proto, a chat-context toggle in flow).

Files:

- `ui/common/design_viewer.html` — `designViewer(v)` macro (+ `protoStage`,
  `deviceChrome`).
- `ui/common/mini_panel.html` — the floating Screens / Controller panel; the
  Controller carries the lens switch (`flow` / `prototype`) and the viewer
  fullscreen button (`data-action="viewer-fullscreen"`, implemented
  client-side by `runtime/vendor/canvas.js` — requestFullscreen on the
  enclosing `.design-viewer`; a `data-action="viewer-fullscreen-exit"` close
  button in `design_viewer.html` shows only under `:fullscreen`), the
  bar-right cluster carries the device rung icons (both modes) — divider —
  bg swatches (every mode).
- `assets/css/viewer.css` — flow canvas, mini panel, `.dv-proto*` + `.device`.

## The `v` contract (produced by the shell facade's `viewerFor`)

```js
{
  screens:  [{ id, label?, state?, chips?, viewports, inContext?, dim?,
               tone?, shell, layout?, primaryWidth,
               tile: { vp, width, height } }],   // dims at the CURRENT rung
  mode:     'flow' | 'proto',          // default 'flow'
  proto:    { active, vp, src },       // proto mode only
  vp:       'mobile' | 'tablet' | 'desktop',   // current rung (default mobile)
  inspect:  bool,                      // inspect island armed
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
  miniPanel: { activePanel,
               bar: { devices: [{ key, icon, active, href }] | null,
                      bgs: [{ value, active, href }] },
               screens, controller: { modes, inspect… } },
}
```

- Every viewer action is `GET {{base}}?bg=&inspect=&panel=&mode=&screen=&vp=`
  with `hx-target="#design-viewer" hx-swap="outerHTML"` — the route records
  the choice and re-renders the viewer fragment. Every control href echoes
  the WHOLE viewer state with defaults elided (`flow`, `mobile`), so
  `setViewer` treats the state keys as authoritative — an absent key means
  "back to default", never "keep" (merging would strand every non-default:
  the canvas chip sends no `mode=`, so a merged `mode:'proto'` could never
  flip back). `panel` is the one sticky key (controller chips don't repeat
  it).
- A `viewports` entry is a key (`'mobile'`) or an authored object
  `{ vp, width, height?, rung?, note?, shot? }`. Real rung sizes are
  390×844 / 744×1133 / 1280×800; devices render at true size — the proto
  stage pans when oversized, centers when it fits, never clamps.
- Proto iframe src: `{stubBase}{active}?vp={vp}&embed=1` — the
  `GET /build/screens/:surface` stub renderer. Flow tiles use the same shape
  with `s.tile.vp` (`{stubBase}{s.id}?vp={tile.vp}&embed=1`).

## Wiring a shell

1. Facade: a `viewerFor` producing the contract above (see
   `services/facades/design_facade.js`), plus a `setViewer` that replaces the
   state keys in namespaced session state (`sessionData.<shell>.viewer`),
   keeping only `panel` sticky (see the authoritative-keys rule above).
2. Viewmodel: whitelist the query params into `setViewer` — see
   `design/prototype/prototype_viewmodel.js` (`bg/inspect/panel/mode/screen/
   vp`). Forgetting a param silently drops that control (the viewer
   renders, the toggle does nothing).
3. View: a `viewerSwap(c)` fragment macro rendering `dv.designViewer(c.viewer)`;
   the canvas block calls the same macro on full renders.
4. `ui/common/base.html` links `assets/css/viewer.css`.

Build evidence uses the same component with `static: true` (read-only
artboards, no drag/marquee/pins) and no `contextBase`.
