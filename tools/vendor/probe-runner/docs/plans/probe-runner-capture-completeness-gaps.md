# probe-runner — capture-completeness gap analysis

**Question:** what is probe-runner missing to capture *every* visual detail of a web page, and which additions would most improve it?

**Method:** local inventory of current coverage (WANT_STYLES, tokens, motion channels, documented limits) diffed against three web-researched reference checklists:
- `docs/research/web-capture-tools-soa.md` — what mature tools (html.to.design, Builder Visual Copilot, Anima, Locofy, Quest, Percy/Chromatic) capture vs miss.
- `docs/research/css-capture-completeness.md` — exhaustive CSS visual-feature checklist (103 rows; 6 covered / 11 under-captured / 78 missing) with per-row CDP readability + capture regime.
- `docs/research/animation-capture-soa.md` — full animation/dynamic-content space, introspection vs pixel-recovery per kind.

---

## The honest ceiling first

"Capture EVERY detail" is **not fully achievable** — three limits are fundamental, not effort:

1. **Authored intent is unrecoverable from resolved values.** `getComputedStyle` returns *resolved* output — `16px` not `1rem`, `rgb(...)` not `var(--brand)`, the post-`@media` value not the `clamp()` curve or the breakpoint that produced it. The design *system* (variables, fluid-type curves, which rule won) lives only in stylesheet source text. Recoverable only by parsing the raw CSSOM / `CSS.getMatchedStylesForNode` — and even then minified/CSS-in-JS output may not round-trip to authored intent.
2. **Cross-origin canvas / WebGL / WebGPU / DRM video are pixel-only and often un-readable.** Pixels aren't in the DOM; `canvas.toDataURL()` throws `SecurityError` on a cross-origin-tainted canvas. Best case is screenshot/flipbook (what's painted), never the scene graph or shader.
3. **Authored spring physics can't be introspected.** rAF spring libraries (react-spring, framer-motion springs) expose no stiffness/damping. You can fit an *equivalent* damped oscillator to the pixel trajectory, but you recover a look-alike, not the authored params.

Everything below the ceiling is "the data is readable; probe-runner just doesn't read it yet." That is the actionable part, and it's large.

---

## What probe-runner nails today

- **Geometry/layout** at a ~0px CSS-px floor (`skeleton_diff`: pos/size 1.0, iou 0.98, matched_frac 0.99) — REST bbox, role, z-index, parent tree, sizing intent (hug/fill/fixed), flex/grid layout.
- **Tokens** — clustered colors → semantic roles; type scale (sizes/weights/families); spacing, radii, box-shadow scales.
- **Motion** — scroll-scrubbed transforms (9 channels incl. Z) with cubic-bezier fit; frame-based "flipbook" for time/event motion, web + iOS + Android + Flutter; WAAPI `getAnimations()` used as an exact oracle on web.
- **Vectors** — opt-in `vtracer` raster→SVG reference traces (non-certified).

The architecture is the right substrate: CDP + the "exact-where-an-oracle-exists, honest-gap-elsewhere" model. The gaps are coverage, not foundation.

---

## The framing that orders everything: capture is 4-dimensional

Every capture tool (probe-runner included) photographs **one cell** of a 4-D matrix:

> **breakpoint × interaction-state × color-scheme × time**

probe-runner currently captures ≈ `{one viewport} × {REST/default} × {light} × {one instant}`, plus partial multi-breakpoint *sizing* inference and the motion (time) axis via web_anim/flipbook. The missing dimensions (hover/focus state, dark mode, real per-breakpoint style deltas) are entire visual layers, not single properties. CDP exposes the levers to sweep them. **This is the single biggest conceptual gap** — and it reframes most individual misses below as "we only sampled one cell."

---

## Tier 1 — cheap, oracle exists, not yet read (do these first)

High visible impact, mostly one-pass additions. Closes most of the *visible* gap for near-zero cost.

### 1a. Widen the `WANT_STYLES` whitelist (free — same DOMSnapshot pass)
Currently captures ~30 props; missing high-impact ones, all readable from the existing getComputedStyle pass:
- **`filter` + `backdrop-filter`** — frosted glass / blur is everywhere on modern sites; renders as flat opaque boxes today. **#1 cheap win.**
- **Gradient parsing** — `background-image` string *is* captured but linear/radial/conic stops/angle aren't decomposed into tokens → hero/button fills lost.
- **All four borders + `border-style`** — only `border-top-width/color` today; asymmetric borders, dashed/dotted, `outline` all missed.
- **`transform-origin`** — without it, transforms you already capture **pivot at the wrong point** (corrupts existing data, not just adds).
- **`margin`** — padding captured, margin never → spacing between blocks wrong.
- **`overflow-x/y`** (scroll containers), **`aspect-ratio`**, **`object-fit/object-position`** (image crop), **`box-shadow`/`text-shadow` per-node binding** (multiple + inset), **`mask`/`clip-path`**, **`mix-blend-mode`/`background-blend-mode`**, **`text-decoration`/`text-transform`/`white-space`/`writing-mode`/`font-style`/`font-feature-settings`**, **`inset`/top/right/bottom/left**, **`cursor`**, **`list-style`**.

### 1b. Pseudo-element pass (`::before` / `::after`) — small new pass
DOMSnapshot **never emits pseudo-elements**, so the entire decorative layer — icons, badges, dividers, quote marks, gradient overlays, underline bars — is **100% invisible** today. Needs a dedicated `getComputedStyle(el, '::before'|'::after')` sweep over candidate nodes, reading `content` + box/background props. Routinely the difference between "looks right" and "looks empty."

### 1c. Full `getAnimations()` reader — the headline animation addition
Supersedes the current `getComputedStyle().transition/animation` text path. Reading `getAnimations({subtree:true})` + `getKeyframes()` + `getComputedTiming()` exactly yields per-keyframe easing/offset/composite and delay/endDelay/iterations/iterationStart/direction/fill — for **every browser-owned (WAAPI + CSS) animation**. This single reader closes three known gaps at once:
- **Per-letter stagger** = each element's `startTime`/`delay` (the kasane menu's 0–300ms cascade currently NOT in the bundle — see `bundle-motion-fidelity-layers`). **Same fix.**
- **Looping/idle animations** = `iterations: Infinity` + full keyframes.
- **Hover-triggered** = synthesize input via CDP, then read.

**Caveat (reconciled with our own evidence):** research framed framer-motion as rAF and thus invisible to `getAnimations()`. That over-states it. Modern framer-motion / Motion route **many** animations through WAAPI — and probe-runner *empirically read kasane's framer menu exactly via `getAnimations()`* (`kasane-page-epoch`). So: WAAPI-routed framer = visible; only genuinely rAF-driven inline-style animation stays invisible. Treat visibility as **animation-type / version dependent**, verified per target — not a blanket "framer is blind."

---

## Tier 2 — new capture pass (sweep the missing matrix dimensions)

Each is a recapture loop, not a property. Real engineering but bounded; CDP has the lever for each.

- **Interaction states** — `CSS.forcePseudoState` to force `:hover/:focus/:active/:checked/:disabled`, then re-run skeleton+tokens. Combinatorial, so scope to interactive nodes (links, buttons, inputs). No mature tool does this; it's an entire missing visual state.
- **Dark mode / media** — `Emulation.setEmulatedMedia({prefers-color-scheme:dark, prefers-reduced-motion})` → recapture the second palette/state.
- **Real per-breakpoint style deltas** — `--viewports` today infers *sizing* only; a full re-capture per discovered `@media`/`@container` breakpoint would capture the actual style deltas (re-flowed layout, swapped values), not just hug/fill.

---

## Tier 3 — fundamental ceiling (manage expectations, don't over-invest)

- **Authored intent** (vars/calc/clamp/breakpoints/specificity) — needs raw CSSOM/`getMatchedStylesForNode` parsing; partial at best; the honest answer is "pixel-faithful yes, editable design-system no" unless this is built.
- **Cross-origin canvas / WebGL / video** — pixel-only via flipbook; no scene capture.
- **rAF JS-lib motion** (GSAP/Lenis/anime.js/react-spring not routed through WAAPI) — invisible to introspection; needs inline-style sampling (MutationObserver/rAF poll) + curve fit; spring params only recoverable as an equivalent oscillator.
- **Real asset bytes** — actual `<img>`/`srcset`/background-image binaries and `@font-face` font files aren't downloaded (by design: content-independent clone swaps them). If "every detail" must include the literal rendered font, add a font-binary fetch — but note the IP/content-independence constraint.

---

## The other certification gap: structural ≠ pixel

`skeleton_diff` certifies **structure + tokens**, not a literal screenshot. A golden-image pixel diff (Pixelmatch/reg-cli style) is explicitly out of scope today. So "pixel-perfect" currently means *geometry + token faithful*, not *rendered-pixels identical*. If the bar is "every detail," a pixel-diff certification layer (rendered clone vs source screenshot, per matrix cell) is the missing top-level acceptance gate — and it would also catch everything Tier 1/2 misses, as a backstop.

---

## Recommended sequencing (anchored to the actual target, not the generic web)

The biggest *generic-web* gap is rAF JS-lib blindness (GSAP/Lenis dominate marketing sites). But for kasane / marketing-site clones the authoring mix is largely **WAAPI-routed + scroll-scrubbed**, which probe-runner already covers. So **do not build rAF inline-sampling speculatively** — verify the target's authoring mix first.

Proposed order:
1. **Tier 1a whitelist widen** (filter/backdrop-filter, gradients, borders, transform-origin, margin, overflow, object-fit) — biggest visible-fidelity gain per hour.
2. **Tier 1c `getAnimations()` reader** — closes the menu-stagger gap already flagged + looping + hover; supersedes the current path.
3. **Tier 1b pseudo-element pass** — recovers the invisible decorative layer.
4. **Tier 2 dark-mode + hover recapture** — second visual state.
5. **Pixel-diff certification layer** — top-level "every detail" backstop.
6. **Tier 3 / rAF sampling** — only if a target needs it (check authoring mix first).

Tiers 1–2 + the pixel-diff gate are the realistic path to "captures essentially every detail a clone needs." Tier 3 is the named, honest ceiling.
