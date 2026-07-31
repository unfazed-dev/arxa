# Web Animation & Dynamic-Content Capture — State of the Art

Reference for an animation-fidelity capture engine. Enumerates every animation / dynamic-content
category, how it is authored, and whether it is recoverable by:

1. **DOM/CDP introspection (EXACT)** — the browser owns the animation and exposes its parameters
   (`getAnimations()` → `Animation` / `KeyframeEffect`, `getComputedStyle`, CSSOM, parsing source).
2. **Frame/pixel recovery (APPROX)** — sample screenshots, track motion (cv2 template / optical flow),
   fit a model. Lossy: recovers the *rendered trajectory*, not the authoring parameters.
3. **Neither** — no semantic signal short of monkey-patching the runtime; pixel-only or opaque.

Sources indexed (label → `ctx_search(source:)`): `mdn-getAnimations`, `mdn-Animation`,
`mdn-getKeyframes`, `mdn-getTiming`, `mdn-getComputedTiming`, `mdn-keyframe-composite`,
`mdn-scroll-timeline`, `mdn-view-timeline`, `mdn-css-transition`, `mdn-svg-smil-animate`,
`motion-one-docs`, `framer-motion-transitions`, `gsap-scrolltrigger`, `mdn-getcomputedstyle`.

---

## Ground truth: what `getAnimations()` actually exposes

`Element.getAnimations({subtree})` returns an array of `Animation` objects for **CSS Transitions,
CSS @keyframes Animations, and Web Animations API (WAAPI)** animations — i.e. *everything the
browser's own animation engine drives*. It does **NOT** include animations a library produces by
writing inline styles every frame via `requestAnimationFrame` (rAF). That single distinction
decides the whole table.

Per `Animation`:
- `currentTime`, `startTime`, `playbackRate`, `playState`, `overallProgress`, `timeline`,
  `id`, `replaceState`, `finished`/`ready` promises.
- `timeline` is the discriminator for scroll-driven: a `ScrollTimeline` / `ViewTimeline` instead of
  the default `DocumentTimeline`.

Per `effect` (`KeyframeEffect`):
- **`getTiming()`** → `delay`, `endDelay`, `duration` (ms or `"auto"`), `iterations` (incl. `Infinity`),
  `iterationStart`, `direction` (`normal|reverse|alternate|alternate-reverse`),
  `fill` (`none|forwards|backwards|both|auto`), `easing` (group-level `<easing-function>` string).
- **`getComputedTiming()`** → same, with `"auto"` resolved, plus `endTime`, `activeDuration`,
  `localTime`, `progress`, `currentIteration`.
- **`getKeyframes()`** → ordered array; each entry has `offset` (0–1 or null), `computedOffset`
  (never null), **per-keyframe `easing`** (function applied *to the next* keyframe), `composite`
  (`replace|add|accumulate`, absent → inherits effect), and all animated property→value pairs.
- `composite`, `pseudoElement`, `target` on the effect.

**Verdict on the stagger/delay question:** stagger is NOT a first-class field. It is *materialized*:
each staggered element is its own `Animation` with its own `delay` (or `startTime`). Reading
`getAnimations({subtree:true})` and recording `(target, getComputedTiming().delay, startTime)` per
element recovers the exact per-element offset ladder — which is the stagger, just expressed
per-element rather than as a `staggerChildren` parameter. Exact for CSS/WAAPI; invisible for
rAF-driven libs (see below).

---

## Master table

| Animation kind | Authoring | Introspection-capturable? | Pixel-recoverable? | What's lost |
|---|---|---|---|---|
| **CSS transition** | `transition: prop dur ease delay` on state change (`:hover`, class) | **EXACT** while running via `getAnimations()` → `getTiming()` (delay/endDelay/duration/easing). At rest, parse `getComputedStyle` `transition-*`. Trigger (which selector/class flips it) is NOT in the animation object | Approx (need to trigger the state) | Trigger condition; transition only exists during the change window |
| **CSS @keyframes animation** | `@keyframes` + `animation:` shorthand | **EXACT** — `getKeyframes()` gives every stop+per-keyframe easing+values; `getComputedTiming()` gives all timing | Approx | Nothing material if read live |
| **@keyframes infinite / looping** | `animation-iteration-count: infinite` | **EXACT** — `iterations: Infinity`, full keyframes/timing | Approx (one cycle) | Nothing; loop is fully described |
| **`steps()` / step easing** | `animation-timing-function: steps(n, jump-*)` | **EXACT** — easing string is `"steps(...)"` verbatim in `getTiming().easing` / per-keyframe `easing` | Poor (aliasing between samples) | Nothing if read |
| **`linear()` easing (incl. baked springs)** | `transition/animation-timing-function: linear(0, .009, ...)` | **EXACT** — full point list returned verbatim in easing string | Approx | Nothing; this is how WAAPI libs serialize springs |
| **Native scroll-timeline** | `animation-timeline: scroll(<scroller> <axis>)` + `@keyframes` | **EXACT** — `Animation.timeline` is a `ScrollTimeline`; keyframes/timing read normally; scroller+axis from `scroll()` / CSSOM. Limited browser availability | Approx via scrollY scrub (your current method) | Nothing if read; pixel path loses scroller binding |
| **Native view-timeline** | `animation-timeline: view(<axis> <inset>)` | **EXACT** — `ViewTimeline`; subject = the animated element; range driven by its visibility ± inset | Approx via scrub | Inset values unless CSSOM-parsed |
| **GSAP (.to/.from/timeline)** | JS; writes **inline styles every frame via rAF** | **NONE** from `getAnimations()` (not WAAPI). Can read live config only by reaching into `gsap.globalTimeline`/`getTweensOf()` in page JS, or parsing source | **APPROX** (primary path) — sample inline `style`/computed transform per frame, fit bezier/curve | Ease *name* (power2.inOut etc.), duration intent, stagger param, timeline structure |
| **GSAP ScrollTrigger (scrub/pin)** | `scrollTrigger:{scrub,pin,start,end,snap}` | **NONE** native. Live: `ScrollTrigger.getAll()` exposes `progress/start/end/direction/getVelocity()`. Pin = element set `position:fixed` + transform inside a `.pin-spacer` wrapper (detectable in DOM) | **APPROX** — scrollY scrub + per-frame transform read; pin detectable by pin-spacer + fixed | start/end expressions, scrub smoothing (catch-up lag), snap config |
| **Lenis / Locomotive (smooth scroll)** | JS hijacks scroll; applies transform/`scrollTo` lerp | **NONE** semantic | **APPROX** — smoothing is a velocity/lerp effect on scroll position; sample scroll vs transform | Lerp factor, easing of the smoothing itself |
| **WAAPI `element.animate()` / `new Animation`** | JS `el.animate(keyframes, opts)` | **EXACT** — the canonical case `getAnimations()` was built for | Approx | Nothing |
| **Motion One — mini** | `animate()` mini → **native WAAPI** | **EXACT** — visible in `getAnimations()`; springs emitted as sampled `linear()` curve | Approx | stiffness/damping/mass (only the baked `linear()` survives) |
| **Motion One / framer-motion — hybrid tween** | WAAPI where possible | **EXACT for WAAPI-routed tweens**; bezier `ease` recoverable as cubic-bezier/named | Approx | Named-ease label maps to bezier |
| **framer-motion spring (`type:"spring"`)** | rAF; physics from `stiffness/damping/mass` (or `duration/bounce`) | **NONE** of the physics params (they live in JS props). Curve only if WAAPI-baked to `linear()` | **APPROX** — fit a damped-harmonic-oscillator model to the position/time trajectory to estimate ω/ζ → stiffness/damping | Exact stiffness/damping/mass/velocity-injection; only an *equivalent* curve is recoverable |
| **framer-motion layout / `AnimatePresence` (FLIP)** | Measure first/last box, animate inverse transform via rAF | **NONE** (rAF transforms) | **APPROX** — capture before/after layout + interpolate; track transform per frame | That it's layout-driven (auto from→to); only the resulting transform tween survives |
| **anime.js** | JS rAF, inline styles | **NONE** from `getAnimations()` | **APPROX** — per-frame property read | Ease name, stagger/`delay` function, timeline |
| **react-spring** | rAF, spring physics (`tension/friction/mass`) | **NONE** of physics params | **APPROX** — fit damped oscillator | tension/friction/mass; only equivalent curve |
| **IntersectionObserver entrance** | JS observes visibility → adds class / triggers WAAPI/CSS | Trigger logic NONE; **the animation it fires is EXACT if CSS/WAAPI** (then `getAnimations()` works once visible) | Approx | The IO threshold/rootMargin (trigger), unless source-parsed |
| **Hover / focus / `:active` micro-interactions** | CSS `:hover`/`:focus` + transition, or JS gesture | EXACT *only while the state is held* — must synthesize the input (CDP `Input.dispatchMouseEvent`), then `getAnimations()` | Approx (drive input + capture) | Nothing if you trigger it; everything if you don't trigger it |
| **Gesture / drag (framer `drag`, `whileTap`)** | JS pointer events → rAF/WAAPI | Mostly NONE (rAF); `whileTap`/`whileHover` variants may route to WAAPI | **APPROX** — synthesize pointer + capture | Physics, drag constraints, momentum/inertia params |
| **SVG SMIL (`<animate>`, `<animateTransform>`, `<animateMotion>`)** | Declarative SVG elements (`attributeName`, `values`, `dur`, `keyTimes`, `keySplines`, `repeatCount`) | **EXACT by source parse** — the elements ARE the spec; read attributes directly. (SMIL is NOT in `getAnimations()`; `SVGAnimationElement` has playback methods but not keyframe getters) | Approx | Nothing if SVG source is parsed |
| **CSS-on-SVG** | CSS transition/@keyframes targeting SVG attrs/props | **EXACT** — same as CSS path, `getAnimations()` applies to SVG elements | Approx | Nothing |
| **JS-driven SVG (path morph, line draw)** | rAF mutates `d`/`stroke-dashoffset`, or WAAPI on `pathLength` | EXACT only if WAAPI; else NONE | **APPROX** — sample attribute/computed per frame | Path interpolation model |
| **Lottie / bodymovin** | After Effects → JSON; SVG/Canvas/HTML renderer | **EXACT by reading the JSON** — the `.json` (or `.lottie`) IS the full animation graph (layers, keyframes, bezier handles, transforms). Player exposes `totalFrames`, `frameRate`, `playSegments` | Approx (canvas renderer → pixel-only at runtime) | Nothing if the JSON asset is captured; everything if only the canvas is filmed |
| **Rive** | `.riv` binary; state machine + runtime (often WebGL/canvas) | **NONE** without the `.riv` + Rive runtime introspection (state machine inputs). DOM/`getAnimations()` blind | **APPROX (pixel-only)** — film canvas; cannot recover state-machine logic | Entire interactive state machine; inputs/triggers |
| **Canvas 2D animation** | JS rAF draws to `<canvas>`; no DOM nodes for shapes | **NONE** (drawing ops not in DOM; only monkey-patching `CanvasRenderingContext2D` exposes calls) | **APPROX (pixel-only)** — film canvas, optical flow | All semantics; only rendered pixels |
| **WebGL / WebGPU / Three.js / shaders** | GPU draw calls; scene graph in JS only | **NONE** (no DOM; only intercepting GL context / engine globals) | **APPROX (pixel-only)** | Geometry, camera, shader params — everything semantic |
| **View Transitions API** | `document.startViewTransition()`; browser snapshots old/new states and cross-fades/morphs via auto-generated `::view-transition-*` pseudo-element tree | **EXACT** — browser-owned; `getAnimations()` on the `::view-transition` pseudo-elements returns the generated keyframes/timing. Customizable via CSS `::view-transition-group/old/new` | Approx | Nothing if read live during the transition window |
| **`<video>`** | Media element | Metadata EXACT (`currentTime`, `duration`, `paused`, `playbackRate`); content not "animation" | Pixel (it's already video) | N/A — it's literally frames |
| **Animated GIF / APNG / animated WebP** | Encoded multi-frame raster | **EXACT by reading the asset** (frame timings in the file); not in `getAnimations()` | Pixel | Nothing if asset decoded; otherwise just frames |
| **Parallax** | scroll → transform (CSS scroll-timeline, or rAF lib) | EXACT if native scroll-timeline; NONE if rAF lib | **APPROX** — scrollY scrub vs transform (your current path) | Depth/rate mapping unless parsed |
| **Marquee** | `@keyframes` translate loop, or `<marquee>`, or JS | EXACT if CSS (`getAnimations()`); NONE if JS rAF | Approx (loop) | Loop seam if rAF |
| **Typewriter / per-letter stagger** | per-char spans with staggered `delay`; or JS rAF typing | **EXACT if per-char CSS/WAAPI** — read each char element's `delay`/`startTime` (this IS the stagger). NONE if JS rAF text mutation | Approx (OCR-ish per frame, fragile) | Per-char timing if JS-driven; clean if CSS per-char |
| **Particle systems** | Canvas/WebGL/JS, often thousands of sprites | **NONE** | **APPROX (pixel-only, statistical)** — can characterize density/flow, not per-particle | Per-particle state; emitter params |
| **Cursor-follow / custom cursor** | JS pointermove → rAF transform (often lerp) | **NONE** semantic | **APPROX** — synthesize pointer path + capture transform; smoothing is lerp | Lerp/spring smoothing factor |

---

## Capture-method legend by mechanism (the real partition)

- **Browser-owned (CSS transition, CSS @keyframes, WAAPI, Motion One mini, native scroll/view-timeline):**
  `getAnimations()` is EXACT and should be the primary path. Springs from these arrive pre-baked as
  `linear()` curves — exact as a curve, but stiffness/damping are already gone at the WAAPI boundary.
- **rAF + inline-style libs (GSAP, anime.js, framer-motion hybrid/spring/layout, react-spring, Lenis,
  Locomotive, most parallax/cursor/typewriter-JS):** INVISIBLE to `getAnimations()`. Two routes:
  (a) reach into the library's live JS API (`gsap.globalTimeline`, `ScrollTrigger.getAll()`, framer
  internals) — fragile, version-specific; (b) sample inline `style`/computed values per frame
  (MutationObserver on `style`, or rAF polling) and fit a model — robust, lossy.
- **Asset-encoded (Lottie JSON, GIF/APNG/WebP, video, SVG SMIL source):** EXACT by capturing/parsing
  the asset, NOT via any runtime animation API. Filming them is pure waste of fidelity.
- **GPU/opaque (Canvas2D, WebGL/WebGPU/Three, Rive, particles):** pixel-only unless you instrument
  the context/runtime.

---

## Spring physics — the right way to capture

Stiffness/damping/mass are **not introspectable** from `getAnimations()` for any library — they are
JS configuration consumed before the browser ever sees a curve:
- **WAAPI-baked springs (Motion One mini, framer WAAPI path):** the spring is pre-sampled into a
  `linear(p0, p1, ...)` easing string. `getKeyframes()/getTiming()` returns that string EXACTLY, so
  you reproduce the *curve* perfectly but cannot read back ω/ζ.
- **rAF springs (framer `type:"spring"`, react-spring):** invisible entirely. Only recoverable by
  **fitting a damped harmonic oscillator** `x(t) = A·e^(−ζω t)·cos(ω_d t + φ) + x∞` to the captured
  per-frame trajectory, then mapping (ω, ζ, mass=1) → (stiffness = ω², damping = 2ζω). This yields an
  *equivalent* spring, not the authored params, and is ambiguous if velocity was injected from a
  prior gesture. Mark all springs: **introspection NO, pixel APPROX (oscillator fit).**

## Canvas / WebGL introspection

There is **no DOM/CDP introspection** for canvas or WebGL motion. The pixels are the only signal.
The sole semantic route is runtime instrumentation: wrapping `CanvasRenderingContext2D` /
`WebGLRenderingContext` / `requestAnimationFrame` via injected script to log draw calls — out of
scope for a passive capture engine and brittle. Treat as pixel-only (category 3).
