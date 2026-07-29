# Integration — shared design viewer (ui/common/design_viewer.html)

The evidence canvas's design viewer is now the shared screen-stage component
for every tab. Everything below is owned by the integrator; the component
itself is done and verified (demo route smoke-tested, then reverted).

Files landed by this component:

- `ui/common/design_viewer.html` — `designViewer(v)` macro (+ private
  `deviceChrome`). Markup/classes are the evidence viewer's canon (`.dv-*`,
  `.device`) plus a `.dv-rungs` body for rungs mode.
- `assets/css/viewer.css` — rungs-mode styles (real device sizes, top-aligned)
  plus the single-mode filmstrip as a floating card over the stage (scrollbars
  hidden there by explicit exception). Other single-mode styles stay
  in `app.css` (`.dv-*`, `.device`); nothing is duplicated.
- `ui/views/main_shell/build/loop/screen_stub_view.html` — surfaces without a
  bespoke florist stub now render a generic labelled stub (nav + placeholder
  blocks) instead of an empty frame. The 4 bespoke variants are untouched.

## The `v` contract

```js
{
  screens:  [{ id, label?, state?, chips? [{ text, title }], viewports }],
  active:   '<screen id>',              // falls back to screens[0]
  vp:       'mobile' | 'tablet' | 'desktop',  // validated against the screen
  os:       'ios' | 'android',          // mobile device chrome
  bg:       'canvas' | 'warm' | 'slate',
  base:     '/build/artifact/evidence/surfaces/viewer',  // per-tab route
  stubBase: '/build/screens/',          // iframe src prefix
  mode:     'single' | 'rungs',
  strip:    true | false,               // filmstrip, single mode only
}
```

- Every toolbar/strip action is `GET {{base}}?screen=&vp=&bg=&os=&mode=`
  with `hx-target="#design-viewer" hx-swap="outerHTML"` — the route records
  the choice in the session and re-renders the viewer fragment.
- A `viewports` entry is a key (`'mobile'`) or an authored object
  `{ vp, width, height?, rung?, note?, shot? }`. The macro maps keys to real
  device sizes (390×844 / 744×1133 / 1280×800); authored objects keep their
  own width (+ optional height) and their rung/note/shot captions. Devices
  render at true size — never clamped; the stage/rungs pan areas scroll.
- `rungs` mode renders every authored width side by side in device chrome
  (mobile rung uses `os`), caption `width×height · rung` underneath, no strip.

## (a) build loop — replace the local macro

In `ui/views/main_shell/build/loop/loop_view.html`: delete the local
`designViewer` macro; keep `viewerSwap` as a thin adapter:

```njk
{% import "ui/common/design_viewer.html" as dv %}
...
{% macro viewerSwap(c) %}{{ dv.designViewer(c.viewer) }}{% endmacro %}
```

`build_facade.js` changes so `c.viewer` matches the contract:

- `viewerFor(sessionData, evidence)` returns the full `v`:
  `screens` = evidence mapped to
  `{ id: e.surface, label: e.surface, state: e.state, chips: e.chips, viewports: e.viewports }`,
  `active` = validated screen, `vp`/`bg`/`os` as today,
  `base: '/build/artifact/evidence/surfaces/viewer'`,
  `stubBase: '/build/screens/'`, `mode` (new, default `'single'`), `strip: true`.
- `setViewer` passes `mode: query.mode` through into `sessionData.viewer`.
- The evidence strip's per-thumb title (`tests/files`) moves into chip titles
  or is dropped — the shared thumb title is the screen id.

## (b) design tab — adopt in both modes (parent-owned)

Facade state: `sessionData.design.viewer = { screen, vp, bg, os, mode }`
(namespaced like the rest of the design session state). Mirror build's
`viewerFor` in `design_facade.js`:

```js
// sessionData.design.viewer = { screen, vp, bg, os, mode }
const RUNG_VP = { 390: 'mobile', 744: 'tablet', 1280: 'desktop' };
function viewerFor(d, screens) {
  const v = d.viewer ?? {};
  const screen = screens.find((s) => s.id === v.screen) ?? screens[0];
  const viewports = screen.rungs.map((r) => ({
    vp: RUNG_VP[r.width], width: r.width, rung: r.rung, note: r.note, shot: r.shot,
  }));
  const keys = viewports.map((x) => x.vp);
  return {
    screens: screens.map((s) => ({ id: s.id, label: s.label, state: s.state, viewports: /* same mapping */ })),
    active: screen.id,
    vp: keys.includes(v.vp) ? v.vp : keys[0],
    bg: VIEWER_BGS.includes(v.bg) ? v.bg : 'canvas',
    os: ['ios', 'android'].includes(v.os) ? v.os : 'ios',
    base: '/design/viewer',
    stubBase: '/build/screens/',   // shared stub renderer until design serves its own
    mode: v.mode === 'rungs' ? 'rungs' : 'single',
    strip: true,
  };
}
```

Routes (parent-owned):

| method | path | handler | purpose |
|---|---|---|---|
| GET | `/design/viewer` | prototype.viewer | viewer fragment: record `sessionData.design.viewer`, render the component |

The prototype canvas (`design/prototype/prototype_view.html`) then renders
`dv.designViewer(c.viewer)` instead of the hand-drawn `.shots` wireframes —
`rungs` mode replaces the three CSS wireframe figures with live renders at
390/744/1280; `single` mode is the focused screen + strip. A thin
`viewerSwap(c)` fragment macro on the prototype view (same shape as build's)
keeps the route's `h.render(c, '...#viewerSwap', ctx)` idiom.

Note: design screens (`intake.mapping`, `design.chat`, …) have no bespoke
stub — they render through the new generic fallback in
`screen_stub_view.html`, served by the existing
`GET /build/screens/:surface` route. If design later serves its own iframe
documents, only `stubBase` changes.

## (c) stylesheet link — `ui/common/base.html`

Add after the `design.css` link:

```html
<link rel="stylesheet" href="/assets/css/viewer.css">
```
