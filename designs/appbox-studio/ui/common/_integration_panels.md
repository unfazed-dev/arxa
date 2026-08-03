# Panels and sections — the canonical vocabulary

This file is the SSOT for what the shell's parts are called. If a term is not
in the **Canon** below, it is not a term. Three words do all the work:

> A **shell** is built from **panels**. A panel is built from **sections**.

## Canon

### Shell

A top-level surface of appbox studio — `intake`, `design`, `build`. A shell is
a composition of panels and nothing else.

### Panel

A card. Five per shell, each named by its **role**. There is no position word
in a panel's name: a panel that moves does not get renamed.

| panel | class / id | is today |
|---|---|---|
| header | `.panel-header` | `ui/common/chrome.html:25` — already named |
| composer | `.panel-composer` | `ui/common/composer_panel.html` — already named |
| main | `.panel-main` | the layout slot; the card is what fills it |
| activity | `.panel-activity` | `ui/common/panel_activity.html` — **was `.panel-frame`**, the only panel that was misnamed |
| footer | `#panel-footer` | `ui/views/main_shell/main_shell_view.html:13` — already named |

Four of the five were already correct. `.timeline` is **not** the footer panel
— it is the footer's *body*, the content the shell's `{% block footer %}`
puts inside `#panel-footer`. Only the activity panel carried a wrong name
(`.panel-frame`, a word describing its chrome rather than its role).

Every panel can be turned off. A shell that omits one renders nothing in its
place — no empty box, no reserved height.

### Section

A slot inside a panel. Five, in fixed order:

| section | class | note |
|---|---|---|
| top | `.panel-top` | full width, above everything |
| side (start) | `.panel-side-start` | full height of the body row |
| body | `.panel-body` | always present; takes the slack |
| side (end) | `.panel-side-end` | full height of the body row |
| bottom | `.panel-bottom` | full width, below everything |

Sides may be on together, singly, or not at all. `start`/`end` rather than
`left`/`right` so the names survive an RTL locale — in the shipped locales
(en, pl, qps-ploc) start is left and end is right.

Top and bottom span the panel's full width; the two sides sit *inside* the
band between them, flanking the body. This is not arbitrary — it is what the
design viewer already does, and why the screens filmstrip is full height of
the tile rows but stops short of the top and bottom bars.

## Section defaults per panel

**A section is on when it is given content.** Passing nothing renders nothing,
so an empty bordered strip is structurally impossible. A section can also be
forced off explicitly, which wins over content.

Four panels have **fixed** section rules — they are chrome, and chrome that
varies is chrome you cannot learn:

| panel | top | side-start | body | side-end | bottom |
|---|---|---|---|---|---|
| header | — | — | ● | — | — |
| composer | ● | — | ● | — | **off** |
| activity | ● | — | ● | — | ● |
| footer | — | — | ● | — | — |

Header and footer are body-only by rule: they are single-purpose strips, and a
strip with its own sub-strips is a panel that should have been split in two.

**Main has no defaults.** It is the one panel whose sections are decided
entirely by what fills it, and that changes per shell and per lens. It has the
*capability* for all five; which ones render is the content's call:

| what fills main | top | side-start | body | side-end | bottom |
|---|---|---|---|---|---|
| design · views lens | shell bar | — | canvas | screens filmstrip | mini panel |
| design · flows, proto | shell bar | — | canvas | — | mini panel |
| a file / doc read | file head | — | the read | — | — |
| build evidence | shell bar | — | canvas | — | mini panel |

Do not read the filmstrip as a main-panel default. It is one lens of one shell
putting content in a slot that is otherwise empty.

## What moves

Same object, five names, now one. This is the migration map:

| section | composer said | main said | activity said |
|---|---|---|---|
| top | `.chat-head` | `.dv-topbar` | `.panel-frame-head` |
| body | *(unnamed)* | `.dv-flow-canvas` | `.panel-frame-body` |
| side-end | — | `.dv-vstrip` | — |
| bottom | — | `.dv-botbar` | `.panel-frame-bar` |

Viewer-specific classes stay as **modifiers** alongside the canonical one —
`class="panel-bottom dv-botbar"` — because the viewer's bars carry real
behaviour the generic section must not inherit (the botbar's zero side padding
exists so the docked mini panel's 50% width is 50% of the *viewer*, not of a
padded box).

## Not panels, despite the name

- `.panel-bar` — the narrow-rung switcher that picks which panel is visible.
  It sits outside every panel and is genuinely a bar *of* panels. Keeps its
  name.
- `.mini-panel` — the viewer's docked toolbar, inside the main panel's bottom
  section. Established in the code and in conversation; a deliberate,
  documented exception.

## Fixed rules

- **The panel is the card, never the layout slot.** `.panel-main` stays a
  transparent flex slot; the card that fills it (`.panel-viewer`,
  `.mp-content`) is the panel. This is not a style choice — `canvas.js`
  fullscreens `#design-viewer`, and anything outside that element vanishes in
  fullscreen, including the exit button. The top, bottom and side sections
  must stay inside it.
- **The shell is viewport-locked; the panels scroll, the page never does.**
  `#app` is `height: 100dvh; overflow: hidden` and a flex column, so the
  panels row is `flex: 1; min-height: 0` — whatever the header and footer
  leave. A document scrollbar in this app is always a bug: it drags the header
  and the timeline, which are chrome, out of view. Never size the row by
  arithmetic over chrome tokens: it used to be
  `calc(100dvh - var(--nav-h) - var(--tl-h))`, deriving its height from two
  tokens that describe *siblings it does not own*, and `--tl-h` measures
  `.timeline` while the footer **panel** around it adds a border — so the
  column summed to 100.97dvh and the whole app scrolled by one pixel. Ask the
  layout, don't re-derive it. `min-height: 0` is load-bearing on both the row
  and `.shell-main-loop`: a flex item defaults to `min-height: auto` and would
  push the footer off-screen rather than scroll inside itself. The lock is
  **desktop-only** — below 840px the panels stack, `.mp-content` deliberately
  gives up its own overflow, and the page is the scroller, so `#app` is
  released in the same media block. Asserted by `probe-panel-contract`
  section K, including that the release is live.
- **The card fills the slot; the reading measure belongs to the content
  inside it.** `.panel-main` is `flex: 1`, so the main panel always takes
  whatever the composer and activity panels leave — the whole row when both
  are off, the remainder when they are on. A `max-width` on the card itself
  breaks that, and breaks it *per shell*: `.step-stage` is `.mp-content`, and
  it carried `max-width: 44rem; margin: 0 auto`, so intake's main panel shrank
  to 44rem and floated mid-slot while design's viewer filled the identical
  slot edge to edge. Cap the **content**: either a child's own `max-width`
  (`.artifact` 45rem, `.mp-doc` 42rem, `.artifact-lede` 40rem) or a centred
  grid track on the card (`grid-template-columns: min(44rem, 100%)` +
  `justify-content: center`). Prefer the track over
  `.stage > * { max-width }` — the track leaves each child's own, narrower
  measure intact, and a `> *` rule loses to any one-class child rule declared
  below it. A grid also needs `align-content: start`, or it stretches its auto
  rows to fill a card that is `flex: 1 1 auto`. Asserted by
  `probe-panel-contract` section J, against the *slot* rather than a number,
  so it keeps holding when a side panel is resized or switched off.
- **CSS owns a panel's width limits; the island reads them.** A panel states
  its own `min-width`/`max-width`; `drag.js` resolves the drag range from
  `getComputedStyle` rather than carrying constants. A limit written twice is
  a limit that will disagree with itself — it already did: the rail clamped to
  a hardcoded `[200, 600]` while the composer floored at 360px and the
  activity panel at 340px, so past the floor `min-width` held the panel still
  while the px readout kept counting down. Nothing rendered wrong; the number
  simply described a drag the element never made. The server's band in
  `setPanelSizePx` is a malformed-POST guard, **not** a limit — it cannot read
  CSS and must stay wider than every panel's real range.

### Panel widths (desktop, ≥840px)

| panel | start = floor | ceiling |
|---|---|---|
| composer | 390px (`--composer-w`, composer.css) | `--panel-max-w` |
| activity | 340px (`--panel-w`, panels.css) | `--panel-max-w` |

`--panel-max-w: 500px` is declared once on `.panel` and shared by both. One
value because there was never a reason for two — the composer's old 576px was
just its width times 1.6, and the activity panel's 600px was a constant in
`drag.js`. Neither was chosen.

Both panels **widen only**: the start width is also the floor, by design
(`--panel-w` is commented "default = minimum width"). The activity panel's
`panel-size-s|m|l` steps are 340 / 425 / `--panel-max-w`; the largest step must
never exceed the cap, because `--panel-w` also feeds `min-width` and a
`min-width` outranks a `max-width` — a wider step would not be clamped, it
would silently win.

Below 840px all three are released and the panel fills the stacked column.
That rule is scoped `.panels .panel-activity, .panels .panel-composer` to win
on **specificity, not source order**: at one class it lost both ways round —
`.panel-activity` is declared later in `panels.css`, and `.panel-composer`
lives in `composer.css`, which loads after it. The rule did nothing at all,
and desktop looked perfect the whole time. Anything added to that media block
needs the same scope. Asserted by `probe-panel-contract` section I.
- **`view-transition-name` is per panel, never on `.panel`.** A name
  duplicated across simultaneously-rendered elements makes Chrome abort the
  whole transition, silently disabling view transitions app-wide (ADR-0003).
- **Ids are load-bearing, classes are not.** `drag.js` resolves the resize
  rail's target by id and oob view-switches target the section ids. Renaming a
  class is free; renaming an id is a server change.

## The rename map — authoritative

Every sweep cites this table and invents nothing. Left column is retired; it
must return zero hits outside this file when the sweep is done.

### Panels

| retired | canonical | note |
|---|---|---|
| `.panel-frame` | `.panel .panel-activity` | the only misnamed panel |
| `.panel-frame-left`, `.panel-frame-right` | *(deleted)* | dead position modifier |
| `.panel-composer` | `.panel .panel-composer` | gains the base class only |
| `.panel-header` | `.panel .panel-header` | gains the base class only |
| `#panel-footer` | `.panel .panel-footer` on the same element | id unchanged |
| `.design-viewer` | `.panel .panel-viewer` | keeps `#design-viewer` — `canvas.js` fullscreens that id |

`.panel-main` is **not** renamed and does **not** get `.panel`: it is the
transparent layout slot, not a card.

### Sections

| retired | canonical |
|---|---|
| `.panel-frame-head` | `.panel-top` |
| `.panel-frame-body` | `.panel-body` |
| `.panel-frame-bar` | `.panel-bottom panel-views` |
| `.pv-icon` | `.panel-views-icon` |
| `.panel-frame-label` | `.panel-label` |
| `.chat-head` | `.panel-top chat-head` |
| `.dv-topbar` | `.panel-top dv-topbar` |
| `.dv-botbar` | `.panel-bottom dv-botbar` |
| `.dv-flow-canvas` | `.panel-body dv-flow-canvas` |
| `.dv-vstrip` | `.panel-side-end dv-vstrip` |
| `.timeline` | `.panel-body timeline` |
| `.dv-flow` | *(deleted — the grid absorbs the wrapper row)* |

The `dv-*` and `timeline` words survive **as modifiers alongside** the
canonical class, never instead of it. They carry behaviour the generic section
must not inherit, and three islands resolve `.dv-flow-canvas` by name.

### The resize rail

| retired | canonical |
|---|---|
| `.panel-frame-handle` | `.panel-resize` |
| `.panel-frame-width` | `.panel-resize-width` |
| `data-side="left"` | `data-persist="activity"` (server key) |
| `'panel-' + (side \|\| 'left')` in drag.js | `data-target`, always explicit |
| `data-edge="left\|right"` | `data-edge="start\|end"` |

### Ids and server contracts

| retired | canonical |
|---|---|
| `#panel-left` | `#panel-activity` |
| `#panel-left-head` | `#panel-activity-top` |
| `#panel-left-body` | `#panel-activity-body` |
| `#panel-left-bar` | `#panel-activity-bottom` |
| `POST /design/panel/size/left` | `POST /design/panel/size/activity` |
| `panelSize.left`, `panelSizePx.left` | `panelSize.activity`, `panelSizePx.activity` |

### l10n keys

| retired | canonical |
|---|---|
| `panelViews.dragHandle` | `panel.resize` |
| `panelViews.aria.left` | `panel.activity.views` |
| `panelViews.aria.right` | *(delete — unreachable; `side` was always `left`)* |

### Deliberately unchanged

`.panel-bar` and `.panel-bar-item` (the narrow-rung panel switcher),
`.panel-main`, `.mini-panel*`, `#mini-panel-actions` (a `drag.js` contract),
`#design-viewer`, `#panels`, `#timeline`, `#composer`, every `composer-*` and
`mp-*` class, and all `panelBar.*` l10n keys. These are already correct under
the canon or are documented exceptions.

## The word this replaces

`side: 'left'` was a panel identity, passed as a hardcoded constant at every
call site, for the panel that sits on the right. It is retired as a *panel*
concept. `side` now means only one thing: a section flanking the body,
addressed as `start` or `end`.

Until the server contract is migrated, the old constant survives inside ids
(`#panel-activity-body`), the resize route (`POST /design/panel/size/left`),
session state (`panelSize.left`) and one l10n key (`panelViews.aria.left`,
whose English string already reads "activity panel views"). Treat every one of
those as an **opaque key that happens to spell a word** — never as a position.
