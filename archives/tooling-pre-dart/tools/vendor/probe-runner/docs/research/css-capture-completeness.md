# CSS / Visual Capture Completeness Checklist

> **Update 2026-05-31 — Regime-1 cut 1 LANDED** (§C9-R-P6): per-node `style` now captures
> filter, backdrop-filter, background-image (gradient), clip-path, box-shadow, mix-blend-mode,
> transform-origin, full border + corner radii; external url() redacted at packaging.
> (`-webkit-backdrop-filter` excluded — invalid for Chrome DOMSnapshot.) Remaining Regime-1
> rows below are follow-on through the same proven pipeline.

> **Update 2026-05-31 — Regime-1 cut 2 LANDED** (§C9-R-P7): per-node `style` now also
> captures background longhands, outline (gated on outline-style), text-shadow, overflow-x/y,
> aspect-ratio, object-fit/position, the typography suite (text-transform/text-decoration-line/
> font-variant/writing-mode/direction), and transform-3d (perspective/transform-style/
> rotate/scale/translate). All 27 props validated against captureSnapshot; real-site run
> (MDN) audits CLEAN. Remaining Regime-1 rows below are now fully covered; next is Regime 2
> (pseudo-elements) + Regime 3 (responsive/theme/interactive).

> **Update 2026-05-31 — Regime-2 pseudo-elements LANDED** (§C9-R-P8): `::before`/`::after`/
> `::marker` resolved box-style + a content-free `content` value now ship as an additive
> per-node `pseudo` field on the originating node. **Premise correction:** `DOMSnapshot.
> captureSnapshot` DOES enumerate pseudo-elements (`nodes.pseudoType` + own `nodeName` +
> parallel `layout.styles` row + `parentIndex` → origin) — so this was a Regime-1-style
> extension, NOT the separate `getComputedStyle(el,"::pseudo")` pass the "regime 2" row below
> assumed. `content` is redacted at packaging (string → `"<text>"`, external `url()` →
> `url("<asset>")`, `counter()`/keywords kept). Real-site run (en.wikipedia.org: 232 pseudo-
> carrying nodes; ::before 80 / ::after 73 / ::marker 91) audits CLEAN. Ceilings: pseudo
> GEOMETRY deferred; only before/after/marker reachable in a static snapshot.

> **Update 2026-05-31 — Regime-3a theme/preference LANDED** (§C9-R-P9): per-node resolved-
> style DELTAS under `prefers-color-scheme:dark`, `forced-colors:active`, and
> `prefers-contrast:more` now ship as an additive per-node `theme` field
> `{condition: {prop: value}}`. Mechanism: pin base media → `Emulation.setEmulatedMedia`
> single-axis flip → recapture (no navigate) → diff resolved styles → emit changed props
> (raw rgb), joined base↔condition by the STABLE `backendNodeId` (NOT the positional
> skeleton id; `backendNodeId` is internal, never written to disk). Redacted by the existing
> style redactor (no new content vector). Real-site (MDN: dark 46.3% of nodes; forced-colors
> 99.7%) + github (forced-colors 99.9%) audit CLEAN; forced-colors is dense by construction
> (UA override restyles all elements) but bounded (~8–11 props/node). The dark-mode and
> emulated-media rows in §9 below are now LANDED via 3a; interactive states (`:hover`/
> `:focus`/`:active` via `CSS.forcePseudoState`) LANDED via 3b (§C9-R-P10). Still missing:
> multi-viewport responsive (→ Regime-3c), `prefers-reduced-motion`, and form-state
> pseudo-classes (`:checked`/`:disabled`, Regime-3b deferred).

> **Update 2026-05-31 — Regime-3c responsive multi-viewport LANDED** (§C9-R-P11): per-node
> resolved-style DELTAS across narrower viewport widths now ship as an additive per-node
> `responsive` field `{width_label: {prop: value}}`. Mechanism: navigate once at base width →
> `Emulation.setDeviceMetricsOverride` (no re-navigate) → recapture over curated
> `RESPONSIVE_PROPS` (discrete-layout set: display/flex-direction/flex-wrap/
> grid-template-columns/rows/gap/column-gap/row-gap/position/font-size/text-align) → diff vs
> base, joined by `backendNodeId`. Real-site (MDN: 32/622 nodes, 5.1%) audit CLEAN; grid
> track-lists passed firewall. `@media` / `@container` / `clamp()` rows in §9 below now
> LANDED via 3c.

Reference checklist for a web-design-capture engine claiming to reproduce "every visual detail."
Diff your tool's coverage against this. Verified against MDN (`getComputedStyle`, CSS property value
processing / resolved value) and the CDP `DOMSnapshot` protocol docs (fetched 2026-05-29).

## How to read this

**Status** — measured against your tool's current per-node whitelist and tokens:
- **Covered** — you already capture it.
- **Under-capturing** — you capture *part* of it; fidelity is lossy (e.g. one border side, gradient string unparsed).
- **Missing** — not captured at all.

**Capture regime** — *how* the data becomes obtainable. Four regimes, in increasing cost:
1. **One-pass add** — just add the property name to the CDP `DOMSnapshot.captureSnapshot` `computedStyles`
   whitelist (or read it from `getComputedStyle`). Cheap. Resolved value is faithful for rendering.
2. **Pseudo-element pass** — `getComputedStyle(el, "::before")` etc. ~~**DOMSnapshot does NOT enumerate
   pseudo-elements**~~ **CORRECTION (§C9-R-P8): `DOMSnapshot.captureSnapshot` DOES enumerate before/after/
   marker pseudo-elements** as nodes (`pseudoType` + own `nodeName` + parallel `layout.styles` row +
   `parentIndex`), so no separate JS pass is needed — this is a one-pass add (regime 1) for those kinds.
   A separate `getComputedStyle(el, "::pseudo")` pass remains the only route for the kinds captureSnapshot
   does NOT enumerate (`::placeholder`/`::selection`/`::first-line`/`::first-letter`/`::backdrop`).
3. **Recapture under changed conditions** — re-run capture with a different viewport, media-feature
   emulation, or forced pseudo-state via CDP. The value only exists under those conditions.
4. **Parse authored source / capture binaries** — the value is *not present in computed/resolved values
   at all*. Requires reading the CSSOM stylesheet rules, downloading font binaries, etc. This is where
   authored *design intent* (variables, clamp expressions, media conditions) is recovered.

### Foundational fact: computed/resolved values ≠ authored values

`getComputedStyle()` (and CDP DOMSnapshot, which serves the same resolved values) returns **resolved
values**: for most properties the computed value, for layout-dependent legacy properties (`width`,
`height`, margins, padding in some engines) the **used value in `px`**. Consequences for design intent:

- `1.5rem` → `24px`. `50%` width → resolved `px`. `em`/`ch`/`vw` units → `px`. Authored unit lost.
- `var(--brand)` → the resolved color (`rgb(...)`). The *reference* to the token is gone — you see the
  value, not that two elements share a variable.
- `clamp(1rem, 2vw + 1rem, 3rem)` → a single resolved `px` at the current viewport. The fluid
  *expression* is gone; you only learn the curve by recapturing at multiple widths (regime 3) or by
  parsing the authored rule (regime 4).
- Shorthands are exploded into longhands; `currentColor`, `inherit`, relative colors are resolved.
- `:visited` styles are **deliberately falsified** by the browser (CSS history-leak mitigation).

Therefore "every visual detail" splits into two goals: (a) **pixel-faithful reproduction** (regimes
1–3 suffice — resolved values render identically) and (b) **editable authored design intent** (needs
regime 4 CSSOM parsing). Your token clustering is a heuristic reconstruction of (b) from (a).

---

## 1. Borders & outline

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| `border-{right,bottom,left}-width` | High — you only capture `border-top-width` | Yes, resolved px | **Under-capturing** | Regime 1: add the other 3 sides |
| `border-{right,bottom,left}-color` | High — only `border-top-color` captured | Yes | **Under-capturing** | Regime 1: add 3 sides |
| `border-style` (all 4 sides) | High — solid vs dashed/dotted/double/groove; you capture width+color but assume solid | Yes | **Missing** | Regime 1: `border-*-style` |
| `border-radius` per-corner | Med — you capture `border-radius`; resolved gives 4 longhands incl. elliptical `x/y` | Partial | **Under-capturing** | Regime 1: capture 4 corner longhands |
| `border-image` (source/slice/width/outset/repeat) | Med — gradient/image borders render nothing today | Yes (string) | **Missing** | Regime 1; +parse like background-image |
| `outline-{width,style,color,offset}` | Med — focus rings, selection outlines | Yes | **Missing** | Regime 1 |

## 2. Backgrounds

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| `background-image` gradients (linear/radial/conic) | **Very high** — you capture the string but don't *parse* it; can't reproduce stops/angles/shape | Yes (resolved string, e.g. `linear-gradient(...)`) | **Under-capturing** | Regime 1 captures string; **build a gradient parser** for stops, angle, color-interpolation, repeating |
| Multiple background layers (comma list) | High — only first layer honored | Yes (full comma list in string) | **Under-capturing** | Parse all comma-separated layers |
| `background-size` | High — `cover`/`contain`/explicit | Yes | **Missing** | Regime 1 |
| `background-position` | High | Yes (resolved %/px) | **Missing** | Regime 1 |
| `background-repeat` | Med | Yes | **Missing** | Regime 1 |
| `background-clip` (e.g. `text` for gradient text) | High — `background-clip:text` is a common hero effect | Yes | **Missing** | Regime 1 |
| `background-origin` | Low–Med | Yes | **Missing** | Regime 1 |
| `background-attachment` (`fixed`) | Med — parallax-ish pinning | Yes | **Missing** | Regime 1 |
| `background-blend-mode` | Med | Yes | **Missing** | Regime 1 |
| Raster background image bytes | High — the actual image asset | URL only via computed | **Missing** | Regime 4: download URL from `url(...)`; or screenshot crop |

## 3. Effects, shadows, compositing

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| `filter` (blur/brightness/drop-shadow/etc.) | **Very high** — glassmorphism, image treatments | Yes (resolved string) | **Missing** | Regime 1 |
| `backdrop-filter` / `-webkit-backdrop-filter` | **Very high** — frosted-glass nav/cards, ubiquitous on modern sites | Yes | **Missing** | Regime 1 (capture both prefixed + unprefixed) |
| `mix-blend-mode` | Med–High | Yes | **Missing** | Regime 1 |
| `box-shadow` multiple + inset | High — you capture shadow strings as tokens but verify multi-shadow + inset survive | Yes (full string) | **Under-capturing** | Regime 1; parse offset/blur/spread/inset/color per shadow |
| `text-shadow` (incl. multiple) | Med–High | Yes | **Missing** | Regime 1 |
| `clip-path` (polygon/circle/inset/path/url) | High — angled sections, shaped cards | Yes (string) | **Missing** | Regime 1; parse shape function |
| `mask` / `-webkit-mask` (+ `mask-image/size/position/repeat/mode`) | High — masked icons/images | Yes | **Missing** | Regime 1 (capture prefixed + unprefixed longhands) |
| `opacity` | — | Yes | **Covered** | — |
| Blended effective colors (overlap stacking) | High — semi-transparent layers' *effective* color | Computed gives per-element only | **Missing** | CDP `includeBlendedBackgroundColors` + `includeTextColorOpacities` (experimental) |
| Paint order / stacking | Med — overlap correctness | — | **Missing** | CDP `includePaintOrder` |

## 4. Transforms (incl. 3D)

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| `transform` (matrix) | High | Yes (resolved as `matrix()/matrix3d()`) | **Covered** | Note: resolved to matrix; authored `rotate(10deg)` decomposable but lossy |
| `transform-origin` | High — without it, captured transforms pivot wrong | Yes | **Missing** | Regime 1 |
| `perspective` | Med — 3D scenes | Yes | **Missing** | Regime 1 |
| `perspective-origin` | Med | Yes | **Missing** | Regime 1 |
| `transform-style` (`preserve-3d`) | Med | Yes | **Missing** | Regime 1 |
| `backface-visibility` | Low–Med — card flips | Yes | **Missing** | Regime 1 |
| `rotate` / `scale` / `translate` (individual props) | Med | Yes | **Missing** | Regime 1 |

## 5. Typography

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| `font-size`/`weight`/`family`/`line-height`/`letter-spacing`/`text-align`/`color` | — | Yes | **Covered** | rem resolved to px (intent loss) |
| `font-style` (italic/oblique) | High | Yes | **Missing** | Regime 1 |
| `text-decoration` (line/style/color/**thickness**/**offset**) | High — underlines, strikethroughs | Yes | **Missing** | Regime 1 (incl. `text-decoration-thickness`, `text-underline-offset`) |
| `text-transform` (uppercase/capitalize) | High — visible casing differs from DOM text | Yes | **Missing** | Regime 1 |
| `text-overflow` (ellipsis) | Med | Yes | **Missing** | Regime 1 |
| `white-space` (nowrap/pre/pre-wrap) | High — wrapping behavior | Yes | **Missing** | Regime 1 |
| `word-break` / `overflow-wrap` | Med | Yes | **Missing** | Regime 1 |
| `writing-mode` (vertical) | High when used | Yes | **Missing** | Regime 1 |
| `direction` (rtl) | High for i18n | Yes | **Missing** | Regime 1 |
| `font-variant` / `font-feature-settings` (ligatures, small-caps, numerics) | Med | Yes | **Missing** | Regime 1 |
| `font-variation-settings` (variable-font axes) | Med–High — wght/wdth/slnt | Yes | **Missing** | Regime 1; meaningless without the variable font binary (regime 4) |
| `font-stretch` | Low–Med | Yes | **Missing** | Regime 1 |
| `text-indent` | Low–Med | Yes | **Missing** | Regime 1 |
| `tab-size` | Low (code blocks) | Yes | **Missing** | Regime 1 |
| `hyphens` | Low | Yes | **Missing** | Regime 1 |
| `text-rendering` / `font-smoothing` (`-webkit-font-smoothing`) | Low–Med — antialias appearance | Yes | **Missing** | Regime 1 |

## 6. Box, layout, sizing

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| `display`/`position`/`z-index`/`box-sizing`/`flex-*`/`padding-*`/`width/height/min/max`/`grid-template-*` | — | Yes | **Covered** | width/height resolved to **used px** |
| `overflow-x` / `overflow-y` | High — clipping, scroll containers, hidden content | Yes | **Missing** | Regime 1 (you have neither axis) |
| `aspect-ratio` | High — responsive media boxes | Yes | **Missing** | Regime 1 |
| `object-fit` | High — img/video crop behavior | Yes | **Missing** | Regime 1 |
| `object-position` | Med | Yes | **Missing** | Regime 1 |
| `inset` / `top`/`right`/`bottom`/`left` | High — absolute/fixed/sticky positioning | Yes (resolved px) | **Missing** | Regime 1 |
| `margin-*` (all 4) | High — spacing; you capture padding but not margin | Yes (used px) | **Missing** | Regime 1 |
| `gap` / `column-gap` / `row-gap` | High — flex/grid spacing | Yes | **Missing** | Regime 1 |
| `place-items` / `place-content` / `justify-*` / `align-*` | High — flex/grid alignment | Yes | **Under-capturing** | Regime 1 (you have some flex-*; add align/justify/place longhands) |
| `grid-auto-*`, `grid-{column,row}`, `order` | Med–High — grid placement | Yes | **Missing** | Regime 1 |
| `float` / `clear` | Low (legacy) | Yes | **Missing** | Regime 1 |
| `visibility` | — | Yes | **Covered** | — |

## 7. Lists, generated content, pseudo-elements

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| `::before` / `::after` `content` + their full box styles | **Very high** — icons, badges, decorative bars, quote marks rendered entirely via pseudo-elements; **invisible to your tool today** | Yes via `getComputedStyle(el,"::before")` | **Missing (structural gap)** | **Regime 2** — DOMSnapshot does NOT enumerate pseudo-elements; needs a separate per-node JS pass |
| `::marker` (list bullet/number style) | Med | Yes via pseudo arg | **Missing** | Regime 2 |
| `list-style` (type/position/image) | Med | Yes | **Missing** | Regime 1 |
| `::first-line` / `::first-letter` | Med — drop caps | Yes via pseudo arg | **Missing** | Regime 2 |
| `::selection` (highlight colors) | Low–Med | Partial — limited props | **Missing** | Regime 2/4 (parse rule) |
| `::placeholder` (input placeholder style) | Med | Yes via pseudo arg | **Missing** | Regime 2 |
| CSS counters (`counter-reset/increment`, `counter()`) | Low–Med | content string shows resolved counter | **Missing** | Regime 2 (read resolved `content`) |

## 8. Interactive / dynamic states

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| `:hover` | **Very high** — buttons, links, cards all restyle on hover | Not in default snapshot | **LANDED (3b)** | **Regime-3b** — `CSS.forcePseudoState` force-all + recapture + style-delta (§C9-R-P10); real-site 28.9% of nodes |
| `:focus` / `:focus-visible` | High — accessibility focus rings | Not default | **LANDED (3b)** | **Regime-3b** — `:focus` via `CSS.forcePseudoState` (`outline-*` deltas, §C9-R-P10); `:focus-visible` forcible but deferred |
| `:active` | Med | Not default | **LANDED (3b)** | **Regime-3b** — `CSS.forcePseudoState` (§C9-R-P10) |
| `:visited` | Low — **browser falsifies values** | Falsified | **Missing (unrecoverable via DOM)** | Regime 4: parse stylesheet rule only |
| `:checked` / `:disabled` / `:indeterminate` | Med–High — form controls | Forcible | **Missing** | Regime-3b DEFERRED — form-state pseudo-classes, forcible via `CSS.forcePseudoState` but outside the hover/focus/active cut |
| Native form-control appearance (`appearance`, default widget look) | Med | Partial | **Missing** | Regime 1 (`appearance`) + screenshot |

## 9. Responsive / conditional / preference-driven

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| `@media` (breakpoints) | **Very high** — single capture sees one viewport's layout only | Not in computed | **LANDED (3c)** | **Regime-3c** — `Emulation.setDeviceMetricsOverride` (no re-navigate) + recapture over `RESPONSIVE_PROPS` + style-delta (§C9-R-P11); per-node `responsive` deltas, joined by `backendNodeId` |
| `@container` queries | High (modern) | Not in computed | **LANDED (3c + P15)** | **Regime-3c** — viewport-tracking containers re-evaluated at each width (§C9-R-P11); **fixed-width** inline-size containers now captured by **P15** — `--container-queries` mutates each container's width and diffs the restyle into the `container` sidecar (§C9-R-P15). `container-type:size` (2D) + authored thresholds remain ceilings. |
| `clamp()` / fluid type | High — type/space scales with viewport | Resolved to one px | **LANDED (3c)** | **Regime-3c** — `font-size` in `RESPONSIVE_PROPS`; clamp() re-resolves at each width, delta captured (§C9-R-P11); authored expression not recovered (regime 4 ceiling) |
| `prefers-color-scheme` (dark mode) | **Very high** — entire alternate palette | Not in default | **LANDED (3a)** | **Regime-3a** — `Emulation.setEmulatedMedia` dark, recapture + style-delta (§C9-R-P9); per-node `theme.dark` deltas, joined by `backendNodeId` |
| `prefers-reduced-motion` | Med (motion-gated) | Not in default | **Missing** | Regime 3 (emulate media) — deferred follow-on |
| `prefers-contrast`, `forced-colors` | Low–Med | Not default | **LANDED (3a)** | **Regime-3a** — `setEmulatedMedia` `prefers-contrast:more` / `forced-colors:active`, recapture + style-delta (§C9-R-P9); forced-colors dense (UA override) but bounded |

## 10. Architecture, assets, authored intent

| Feature | Visual impact | Readable? | Status | Capture technique |
|---|---|---|---|---|
| CSS custom properties (`--*`) as token source of truth | **Very high** — the *authored* design system; computed values lose the linkage | Per-name value queryable; `var()` reference lost in props | **Under-capturing** | **Regime 4** — parse CSSOM `:root`/scoped rules for `--*` definitions + which props reference them (DOMSnapshot `--*` whitelist support is uncertain; CSSOM parsing is the robust path). Your token clustering approximates this from resolved values |
| `@font-face` + web-font binaries | **Very high** — exact typefaces; without files, font-family names are unbound | Computed gives family name only | **Missing** | Regime 4 — parse `@font-face` `src`, download `.woff2`/`.ttf` |
| `@keyframes` + `transition-*` / `animation-*` | High (motion) | Animation props readable (regime 1); keyframes need regime 4 | **Missing** | **Owned by web_anim / flipbook subsystems** — capture one row, don't expand here (see motion-recovery memory) |
| Shadow DOM / web components | High — encapsulated styles | DOMSnapshot **flattens** shadow DOM into the tree | **Likely covered structurally** | Verify flattened nodes carry correct styles; pseudo-elements inside shadow still need regime 2 |
| `scroll-snap-*` (type/align/stop) | Med — carousels, snapping sections | Yes | **Missing** | Regime 1 |
| `position: sticky` pinning behavior | High — sticky headers | `position` value yes; pin *behavior* is runtime | **Under-capturing** | Regime 1 captures `position:sticky` + `inset`; pin behavior needs scroll capture |
| `scrollbar-width` / `scrollbar-color` / `::-webkit-scrollbar` | Low–Med | Partial | **Missing** | Regime 1 (standard) + regime 2/4 (webkit pseudo) |
| `cursor` | Med — interaction affordance | Yes | **Missing** | Regime 1 |
| `accent-color` | Med — checkbox/radio/range tint | Yes | **Missing** | Regime 1 |
| `caret-color` | Low | Yes | **Missing** | Regime 1 |
| `pointer-events` | Low (visual: none disables) | Yes | **Missing** | Regime 1 |
| `user-select` | Low | Yes | **Missing** | Regime 1 |
| `content-visibility` / `will-change` | Low (perf, rare visual) | Yes | **Missing** | Regime 1 |

---

## Highest-impact missing categories (ranked)

Ranked by **prominence on modern pages × how wrong/invisible the output is today** (not raw frequency):

1. **`backdrop-filter` + `filter`** (regime 1, trivial add). Frosted-glass nav/cards are everywhere on
   2020s sites and render as flat opaque boxes without these. One whitelist line each.
2. **`::before`/`::after` generated content** (regime 2, structural). Icons, badges, decorative
   dividers, quote marks live entirely in pseudo-elements that DOMSnapshot never emits — currently
   100% invisible. Needs a dedicated getComputedStyle-pseudo pass.
3. **Gradient parsing for `background-image`** (regime 1 + parser). You capture the string but can't
   reproduce stops/angle/shape; hero sections and buttons lose their fills.
4. **Interactive states `:hover`/`:focus`/`:active`** (regime 3, recapture) — **LANDED (3b)**. The
   second visual state is now captured as the per-node `pseudo_state` sidecar via
   `CSS.forcePseudoState` force-all + recapture + style-delta (§C9-R-P10; dark-mode/forced-colors/
   contrast LANDED earlier via Regime-3a, §C9-R-P9). Remaining interactive: form-state pseudo-classes
   (`:checked`/`:disabled`) deferred.
5. **Border completeness + `border-style`/`outline`** (regime 1). You capture only the top side and
   assume solid — dashed/per-side/outline borders reproduce wrong.
6. **`overflow-x/y`, `aspect-ratio`, `object-fit`, `margin`, `gap`, `transform-origin`** (regime 1).
   Cheap whitelist adds that fix systematic layout/clipping/spacing errors.
7. **`@font-face` binaries + `--*` token linkage** (regime 4, CSSOM parsing). Required to cross from
   pixel-faithful into *editable authored design intent* — the gap your token clustering only
   approximates from resolved values.

**Structural takeaways:** (a) Most one-pass adds are nearly free — widen the DOMSnapshot whitelist.
(b) Two capabilities require new capture *passes*, not just more properties: a pseudo-element pass
(regime 2) and a multi-condition recapture loop (regime 3: viewports + media emulation + forced
pseudo-states). (c) True authored intent (variables, clamp curves, fonts, breakpoints) lives only in
the stylesheet source — needs CSSOM parsing (regime 4); resolved values can never recover it.
