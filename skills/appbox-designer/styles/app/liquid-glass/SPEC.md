# liquid-glass — style SPEC (iOS 26 / Apple HIG)

> The designer's binding law for this style. Compiled verbatim from
> energize `docs/technique-layer/component-craft.md` (R7/R8/R9a–R9p) and
> `component-specs.md` (R9a metric tables) — those files remain the SSOT;
> this module is the designer-consumable distillation. `overlay.css` is the
> gate-proven CSS implementation; `motion.css` the physics constants.
> Conflict between CSS and this SPEC = a bug in one of them.

## Doctrine

- **Primary sources only**: developer.apple.com HIG (read via appbox lens —
  JS-rendered), UIKit/SwiftUI runtime facts, real-reference specimens.
  Apple publishes **no per-component pixel specs** — the sole number in ten
  HIG pages read is tvOS (68/46 tab bar), which does NOT apply to iOS.
  Consequence: **glass is gated on RELATIONSHIPS, not absolutes**
  (capsule-where-capsule, concentric radii, thumb/track ratio).
- **Real controls outrank stylized figures.** Four measured lessons: the
  toggles intro art is pre-26 (gray track) and horizontally stretched
  (2.29 aspect is not real — the real control is 52×32); take SHAPE from
  figures, SIZE from the real control.
- **Glass is the navigation/overlay layer ONLY** (HIG Materials: "Don't use
  Liquid Glass in the content layer"). Bars float as capsules; content
  scrolls beneath. Menus/popovers/dialogs/sheets/toasts float as material;
  content surfaces (calendar, table, accordion, cards, forms) stay SOLID,
  shadow-free. Sole in-content exception: transient controls (sliders,
  toggles).

## Tokens (light)

| token | value | meaning |
|---|---|---|
| `--field` | #F2F2F7 | systemGroupedBackground |
| `--field-alt` | #E9E9EE | tertiarySystemGroupedBackground |
| `--surface` | #FFFFFF | secondarySystemGroupedBackground (content cards) |
| `--ink` / `--ink-soft` / `--ink-soft2` | #1C1C1E / #6C6C70 / #C5C5C7 | label / secondaryLabel / tertiaryLabel |
| `--hairline` | rgb(60 60 67 / 0.12) | separator |
| `--accent` family | #0FA3A3 / #006F6F text / #0C8C8C hover / #D9F0F0 soft | brand teal via color-craft roles |
| `--r-card` / `--r-ctl` | 16px / 10px | card / control radius |
| `--glass-regular` | rgb(250 250 252 / 0.62) | nav bars |
| `--glass-thick` | rgb(252 252 253 / 0.78) | menus, dialogs, sheets, popovers, toasts |
| `--specular` | inset 0 1px 0 rgb(255 255 255 / 0.55), inset 0 -0.5px 0 rgb(0 0 0 / 0.05) | lensing cue |
| `--knob` | #FFFFFF | switch/slider thumb face — WHITE in BOTH themes (invariant, never `--surface`) |
| `--shadow-1` | none | iOS content cards carry no drop shadow |
| fonts | -apple-system SF stack; nav titles semibold, h1/h2 bold, tracking -0.015em | platform owns type conventions |

## Tokens (dark) — token-level variant, NEVER a restyle (R8)

systemGroupedBackground goes true black (`#000000`); tints LIGHTEN (HIG):
`--accent #30BDBD`, `--accent-text #3EC9C9`, `--accent-soft #0C3534`;
`--surface #1C1C1E`, `--field-alt #2C2C2E` (one step LIGHTER than surface —
the present card must read on it); fills DOUBLE their alpha
(systemFill 0.12 → 0.24); glass darkens (28 28 30 / 0.62+0.78); specular rim
flips (white 0.14 top / black 0.4 bottom). Danger flips to dark system red
(#FF453A, emsg #FF6961). **Theme swap is INSTANT** — a token swap, never a
transition (a 150ms wash once made the contrast gate measure a mid-flight
1.45:1 blend). Tri-state control: system default / light / dark.

## Shape system (WWDC25-356)

1. **Fixed** — continuous rounded rect: text fields r = h/4 (10px on 40px),
   menus/dialogs 14px, sheets 24px top, picker button r8.
2. **Capsule** (r = h/2) — controls and SEARCH fields only: buttons, seg
   track/thumb, toggles, chips, FAB(−ish), toast capsule, search field.
3. **Concentric** — `inner = outer − gap` (HIG Toolbars, Dec 2025 update):
   standard buttons/fields/headers/footers concentric with bar corners.

## Families (26) — glass truths

Full inventory + behavior laws: component-craft.md §inventory and
§behavior-laws. Glass essentials:

- **buttons** — tinted glass capsule (accent 15% fill, accent-text label,
  specular rim); ghost = hairline ring; danger = red tint w/ #D70015 label
  (contrast-stepped); dialog buttons 34px in a separated bottom row.
- **segmented + tabs** — iOS 26 GLASS idiom: track = floating glass capsule
  (surface + specular + soft shadow); SELECTED segment = flat systemFill pill
  (rgb 120 120 128 / 0.16 light, 0.32 dark) sliding on the MOVE spring.
  **Labels NEVER change typography on selection** (R9c — a weight flip
  reflows glyph widths, labels visibly moved ~1.5px mid-slide). Tabs render
  as the SAME segmented idiom — underlined tabs are NOT an iOS pattern.
- **selection** — switch: iOS 26 toggle, REAL SIZE 52×32 (SwiftUI
  LiquidGlassSwitch default; UIKit lineage 51×31), CLEAN capsule, no inner
  glyphs, white STADIUM knob 32×28 @2px inset in both states/themes
  (`--knob`), travel 16px on the MOVE spring, accent track when on
  (dark ON keeps tint via a (0,3,1) rule — the dark track override (0,2,1)
  otherwise grays it out). Checkbox/radio are NOT iOS idioms (HIG: macOS
  only) — render list-row checkmark accessories; a round check circle for
  forms. Radio = 6px accent ring.
- **range + progress** — slider: 4px tinted track, 26px white thumb
  (`--knob` — same invariant as the switch; geometry gate asserts
  slider-thumb background == switch-knob background, computed). Spinner
  (R9l): 8 radial CAPSULE blades, 45° pitch, hub hole 38% of diameter,
  blade width ~5% (~3:1 capsule), brightest at 12 o'clock, QUANTIZED
  clockwise fade 1.0/.7/.4/.2/.1/.05/.02/0, 20px medium, 0.8s linear
  rotation — conic ladder × pitch mask × hub mask, mask-composite
  intersect. NEVER a border-top ring.
- **select + combobox** — picker button = gray fill r8 capsule-adjacent;
  listbox floats (datepop pattern) as thick glass 14px, items 8px, single-
  line (see laws below). Combobox = input + filtered suggestion list.
- **text inputs** — systemFill r10 (h/4), NO border, no gloss; search =
  capsule; error = inset 0 0 0 1.5px #FF3B30 (dark #FF453A), emsg #D70015
  (dark #FF6961). See field laws below.
- **menus** — pull-down menu material: thick glass, 14px continuous corners,
  6px pad, items 8px radius, hover = systemFill 0.16, destructive = system
  red (contrast-stepped #D70015 light), checkmark accessory marks selection
  (never a tint wash, never weight).
- **popovers + tips** — popover/hover-card = thick glass 14px; tooltip =
  thick glass 8px, ink text, NO arrow.
- **date + time** — calendar = content: SOLID surface card, no shadow; month
  title semibold; day cells 40px circles; selection = solid accent circle
  w/ dark-ink text (#06201F, 6.4:1); today = accent-text ring; range = soft
  band between solid caps. Date field = fill r10 + popover calendar.
- **dialogs** — iOS alert: thick glass, 14px, centered, title 600, buttons
  as a hairline-separated bottom row (cancel regular / default bold).
- **sheets + drawers** — sheet 24px top corners, grabber, thick glass;
  drawer = regular material column (visionOS law: regular separates a
  sidebar).
- **feedback** — toast: thick glass capsule, bottom rack, NO action buttons
  (HIG: alerts/sheets own actions); banner = grouped-row idiom, tinted fill,
  no left strip.
- **wayfinding** — pagination: active = solid accent circle w/ dark-ink
  text; crumbs follow base.
- **tables / list rows** — selection = gray systemFill row (never tint);
  shadow-free.
- **disclosure (accordion)** — inset-grouped list: row 44px (UIKit rowHeight
  / SwiftUI defaultMinListRowHeight), title REGULAR weight, separators INSET
  to text lead, chevron = outline-disclosure glyph on the TRAILING edge:
  RIGHT when collapsed → rotates 90° to DOWN when expanded (the 180° spin
  is the macOS idiom — wrong platform). Press = CELL HIGHLIGHT fill
  (systemFill 150ms linear), never scale.
- **cards** — solid surface, no shadow; selection = accent ring.
- **identity** — badge = system red (contrast-stepped #D70015 light /
  #FF453A dark w/ dark ink); avatar = gray fill; chips = iOS fill-material
  capsule.
- **top bar / nav rail** — floating glass capsule bars (sticky, margins
  10/14px, specular + shadow); rail rows r10, selection = gray systemFill
  (never tint — HIG sidebar law), group labels sentence-case gray 12/600.
- **empty states** — solid, shadow-free.
- **type + rhythm** — platform stack; titles bold per platform convention.
- **iconography (R9b)** — Lucide only, vendored lucide-static@1.27.0
  sprite, `<symbol>`+`<use>` (never the UMD runtime — it mutates DOM post-
  load and races gates), kebab-case names, stroke=currentColor, size via
  `--ic` (16 default). Unicode glyphs are not icons.

## Field laws (R9m)

SHAPE/MATERIAL — single-line field = fixed rounded rect r ≈ h/4, flat quiet
systemFill, no border, NO glass (content layer). Capsule reserved for
controls + search.
INDICATOR EXCLUSIVITY — one field boundary indicator at a time; ERROR
outranks FOCUS: err inputs suppress the accent focus outline; the red inset
ring is the single boundary.

## Dropdown laws (R9n/R9o/R9p — eight laws)

1. A listbox that presents/dismisses FLOATS — absolute under its field;
   in-flow + visibility:hidden keeps the layout box (permanent void).
2. The revealed check CLUSTERS LEFT with its label (flex-start; kbd hints
   margin-left:auto); only kbd hints sit at the right edge.
3. State icon = the CLASS-TOGGLED .mi-check and nothing else — no stray
   always-on svgs.
4. Menu items are SINGLE-LINE (M2: "limited to a single line of text";
   two-line content is a dialog) — ellipsis truncation.
5. The state check sits in a RESERVED slot on every row (shadcn SelectItem
   pattern) — visibility toggles, geometry never moves.
6. Selection NEVER changes row metrics — no font-weight on selected items.
7. The FIELD's width is a layout property, never value-driven (floor 176 /
   cap 280, value truncates); menu floors at field width, caps at 280.
8. A field's trailing affordance (chevron) is PINNED right — auto margin;
   the gap is constant field padding, never a function of the value.

## Motion (the recipe — glass column)

| class | constant |
|---|---|
| press | spring k=322, c=26.9 (response 0.35 / damping 0.75); scale 0.94 ctl / 0.96 items / 0.98 rows |
| move (spatial) | spring k=158, c=20.7 (Apple default 0.50 / 0.825) |
| effects (opacity/color) | 180ms linear — critically damped, never a spring |
| disclosure | 300ms cubic-bezier(0.42, 0, 0.58, 1) — UIKit's documented default; EFFECTS class, never a spring |
| direct manipulation | 1:1 with pointer, no inertia, no spring |

Accordion ONE-CLOCK law (R9h): height, padding-bottom and chevron rotation
start together at click, ride the DISCLOSE curve; guard transitionend by
propertyName (opacity ends 60–90ms earlier); chevron rotates via inline
transform at click time in BOTH directions. Switch travel is engine-measured
AND re-measured on reseat (the overlay lands async; a stale travel overrides
forever otherwise).

## Gate contract

Four gates run against the artifact's specimen route, this style, light +
dark: **geometry** (relationships-only for glass — capsule where capsule,
concentric radii, thumb/track ratios, r=h/4 fields, 52×32 switch, rFrac
checkers), **icons** (sprite integrity, name resolution), **audit**
(per-family per-theme composited contrast ≥ 4.5:1, transitions disabled
while probing), **interact** (the behavior smoke: every family driven, state
lands; includes the R9o/R9p size-stability + chevron-pin assertions).
Overlay-load hard-fail guard: a named style whose overlay sheet has not
loaded fails the gate outright (the ?style=glass 404 false-green lesson).
