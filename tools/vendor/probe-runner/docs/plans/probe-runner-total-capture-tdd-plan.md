# probe-runner — total-capture + content-firewall TDD plan

Supersedes `probe-runner-capture-completeness-gaps.md` and the prior draft of this file.

**Thesis (user-set):** probe-runner reproduces **exactly** every *mechanism* a page exhibits —
layout, sizing, theme, CSS/WAAPI animations, timing, stagger — and **never persists** any IP:
images, video, canvas pixels, or text content. Those are **detected and discarded at scan time**
and replaced with **typed placeholder slots** that the downstream rebuilding agent recognizes and
fills with its own free content. The bundle is content-free **by construction**, verified by a
hard audit gate — not by an opt-out flag.

**Two typed products (the invariant is product-scoped, never flag-overridden):**
- **`bundle/`** — the default, content-independent product. R5 audit is unconditional; it is
  content-free *by construction* and can never be relaxed by any flag.
- **`replica/`** — an explicitly separate, permission-gated full-fidelity copy *with* content
  (Mode Z), carrying its own provenance manifest. It is NOT a `bundle/`, so R5's "no content in
  bundle/" rule never applies to it. You don't override the bundle's guarantee — you choose a
  different product. The two are produced by distinct runs and never silently coexist.

---

## Invariant 0 — observation vs emission (read this first)
The firewall governs what probe-runner **persists**, NOT what it transiently **observes**.
probe-runner MUST load and render the live page (it cannot measure an animation or theme without
running it) — the same way `web_anim` already scrubs the live IP page. "Discard at scan stage"
means: content never reaches any *emitted artifact* (bundle, sidecar, log, screenshot kept on
disk). Transient in-memory observation is unavoidable and allowed; persistence of content is
forbidden and audited.

## The classification boundary
**CSS-expressible ⇒ mechanism ⇒ reproduce exactly. Pixels / glyphs / media bytes / text ⇒
content ⇒ redact to a slot.**

| Keep (mechanism / theme) | Redact to slot (content) |
|---|---|
| gradients, shadows, filters, backdrop-filter, clip-path, masks-as-shape | `<img>`, `<picture>`, `srcset`, `background-image: url()` |
| borders, radius, outline, blend-modes | `<video>`, poster, `<audio>` |
| transforms, transform-origin, perspective | `<canvas>` / WebGL / WebGPU pixels + shaders |
| layout (flex/grid), sizing, spacing, overflow | `<iframe>` / `<object>` / `<embed>` embedded content |
| CSS + WAAPI animations: easing, timing, delay, stagger, iterations | **all text strings** (kept as length/role only) |
| color tokens, type **spec** (family/size/weight/spacing) | font **binary** files (spec kept; bytes never) |
| **native inline `<svg>` geometry** (kept — see exception) | data: URIs, base64 blobs anywhere |

### ⚠️ The SVG exception (user-sanctioned, stated plainly)
Per the user's call, **native inline `<svg>` geometry is KEPT** (it's vector mechanism, not raster
bytes). This means "content-free by construction" has **one explicit exception**: an inline `<svg>`
that is a **brand logo or illustration is IP**, and keeping its path data retains that IP. So the
firewall keeps SVG geometry **but classifies every `<svg>`** as
`decorative | icon | logo | illustration` and tags `logo`/`illustration` as **swap-recommended**,
so the rebuilding agent can replace a logo. Raster→SVG **tracing** (the `web_vectors` path) is
**NOT used for content-independent bundles** — tracing an `<img>` photo into vectors reproduces the
photo's content, so for a normal capture raster always becomes a slot, never a trace. The tracer
itself is **retained as a disabled owned-content tool** (Mode X) for designs you own.

## The residue list — TRANSFORMED, not shrunk
Under the firewall, most former "ceiling" residues **dissolve** — DRM video, un-triggered content
bytes, asset/font binaries, WebGPU/OffscreenCanvas pixels are now simply *"content, slotted by
design,"* not failures (and capturable on purpose via the disabled owned-content tools in Mode X
when you own the design). What genuinely survives for a content-independent bundle is
**mechanism-only**:
1. **Exact authored spring params** — rAF spring stiffness/damping never exposed → equivalent-fit
   (look-identical, not authored numbers).
2. **Ambient canvas / shader / Lottie motion** — pixels are content, so its animation is captured
   as a content-independent **behavior class + motion law** (via flipbook), not pixel-exact. This
   is the one qualification on "reproduce animations exactly."
3. **Mangled authored token names** — minified / CSS-in-JS hashed `--var` names: the *value* is
   kept, the authored *name* is lost.
Plus the always-true limit: content probe-runner never triggers, it never sees.

---

## Conventions (every task)
- TDD: failing test (feeding **varying** data across steps — synthetic-green-trap guard) → minimal
  code → commit. Single-line message, explicit staging, **no push**.
- Append, don't reorder ordered contracts (`WANT_STYLES` ∥ `layout.styles[i]`; `CHANNELS`).
- Canonical first (`~/Developer/artificial_intelligence/skills/probe-runner`), then propagate to
  engineering-pack + brainiac; verify blobs parse (`git cat-file | ast.parse`).
- **Default bias on uncertain classification: over-redact (slot it), never under-redact (leak IP).**

Six modes. **Mode R (firewall) is mandatory and the spine**; A/B/C are the mechanism-capture
breadth; E is a rebuild-time gate; F propagates.

---

# MODE R — content firewall (MANDATORY; governs all emission)

New module `content_firewall.py` + `slots.py`, invoked by `web_skeleton`/`web_tokens`/
`bundle_writer` before anything is written. Five responsibilities, one spec-level task each.

### R1 — detect
Identify every content-bearing node/resource: `<img>/<picture>/<source>`, `background-image:url()`
(distinguish from gradients — gradients are mechanism), `<video>/<audio>`, `<canvas>`/WebGL,
`<iframe>/<object>/<embed>`, inline `<svg>`, any **text node**, **text-bearing attributes**
(`alt`,`title`,`aria-label`,`placeholder`,`value`,`<input value>`), font `@font-face` sources, and
**CSS custom-property values containing `url()` / content strings**.
- **Test:** fixture with one of each → detector returns the correct typed hit list; a pure-CSS
  gradient/shadow node is NOT flagged (mechanism). Synthetic-green: vary node types.

### R2 — classify
Assign each hit a `type` + `role` + (for svg) `svg_class` (decorative/icon/logo/illustration) +
(for media) a behavior probe handle. Roles from position/size/context (hero/avatar/logo/gallery/
background/body/heading/label/nav-icon/decorative).
- **Test:** a large top-of-page `<img>` → role `hero`; a small nav `<svg>` → `icon`; a header
  `<svg>` with brand path → `logo` (swap-recommended). Synthetic-green: distinct inputs → distinct
  classes (no collapse).

### R3 — redact
Strip content before emission: drop image/video/canvas bytes & URLs; reduce text to
`{char_len_bucket, line_count, dir}`; redact text-bearing attrs; redact `url()`-bearing CSS vars;
never download fonts. Keep the surrounding CSS (theme) and `anim_ref` (motion).
- **Test:** post-redact node carries NO raw text, NO src/url, NO data:URI — but retains bbox,
  token_ref, anim_ref, type spec. Synthetic-green: a node with real prose → only length survives.

### R4 — emit typed slot (+ `slots.json` index)  — **per user: typed objects + index**
```
slot = {
  id,                         # stable
  type,                       # image|background-image|video|canvas|iframe|text|font|svg
  role,
  box:{x,y,w,h}, aspect_ratio, object_fit, object_position,
  theme_ref:{bg,border,radius,shadow,filter,blend},   # CSS around the hole (kept)
  anim_ref:[...],                                       # how it animates (kept)
  behavior:{loop,autoplay,controls,motion_class,period_s,confidence},  # media only (flipbook)
  text_class:{role,char_len_bucket,line_count,dir},    # text only (no words)
  svg_class,                                            # kept svg only
  fill_hint                                             # machine/human hint for the agent
}
```
Nodes carry `slot_ref → id`; bundle gains `slots.json` (the index the rebuilding agent reads).
- **Test:** each detected type → a well-formed slot; `slots.json` indexes all; node back-references
  resolve. Synthetic-green: N distinct holes → N distinct slots.

### R5 — audit gate (HARD FAIL, conservative, bias to false-positive) — THE invariant
**This is where IP-safety lives — at the output boundary, not in code-absence** (user decision).
It runs **unconditionally on every `bundle/` write, regardless of any Mode-X capture flag** — so
even with owned-content capture ON, nothing content-bearing can reach a content-independent bundle.
A post-bundle scan that **fails the build** (rc≠0) on any leak:
- any `data:` URI or long base64 run in any bundle file;
- any raster/font binary in the bundle dir (magic-byte scan: PNG/JPEG/GIF/WEBP/AVIF/WOFF/WOFF2/
  TTF/OTF/MP4/WEBM…);
- any retained content URL (img/video/bg-url/font src) — must be a slot, not a URL;
- any prose-like string > N chars (alphanumeric + spaces) outside whitelisted theme fields;
- any un-redacted text-bearing attribute.
- **Test:** a deliberately-poisoned bundle (planted data:URI / prose / .png) → audit rc≠0 with the
  offending path; a clean bundle → rc=0. Synthetic-green: each leak class tested separately.
- **Commit (R1–R5):** `feat(content_firewall): detect/classify/redact/slot/audit — content-free bundle by construction`

---

# MODE A — snapshot-extend (mechanism breadth; cheap)

### A1 — widen `WANT_STYLES`
Add (readable from the existing pass): `filter`, `backdrop-filter`, `border-{r,b,l}-{width,color}`,
`border-style`, `outline`, `margin-*`, `overflow-x/y`, `aspect-ratio`, `object-fit`,
`object-position`, `mix-blend-mode`, `background-blend-mode`, `clip-path`, `mask`,
`text-decoration`, `text-transform`, `white-space`, `writing-mode`, `direction`, `font-style`,
`font-feature-settings`, `cursor`, `list-style`, `inset`/top/right/bottom/left, `column-gap`,
`row-gap`, `text-shadow`, `box-shadow`. APPEND; assert old fixtures still align.
- **Commit:** `feat(web_skeleton): widen WANT_STYLES (filter/borders/overflow/text visual props)`

### A2 — gradient parsing → tokens (mechanism — NOT content)
Parse linear/radial/conic `background-image` into `{type,angle,stops}` (multi-layer split). Note:
gradients are CSS mechanism and stay; only `url()` backgrounds are content (→ R).
- **Commit:** `feat(web_tokens): parse gradients into structured fill tokens`

### A3 — per-node shadow/filter token binding
`token_ref += {shadow,filter}`; two nodes with different shadows → different refs.
- **Commit:** `feat(bundle_writer): bind shadow/filter per node via token_ref`

### A4 — `transform-origin` + `margin`
Carry origin (motion pivot — corrects transforms we already capture) + margin spacing.
- **Commit:** `feat(web_skeleton): capture transform-origin (pivot) + margin`

### A5 — pseudo-element pass → through the firewall
`getComputedStyle(el,'::before'|'::after')` (DOMSnapshot omits pseudo-elements). Keep CSS box/bg
(mechanism); route `content` strings through **R3** (textual content → text-slot; pure decorative
glyph → kept, classed `decorative`).
- **Commit:** `feat(web_skeleton): capture ::before/::after styling; content via firewall`

### A6 — authored-intent recovery
New `web_styles.py`: `CSS.getMatchedStylesForNode` + `getStyleSheetText` → `authored` tokens
(`--var`, `calc`, `clamp`), `@media` breakpoints, specificity. `clamp(...)` round-trips to 3 parts.
Mangled name → `confidence:'low'` + value (honest gap). **`url()`-bearing var values → R3.**
- **Commit:** `feat(web_styles): recover authored CSS (vars/calc/clamp/@media) via getMatchedStylesForNode`

---

# MODE B — multi-pass recapture (sweep the matrix: state × scheme × breakpoint)

### B1 — interaction states — `CSS.forcePseudoState` (`:hover/:focus/:active`), scoped to interactive nodes → `states` deltas.
`feat(web_states): capture hover/focus/active deltas via forcePseudoState`
### B2 — dark mode + reduced-motion — `Emulation.setEmulatedMedia` → `schemes:{light,dark}`.
`feat(web_states): capture dark-mode palette + reduced-motion`
### B3 — real per-breakpoint deltas — recapture per discovered `@media`/`@container` breakpoint (not just sizing).
`feat(web_skeleton): capture real per-breakpoint style deltas`

---

# MODE C — record-during-execution (motion; heavier)

### C1 — full `getAnimations()` reader (headline)
New `web_waapi.py` (reuses flipbook's `getAnimations({subtree:true})` JS) + `getKeyframes()` +
`getComputedTiming()`. Closes **stagger** (per-element `startTime`/`delay` = the kasane menu
cascade), **looping** (`iterations:Infinity`), **hover-triggered**. Motion row +=
`delay,iterations,direction,fill,keyframes[]`. Reconcile: WAAPI-routed framer IS visible here
(kasane menu proven); only pure-rAF stays invisible → C2.
- **Test:** 52 elements at distinct increasing startTimes → distinct `delay`, not collapsed.
- **Commit:** `feat(web_waapi): getAnimations reader — stagger/looping/keyframes into motion.json`

### C2 — rAF sampling + spring equivalent-fit (conditional; skip for kasane = WAAPI+scroll)
New `web_raf.py` (inject MutationObserver/rAF poll via `addScriptToEvaluateOnNewDocument`) +
`_anim_core` damped-oscillator fit (`k=ω²,c=2ζω`). Row `source:'raf-fit'`,`confidence`.
- **Commit:** `feat(web_raf): sample rAF inline-style motion + fit equivalent spring/bezier`

### C3 — ambient media motion = behavior-class via flipbook (per user decision 1)
For `<canvas>`/WebGL/`<video>` regions: run flipbook **global** motion analysis on the region to
recover a **content-independent** behavior class (`motion_class∈{drift,pulse,flow,scroll,none}`,
`period_s`, `loop`, `confidence`) — **what moves, never the pixels** — and write it into the
slot's `behavior` (Mode R4). This is the **IP-safe default** for canvas/video motion; the full
draw-command recorder (Mode X2) is the disabled owned-content alternative — it is never on the
content-independent path.
- **Test:** synthetic looping vs static region → correct `loop` + motion_class; assert NO pixel/
  command bytes emitted on the default path. Synthetic-green: drift vs pulse distinguished.
- **Commit:** `feat(content_firewall): ambient media motion as content-independent behavior-class (flipbook)`

---

# MODE X — owned-content capture (BUILT, DISABLED by default, interlocked)

Full content capture for designs **you own** (archive / migrate your own site, capture a licensed
or self-authored asset). Built and kept per user decision, but it can **never** touch a
content-independent bundle. Safety is the interlock + the unconditional R5 audit — not absence of
code.

### The interlock (one shared guard module `owned_content.py`, tested first)
- Master flag `--capture-content` **default OFF**; additionally requires an explicit
  `--i-own-this-content` acknowledgment (two-key arm). Loud banner when armed.
- All X output goes ONLY to a **`raw-content/` sidecar** that is **`.gitignore`d** and lives
  *outside* `bundle/`. The writer **refuses** any path under `bundle/` (raises, doesn't warn).
- R5 audit runs regardless and fails on any content byte in `bundle/`, so a mis-set flag cannot
  leak into a shippable bundle.
- **Test (`test_owned_content.py`):** (a) default run (no flags) → `raw-content/` never created,
  zero content bytes anywhere; (b) writer pointed at a `bundle/` path → refused (raises); (c) armed
  capture → bytes land only under `raw-content/`, and R5 on the bundle still passes; (d) plant a
  content byte in `bundle/` with capture armed → R5 still FAILS. Synthetic-green: each interlock
  branch tested separately.
- **Commit:** `feat(owned_content): two-key interlock + raw-content sidecar + bundle-write refusal`

### X1 — asset / font byte fetch
`web_assets.py`: `Network.getResponseBody` / `Page.getResourceContent` → images/`srcset`/bg-image +
`@font-face` binaries → `raw-content/assets/` + manifest. Disabled by interlock.
- **Commit:** `feat(web_assets): owned-content asset/font byte capture (interlocked, default-off)`

### X2 — canvas / WebGL command recorder (Spector/rrweb-style)
`web_scene.py`: inject a context proxy via `Page.addScriptToEvaluateOnNewDocument` recording
`CanvasRenderingContext2D` + `WebGLRenderingContext` draw-command streams + shaders/buffers →
`raw-content/scene/`. (Cross-origin taint doesn't block command recording.) Disabled by interlock.
WebGPU/OffscreenCanvas = documented follow-on, same technique.
- **Test:** synthetic recorded command list → structured scene; default-off → nothing emitted.
- **Commit:** `feat(web_scene): owned-content canvas/WebGL command recorder (interlocked, default-off)`

### X3 — raster→SVG tracing (retained `web_vectors`)
Keep the existing `vtracer` path, **rewired behind the interlock** → `raw-content/vectors/`. Never
on the content-independent path (raster → slot there).
- **Commit:** `refactor(web_vectors): gate raster tracing behind owned-content interlock`

---

# MODE Z — full-fidelity replica (permission-gated SEPARATE product)

For identically replicating a site **you have permission to copy** (author granted it). This does
NOT relax R5 — it produces a **different product** (`replica/`), so the `bundle/` guarantee stays
absolute. Architecturally: run the normal mechanism + slot capture, then the armed Mode-X capture,
then **fill each slot with its real captured asset** and emit to `replica/`.

### Z1 — replica assembler + permission gate
- **CLI:** `--mode replica` + `--permission-ref <url|note|PERMISSION.txt>` (required; refuse to run
  replica without it). Loud banner; logged.
- **Output:** `replica/` = the bundle's mechanism/skeleton/tokens/motion + slots **filled** from
  `raw-content/` (X1–X3) + `replica/PROVENANCE.json` = `{source_url, captured_at, permission_ref,
  operator_attestation, tool_version}`. **Never writes under `bundle/`.**
- **Honest framing (in PROVENANCE + banner):** the attestation **records** the operator's assertion
  of permission; it does **not verify** it. probe-runner supplies capability + provenance trail;
  confirming permission is the operator's responsibility.
- **Interlock continuity:** replica mode implies the Mode-X two-key arm; `bundle/` R5 still runs
  unconditionally on any bundle written in the same session.
- **Test (`test_replica.py`):** (a) `--mode replica` without `--permission-ref` → refuses (rc≠0);
  (b) with it → `replica/` has filled slots + a complete `PROVENANCE.json`; (c) replica run that
  also emits a `bundle/` → that bundle still passes R5 (content-free); (d) assembler pointed at a
  `bundle/` path → refused. Synthetic-green: distinct slots fill with distinct assets.
- **Commit:** `feat(replica): permission-gated full-fidelity replica/ product + provenance stamp`

---

# MODE E — rebuild-time pixel certification (NOT in the capture pipeline)

probe-runner captures; a downstream agent builds the clone. So clone-vs-source is a **rebuild
acceptance gate**, run after the agent fills slots — and post-firewall the **content regions
differ by design**, so the diff MUST mask them.
- New `design_diff.py` (extends `pixdiff.py`): given a rebuilt clone screenshot + a **transient**
  source screenshot + the slot bboxes, **mask every slot region** and perceptual-diff only the
  mechanism/theme pixels (SSIM + max-channel + changed-fraction), calibrated to a self-diff floor
  (reuse `fixtures/skdiff-calib`). **Never persist the source screenshot or diff image** (they
  contain IP) — measurement only.
- **Test:** identical mechanism + differing slot content → PASS (slots masked); a real theme/layout
  regression outside slots → FAIL with score. Synthetic-green: the fail case must fail.
- **Replica mode:** since `replica/` contains the real content, design_diff runs **unmasked**
  (full clone-vs-source) for a true pixel-identical check — masking is only for the content-free
  bundle path.
- **Commit:** `feat(design_diff): masked mechanism-only pixel cert (rebuild-time; source transient)`

---

# MODE F — propagate
Copy all new/changed scripts + tests (`content_firewall`,`slots`,`web_styles`,`web_states`,
`web_waapi`,`web_raf`,`design_diff`,`owned_content`,`web_assets`,`web_scene`,`replica` +
`web_vectors` rewire + edits) to engineering-pack + brainiac; update SKILL.md verb tables (mark
Mode-X verbs **default-off / owned-content** and `replica` **permission-gated**). md5-identical; suites green; blobs parse; no content leak (run R5
audit on a sample bundle in each copy + assert default-off X-modes emit nothing); **no push**.
- **Commit:** `chore(probe-runner): propagate firewall + total-capture verbs to 3 copies`

---

## Coverage map
| Former gap | Where | Coverage |
|---|---|---|
| Narrow CSS whitelist | A1–A4 | **Full** |
| Pseudo-elements | A5 (+R) | **Full**, content firewalled |
| Authored intent | A6 | Full except mangled names |
| Interaction / dark / breakpoint states | B1–B3 | **Full** (CQ best-effort) |
| Stagger / looping / keyframes | C1 | **Full** (browser-owned anims) |
| rAF + spring motion | C2 | Equivalent-fit |
| Canvas/WebGL/video **content** | R | **Discarded → slot** (by design) |
| Canvas/WebGL/video **motion** | C3 | Behavior-class (content-independent) |
| Images / fonts / text **content** | R | **Discarded → typed slot** (by design) |
| Native inline SVG | R2 | **Kept** + classed (logo = swap-recommended) |
| Owned-content full capture (assets/scene/trace) | X1–X3 | **Built but disabled** (interlock + sidecar; never in a content-independent bundle) |
| Full-fidelity replication (with permission) | Z | **Separate `replica/` product** (permission-gated + provenance; `bundle/` guarantee untouched) |
| Pixel-level mechanism cert | E | **Full** (masked for bundle; unmasked for replica) |

Every gap is covered to its real maximum; content is *removed by design*, not "missed." Honest
residue = the 3 mechanism-only items named above.

## Execution
`superpowers:subagent-driven-development`. Order: **R first** (the firewall must exist before any
breadth lands content in a bundle) → A → C1 → B → C3 → E → (C2 only if a target needs it). R + A +
C1 + the audit gate is the minimum that yields a content-free, mechanism-faithful bundle.
**Mode X is built LAST**, only after R5 is proven green — build the `owned_content` interlock
(with its leak tests) BEFORE X1–X3, so the disabled-by-default safety exists before any
content-capture code does. **Mode Z (replica) builds on X** — after X1–X3, gated by its own
permission test; its acceptance check is that a replica run still leaves any co-emitted `bundle/`
content-free under R5.
