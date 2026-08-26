# starter-partials/widgets — kinds + the family contract

The 15 `_`-files here are the **closed widget-kind vocabulary** (W7's kind
law derives from this file list) AND the generic drop-in set: self-contained,
zero-JS, styled by the `widgets.css` beside them. They work in ANY artifact.

## App-kind artifacts: the family contract takes precedence

For **app-kind** artifacts the component-craft system
([`styles/app/`](../../styles/app/README.md)) is binding (TL-19): the
widget library implements the 26 families with the canonical family classes
the style overlays key on. The starters below map onto that contract — copy
the starter, swap the markup onto the family classes, and ship
`families.css` + the active style overlay instead of (or after) this
folder's `widgets.css`:

| kind (this folder) | family class contract | notes |
|---|---|---|
| `_appbar` | `.appbar` + `.ibtn`, `b`, `.sp`, `.appmenu` | family 23; per-style heights in the overlay. Glass floats the bar's ELEMENTS and re-sequences them with flex `order`, so it needs all four inner hooks — a `<b>` title, a `.sp` flex spacer, an `.appmenu` trailing menu — not just `.appbar` |
| `_tabbar` | `.navbar .nb` | family 24; glass selection = tint only, never a filled indicator. Glass placement is per-rung: bottom capsule compact, TOP capsule medium |
| `_nav-rail` | `.navrail .nr` | family 25; **glass renders no rail at expanded (`≥ 840`)** — the sidebar replaces it |
| *(no starter yet)* | `.sidebar` | family 26; glass's expanded-rung primary nav, width 260 (m3 360, shadcn 256). Rendered in the same shell slot as the rail — when an app has a second shell with its own plain `.sidebar` there, the swapped-in one needs a discriminator class (e.g. `.sidebar--alt`) |
| `_tabs` | `.tabset a` | family 3; glass renders tabs AS the segmented idiom |
| `_form-field` | `.fieldwrap .input` | family 8; field laws: r=h/4, no border, ONE boundary indicator, error outranks focus |
| `_dialog` / `_modal` | `.dlg` + `.stage .scrim` | family 12; present/dismiss rides the style's move preset |
| `_bottom-sheet` | `.sheet` | family 13 |
| `_toast` | `.toast` | family 14; glass = NO action buttons on toasts |
| `_card` | `.hub-card` / `.g-card` | family 18 |
| `_chip` | `.chip` | family 20; the pill radius belongs HERE (W5) |
| `_list-row` | `.row` + accessories | family 19 |
| `_empty-state` | `.empty` | family 21 |
| `_cta-link` | `.btn` | family 1 |
| `_panel-activity` | — (artifact chrome, no family) | keep as authored |

Site-kind artifacts keep using the starters as-is — the family contract is
app-kind scoped (R7).

Behavior in app-kind artifacts comes from the **interaction recipe**
(`assets/app/interaction.js` port, or the artifact's engine): press /
indicator-move / present-dismiss / disclosure / direct-manipulation, the
style's exact constants (`styles/app/<style>/motion.css`). Widgets carry
no JS.
