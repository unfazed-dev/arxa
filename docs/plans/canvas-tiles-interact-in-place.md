# Canvas tiles: interact-in-place (views + flows lenses)

## Requirement

In the design shell's views and flows panels, every screen tile must be
interactive *to its own screen* — scroll, tap, click with normal feedback —
without navigating anywhere (Figma-style limited dynamics). Prototype lens
keeps full wired navigation; build-evidence canvas (`data-static`) stays
fenced.

## Root cause of today's static tiles

1. `viewer.css:201` — `.dv-tile-frame { pointer-events: none }`; only
   `.is-live` / `.is-inspecting` re-enable.
2. `design_viewer.html:220` — `scrolling="no"` on tile frames blocks inner
   scroll even when pointer events flow.
3. `still=1` stubs are script-free (no htmx), so a raw anchor click would
   full-document-load another screen into the iframe — the original reason
   for the pointer-events fence.

## Fix (ADR-0002 compliant, no stub scripts)

- **viewer.css** — `.dv-flow-canvas:not([data-static]) .dv-tile-frame
  { pointer-events: auto; }` (views + flows share `.dv-flow-canvas`;
  `data-static` marks the read-only evidence canvas).
- **design_viewer.html** — drop `scrolling="no"` from the tile frame so the
  stub scrolls in place.
- **canvas.js** (charter extension, parent-side) — the island already wires
  into same-origin stub documents (pinch forwarding). Extend that wire: for
  frames whose document URL carries `still=1` and not `inspect=1`, add
  capture-phase `click` (cancel anchor default) and `submit` (cancel)
  listeners. Taps, hover, scroll, inputs stay native; navigation is inert.
  Inspected frames keep real navigation (pqs deliberately carries
  `inspect=1` across hops). Live tile drops `still=1` → untouched.
- Docs: canvas.js header idiom, ADR-0002 charter note, stub-view comment,
  `_integration_viewer.md` tiles paragraph.

## Verification

Disposable server on 4991 (`ARXA_PROJECT=portalo`, `--no-watch`), one async
lens `--expect` on `/design` (views) and `/design?mode=flows`: frame
pointer-events auto, no `scrolling` attr, inner scrollTop moves, anchor click
does not change `contentWindow.location.href`; console clean; design lint.
