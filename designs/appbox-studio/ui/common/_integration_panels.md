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
  transparent flex slot; the card that fills it (`.design-viewer`,
  `.mp-content`) is the panel. This is not a style choice — `canvas.js`
  fullscreens `.design-viewer`, and anything outside that element vanishes in
  fullscreen, including the exit button. The top, bottom and side sections
  must stay inside it.
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
