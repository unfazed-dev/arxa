# Canvas redesign — shared implementation contract

> **Superseded (2026-07-30).** This contract describes the retired rail /
> mini-rail chrome and the dropped `prototype` viewer mode. The panel
> architecture replaced it: activity / main / composer panels (composer
> permanent and single-state), footer panel, panel bar on compact/medium, and
> a flow/art-only design viewer. Current truth: `docs/VOCABULARY.md` and
> `docs/design/brief.md`. Kept for history — do not implement against it.

Binding interface spec for the parallel slices of that effort (historical — see
the Superseded note above). Every subagent read this file,
the plan (`design-shell-canvas-redesign.md`), and its assigned source files.
Class names, context shapes, routes, and swap targets defined here were the
contract for that work.

## Architecture facts (verified)

- **Vendor islands** serve from the SKILL's `runtime/vendor/` dir at URL
  `/assets/vendor/<name>.js`. The router maps `/assets/vendor/*` → `runtime/vendor/`.
  New islands go in `.kimi-code/skills/app-box-designer/runtime/vendor/`.
- **lint.mjs** allows `<script src="/assets/vendor/...">` tags only. Any other
  `<script>`, `hx-on:*`, `js:` attrs, or `[expr]` triggers FAIL the lint.
- **base.html** loads vendor scripts `defer`. Add new islands the same way:
  `<script src="/assets/vendor/drag.js" defer></script>`.
- **canvas.js** current scope: `.dv-stage, .dv-rungs`. The new flow canvas uses
  `.dv-flow-canvas`. Amend canvas.js SEL to include it, OR have drag.js own it.
- **Swap targets:** `#design-viewer` (viewer block), `#stage-layout` (whole
  stage = chat + canvas), `#rail-left` (left rail aside).
- **Routes** integrate via `routes.design.js` → spread into `app.routes.js`.
- **Stubs** served at `GET /build/screens/:surface` by `loop_viewmodel.screenStub`,
  rendered through `screen_stub_view.html`. The `screenStub` facade function
  reads `repo.evidence(locale)` and returns `{ surface, vp, width, kind, theme }`.
- **Registry** at `models/screens_model/registry.json` — entries have
  `{ id, label, surface, shell, comp, labelKey }`. No `route` field yet.

## 1. Viewer context shape (produced by `viewerFor`, consumed by templates)

The `v` object passed to `designViewer(v)`:

```
{
  mode: 'flow' | 'prototype',          // replaces single|rungs|board
  inspect: bool,                        // inspect island armed (default false)
  embed: bool,                          // bare render mode (?embed=1)

  screens: [{
    id, label, state, inContext, dim, tone, chips,   // unchanged from today
    viewports: [{ vp, width, height?, rung?, note?, shot? }],
    shell,          // NEW — for flow grouping (from registry/structure shell)
    route,          // NEW — the screen's URL (registry route field, default '/' + id)
    layout,         // NEW — { x, y } persisted tile position (flow mode; null = auto-grid)
    primaryWidth,   // NEW — first viewport width (for flow tile sizing)
  }],

  active,           // focused screen id
  vp, bg, os,       // viewport / device / background (prototype mode only)
  strip: true,
  base: '/design/viewer',
  stubBase: '/build/screens/',
  contextBase: '/design/chat/context/',

  // NEW — mini-rail panel data (see §3)
  rail: {
    screens: [{ id, label, tone, inContext, dim, src, contextHref }],
    controller: {
      inspectOn: bool,
      inspectHref: '/design/viewer?...&inspect=1',   // toggles inspect param
      bgs: [{ value, active, href }],
      vps: [{ value, active, href }],                 // prototype mode only
      oss: [{ value, active, href }],                 // prototype mode only
      undo: { can: bool, href: '/design/undo/canvas' },
      redo: { can: bool, href: '/design/redo/canvas' },
    },
    actions: {
      selectedCount: 0,                               // updated by drag.js marquee
      bulkPinHref: '/design/chat/context/bulk',       // POST target for bulk pin
      simHref: null,                                  // sim toggle (placeholder)
    },
  },

  // NEW — undo/redo availability (drives button disabled state)
  undoRedo: {
    canvas: { canUndo: bool, canRedo: bool },
    chat:   { canUndo: bool, canRedo: bool },
  },

  // NEW — element context chips (composer tray, alongside screen chips)
  elements: [{ screenId, name, kind, tone, removeHref }],
}
```

## 2. Routes (new + changed)

Add to `routes.design.js`:

```js
['POST', '/design/layout/artboard/:id', prototype.artboardLayout],  // {x,y} body → persist
['POST', '/design/rail/size/:side',     prototype.railSizePx],       // {width} body → persist px
['POST', '/design/chat/context/element', chat.elementContext],       // {screen,name,kind} body → pin element
['POST', '/design/undo/:stack',          prototype.undo],            // stack ∈ 'canvas'|'chat'
['POST', '/design/redo/:stack',          prototype.redo],            // stack ∈ 'canvas'|'chat'
```

Changed: `GET /design/viewer` already exists; its query handler gains
`mode` (now `flow|prototype`), `inspect` (`1` = on), `embed` (`1` = on).

Keep: `GET /design/rail/size/:side/:size` (old s/m/l) until the chips are
fully removed from markup — the drag handle replaces it but the route stays.

## 3. HTML structure and class names

### Flow mode (canvas with tiles)
```
.dv-flow                              // flow mode container
  .dv-flow-canvas.dv-zoom             // pan/zoom area (drag.js manages here)
    .dv-tile-group[data-shell="app"]  // one per shell, groupBy
      .dv-tile[data-id="app.splash"]  // positioned absolute (left/top from layout)
        .dv-tile-chrome               // label + pin (always-on per-screen pin)
          a.dv-pin[href=contextHref]  // toggle context pin
          .dv-tile-label              // <strong>label</strong> <code>id</code>
        iframe.dv-tile-frame          // src = stubBase + id + "?embed=1"
```

### Prototype mode (device chrome)
```
.dv-proto                             // prototype mode container
  .dv-proto-stage.dv-zoom             // pan/zoom area (canvas.js manages)
    .device.device-{os}               // existing deviceChrome macro
      iframe.dv-frame                 // src = stubBase + id + "?vp=" + vp
```

### Mode toggle (artboard top-right)
```
a.dv-mode-toggle[href=viewerHref]     // icon button; hx-get swaps #design-viewer
```

### Mini-rail (bottom-anchored floating bar)
```
nav.mini-rail
  .mini-rail-bar
    button.mini-rail-tab[data-panel="screens"][aria-pressed=true/false]
    button.mini-rail-tab[data-panel="controller"]
    button.mini-rail-tab[data-panel="actions"]
  .mini-rail-panel#mini-rail-screens      // filmstrip thumbs (context picker)
  .mini-rail-panel#mini-rail-controller   // inspect, zoom-to-fit, bg, vp/os, undo/redo
  .mini-rail-panel#mini-rail-actions      // marquee bulk-pin, sim
```
Panels are zero-JS: the active tab is a server param. A tab click is a GET that
swaps `#design-viewer` with the new active panel. One panel visible at a time.

### Marquee (drag.js creates/destroys this)
```
.dv-marquee                           // absolutely-positioned selection rect
.dv-tile.is-selected                  // tiles inside marquee bounds
.dv-bulk-pin[href=bulkPinHref]        // floating "Pin N screens" action (htmx POST)
```

### Inspect overlay (inspect.js creates/destroys this)
```
.inspect-outline                      // absolutely positioned over the hovered element
.inspect-label                        // element name badge
```

### Rail drag handle (replaces s/m/l grip)
```
.mv-rail-handle                       // center-aligned on rail edge, drag icon on hover
```
Live width shown during drag via drag.js updating a `.mv-rail-width` badge.
On release, drag.js POSTs px width to `/design/rail/size/:side`.

### Undo/redo buttons
```
button.undo-btn[disabled]             // in mini-rail controller panel (canvas stack)
button.redo-btn[disabled]             // in mini-rail controller panel (canvas stack)
button.undo-btn[disabled]             // in chat composer bar (chat stack)
button.redo-btn[disabled]             // in chat composer bar (chat stack)
```
Each is an hx-post to `/design/undo/<stack>` or `/design/redo/<stack>`,
swapping `#stage-layout`.

### Element chips (composer tray, alongside screen chips)
```
span.cs-el-chip.ctx-{tone}            // element context chip
  code.cs-el-name                     // "product-card:Bouquet 3"
  a.ctx-x[href=removeHref]            // unpin element
```

## 4. Island APIs

### drag.js — gesture island
- Scope: `.dv-flow-canvas` (marquee + tile drag), `.mv-rail-handle` (rail resize).
- **Marquee:** pointerdown on empty `.dv-flow-canvas` (not on a `.dv-tile` or
  iframe) → draw `.dv-marquee` rect. Tiles whose bounds intersect get
  `.is-selected`. Esc / pointerup on empty canvas clears selection. When ≥1
  tile selected, show a floating `.dv-bulk-pin` button (its href pre-set from
  `v.rail.actions.bulkPinHref` — the selected ids go in a hidden form field or
  query string appended by JS).
- **Tile drag:** pointerdown on `.dv-tile` (not on `.dv-pin` or iframe) →
  free-drag the tile, update `left/top` inline. On pointerup, POST `{x, y}` to
  `/design/layout/artboard/:id` (the id from `data-id`).
- **Pan:** Space+drag or middle-drag on `.dv-flow-canvas` → pan the scroll
  container (same idiom as canvas.js pointer-pan).
- **Rail handle:** pointerdown on `.mv-rail-handle` → drag-resize the
  `#rail-left` aside width, show live px in `.mv-rail-width` badge. On
  pointerup, POST `{width}` to `/design/rail/size/left`.
- Re-arm on `htmx.onLoad(scan)` — same pattern as canvas.js.
- No globals, no framework, no build step. IIFE.

### inspect.js — element inspect island
- Included in stub renders only when `inspect=1` (conditional `<script>` in
  `screen_stub_view.html`).
- Arming: reads a `data-inspect-armed` attribute on `document.body` (set by
  the parent page's controller toggle). While armed:
  - Hover over any `[data-el]` element → draw `.inspect-outline` (accent-tinted
    overlay matching the element's bounding rect) + `.inspect-label` (element
    name from `data-el`).
  - Click on `[data-el]` → `fetch()` the parent's context endpoint
    (`/design/chat/context/element` POST with `{screen, name, kind}`), then
    call `parent.htmx.trigger('#stage-layout', 'none')` to re-swap. Navigation
    suppressed (preventDefault on click).
  - Stays armed for multi-pick until disarmed.
- Momentary mode: hold a key (e.g. Alt) → temporarily arm; release → disarm.
- No globals, IIFE, same-island shape as canvas.js.

## 5. data-el contract (element identity)

- The component-macro layer stamps `data-el="<macroName>:<authorLabel>"` on
  every macro instance. In stubs, this is hand-annotated on key elements.
- Example: `<article class="stub-card" data-el="product-card:Bouquet 1">`.
- inspect.js reads `data-el` to show the name; the click sends
  `{screen: surfaceId, name: dataElValue, kind: tagName.toLowerCase()}`.

## 6. Undo/redo contract (session stacks)

- Two server-side session stacks: `d.undoStacks.canvas` and `d.undoStacks.chat`.
- Canvas stack records: artboard moves (x/y), pins, unpins, bulk-pins.
- Chat stack records: design-change checkpoints (same stack checkpoint revert
  uses — undo/redo walks it instead of one-tap revert).
- `pushUndo(d, stack, entry)` / `undo(d, stack)` / `redo(d, stack)` in the
  facade. `undoRedo` in the context shape reflects `.canUndo`/`.canRedo`.
- Element-context changes write element-scoped checkpoints (before/after on
  the element, element-level revert).
