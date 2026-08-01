# Integration — shared design viewer (ui/common/design_viewer.html)

The shared screen-stage component: two lenses over the shell's screen
registry, switched by server-side viewer state and swapped through
`#design-viewer`.

- `flow` (default) — every screen as a chromeless tile (`?embed=1`) at its
  primary authored width, grouped by shell into block-flow rows. Tiles drag
  freely (drag.js); x/y is POSTed on drop (`/design/artboard/:id/layout`),
  a saved position renders the tile absolute, group-relative. CSS flow
  layout IS the auto-grid — no facade grid math.
- `proto` — the wired-app preview: ONE screen live at a REAL rung size
  inside device chrome (ios/android phone, tablet, desktop window —
  `.device` in `assets/css/viewer.css`). The rung and os switch from the
  proto bar; the active screen is picked from the Screens mini panel (a
  thumb is a picker in proto, a chat-context toggle in flow).

Files:

- `ui/common/design_viewer.html` — `designViewer(v)` macro (+ `protoStage`,
  `deviceChrome`).
- `ui/common/mini_panel.html` — the floating Screens / Controller / Actions
  panel; the Controller carries the lens switch (`flow` / `prototype`).
- `assets/css/viewer.css` — flow canvas, mini panel, `.dv-proto*` + `.device`.

## The `v` contract (produced by the shell facade's `viewerFor`)

```js
{
  screens:  [{ id, label?, state?, chips?, viewports, inContext?, dim?,
               tone?, shell, layout?, primaryWidth }],
  mode:     'flow' | 'proto',          // default 'flow'
  proto:    { active, vp, os, src,     // proto mode only
              rungs: [{ key, active, href }], oss: [{ key, active, href }] | null },
  inspect:  bool,                      // inspect island armed
  static:   bool,                      // build evidence: read-only canvas
  bg:       'canvas' | 'warm' | 'slate',
  base:     '/design/viewer',          // per-shell viewer route
  stubBase: '/build/screens/',         // iframe src prefix
  contextBase: '/design/chat/context/',// present where tiles pin as context
  miniPanel: { activePanel, screens, controller: { modes, bgs, inspect… }, actions },
}
```

- Every viewer action is `GET {{base}}?bg=&inspect=&panel=&mode=&screen=&vp=&os=`
  with `hx-target="#design-viewer" hx-swap="outerHTML"` — the route records
  the choice and re-renders the viewer fragment. Every control href echoes
  the WHOLE viewer state with defaults elided (`flow`, `mobile`, `ios`), so
  `setViewer` treats the state keys as authoritative — an absent key means
  "back to default", never "keep" (merging would strand every non-default:
  the canvas chip sends no `mode=`, so a merged `mode:'proto'` could never
  flip back). `panel` is the one sticky key (controller chips don't repeat
  it).
- A `viewports` entry is a key (`'mobile'`) or an authored object
  `{ vp, width, height?, rung?, note?, shot? }`. Real rung sizes are
  390×844 / 744×1133 / 1280×800; devices render at true size — the proto
  stage pans when oversized, centers when it fits, never clamps.
- Proto iframe src: `{stubBase}{active}?vp={vp}&embed=1` — served by the
  existing `GET /build/screens/:surface` stub renderer. Flow tiles append
  only `?embed=1`.

## Wiring a shell

1. Facade: a `viewerFor` producing the contract above (see
   `services/facades/design_facade.js`), plus a `setViewer` that replaces the
   state keys in namespaced session state (`sessionData.<shell>.viewer`),
   keeping only `panel` sticky (see the authoritative-keys rule above).
2. Viewmodel: whitelist the query params into `setViewer` — see
   `design/prototype/prototype_viewmodel.js` (`bg/inspect/panel/mode/screen/
   vp/os`). Forgetting a param silently drops that control (the viewer
   renders, the toggle does nothing).
3. View: a `viewerSwap(c)` fragment macro rendering `dv.designViewer(c.viewer)`;
   the canvas block calls the same macro on full renders.
4. `ui/common/base.html` links `assets/css/viewer.css`.

Build evidence uses the same component with `static: true` (read-only
artboards, no drag/marquee/pins) and no `contextBase`.
