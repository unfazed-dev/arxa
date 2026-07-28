# Web-Page Visual Capture: State of the Art and Gap Checklist

Research for **probe-runner**: programmatically capturing a live web page's COMPLETE
visual design into a portable/reproducible representation (DOM/CSSOM → design tokens +
layout + assets).

**Date:** 2026-05-29
**Provenance legend:** `[SRC]` = stated in a cited source · `[INF]` = inferred from the
tool's architecture (no vendor publishes its own gaps; "what it misses" is reasoned from
the extraction substrate it must use).

---

## TL;DR — the axis every tool fails on

Every surveyed tool produces **one static frame**. A web page is not a frame — it is a
*function over time, input, and viewport*: `render(t, pointer, focus, viewport, scroll)`.
The universal failure mode is the collapse of that function to a single sample. probe-runner's
edge is to treat capture as sampling that function, not photographing one output. Rank order
of gaps is at the bottom of this doc.

---

## 1. The extraction substrate (what *anything* can physically read)

Before per-tool analysis: every tool that reads a *live page* (vs. a Figma file) is limited
by what the browser will hand back. Three substrates exist, each lossy in a known way.

| Substrate | API | Returns | Structural ceiling |
|---|---|---|---|
| **CSSOM resolved values** | `getComputedStyle(el[, pseudoElt])` | "Resolved values" — *not* authored CSS | `var()`, `calc()`, relative units, gradients are **already collapsed** to a serialized string; you can never recover the authored token. `width`/`height` return *used* value (px), most others the *computed* value. `:visited` styles are deliberately faked for privacy. [SRC: MDN] |
| **CDP DOMSnapshot** | `DOMSnapshot.captureSnapshot` | Flattened DOM + layout tree + **whitelisted** computed styles + paint order + DOM rects | You must pre-name the styles you want (`computedStyles` whitelist) — unknown/new properties are silently absent. **Shadow DOM is flattened** (boundaries lost). `includeBlendedBackgroundColors`/`includeTextColorOpacities` are *experimental*. One snapshot = one viewport, one instant. [SRC: CDP] |
| **CDP CSS (authored)** | `CSS.getMatchedStylesForNode` | Inline + attribute + matched rules + **pseudoElements** + inherited + `@keyframes` + `@position-try` + custom-property rules | This is the *only* path to authored rules, selector specificity, and which rule won. Per-node, slow, requires a live debugger session; not a bulk snapshot. `CSS.forcePseudoState` can *force* `:hover/:focus/:active` before reading. [SRC: CDP] |

**Key consequence:** Resolved-value capture (the easy path, used by most design-import
tools) destroys design *intent*. `padding: var(--space-3)` becomes `padding: 16px`. The
token system — the actual "design system" — is gone. Recovering tokens requires the authored
CSSOM (`getMatchedStylesForNode` / stylesheet text), not `getComputedStyle`.

---

## 2. Per-tool capability matrix

Columns: **Captures** (faithfully) · **Approximates** (lossy) · **Misses** (absent) ·
**Why** (technical reason).

### html.to.design (‹div›RIOTS) — DOM→Figma layers
- **Maps:** containers→Frames, text→Text layers, backgrounds→Rectangles, SVG→vector paths;
  optional auto-layout inference, local styles/variables, "hover states as Figma components." [SRC: html.to.design blog]
- **Captures:** geometry, fonts/colors/spacing as flat values, images, computed layout. [SRC]
- **Approximates:** auto-layout (re-inferred from box geometry, not from authored flex/grid);
  hover (only if a discrete second state is requested — not a transition). [SRC/INF]
- **Misses:** authored CSS tokens (Figma variables are *derived*, not the page's `--vars`),
  CSS animation/transition timing, canvas/WebGL pixels as live content, `::before/::after`
  generated content unless the renderer materializes it, blend-modes/filters that Figma can't
  express. **Why:** Figma's node model has no concept of computed-vs-authored, no timeline,
  no shader; the importer must down-project to a static Figma scene graph. [INF]

### Builder.io Visual Copilot / DevTools
- **Pipeline:** AI model (2M+ data points) flattens design → **Mitosis** IR → framework code;
  final LLM pass tailors to React/Vue/Svelte/Tailwind/etc. Direction is *design→code* and
  *Figma→code*; the value is code synthesis, not fidelity capture. [SRC: Builder blog]
- **Captures:** layer hierarchy, responsive intent ("automatic responsiveness"). [SRC]
- **Approximates:** responsiveness (model-predicted breakpoints, not measured); styling library
  mapping. [SRC/INF]
- **Misses:** exact pixel fidelity is explicitly *not* the goal — it produces "clean code,"
  which means it **normalizes away** idiosyncratic values. Animation, interactive state,
  canvas. **Why:** an LLM/IR compiler optimizes for plausible maintainable code, so it
  regularizes magic numbers and drops what it can't name in the IR. [INF]

### Anima / Locofy.ai / quest.ai / TeleportHQ — design↔code
- **Anima/Locofy/Quest:** primarily *Figma→code*; consume a design file, not a live DOM.
  Quest: captures Auto-Layout (padding/spacing/alignment), design tokens, components;
  **explicitly drops rotation, and flattens "Crop"/"Tile" image fills to Fill/Fit.** [SRC: Quest]
- **Anima:** respects Figma auto-layouts, breakpoints, constraints → responsive HTML/CSS,
  React/Vue/Tailwind/MUI; **documented to slip on interactive states (hover/focus) and complex
  animations — "often requiring manual adjustment."** [SRC: Anima docs/blog]
- **Locofy:** tags interactivity *manually* (hover effects, carousels, popups are "prebuilt
  prompts"/agent recipes), implying these are **not auto-extracted from a source page.** [SRC: Locofy docs]
- **TeleportHQ:** visual builder + code; design→code direction, no live-page structural capture. [SRC: blog index — no capture mechanism documented]
- **Misses (all):** since input is a Figma file, anything never expressed *in* Figma (real
  fonts' hinting, CSS filters, video, scroll-linked animation, computed-from-JS layout) is
  absent at the source. **Why:** the lossy step happened upstream — the design file already
  lacks the runtime. [INF]

### Figma "import HTML/CSS" (plugins)
- **Captures:** native layers (frames/text/rect/vector), fonts/colors/spacing, images,
  optional auto-layout, optional hover-state-as-component. [SRC: web search synthesis]
- **Approximates:** web fonts (must detach/replace if not in Figma library → drift), local
  asset paths (break → drift). [SRC]
- **Misses:** same static-frame ceiling as html.to.design. **Why:** Figma scene graph. [INF]

### Webflow capture
- **No automated whole-site import exists.** Manual paste hits embed character limits; you
  must re-map HTML→Webflow components and re-author CSS by hand. **Why:** Webflow's model is
  authored components, not arbitrary captured CSS; "everyone codes differently." [SRC: Webflow forum/help]

### Playwright / Puppeteer + CDP (the substrate, not a product)
- **Captures:** anything in §1 — full computed styles, layout rects, paint order, authored
  rules (per node), forced pseudo-states, screenshots. This is the **most complete** programmatic
  reader and what probe-runner should build on. [SRC: CDP]
- **Approximates / Misses by default:** nothing is *captured* unless you ask; it's a substrate.
  The gaps are whatever §1 says (var/calc collapse in resolved values, shadow flattening,
  single-instant). **Why:** it's an API, fidelity = the capture program you write on top. [INF]

### Chrome DevTools "Copy styles" / CSS Overview panel
- **Copy styles:** copies *resolved* declarations for one element → same collapse as
  `getComputedStyle`; no tokens, no states. [INF]
- **CSS Overview:** *aggregate audit* — color/font/media-query inventory, unused declarations,
  contrast issues. It is an **analysis report, not a reproduction** — no geometry, no per-node
  fidelity, no assets. **Why:** designed to surface CSS hygiene, not rebuild the page. [SRC: DevTools docs]

### Screenshot / visual-regression (Percy, Chromatic, reg-cli, Pixelmatch)
- **Captures:** the *rendered pixels*. Percy **stores the DOM snapshot + page assets, then
  re-renders server-side** across browsers and at different widths (resizing the browser);
  it freezes animations, stabilizes fonts/dynamic data. [SRC: Percy docs] Chromatic
  **archives a complete UI bundle (DOM, styles, assets), renders it in cloud browsers, then
  pixel-diffs**; TurboSnap only re-snaps stories whose Git/dependency graph changed. [SRC: Chromatic docs]
- **Approximates:** nothing about *structure or tokens* — they intentionally don't model it.
  Animation is **deliberately frozen** to stabilize diffs — the opposite of capturing it. [SRC: Percy]
- **Misses:** **all structural/design-token data.** Pixelmatch/reg-cli diff two PNGs;
  there is no design representation at all. Percy/Chromatic re-render but to *compare*, not
  to extract a portable token+layout model. **Why:** the product is *change detection*, so
  the output is a diff/score, not a reusable design representation. They answer "did it
  change?" never "what is it made of?" [SRC for mechanism; INF for the gap]

---

## 3. The hard problems everyone hits (cross-cutting)

| Problem | Why it's hard (mechanism) | What survives capture today |
|---|---|---|
| **`::before` / `::after` generated content** | Pseudo-elements have **no DOM node**. `content:` strings/`url()`/counters exist only at render. Readable only via `getComputedStyle(el, '::before')` or CDP `pseudoElements` — most importers iterate real DOM nodes and skip them. `::before` is invalid on replaced elements. [SRC: MDN, CDP] | Only if the tool explicitly walks pseudo-elements; usually lost. |
| **Interactive states (`:hover`/`:focus`/`:active`/`:checked`)** | Not present in a static snapshot. Must be *forced* (`CSS.forcePseudoState`) **then re-read**, once per state per node. Combinatorial; no tool does it exhaustively. [SRC: CDP] | A best tool captures the *default* state only. |
| **Computed vs authored styles** | `getComputedStyle` returns **resolved values** — backward-compat serialized output, not author CSS. Recovering authorship needs matched-rules + specificity from the CSSOM. [SRC: MDN, CDP] | Computed values (works); authored intent (lost on the easy path). |
| **CSS custom properties (`--vars`)** | `var()` is **substituted before** computed value; `getComputedStyle` shows the *result*, not the var. The token graph (definitions, fallbacks, `@property`, cascade/inheritance) lives only in stylesheet text. [SRC: MDN] | The flat result; the *system* is gone unless stylesheets are parsed. |
| **Web fonts** | Computed `font-family` is a *list*; the **actually-rendered** face needs `CSS.getPlatformFontsForNode` (familyName, postScriptName, `isCustomFont`, glyphCount). Font *files* are separate fetches; licensing/subsetting can block re-embedding. [SRC: CDP] | Font name; rarely the binary or which face truly rendered. |
| **Gradients / filters / masks / blend-modes** | `getComputedStyle` serializes a gradient to a string (re-parseable) but `filter`/`mask`/`mix-blend-mode` often have **no target-format equivalent** (Figma, design tokens). CDP `getBackgroundColors` returns gradient *stops* but **"anything more complicated → empty array," images ignored.** [SRC: CDP] | Simple gradients (as strings/stops); complex filters/masks dropped or rasterized. |
| **Responsive breakpoints** | `var()` can't live in media/container queries; breakpoints exist only as `@media`/`@container` rules in stylesheet text. A single snapshot = one viewport → others are **unobserved** unless you re-capture per width. [SRC: MDN/CDP] | One viewport per snapshot; multi-breakpoint needs N captures. |
| **Canvas / WebGL / video** | Pixels live in a GPU/element buffer, not the DOM. `canvas.toDataURL()` throws `SecurityError` if the bitmap is **not origin-clean** (any cross-origin pixel taints it). WebGL framebuffer + video frames aren't in computed style at all. [SRC: MDN] | At best one rasterized frame (if origin-clean); live content never. |
| **Shadow DOM / web components** | `DOMSnapshot` **flattens** shadow trees (boundary, slotting, `mode:'closed'` lost). Encapsulated styles don't appear via outer-page CSS reads. `::part`/`::slotted` rejected by `getComputedStyle`. [SRC: MDN, CDP] | Flattened visual result; component identity & encapsulation lost. |
| **Lottie / SVG animation** | Time-driven (JS/SMIL/CSS). A snapshot freezes frame 0. Even SVG static markup misses the animation *driver*. [INF] | One frozen frame. |

---

## 4. Ranked gap checklist — what a "capture every detail" engine must close

Ranked by impact on a *reproduction* engine (probe-runner). Per project memory, **exact
animation fidelity is the user's sole interest**; content/images are filler — so the temporal
axis leads.

1. **TIME / animation (the #1 gap, universally unsolved).** No surveyed tool captures the
   timeline: CSS transitions/keyframes timing+easing, scroll-linked & view-timeline anim,
   JS-driven motion, Lottie/SVG. *Action:* sample the render function over time
   (frame-based / flipbook capture), not one instant. Capture `@keyframes` (CDP exposes
   `cssKeyframesRules`) **and** the realized motion. This is probe-runner's actual edge.

2. **Interactive state space (`:hover/:focus/:active/:checked`, `forceStartingStyle`).**
   Everyone ships the default state only. *Action:* enumerate states via
   `CSS.forcePseudoState`, re-capture per state. Combinatorial — needs a budgeted strategy.

3. **Authored tokens vs resolved values (design-system recovery).** The easy `getComputedStyle`
   path destroys `--vars`/`calc`/breakpoints — i.e. the design system itself. *Action:* parse
   stylesheet text + `getMatchedStylesForNode`; reconstruct the token graph, don't read flat px.

4. **Multi-viewport / responsive.** One snapshot = one width. *Action:* re-capture across the
   `@media`/`@container` breakpoints found in stylesheet text; diff to recover responsive rules.

5. **Canvas / WebGL / video (dynamic raster surfaces).** Often the hero content; tainting blocks
   even one frame. *Action:* frame-sample where origin-clean; otherwise compositor/screenshot
   capture as fallback; flag as non-reproducible-as-vectors.

6. **Pseudo-elements & generated content.** Cheap to fix, routinely missed. *Action:* walk
   `::before/::after/::marker` via `getComputedStyle(el, pseudo)` + CDP `pseudoElements`.

7. **Shadow DOM / web-component identity.** Snapshots flatten it. *Action:* traverse shadow
   roots explicitly (open mode); record boundaries/slots; accept `closed` as a hard limit.

8. **Web-font binary + true rendered face.** *Action:* `getPlatformFontsForNode` for the real
   face; fetch+embed font files (handle subsetting/licensing).

9. **Filters / masks / blend-modes.** No clean target-format mapping. *Action:* preserve the
   authored CSS string verbatim as a fidelity layer; rasterize only as last resort.

---

## 5. Sources indexed (ctx source labels)
`CDP DOMSnapshot protocol`, `CDP CSS domain`, `MDN getComputedStyle`,
`MDN CSS custom properties`, `MDN pseudo-element before`, `MDN shadow DOM`,
`MDN canvas toDataURL`, `Builder Visual Copilot blog`, `Locofy docs best practices`,
`DevTools CSS Overview`, `TeleportHQ blog`, `html.to.design mapping blog`.
Web-search-anchored (vendor docs, not scraped into ctx): quest.ai, Webflow import,
Figma HTML/CSS plugins, Percy (browserstack.com/docs/percy), Chromatic (chromatic.com/docs),
Anima (animaapp.com).
