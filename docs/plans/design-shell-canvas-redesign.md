# Design shell canvas redesign — decision record

> **Superseded (2026-07-30).** The panel architecture replaced the chrome this
> record designed: the rails and the floating mini-rail are now the activity /
> main / composer panels (the composer panel is permanent and single-state —
> the two-state centered/docked chat below is retired), the bottom bar is the
> footer panel, and the design viewer's `prototype` mode was dropped (flow/art
> only). Current truth: `docs/VOCABULARY.md` and `docs/design/brief.md`.
> Kept for history — do not implement against it.

Grilled and confirmed with the operator (session 2026-07-30). Every line below
was a decided behavior at the time, not a proposal — see the Superseded note
above for what replaced it. Target artifact: `designs/appbox`. Skill
amendments: `.kimi-code/skills/app-box-designer`.

## Stage

- Canvas-first: once screens are drafted, the shell opens on the canvas as the
  main area, chat docked (`is-docked`). Chat-centered entry remains only for
  the pre-draft draft-all offer.
- ONE artboard canvas with two content modes, toggled by an icon button at the
  top-right corner of the artboard. Mode is a server-side viewer param
  (`mode=flow|prototype`). The two modes never render side by side.
- **Rungs mode dies.** `single` is absorbed by prototype, `board` by flow.

## Modes

- **Flow** — every screen as a tile, rows grouped by shell (groupBy on
  `structure.json` `screens[].shell`). Tiles are chromeless renders
  (`?embed=1`, new bare render mode) at each screen's primary authored width.
  Tiles drag freely; x/y POSTed on drop, server-persisted in session, auto-grid
  on first render. Marquee selects tiles → floating "Pin N screens" bulk action
  (one request); Esc/click-away clears. Per-screen pin stays always-on.
- **Prototype** — one device chrome running the wired app (boosted htmx MPA,
  ADR-0003), opening on the focused screen's route; free navigation inside the
  iframe. vp/os device switching lives in the floating controller panel.
- Registry gains a `route` field per surface (id→URL join; today it exists only
  by convention in `app.routes.js`).

## Gestures (parent page)

- Figma mapping: drag on empty canvas = marquee; Space+drag or middle-drag =
  pan; wheel = zoom (existing canvas.js); zoom-to-fit button in the controller.
  Minimap cut (YAGNI).
- `drag.js` gesture island shared by canvas artboard drag and the rail handle.

## Inspect (in-iframe island)

- New named island `inspect.js` (ADR-0002 amendment, sibling to canvas.js),
  vendored, included in artifact/stub renders only when the inspect server
  param is on. Works in both modes.
- Arming: toolbar/controller toggle button + keyboard shortcut + hold-key for
  momentary inspect (release disarms). While armed: hover outlines the element
  with an overlay tinted in the app accent and shows its name; click pins it to
  chat context (navigation suppressed); stays armed for multi-pick.
- Click plumbing: inspect.js fetches the existing context-toggle endpoint, then
  the parent's already-loaded htmx re-swaps `#stage-layout`. Same-origin
  iframes; no new routes for this.

## Element identity (designer-skill amendment)

- The component-macro layer (`ui/common` + `ui/widgets`) stamps `data-el`
  automatically on every macro instance — surfaces compose only from macros, so
  that is the single choke point. Name = macro name + author label
  (e.g. `product-card:Bouquet 3`).
- Context chip carries element name + screen id + kind; the agent resolves
  markup/styles from the structure SSOT at send time (no snapshots).
- The stub screens (`screen_stub_view.html`) get `data-el` annotations +
  conditional inspect.js include + `?embed=1` support.

## Context & history

- Screen chips and element chips fully independent in the composer tray;
  redundancy allowed, the agent reconciles.
- Undo/redo: server-side session stacks, two explicit icon-button pairs +
  keyboard (Cmd/Ctrl+Z / Shift+Cmd/Ctrl+Z):
  - floating controller pair → canvas actions (artboard moves, pins, unpins,
    bulk-pins);
  - chat composer pair → design changes (walks the same stack checkpoint
    revert uses; revert cards remain as the card-level UI).
- Element-context changes write element-scoped checkpoints (before/after on the
  element, element-level revert).

## Floating mini-rail (replaces viewer toolbar + filmstrip)

- Reusable common component (`ui/common/mini_rail.html`), bottom-anchored
  floating bar with icon-tab panels (same multi-view idiom as the left rail):
  - **Screens** — the filmstrip (context picker, as today).
  - **Controller** — inspect toggle, zoom-to-fit, bg, vp/os, canvas undo/redo.
  - **Actions** — marquee bulk-pin, sim.
- Artboard chrome keeps strict minimum: label + pin + the mode toggle.
- The old `dv-toolbar` dissolves into these panels; well organized.

## Rail

- s/m/l size chips deleted. Drag handle only: center-aligned on the rail edge,
  drag icon shown on hover, live width during drag (island), px width POSTed on
  release into the same session slot the chips used.
- Trade-off accepted by operator: keyboard/AT rail resize is lost with the
  chips.

## Server surface (new/changed routes)

- `POST /design/layout/artboard/:id` — x/y persist on drop.
- `POST /design/rail/size/:side` — px width (replaces s/m/l route over time;
  keep the old route until the chips are gone from markup).
- `POST /design/chat/context/element` — screen id + data-el name + kind.
- `POST /design/undo/:stack` / `POST /design/redo/:stack` — stack ∈ canvas|chat.
- `GET /design/viewer` gains `mode=flow|prototype`, `inspect=1`, `embed=1`.

## Skill amendments (app-box-designer)

- ADR-0002 amendment: `inspect.js` as the second named island; `drag.js` as the
  gesture island (or fold gestures into canvas.js — decided at build time,
  documented either way).
- `declare-structure.md` / `DESIGN-ARCHITECTURE.md`: the macro-stamped `data-el`
  contract; registry `route` field; `?embed=1` bare render mode; undo/redo
  contract for chat-driven design changes.
