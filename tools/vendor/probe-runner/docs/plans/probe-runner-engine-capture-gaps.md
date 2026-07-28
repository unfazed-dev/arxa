# Probe-runner engine capture gaps (consolidated intel)

**Date:** 2026-05-29 · **Transport:** headed Chrome, CDP :9334, retina dpr=2 (verbs run fresh-nav, as-is).
Targets probed live: kasane (Framer SPA), **YouTube** watch page (Polymer app shell),
**rive.app/login** (Next.js SPA leaf), **en.wikipedia.org/wiki/Cat** (server-rendered MPA).

> Master engine-gap doc. §A = capture-axis taxonomy (what does / doesn't decompose, incl.
> multi-page & SPA). §B = detailed YouTube run. Don't spawn per-site files — fold new findings here.

---

## §A — Capture-axis taxonomy: what decomposes, what doesn't

### A0. No multi-page / site-level decomposition (code-confirmed)
probe-runner is **single-route: one `--url` = one rendered DOM state = one bundle.** Grep of
every web verb: no crawl, no sitemap, no `--urls`/`nargs='+'`, no link-following, no
client-side route enumeration, no history/pushState handling. The only "multi" is
`web_skeleton --viewports` = **same page at N widths** (responsive), NOT N pages. There is no
"site" object: no route enumeration, no aggregation across pages, no dedup of shared chrome
(header/footer/nav re-captured per page), no nav/site graph. "Page-by-page" output is only
achievable as N manual invocations producing N independent, unlinked bundles.

### A1. The real axes (MPA-vs-SPA mostly collapses)
What governs capture is **not** MPA-vs-SPA but three orthogonal axes:

1. **URL-addressable vs non-URL state.** A state reachable by a distinct URL is capturable
   (one invocation each); a state that is NOT (modals, dropdown/hover menus, tab panels,
   wizard steps, post-login/auth-gated views, anything behind a click) is **invisible** to a
   `--url` capture — true for BOTH MPAs and SPAs. Deep-linkable SPA routes (Next.js, incl.
   rive) capture exactly like MPA pages. *This — not "SPA" — is the gap.*
2. **Render substrate: DOM vs canvas/WebGL.** DOMSnapshot can only see DOM. A canvas/WebGL
   design surface (the rive **editor**, Figma, CanvasKit Flutter-web, games) paints its entire
   content into one `<canvas>` → DOMSnapshot sees ~1 opaque box, zero skeleton/tokens/vectors
   of the real content. The whole app is a blind spot (distinct from the single-element
   media-slot point and from settle-timing).
3. **Hydration speed (= §B gap 1).** Server-rendered and fast-hydrating client apps capture
   fully through the fixed 2s settle; slow client-render does not.

### A2. Render-substrate contrast (live, same verb, same settle)
| Page | Substrate | Verb-captured skeleton nodes | Page height | Verdict |
|---|---|---|---|---|
| **Wikipedia /Cat** | server-rendered MPA | **16992** (text 7033, img 1482) | 46356px | full ✓ |
| **rive.app/login** | Next.js SPA, fast hydrate | **103** (text 13, svg 23, img 7) | 1233px (== hydrated scrollH) | shell ✓ |
| **YouTube** watch | client SPA, slow hydrate | **1** (empty box) | viewport-only | empty ✗ |

→ **§B gap 1 is hydration-speed-dependent, not universal.** Clean proof the rive verb fired
*post*-hydration: its captured page-height (1233px) equals the char-probe's fully-hydrated
`scrollHeight` (1233px), and 103 ≫ 1 — whereas YouTube's verb height was viewport-only with 1
node. Server-render (Wikipedia) and fast-hydrate SPA (rive) both snapshot a built DOM; only
slow client-render (YouTube) fails. "SPA" alone does not predict failure.

### A3. rive specifics
rive.app/login = small Next.js/React leaf, **page shell captured** (103 nodes; verb page-height
1233px matches the char-probe hydrated scrollH 1233px → snapshot fired post-hydration. The char
probe saw 0 native `<button>`/`<input>`; SSO entry is *inferred* as the 8 external links — could
also render late or in the canvas. 1 Rive-animation `<canvas>` classified as a generic opaque box
— the canvas blind-spot in miniature). The real canvas case is the **editor**
(`editor.rive.app`): a WebGL design surface that is BOTH auth-gated (non-URL/login state, axis
A1.1) AND canvas-substrate (axis A1.2) — a double blind spot. Not reached (no credentials; not attempted).

### A4. New gap items for the backlog
- **G3 — no site/route orchestration:** optional crawl or `--urls` list + per-route bundles +
  shared-chrome dedup + a nav/site graph. Today: N manual runs, no linkage.
- **G4 — non-URL state capture:** a trigger script (click/hover/route-push) to drive the page
  into a state, then capture — so modals/tabs/post-login views become reachable. (Overlaps the
  Mode C1 event work + `web_flipbook --click`.)
- **G5 — canvas/WebGL substrate:** out of scope for DOM capture by design; the honest output is
  a behavior-class box + (if owned) a recorded clip. Document as a hard boundary, not a DOM "fix".
- **G6 — consent/overlay not dismissed (NEW, §C) — LATENT/code-confirmed, NOT demonstrated to bite:**
  `navigate()` has no dismiss step (true code fact). The §C sweep did NOT prove it harms capture — the
  verb subprocesses shared the char-probe's Chrome profile, so the consent cookie the TRUTH probe set
  persisted and the verb's re-nav saw no wall; and overlays *cover* the DOM, they don't remove it, so
  DOMSnapshot still captures the page behind. Cheap defensive fix anyway: dismiss-overlay in `navigate()`
  (OneTrust/Didomi/Cookiebot + Accept-text fallback; dismiss-JS proven to click on 2/7). Firm proof
  would need a same-pipeline isolation (parse_snapshot on dismissed vs walled fresh-nav).
> ⚠️ **SUPERSEDED (2026-05-30) — see `docs/plans/p0-scroll-driven-motion-fix.md`.** This G7/G8 framing is wrong:
> `web_anim` never calls `getAnimations` (grep: absent from `scripts/`); it discovers movers by transform-diff
> and reads computed style at static `scrollY` — it is **already scroll-position-driven**. The "~0" came from the
> canary `aw_probe.py`, which measures `getAnimations` and runs **no** `web_anim`. Run live, `web_anim` certifies
> native-scroll GSAP fine (Ashley: range [0,12550], 60 movers). Real G7 gaps = readiness-wait (it measured a
> pre-hydration shell → `range 0:0`), multi-segment timelines (Ashley 41/60), band-localized sampling (21/60).
> G8 is largely already solved (`klass="scroll"` rows exist). Virtual-scroll NOT observed (Ashley/Razorpay native).
- **G7 — getAnimations/WAAPI oracle blind to GSAP scroll motion (NEW, §C):** GSAP/ScrollTrigger
  (the dominant awwwards motion tech) does NOT use WAAPI, so `web_anim`'s `getAnimations()`
  enumeration returns ~0 even on heavily-animated pages (ashley: 80 ScrollTriggers, getAnimations=0).
  flipbook recovers per-element time-based triggered motion only — not scroll-scrubbed timelines.
- **G8 — scroll-driven motion is a different model (NEW, §C):** progress bound to scrollY, not
  time. The bundle's anim model is time-curve-based; scroll-linked motion needs a scroll→progress
  binding (ScrollTrigger scrub). Conceptual gap, not just an oracle gap.
- **G9 — video-bg substrate (NEW, §C):** background `<video>` as the entire visual (detroit: 6).
  Behavior-class by firewall design; an OWNED repro needs a recorded clip. Distinct un-reproducible
  substrate from canvas (G5); not scored by canvas-area-ratio.
- **G10 — web_tokens shadow-DOM blindness (NEW, §C6) — DEMONSTRATED (was latent):** `web_skeleton`'s
  `DOMSnapshot.captureSnapshot` pierces OPEN shadow roots (captures structure), but `web_tokens`'
  `document.querySelectorAll('*')` does NOT → asymmetric capture: geometry captured, the design tokens
  of web components (colors/type/radius living inside `sl-*`-style shadow roots) missed. Proven on
  shoelace.style (28 Lit hosts: light 455 vs deep 638 vs DOMSnapshot raw 1779). Fix: recursive
  `shadowRoot`-descending walk in web_tokens. Sub-case: **closed** shadow roots (`mode:'closed'`) are
  invisible to BOTH paths — a harder boundary, no API workaround.
- **G11 — cross-origin iframe opaque (NEW, §C8) — DEMONSTRATED:** `DOMSnapshot.captureSnapshot` cannot
  pierce a cross-origin iframe (security). Controlled inject (example.com parent + cross-origin iana.org
  iframe + same-origin iframe): snapshot returned **2 documents** — the same-origin iframe's document
  IS captured, the cross-origin one is NOT (`contentDocument` inaccessible). Same-origin iframes are
  fine; cross-origin embeds (maps, players, widgets, micro-frontends) are a hard boundary like canvas.

---

## §B — Detailed run: YouTube (slow-hydrate Polymer app shell)

**Target:** `https://www.youtube.com/watch?v=41MGDo-GNnc` (English news content).
**Why:** stress the engine against a style opposite to kasane (kasane = Framer/React light-DOM
artisan SPA, finite scroll; YouTube = Polymer app shell, `<video>`, virtualized infinite scroll,
dense third-party content).

## TL;DR — what a different page style exposed

The shadow-DOM hypothesis was **falsified**; two real engine gaps surfaced instead, the
first severe. A framing probe (proper hydration wait) measured the page's true shape; the
actual verbs (fixed-delay nav) then under-captured against it.

| Measurement (framing probe, hydrated) | Value |
|---|---|
| Shadow-DOM hosts (open) | **0** — `deep==light==8912`, ratio 1.0 (pure light DOM + scoped classes) |
| DOM at top (above-fold) | 8912 nodes / scrollH 3715px |
| DOM after scroll-to-bottom | 15678 nodes / scrollH 8753px (**+6766 nodes, +135% height, still growing**) |
| Media | `<video>`×1 (750×422), `<canvas>`×2 (1125×844 ambient glow), `<iframe>`×1 (0×0 collapsed ad), img×204, svg×501 |

| Verb result (fresh-nav, as-is) | Value |
|---|---|
| `web_skeleton` nodes | **1** (single empty `unknown_box`, bbox 0,0,1200,887, all colors null) |
| `web_skeleton` page height | 887px (viewport only — never saw the real 3715px+) |
| `web_tokens` | partial-but-real: dark palette `#0f0f0f`, type scale `[10,11,12,13,14,17,18,20…]` |
| `bundle_writer` | ok, nodes 1 / motion_rows 0 / **slots 0**; `audit_bundle` clean (vacuously — nothing captured) |

## Gaps, ranked

### 1. CRITICAL — fixed-delay settle, no content-ready wait
`_web_eval.navigate()` does `location.assign(url)` then a hard-coded `time.sleep(2.0)`;
`web_skeleton` adds `time.sleep(0.15)` and snapshots. YouTube's watch page is a
client-rendered shell that hydrates in ~3–8s, so at ~2.15s the DOM is a **single empty box**
→ skeleton captured **1 node**. kasane laid out content within 2s (faster/SSR-ish hydrate)
so it got 951 nodes — the fixed delay *happened* to be enough there, masking the defect.

- **Cascade:** a 1-node skeleton is a single point of failure. web_vectors got 0 SVG nodes
  (501-svg volume untested), `bundle_writer` produced **0 slots** (the `<video>` media slot
  never classified), 0 motion rows to bind, and the firewall had nothing to audit (IP
  stress-test blocked).
- **Non-determinism:** `web_tokens` (a separate fresh-nav seconds later) caught a
  partially-built page with real values — same URL, different hydration state. Capture is
  timing-dependent and flaky on slow SPAs.
- **Root cause isolated (verified, not inferred):** re-ran web_skeleton's *exact*
  `DOMSnapshot.captureSnapshot` params + its own `parse_snapshot` on a properly-hydrated page
  (waited `video.videoWidth>0` + 2s): raw snapshot **18067 nodes** (2 documents),
  `parse_snapshot` → **4067 recs** — vs **1** from the fixed-delay verb run. The snapshot/parse
  path works correctly when hydrated; the 1-node skeleton is purely settle-timing (the verb
  snapshots at ~2.15s, before YouTube builds its DOM). Not a CDP/snapshot/parse bug.
- **Fix:** replace the fixed sleep with a content-ready wait — DOMContentLoaded +
  network-idle + node-count stabilization (poll until `querySelectorAll('*').length` stops
  growing for N ms), and/or a `--wait-for <selector>` / `--settle <ms>` flag. Mirror the
  probe's hydration gate.

### 2. MAJOR — single snapshot misses virtualized / below-fold content
Even with hydration fixed, one DOMSnapshot only sees what is currently rendered. YouTube
virtualizes: comments and most recommendations are **absent from the DOM until scrolled**
(+6766 nodes appear on scroll; infinite-scroll keeps growing, so no fixed % is honest —
qualitatively, you capture the above-fold shell and miss the rest). kasane rendered its whole
long page, so this never showed.

- **Fix:** a scroll-settle sweep before capture — incrementally scroll the page, let
  virtualized content mount at each step, then snapshot (or merge per-step snapshots).

### 3. MODERATE (latent, not exercised here) — tokens is light-DOM-only
`web_tokens` samples via `document.querySelectorAll('*')`, which does not pierce shadow
roots. **Zero impact on YouTube** (0 shadow hosts). But real for web-component design systems
(Lit / Stencil / shadow-Polymer). Falsified-here, flagged-for-future.
- **Fix:** recursive `shadowRoot`-descending walk when sampling computed styles.

### 4. MODERATE — media-slot pipeline unverified on a real media page
`<video>`×1 + `<canvas>`×2 are correctly behavior-class by firewall design, but the bundle
never reached slot classification (gap #1). The `<video>`→typed-media-slot path is proven in
unit tests but was **not** exercised live here because skeleton captured 0 of them.

### 5. LOW — volume untested
501 inline SVG + 204 img on the hydrated page. `web_vectors` at that scale (dedup? perf? no
macOS `timeout`) is unverified — gap #1 blocked it (0 svg nodes reached vectors). img×204 =
thumbnails = content the firewall would redact.

### 6. NOT EXERCISED — visible cross-origin iframe
The only iframe was 0×0 (collapsed ad). A real visible cross-origin iframe (embed) — which
DOMSnapshot cannot pierce — was not tested. Known boundary, unconfirmed here.

### Incidental
- Dark-theme tokens captured correctly (`#0f0f0f` bg) — theme detection works.
- Third-party ad DOM injects its own content ("Sponsored", "iselect.com.au", "Get quote") +
  a11y skip-link — content classes kasane lacked; relevant once capture+firewall actually run.

## Net

probe-runner's **content/IP firewall and the animation oracle held up** (animations:
player-chrome only, 0 targeting `<video>`; firewall: 173 tests + clean kasane audits). The
weak link a YouTube-class page exposes is **capture acquisition**, not capture *modeling*:
the fixed-delay nav settle (gap #1) and single-snapshot virtualization blindness (gap #2)
mean the engine never even *sees* a heavy client-rendered, virtualized app shell. Fix those
two and the rest of the pipeline (already correct on kasane) gets real input to work on.

Artifacts: `/tmp/yt_full.json` (framing probe), `/tmp/yt_bundle/` (skeleton/tokens/bundle),
`/tmp/yt_sk.out` `/tmp/yt_tok.out` `/tmp/yt_bundle_out.txt` (verb stdout).

---

## §C — awwwards sweep: 7 award-winning sites, extreme→simple (2026-05-30)

**Why:** stress "reproduce ANY site pixel-perfect + all animations (minus IP)" against a deliberately
varied set spanning render-substrate, render-arch, motion tech, and difficulty. Picked from awwwards
Sites-of-the-Day. Methodology = **TRUTH** (properly hydrated, consent dismissed, scroll-swept char
probe) vs **VERB-AS-IS** (real `web_skeleton`/`web_tokens`/`bundle_writer` CLIs, fresh-nav fixed-delay).
Harness `/tmp/aw_probe.py` + `/tmp/aw_run.sh`; per-site JSON `/tmp/aw/<label>.json` (counts/ratios/
class-labels only — no content persisted). Three INDEPENDENT axes scored (advisor: never collapse):
substrate-blindness, DOM-structure-shortfall, motion-demand-vs-capturable.

### C1. Master table

| Site | Difficulty | Arch (detected) | Hydrated nodes | scrollH | Verb nodes | Struct ratio | Substrate-blind | Structure shortfall |
|---|---|---|---|---|---|---|---|---|
| Cartier W&W | EXTREME | Nuxt (SSR-rehydrate) | 3693 | 1980 | 337 | 0.09 † | **100%** (1 WebGL hero) | **hydration-timing-G1** (verb 2s ⟪ 25.9s hydrate) |
| AIR | HARD | MPA/static | 796 | 813 | 441 | 0.55 † | 0% | **near-miss** (DOM/SVG; ratio cross-pipeline) |
| Cdiscount Jumping Max | HARD | client-SPA (custom) | 167 | 813 | 57 | 0.34 † | **100%** (WebGL game) | **content-in-canvas-G5** |
| Razorpay Sprint 26 | HARD | MPA/static | 1276 | 22117 | 1599 | 1.25 † | **100%** (44 WebGL, area 7.73×) | ok-domcaptured |
| Detroit Paris | MEDIUM | client-SPA (custom) | 437 | 813 | 591 | 1.35 † | 0% (but 6 video-bg, G9) | ok-domcaptured |
| Sowieso Wero | MED-SIMPLE | MPA/static | 6948 | 13669 | 1790 | 0.26 † | 100%* (3 2D canvas, decorative) | undetermined (6948-node DOM intact) |
| Ashley Brooke | SIMPLE | MPA/static | 1344 | 13261 | 1829 | 1.36 † | 0% | ok-domcaptured |

**† `Struct ratio` is CROSS-PIPELINE and is NOT a capture fraction** — numerator = `web_skeleton`'s
`parse_snapshot` recs (DOMSnapshot path, includes text/pseudo nodes), denominator = the char-probe's
`querySelectorAll('*')` (light elements only). Ratios >1 (ashley 1.36, detroit 1.35) prove the two
counts aren't comparable as a fraction. So a sub-1 ratio (air 0.55, sowieso 0.26) is **NOT** a measured
acquisition loss — it's pipeline mismatch. The decisive structure-shortfall test (run for YouTube,
skipped here) is `parse_snapshot` on the hydrated page vs the verb's fresh-nav, **same pipeline both
sides**. The robust, directly-measured findings below do not depend on the ratio.

> ⚠️ **SUPERSEDED by §C7 (same-pipeline isolation, run later):** the "shortfall" column above is
> cross-pipeline noise. The isolation proved **G1 timing ≈0 and G6 consent ≈0** on all three suspect
> sites — the verb captures the hydrated structure; **neither acquisition gap bites the awwwards
> sample.** Read §C7 + §C9 for the corrected conclusion. The substrate (G5), motion (G7), and
> shadow/iframe (G10/G11) findings are unaffected (direct measures).

\* Sowieso's canvas-area is decorative overlay on a 6948-node DOM — substrate-blind flags the canvas
hero, but the large DOM means content is NOT in the canvas. **Axis-independence lesson:** high
canvas-area ≠ content-in-canvas when a big DOM exists. (Razorpay is the dual proof — direct canvas
measure = 44 WebGL, area 7.73× ⇒ 100% substrate-blind, while its DOM captured fine. A single
`primary_gap` field would have mislabeled both. But note the structure side of both judgments rests on
direct DOM/canvas counts, NOT the cross-pipeline ratio.)

### C2. Render-arch coverage (the SPA/MPA/rehydrate question, empirical)
Detected: **4 MPA/static · 2 client-SPA · 1 Nuxt SSR-rehydrate.** With prior baselines
(Wikipedia=server-MPA ✓ full, kasane=Framer-SPA ✓, YouTube=slow-client-SPA ✗) the arch axis is
covered. Confirms §A1: **arch does not predict capture** — MPA Ashley captures fully (1.36); MPA
Sowieso fails (consent); MPA Cartier… is actually Nuxt and fails (timing). Substrate + acquisition
gates govern, not SPA-vs-MPA.

### C3. Gaps ranked (4 demonstrated by direct measure + 1 latent/code-confirmed; 3 NEW vs §A/§B)
1. **G5 canvas/WebGL substrate — 4/7.** The signature visual lives in canvas: Cartier (1 full-bleed
   WebGL hero), Cdiscount (whole game in canvas, 167-node DOM shell), Razorpay (44 WebGL canvases,
   total area 7.73× viewport — pervasive scroll-driven 3D), Sowieso (3 scroll-pinned 2D canvases).
   **Dominant ceiling on pixel-perfect reproduction.** DOM-blind by design; honest output = behavior
   box (+ owned canvas-capture/clip if permitted).
2. **G7 GSAP scroll-motion invisible to the WAAPI oracle — 3/7.** Ashley (ScrollTrigger=80,
   getAnimations=0), Razorpay, Detroit. GSAP doesn't use WAAPI → `web_anim` sees ~0. **Even the
   simplest site breaks motion capture.** flipbook recovers per-element triggered time-curves only.
   > ⚠️ **SUPERSEDED (2026-05-30) — see `docs/plans/p0-scroll-driven-motion-fix.md`.** `web_anim` was
   > never run here (this row reads the `getAnimations` canary). Run live, Ashley gives range [0,12550],
   > 60 movers; the gaps are readiness-wait + multi-segment + band-localized sampling, not a WAAPI oracle.
3. **G9 video-bg substrate — 1/7 (NEW).** Detroit's 6 background videos (direct `<video>` count) =
   the whole visual. Behavior-class only; un-reproducible without an owned clip.
4. **G1 hydration-timing — 1/7.** Cartier hydrated at **25.9s** (loader never cleared in 24s window);
   the verb snapshots at ~2s, necessarily capturing a **pre-hydration** state (337 parse-recs, page
   ends at 3693 light nodes). Anchored on the **hydration TIME**, not the cross-pipeline ratio.
   Razorpay also showed a 25s loader but its DOM built fast enough for the 2s snapshot — **G1 bites
   only when DOM-build itself exceeds the fixed settle, not merely when a loader lingers.**
5. **G6 consent not dismissed — LATENT/code-confirmed (NEW), NOT demonstrated to bite here.**
   `navigate()` has no dismiss step. The sweep did NOT prove harm: verb subprocesses shared the
   char-probe's profile, so the consent cookie persisted and the verb's re-nav hit no wall; overlays
   cover the DOM rather than remove it (DOMSnapshot still sees the page behind). AIR/Sowieso's sub-1
   ratios were cross-pipeline noise, not consent loss. Keep the dismiss-step as a cheap defensive fix;
   prove/disprove with the same-pipeline isolation if a firm number is wanted.

**Negative result (honest):** **G2 virtualization NOT exercised** — `virt_delta=0` on all 7 (awwwards
sites render full pages, incl. Razorpay's 22117px). G2 stays a feed/infinite-scroll (YouTube) class
gap, not an awwwards-class one. **G3 multi-route** also not stressed (each pick = one designed page).

### C4. Reproduction verdict matrix — can we faithfully reproduce (minus IP)?
✓ = reproducible today · ◑ = partial · ✗ = blocked.

| Site | Geometry+Tokens | Visual substrate | Animation | Blocked by |
|---|---|---|---|---|
| Cartier | ◑ (G1, after settle-fix) | ✗ WebGL hero | ◑ (WAAPI×6; canvas ✗) | G1, G5 |
| AIR | ✓ | ✓ DOM/SVG | ◑ (WAAPI×1 + css; cursor/dialog state G4) | **near-miss — G4 only** |
| Cdiscount | ✗ (content in canvas) | ✗ WebGL game | ✗ canvas | G5 |
| Razorpay | ✓ | ✗ 44 WebGL | ✗ GSAP+canvas | G5, G7 |
| Detroit | ✓ | ✗ 6 video-bg | ✗ GSAP+video | G7, G9 |
| Sowieso | ✓ (6948-node DOM) | ◑ 2D canvas hero | ◑ WAAPI×7 + 45 accordions (G4) | G5, G4 |
| Ashley | ✓ | ✓ | ✗ 80 GSAP ScrollTriggers | G7 |

**Headline: 0 of 7 are a clean ✓✓✓ today — but AIR is the near-miss** (DOM/SVG substrate, WAAPI+CSS
motion, only custom-cursor/dialog *interaction-state* (G4) as the residual — a soft, not structural,
blocker). It exemplifies the reproducible tier. Geometry+tokens reproduce broadly (≈5/7; Cartier after
a G1 settle-fix). The **hard, structural blockers are the canvas/WebGL visual substrate (4/7 + 1 video
= 5/7) and scroll-driven GSAP motion (3/7, incl. the simplest site).** As with YouTube, the **content/IP
firewall and the DOM-modeling pipeline are sound** — every gap is **acquisition (G1), substrate
(G5/G9), motion-model (G7/G8), or interaction-state (G4)**, never DOM classification. Pixel-perfect
reproduction of "any awwwards site" is achievable for the **DOM-substrate + time-based-motion tier**
(after a G1 settle-fix) and **structurally blocked** for the WebGL/scroll-spectacle tier these awards
actually reward.

### C5. Fix priority — SUPERSEDED by §C9 (post-isolation)
This draft led with P0 G1, which §C7's same-pipeline isolation then showed does NOT bite the awwwards
sample. **See §C9 for the authoritative, corrected ranking.**

Artifacts: `/tmp/aw/<label>.json` ×7 (cartier, air, cdiscount, razorpay, detroit, sowieso, ashley) +
`/tmp/aw/<label>_sk.json`/`_tok.json`/`_bundle/` (verb outputs); harness `/tmp/aw_probe.py`,
`/tmp/aw_run.sh`. No site content persisted (counts/ratios/class-labels only).

---

## §C6 — Arch-completeness sweep: closing the render-architecture axis (2026-05-30)

**Why:** verify no render-architecture was missed, so the fix plan covers all. The space splits into
**4 orthogonal axes** (advisor-confirmed complete) — "arch" (render-delivery) is only one:

| Axis | Values | Coverage |
|---|---|---|
| **1 render-delivery** | static/SSG · server-MPA · SSR-rehydrate · client-SPA/CSR · islands/partial-hydration · streaming-SSR/RSC · web-component/shadow-DOM · iframe-composed | SSG≈MPA ✓(ashley,wikipedia) · server-MPA ✓(wikipedia,sowieso) · SSR ✓(cartier-Nuxt) · CSR ✓(kasane,youtube,air,cdiscount,detroit) · **RSC ✓ now (offmenu)** · **shadow-DOM ✓ now (shoelace ref)** · islands/iframe = untested-in-wild (absent on awwwards) |
| **2 substrate** | DOM · canvas-2D · WebGL · video · Flutter/CanvasKit(zero-DOM) · WebGPU | DOM/canvas/WebGL/video ✓; Flutter/WebGPU not seen (rare; Flutter = extreme-G5 by extension) |
| **3 motion tech** | WAAPI/CSS · GSAP/ScrollTrigger · canvas-anim · video · Lottie · Rive/Three · SVG-SMIL | WAAPI/CSS/GSAP/canvas/video ✓; Lottie = G7-class by mechanism (bodymovin is rAF-driven, not WAAPI → getAnimations blind) — noted, not separately run; Rive/Three → G5 |
| **4 state** | URL-route · non-URL (modal/tab/wizard/post-login/cursor) | URL ✓; non-URL = G3/G4 |

### C6a. Arch-scan (8 awwwards candidates, detection-only, short-stabilize)
unseen, lookback(Nuxt), corentin, shed(Nuxt), gqlab(Nuxt), offmenu, donmol(Nuxt), wildweek(Framer).
**Result: the field collapses to Nuxt/Framer/Next-SPA + WebGL/canvas** (advisor predicted). **No real
shadow-DOM, no Lottie, no Astro-islands, no cross-origin embed in the wild here.** unseen/corentin/gqlab
carry a WebGL canvas; wildweek = 10 2D canvases (Framer + canvas motion).

**Two detector lessons (honest):**
- **`navigator.gpu` is a FALSE WebGPU signal** — it reports *browser* capability (Chrome has it), not
  site usage. All 8 read `webgpu=True`; discard. Real WebGPU detection needs context-creation hooking.
- **Next-detection was Pages-Router-only** (`__NEXT_DATA__`) → it MISSED offmenu, which is **Next App
  Router / RSC** (tell: a `next-route-announcer` shadow host, no `__NEXT_DATA__`). Arch detection needs
  RSC-aware signals. **RSC implication for the P0 G1 fix:** streaming-SSR/RSC streams DOM *indefinitely*,
  so pure node-count-stabilization may never cleanly settle — the settle-fix needs a max-wait +
  network-idle fallback, not stabilization alone.

### C6b. Shadow-DOM split (reference: shoelace.style — 28 Lit web components)
awwwards lacks it → known reference (as with the Wikipedia baseline). Measured same-page, three ways:

| Measure | Count | = scope of |
|---|---|---|
| light (`querySelectorAll('*')`) | 455 | **web_tokens** |
| deep (recursive shadowRoot walk) | 638 | true element count (**183 hidden in shadow**) |
| raw (`DOMSnapshot.captureSnapshot`) | 1779 | **web_skeleton** |
| verb `web_skeleton` nodes | 791 (rc 0) | pierces shadow ✓ |
| verb `web_tokens` | palette 6 / type 6 (rc 0) | light-only, **blind to shadow tokens** |

**→ G10 CONFIRMED (was latent, falsified-on-YouTube but never positively tested):** the two verbs
*disagree* on the same page — `web_skeleton`'s DOMSnapshot pierces OPEN shadow roots and captures the
component structure, while `web_tokens`' `querySelectorAll` cannot, so the design tokens that live
*inside* web-component shadow roots are missed. Asymmetric: geometry ✓, web-component tokens ✗. Fix =
recursive `shadowRoot` walk in web_tokens. Harder sub-case: **closed** roots are invisible to both.

### C6c. Net for the arch axis
**Closed.** All 4 axes enumerated; the ONLY render-arch that introduces a *new* gap is
web-component/shadow-DOM (**G10**, tokens-side only — skeleton already pierces). RSC/islands/SSG/
streaming are **capture-equivalent** to already-covered tiers (all resolve to DOM once settled; only
the settle *timing* differs, which is G1). Reaffirms **§C2: arch is the least-predictive axis** —
covering every arch does not move the ceiling; **substrate (G5) and motion-tech (G7) remain the
blockers, and neither is an arch.**

Artifacts: `/tmp/aw/scan.json` (8-site arch scan), `/tmp/aw/shadow_ref.json` +
`/tmp/aw/shoelace_sk.json`/`_tok.json`; harness `/tmp/aw_scan.py`, `/tmp/aw_ref.py`.

---

## §C7 — Same-pipeline isolation: G1 timing & G6 consent do NOT bite awwwards (2026-05-30)

**Why:** §C1's `struct ratio` was cross-pipeline (parse_snapshot recs ÷ querySelectorAll) — not a
capture fraction. To get a real number, measure the SAME pipeline (`web_skeleton`'s own
`captureSnapshot`+`parse_snapshot`) at three points in one cold session per origin:
C1 = verb-timing (~2s, no dismiss) · C2 = hydrated, no dismiss · C3 = hydrated + consent dismissed.
**Timing effect = C2−C1 · consent effect = C3−C2.** (Cold per origin; awwwards consent is per-origin.)

| Site | C1 verb-timing | C2 hydrated | C3 dismissed | TIMING (C2−C1) | CONSENT (C3−C2) | overlay@C1 |
|---|---|---|---|---|---|---|
| Cartier | 465 | 468 | 468 | **+3** | **0** | none |
| AIR | 720 | 715 | 698 | −5 | **−17** | yes |
| Sowieso | 5372 | 5372 | 5269 | **0** | **−103** | yes |

**Conclusions (these supersede §C1/§C3/§C5):**
- **G1 timing ≈ 0 on all three.** The DOM was already built by ~2s (Cartier light=3631 at C1). My
  earlier "Cartier 25.9s hydrate → 9% capture" was **two artifacts stacked**: (a) the 9% was
  cross-pipeline (337 parse vs 3693 querySelectorAll); (b) the 25.9s was a **loader-detector
  false-positive** — a decorative element kept matching `[class*=loader]`; the DOM itself was fast.
  **G1 is NOT demonstrated on the awwwards sample.** It remains real only for genuinely slow-hydrate
  SPAs (YouTube: verb 1 node vs hydrated parse 4067) — not exercised by these sites.
- **G6 consent does NOT block capture.** Dismissing makes parse go *down* (−17 / −103) because it
  removes the overlay's OWN nodes — the page DOM behind the overlay was captured all along. **Overlays
  cover the DOM, they don't remove it** (advisor's claim, now proven). The only consent risk is a wall
  that blocks content *render* until accepted — none of these did. G6 → cheap defensive nicety, not a blocker.
**Verb-node-count reconcile (advisor-prompted) — apples-to-oranges, now pinned.** The shipped
`web_skeleton.py` emits FEWER nodes than the raw iso parse (sowieso 1790 vs 5372; air 441 vs 720;
cartier 337 vs 465), same direction every site. Checked, no live run: **viewport is identical** (verb
& iso both 1280×813 dpr=2 — read from the saved `_sk.json`), so it is NOT a viewport/dpr divergence.
The cause is `web_skeleton.to_skeleton`→`classify()` (web_skeleton.py:100-119): it keeps a rec only if
its bbox has **area > 0**, dropping zero-area nodes (`<script>/<style>/<head>`, `display:contents`
wrappers, and **collapsed/hidden panels**). So:
- **Acquisition is genuinely full** — `parse_snapshot` captured all 5372 recs (= the live DOM); nothing
  lost in the capture step. The "acquisition is fine for awwwards" conclusion holds.
- The verb's node list is a **deliberate visible-only subset** (1790 = on-screen boxes), not an
  under-capture. My 5372-vs-1790 comparison mixed raw recs with classified-visible nodes — drop it.
- The only *visible-content* drop is collapsed state (e.g. sowieso's 45 accordions) — that is **G4**
  (non-URL state), already ranked, not a new gap.
- Therefore the earlier "Cartier 468 boxes / 3631 elements = content-in-canvas" aside is **withdrawn**
  — it's the same `classify(area>0)` reduction, not a G5 corroboration. (G5 for Cartier stands on the
  direct canvas-area=1.0 measure, independently.)

Artifact: `/tmp/aw/iso.json`; harness `/tmp/aw_iso.py`.

## §C8 — Axes 2–3 reference probes (2026-05-30)

| Arch (axis) | Reference | Result |
|---|---|---|
| **cross-origin iframe** (1h) | controlled inject (example.com + iana.org + same-origin) | **G11 CONFIRMED** — snapshot had 2 documents; same-origin iframe captured, cross-origin NOT (`contentDocument` inaccessible). Hard boundary like canvas. |
| **Lottie** (motion 3) | lottiefiles.com | previews render to **101 canvases**, `getAnimations=4` → lottie motion is rAF/canvas → **oracle-blind, G7/G5-class by mechanism** (not the `<lottie-player>` SVG variant — partial confirm). |
| **Astro islands** (1e) | astro.build | DOM-captured (1858 nodes), `astro-island=0` at runtime (markers consumed post-hydration) → **capture-equivalent to SPA/MPA**, as predicted (low new-gap). |
| **Flutter/CanvasKit** (substrate 2) | gallery.flutter.dev | **test failed** — redirected to GitHub (canvas=0). NOT cleanly exercised. CanvasKit = whole-app canvas, ~zero semantic DOM = **extreme G5** stands on existing rive-editor (§A3) + flutter_flipbook tooling evidence. |

## §C9 — Corrected synthesis & authoritative fix priority (post-isolation)

**What actually blocks reproduction of the awwwards sample (all by DIRECT measure):**
1. **G5 canvas/WebGL substrate** — 4/7 (Cartier, Cdiscount, Razorpay, Sowieso-2D). The signature visual
   is outside the DOM. **Hard boundary.**
2. **G9 video-bg** — Detroit (6). Hard boundary.
3. **G7/G8 GSAP scroll-driven motion** — 3/7 (Ashley, Razorpay, Detroit), incl. the simplest site.
   `getAnimations()` sees ~0. **Fixable.**
4. **G10 web_tokens shadow blindness** — reference-confirmed (shoelace). **Fixable.**
5. **G11 cross-origin iframe** — reference-confirmed. Hard boundary (same-origin is fine).
6. **G4 non-URL interaction state** — cursor/accordions/dialogs (AIR, Sowieso, Cartier). **Fixable** (triggers).

**NOT blockers on awwwards (corrected):** G1 hydration-timing (≈0 here; real only for slow-hydrate
SPAs), G6 consent (overlays cover, don't remove), G2 virtualization (full-page render), G3 multi-route
(one designed page each). Acquisition is *fine* for awwwards; the ceilings are substrate + motion + tokens-shadow + state.

**Reproduction target = TIERED-HONEST (user-chosen):**
- **DOM-substrate tier** → full pixel+token+time-motion repro is reachable after the *fixable* gaps:
  **G7/G8** (scroll-motion), **G10** (tokens shadow-walk), **G4** (interaction-state triggers). No
  acquisition fix needed for this tier. AIR is the near-miss (blocked only by G4). Ashley/Detroit/
  Sowieso join once G7+G10+G4 land (minus their canvas/video regions).
- **Canvas/WebGL/video/cross-origin tier** → faithful output = **behavior-class box + (owned-content-only)
  recorded clip/canvas-capture**. This *is* the honest deliverable; literal third-party pixels are
  IP-blocked by the firewall. "7/7" = each site captured to its substrate's honest ceiling.

**Authoritative fix priority:**
> ⚠️ **P0 CORRECTED (2026-05-30) — full plan in `docs/plans/p0-scroll-driven-motion-fix.md`.** The flipbook
> framing below is wrong (`web_anim` is already scroll-position-driven). Real P0 = (1) readiness-wait before
> ranging (web_anim was measuring a pre-hydration shell → `range 0:0`); (2) multi-segment timeline certification
> (`_anim_core` split-at-extrema → N scroll rows); (3) adaptive second sweep for band-localized motion; (4) raise
> `--top` 12→48. All proven on Ashley (1 → majority of 60 channels certified). Virtual-scroll deferred (not observed).
- **P0 — G7/G8 scroll-driven motion model.** Detect ScrollTrigger/scroll-linked; capture via flipbook
  driven by *scroll position* (not time) → scroll→progress curves bound into the bundle. Biggest, most
  pervasive win; the one fixable gap that blocks the DOM tier on the most sites.
- **P1 — G10 web_tokens shadow-walk** (recursive `shadowRoot` descent) + **G4 interaction-state triggers**
  (cursor/accordion/dialog → drive state, then capture).
- **P2 — substrate honesty (G5/G9/G11)**: behavior-class box + owned-only clip/canvas-capture; document
  the boundary, degrade gracefully. Not a DOM "fix".
- **P3 — G1 settle (RSC-safe: max-wait + network-idle, not stabilization-only) + G6 consent-dismiss.**
  Defensive; needed for slow-hydrate / cold-EU runs beyond this sample, not for awwwards itself.

Artifact: `/tmp/aw/ref2.json`; harness `/tmp/aw_ref2.py`.

---

## §C9-R — Results: P1 (G10 + G4) LANDED (2026-05-30)

The §C9 "P1" pair is implemented + verified (plan: `docs/plans/g10-g4-shadow-tokens-interaction-state.md`;
full unit suite 198 passed; three host gates green — G10 shadow tokens, G4 single-trigger reveal, G4
multi-trigger cross-attribution). The P1 entry above is the *pre-impl prediction*; this is the post-impl record.

- **G10 — web_tokens shadow-token walk: DONE.** `_COLLECT_JS` now recurses `if (el.shadowRoot) visit(el.shadowRoot)`,
  so tokens scoped inside OPEN web-component shadow roots are sampled (they were missed — §C6b: light-only
  `querySelectorAll` never crossed the boundary). Host gate (deterministic `<x-card>` fixture): the shadow-only
  bg/radius/type-size are now captured. `web_skeleton` already pierced open roots, so geometry was never the gap —
  only tokens. **Hard limit (unchanged):** CLOSED roots (`mode:'closed'`) expose no handle → unreachable, like a
  cross-origin iframe (§C8). Documented in `web_tokens._COLLECT_JS`.
- **G4 — interaction-state capture: DONE.** New verb `web_states` navigates once, snapshots REST, scans
  interaction affordances, drives each (click), re-snapshots WITHOUT re-navigating (via the extracted
  `web_skeleton._snapshot_skeleton` seam), and diffs to record APPEARED nodes → content-free `states.json`
  (`schema: probe-states/1`). Host gate (click-to-reveal fixture): a hidden panel's nodes are recovered
  (`n_appeared` ≥ 3). Optional `bundle_writer` artifact (`assemble(states=...)` / `write_bundle`), firewall-audited.
- **Firewall:** content-free by construction — trigger selectors are structural `tag:nth-of-type(n)` paths (mechanism,
  not content, per the mode-c1 precedent); appeared descriptors carry `role`/`bbox`/`z` only. `audit_bundle` scans
  `states.json` like every other artifact.

**Honest limits (real, not overstated):**
- Trigger scan is **explicit-affordance only** — `[aria-haspopup],[aria-expanded],summary,[role=menu]`.
  Hover-only menus and JS-custom triggers with no ARIA are NOT scanned (follow-up: a hover/Input-dispatch path +
  heuristic affordance detection).
- `diff_skeletons` excludes **same-corner container reflow** (a grown `<body>`/`<html>` when the page expands is
  not "revealed content") — verified live: the disclosure fixture dropped from 6→4 appeared (panel + 3 items,
  no html/body). Residual (inherent, documented + unit-pinned): the corner rule cannot tell a grown `<body>`
  from a NEW same-role node at the same corner — an **origin-anchored full-bleed modal/overlay** (role box, like
  `<body>`) is under-counted (its non-origin children still count); the match is also a **greedy count, not
  bijective pairing**. Both err toward under-, not over-count — the safe direction vs. counting every page-growth
  reflow as content.
- **Per-trigger re-baseline is host-verified** (multi-trigger gate): a one-way panel A that stays open does NOT
  inflate trigger B's count (B=3 excludes A's 4). Toggle-back is best-effort only; correctness does not depend on it.
- Bundling is **programmatic only** (`assemble(states=)`); there is no `bundle_writer --states` CLI flag yet.

**Next on the §C9 ladder (at the time of P1):** P2 substrate honesty → P3-G1 settle → G6 consent. P2 landed (§C9-R-P2); P3-G1 landed (§C9-R-P3); the live pointer is at the end of §C9-R-P3.

---

## §C9-R-P2 — Results: P2 (G5 / G9 / G11) substrate honesty LANDED (2026-05-30)

P2 is implemented + verified (plan: `docs/plans/p2-substrate-honesty-g5-g9-g11.md`; full unit suite 216 passed; one host gate green). The fix is HONEST LABELING, not pixel capture — the content firewall blocks third-party pixels by construction, so the deliverable is a content-free manifest that marks each un-reproducible substrate region. Pure core `_substrate.py` (`classify_substrate` + `collect_substrate`, unit-tested); `web_skeleton` attaches a per-node `substrate` marker; `bundle_writer` ALWAYS emits `substrate.json` (schema `probe-substrate/1`), firewall-audited like every other artifact.

- **G5 canvas / G9 video — DONE (labeling).** `web_skeleton` tags `<canvas>` (`substrate:"canvas"`) and `<video>` (`substrate:"video"`) by element tag; `bundle_writer` surfaces them in `substrate.json` (`regions[]` = `{node_id, kind, role, bbox, z}`, plus per-kind `kinds` counts). This says "this region is an un-reproducible substrate," nothing more. **Owned-content clip / canvas-capture is a documented NON-GOAL:** ownership is unverifiable and literal third-party pixels are IP-blocked by the firewall.
- **G11 cross-site iframe — DONE (labeling) + FRAMING CORRECTED.** The real discriminator is whether the snapshot CAPTURED the iframe's document (`contentDocumentIndex` present), **NOT origin**. The earlier §C8 "cross-origin iframe is opaque" wording is imprecise: a same-site cross-ORIGIN iframe shares the renderer process and IS captured (reproducible). Only a cross-SITE iframe goes out-of-process (OOPIF) and is opaque. Empirically grounded (host probe, 2026-05-30): parent `127.0.0.1:A` + child `127.0.0.1:B` (same-site cross-origin) → 3 documents, child captured (`contentDocumentIndex` present); child `localhost:B` (cross-site) → absent from `documents`, `contentDocumentIndex` absent. Marker named `iframe_uncaptured` — honest about the MECHANISM ("its document is not in the snapshot"), not a guessed cause.
- **Honest limits (real, not overstated):**
  - 2D-vs-WebGL canvas is NOT distinguished — the only probe (`getContext`) is destructive and the verdict (un-reproducible) is the same either way.
  - The captured-frame set is rebuilt PER DOCUMENT (node-indexed, doc-local `contentDocumentIndex`), so a cross-site iframe in ANY captured child document is still detected — the cross-document (sibling) case is unit-pinned (`test_parse_substrate_is_per_document`); the nested-in-a-same-origin-child case follows from the same per-document rebuild but is not separately pinned. A 0-size substrate element (bbox w≤0/h≤0) is not emitted by `to_skeleton`, so it carries no marker (invisible → correctly absent).
  - Same-origin AND same-site-cross-origin embeds are correctly NOT flagged (reproducible). The honest manifest UNDER-claims rather than over-claims un-reproducibility.
  - Pre-existing firewall behavior (NOT introduced by P2, shared by `meta.json`/`skeleton.json`/`states.json` which all also carry the page `url`): a captured page whose OWN url ends in an asset extension (`.svg`/`.mp4`/…) trips `_CONTENT_URL` by design (`test_audit_catches_each_leak_class`), while a normal page url passes (`test_audit_allows_...page_url`). `substrate.json`'s `url` adds zero new failure surface.
- **Verification:** full unit suite 216 passed (incl. `_substrate`, `web_skeleton` per-doc, `bundle_writer` empty + canvas round-trips). Host gate (`fixtures/substrate/run_substrate.py`, deterministic offline `localhost` vs `127.0.0.1` cross-site pair): `substrate.json` kinds `{"canvas":1,"video":1,"iframe_uncaptured":1}`, n_regions 3 — canvas + video + the cross-SITE iframe flagged; same-origin + same-site-cross-origin iframes NOT flagged; `bundle_writer` did not raise (firewall passed).

---

## §C9-R-P3 — Results: P3-G1 adaptive settle LANDED (2026-05-30)

P3-G1 is implemented + verified (plan: `docs/plans/p3-g1-adaptive-settle.md`; full unit suite 226 passed; one host gate green). `navigate()`'s fixed `time.sleep(2.0)` is replaced by a content-blind adaptive settle used by ALL 7 web verbs (web_skeleton/tokens/states/anim/flipbook/vectors/eval).

**Locked settle definition** (pure core `_settle.adaptive_settle`, unit-pinned):
`quiet := in-flight ≤ K(=2) AND no new resource STARTED within QUIET_MS(=800)`;
`settle := quiet AND node-count stable for STABLE_POLLS(=3) AND readyState complete AND elapsed ≥ MIN_FLOOR(=500ms)`; else **cap** at `MAX_WAIT` (default 10s). Always records provenance `{settled, capped, waited_ms, n_nodes}` onto `skeleton.json` (`web_skeleton` adds `--max-wait`).

**Engine-agnostic signal.** One JS read (`_web_eval._SETTLE_JS`) over `performance.getEntriesByType('resource')` + node count + `readyState`, returned by-value identically on CDP (`returnByValue`) and WebDriver (`execute_script`) → the same settle runs on Chrome, Safari/iOS, Android. In-flight = resources with `responseEnd===0`; `since_start_ms` = `performance.now()` − max `startTime`.

**Empirical grounding (probe, retired):** a deterministic slow-hydrate probe pinned three facts before any code:
1. **Real slow-hydrate is catchable.** Cartier-class hydration *builds DOM progressively* across ~26s → node-count is changing throughout, so node-count-stabilization + max-wait waits it out. (Host gate: a 6-batch network-driven build over ~3s is captured at `waited_ms≈3588`, 1206 nodes — NOT the early shell the old 2.0s would have caught.)
2. **`networkidle0` hangs on RSC.** A long-lived stream floors in-flight at 1, never 0 → quiet MUST tolerate K≥1 (RSC-safe). A lone stream still settles (it starts nothing new → `since_start_ms` grows).
3. **`responseEnd===0` is a sound in-flight proxy even cross-origin** (verified host probe: a finished cross-SITE no-TAO image reports `responseEnd>0`, only `responseStart`/`connect*`/sizes are zeroed). So real ad/CDN-heavy pages do NOT falsely pin in-flight — they settle, not cap.

**Honest ceiling (irreducible, documented + unit-pinned `test_shell_trap_is_the_documented_ceiling`):** a pre-hydration shell that is node-stable AND quiet, then hydrates via a *silent timer with no network*, is indistinguishable from a settled page — only the DOM mutation proves hydration, and you cannot know one is coming without waiting (which would tax every fast page). Such a page is captured pre-mutation; the `settle` provenance is honest about it. This is the narrow residual class; progressive builds (the motivating target) are caught.

**Latency:** fast pages quiet-exit early (host gate: static page `waited_ms≈1050` < the old flat 2000ms — a net speedup), busy/building pages wait up to the cap. Cartier-class 26s hydration is an explicit `--max-wait 30` opt-in (a 26s default would tax every capture).

**Firewall:** `settle` is bools + ints only (no strings/urls) — content-free by construction; `audit_bundle` scans it like every other artifact, no new surface.

**Nav-commit race (final review flagged, empirically REFUTED).** Because `navigate()` does an async `location.assign` on a REUSED, already-loaded tab then polls immediately, a reviewer flagged that the settle could read the OLD document (ready/quiet/stable) and settle on the wrong page if the new doc's TTFB exceeds `MIN_FLOOR` (500ms). Direct timeline instrumentation (probe, retired): seed a low-node page, assign to a /slow page (1.2s TTFB), tight-poll. Result: **CDP `Runtime.evaluate` BLOCKS through the navigation-commit window and returns only the NEW document's context** — the old seed doc is never readable post-assign (readyState values observed in the 500–1150ms TTFB window: none; first readable read at ~1276ms is already the new 306-node doc). `MIN_FLOOR` + the `readyState==='complete'` gate are belt-and-suspenders. **Guardrail:** do NOT lower `MIN_FLOOR` below commit latency or drop the readyState gate — the reused-tab race is pinned by host gate `fixtures/settle/run_navrace.py` (a unit test cannot reach this browser-level behavior).

**Next on the §C9 ladder:** G6 consent-dismiss LANDED — see §C9-R-P3-G6 (consent overlay = `web_states` `occluding_overlay` State; content-blind Escape dismiss Transition; honest `cleared` outcome). The defensive P3 rung (G1 settle + G6 consent) is complete; the live pointer is at the end of §C9-R-P3-G6.

---

## §C9-R-P3-G6 — Results: G6 occluding-overlay (consent) State LANDED (2026-05-30)

G6 is implemented + verified (plan: `docs/plans/p3-g6-consent-state.md`; full unit suite green incl. `test_consent.py`; host gate `fixtures/consent/run_consent.py` green BOTH cases). Per the decided design, a consent overlay is a `web_states` State and dismiss is a Transition reusing the G4 machinery — NOT a `navigate()` concern.

**What it does.** After the REST snapshot, `web_states` scans for a load-time occluding overlay (content-blind: `position:fixed` + viewport coverage ≥ 0.5 + z-index > 0 — never text/class/id), records it as a content-free State (`kind:"occluding_overlay"`, `coverage`, `z`, `role`, `bbox`), fires one content-blind Escape keydown (the Transition), re-scans, and records `cleared: true|false`. Emitted as an additive `consent` key on `states.json` (schema stays `probe-states/1`); `null` when no occluding overlay is detected (the common case).

**Why it's small (§C7 is load-bearing).** §C7 proved overlays cover the DOM but do not remove it — the page behind is captured regardless. G6 is therefore a content-free RECORD of the occluding layer + an honest dismiss outcome, not an acquisition fix. The "defensive nicety" framing from the gap list holds.

**Honest ceiling (the both-cases gate pins it).** A blind button click is refused on principle (it takes an unknown real action — accept-tracking / nav-away). Escape clears only overlays that honor it; cookie WALLS that require reading "Accept" stay honestly `cleared: false`. The host gate exercises BOTH an Escape-dismissable overlay (`cleared:true`) and an Escape-ignoring one (`cleared:false`) — a gate testing only the dismissable case would fake coverage (the analog of P3-G1's `test_shell_trap_is_the_documented_ceiling`). A second, narrower miss (surfaced in the Task-4 quality review): `_ESCAPE_JS` dispatches the Escape on `document`, which bubbles to `document`/`window` listeners but never propagates DOWN — an overlay whose keydown listener is bound to a descendant (its own modal/focus-trap container, `document.body`, `documentElement`) never sees it and stays `cleared:false`. Like the shadow-root/OOPIF ceilings, this is a declared boundary, not a bug; the honest output is unchanged (overlay recorded, page-behind captured per §C7). The gate proves the MECHANISM on a synthetic document-level overlay — it does not establish a real-world clear-rate (and need not, since §C7 shows the page behind is captured regardless).

**Detection bias = UNDER-detect (documented).** `classify_overlay` requires `fixed` (not `absolute`/`sticky`) + coverage ≥ 0.5 + z > 0. Missing an overlay degrades to current behavior (page-behind still captured); over-detect would mislabel a sticky-nav / hero / splash as an un-cleared consent State. Same safe direction as G4's `diff_skeletons` under-count. Mechanism-honest naming: the data says `occluding_overlay` (it cannot prove "consent" content-blind), echoing P2's `iframe_uncaptured` and P3-G1's `settle`.

**Firewall:** the stored `consent` payload is `{kind, coverage, z, role, bbox, dismiss:"escape", cleared}` — geometry (ints) + an ARIA `role` + constants (`position` is a detection filter only, never persisted) — content-free by construction; `audit_bundle` scans `states.json` as before, no new surface.

**§C9 ladder status (at G6):** P0 (scroll-motion), P1 (G10+G4), P2 (G5/G9/G11), P3-G1 (settle), **P3-G6 (consent) all landed.** The defensive P3 rung is complete. (Updated below: per-state component capture has since landed — see §C9-R-P4.)

---

## §C9-R-P4 — Results: per-state component capture LANDED (2026-05-31)

First roadmap item beyond the §C9 ladder; continues the G4 / `web_states` line. Implemented + verified (spec `docs/plans/per-state-component-capture-design.md`; plan `docs/plans/per-state-component-capture.md`; full unit suite **249 passed**; host gate `fixtures/component/run_component.py` GREEN, exit 0).

**What it does.** `web_states` already drove each interaction affordance and recorded what *appeared* as a node COUNT + flat `{role,bbox,z}` descriptors — not reproducible. It now ALSO records each driven state's revealed subtree as a content-free, reproducible **component**: a new pure core `_states.build_component(rest, after)` re-roots the revealed nodes into a mini-skeleton — component-local parent ids, per-node `sizing`/`layout`/`font`(text)/`colors{bg,fg,border}`, and a `mount` descriptor on each root (its REST attach point, *with colors*). Emitted as an additive `component` key per state on `states.json`; `null` when nothing was revealed. Schema stays `probe-states/1` (additive — `settle`/`consent` precedent).

**Why it's cheap (reuse, not new capture).** The post-trigger `after` skeleton is ALREADY captured in the per-trigger loop — `diff_skeletons` threw all of it away except the count. `build_component` stops discarding it. Colors come from the after-skeleton's own `_node_colors` sidecar; `font` is already on text nodes. **No extra CDP round-trip.** The revealed set uses the SAME predicate as `diff_skeletons` (extracted to a shared `_matches_rest`), so `component.n_nodes == n_appeared` — a free cross-check (unit-pinned).

**Honest ceilings (documented, not bugs).** (1) An origin-anchored full-bleed modal *container* corner-matches `<body>`, so `_matches_rest` treats it as the **mount**, not a first-class component node — but its backdrop colors survive via `mount.colors` (near-zero loss; same under-capture direction as `diff_skeletons`). (2) Closed shadow-roots / OOPIF revealed content is unreachable (inherited from `_snapshot_skeleton`). (3) One post-click snapshot, no animation timeline — motion is `web_anim`'s axis. (4) A root whose after-parent is absent (doc root) or dangling gets `mount:null` (unit-pinned).

**Firewall.** The component carries only role/bbox/z/sizing/layout/font/colors — content-free by construction. Notably it is the FIRST audited file to carry **raw `rgb()`/`rgba()` color strings** (`tokens.json` ships hex; the skeleton's `_node_colors` is popped pre-disk). Verified clean: `cf.audit_bundle` returns `[]` on a `states.json` carrying a full component incl. `rgba(0,0,0,0.6)` alpha (pinned by `test_audit_passes_states_with_component`). Hex-normalizing was rejected — it would destroy modal-backdrop alpha, which `mount.colors` exists to preserve.

**Verification.** Pure-core unit tests pin re-rooting, root mount, colors/font None-safe carry, multi-root, modal-collapse-via-mount, the count invariant, and the none/dangling-parent root. Host gate (offline, `aria-expanded` button reveals a `display:none` styled panel; marker `#123456` on a sized `.item` leaf certain to survive `classify`): `web_states` → `states:1 components:1`, `n_nodes=4`, the panel color carried (parsed → format-robust), parent links resolve, a root records a mount → GATE PASS.

**§C9 ladder + roadmap status:** P0/P1/P2/P3-G1/P3-G6 (the §C9 ladder) + **per-state component capture (P4) all landed.** Remaining roadmap (not started): later acquisition gaps as they surface, iOS/Android/Flutter native. Full per-state *component* capture is now done at the web (CDP) substrate.

---

## §C9-R-P5 — Results: driven-state transition capture LANDED (2026-05-31)

Second roadmap item after the §C9 ladder; completes CONTEXT.md principle #3 (component
= States + Transitions) for the web substrate. P4 captured each driven State as a
content-free `component`; P5 captures the reveal `transition` (the motion-law between
REST and that State).

- **Mechanism:** WAAPI `document.getAnimations()` read in the live window (≈1-2 frames)
  after the click, over the existing `ev()` transport — no new CDP plumbing. New pure
  core `_transition.py` (`map_easing`/`_bind_node`/`build_transition`) maps the declared
  CSS easing onto `_anim_core.EASINGS` and binds each anim to a component-local node by
  bbox. `web_states` reorders the loop to click → capture LIVE → settle → snapshot.
- **Content-free:** CSS property NAMES (never values) + numeric timings + easing strings
  + bbox. Re-verified by `test_content_firewall.py` (real `cf.audit_bundle`).
- **Honest ceilings:** coverage is best-effort (getAnimations() snapshot poll-race; JS-rAF
  motion with no WAAPI/CSS object is invisible); `steps()`/mixed-per-keyframe easing →
  `certified:false`, never force-fit. An unrecognized easing function is uncertified, not
  silently linear. An anim naming no real CSS property is dropped. Each captured law's
  value is exact. Node binding reads the anchor bbox live (mid-animation) against settled
  nodes, so a large/slow transform reveal may bind to None or misattribute to a nearer
  settled sibling — proximity-based, best-effort, not identity-verified.
- **Verified:** pure-core unit tests (20 in test_transition.py) + firewall test + host gate
  (`fixtures/transition/run_transition.py`, GATE PASS on a 240ms ease-out reveal: node
  bound, dur=240, klass=ease-out, props=[opacity,transform]). Full suite 270 passed.

**§C9 ladder + roadmap status:** P0/P1/P2/P3-G1/P3-G6 (the §C9 ladder) + per-state
component capture (P4) + driven-state transition capture (P5) all landed. Remaining
roadmap (not started): later acquisition gaps as they surface, iOS/Android/Flutter
native.

---

## §C9-R-P6 — Results: Regime-1 CSS property coverage (cut 1) LANDED (2026-05-31)

First of the "later acquisition gaps" (source: `docs/research/css-capture-completeness.md`).
Captures high-impact visual CSS the tool dropped, as a content-free per-node `style` field.

- **Properties (cut 1):** filter, backdrop-filter, background-image (gradient string), clip-path,
  box-shadow, mix-blend-mode, transform-origin (only when transform set), full border (4-side
  width/style + right/bottom/left color) + 4-corner radius.
- **Architecture:** content-blind capture — web_skeleton reads via its `WANT_STYLES`
  parallel-index whitelist and emits a RAW `_node_style` sidecar (incl. url()); new pure core
  `_style.py` redacts only external/`data:` url() (→ `url("<asset>")`), keeping same-doc
  `#fragment` mechanism refs; bundle_writer pops the sidecar, redacts, attaches per-node
  `style` (survives `cf.redact_node`'s content-key blacklist), then audits.
- **Firewall (de-risked in sandbox first):** gradients/shadows/enums/`#refs` clean; external/
  `data:` url() trip content-url/data-uri → redacted. Re-verified by a clean test + an
  un-redacted-url canary.
- **Dropped from cut 1:** `-webkit-backdrop-filter` — INVALID for Chrome's
  `DOMSnapshot.captureSnapshot` `computedStyles` (Blink exposes only the unprefixed
  `backdrop-filter`, which captures the mechanism on the Chromium capture path; one bad prop
  aborts the whole snapshot). Caught by the live host gate, not the unit suite.
- **Live-behavior confirmed:** Chrome captures `clip-path:url(#c)` as the same-doc `url("#c")`
  (not an absolute url), so NO fragment carve-out in `_style` was needed — the external/`data:`
  discriminator is sufficient.
- **Honest ceilings:** external background images → `url("<asset>")` marker (slot-like fill
  point), never the URL/bytes; resolved values are faithful but UNPARSED (gradient/shadow
  structured decomposition deferred — reproduction-side, not acquisition).
- **Deferred (trivial follow-on through the proven pipeline):** background-* longhands, outline,
  text-shadow, overflow/aspect-ratio/object-fit, typography suite, transform-3d, gradient/shadow
  parsers. Regime 2 (pseudo-elements) and Regime 3 (responsive/dark-mode/interactive states)
  are separate gaps.
- **Verified:** pure-core unit tests + parallel-index pin + STYLE_PROPS⊆WANT_STYLES guard +
  firewall clean/canary + round-trip + host gate (`fixtures/css_style/run_css_style.py`, GATE PASS).

**§C9 ladder + roadmap status:** §C9 ladder + P4 component + P5 transition + P6 Regime-1 CSS
(cut 1) landed. Remaining: Regime-1 follow-on props; Regime 2 pseudo-elements; Regime 3
responsive/theme/interactive; G2/G3/G7-remaining; iOS/Android/Flutter native.

## §C9-R-P7 — Results: Regime-1 CSS property coverage (cut 2) LANDED (2026-05-31)

The deferred follow-on from cut 1 (§C9-R-P6). Adds 27 more resolved-CSS props to the
content-free per-node `style` field, through the SAME proven pipeline.

- **Properties (cut 2, 27):** background longhands (size/position/repeat/clip/origin/
  attachment/blend-mode), outline (style/width/color/offset), text-shadow, overflow-x/y,
  aspect-ratio, object-fit/position, typography (text-transform/text-decoration-line/
  font-variant/writing-mode/direction), transform-3d (perspective/transform-style/
  rotate/scale/translate).
- **Empirical de-risk (host probe, before wiring):** all 27 props ACCEPTED by
  `DOMSnapshot.captureSnapshot` (no `-webkit`-style rejects this time); Chrome's resolved
  defaults dumped and baked into a 12-entry `_STYLE_DEFAULTS` map verbatim.
- **Sparse-drop:** universal noop (covers background-size:auto, blend-mode:normal,
  aspect-ratio:auto, text-shadow:none, etc.) + `_STYLE_DEFAULTS` (the 12 props whose
  default is NOT noop, e.g. background-repeat:repeat, writing-mode:horizontal-tb,
  transform-style:flat) + an outline-group GATE.
- **Probe correction:** Chrome resolves `outline-width:1.5px` (NOT 0) on every node, so
  the zero-metric rule cannot suppress a default outline; `outline-width`/`outline-color`/
  `outline-offset` are GATED on `outline-style` being set (like transform-origin on
  transform), not zero-dropped.
- **Architecture:** ONLY `web_skeleton.py` changed (append-only whitelist + richer
  `_collect_style`). `_style.py` and `bundle_writer.py` UNCHANGED — none of the 27 props
  carry a `url()`, so cut-2 adds ZERO new content vectors; the cut-1 redactor + prop-
  agnostic attach already cover everything.
- **Verified:** 300 unit tests pass (default-map drop, non-default keep, outline-gate both
  sides, parallel-index pin + STYLE_PROPS⊆WANT_STYLES guard auto-extended) + firewall
  clean (no new canary needed — no new url() vector) + bundle round-trip + extended
  synthetic host gate (`fixtures/css_style/run_css_style.py`: cut-1 + cut-2 + default-
  suppression assertions, GATE PASS).
- **Real-site validation (Flag 2 from cut 1, content-free host run):** `developer.mozilla.org`
  — 707 nodes / 706 styled, **bundle audit CLEAN** at scale. Cut-2 populated (name:count):
  overflow-x 29, overflow-y 28, aspect-ratio 2, text-transform 8, text-decoration-line 68,
  font-variant 701. Observation: `font-variant` resolves non-`normal` on ~every node.
  Discriminator probed (it IS a shorthand, like the `text-decoration` one we avoided): the
  distinct values are `{styleset(disambiguation): 736, normal: 1}`, and the body longhands
  show `font-variant-alternates: styleset(disambiguation)` (all other sub-props `normal`).
  So this is a SINGLE clean INHERITED authored value (MDN sets `font-variant-alternates`
  globally), NOT a multi-token shorthand serialization slipping past noop — faithful capture,
  content-free. (Uniform-on-every-node is a candidate for future inherited-value hoisting to
  cut sidecar bloat, not a defect.) outline/text-shadow/
  transform-3d/object-fit are sparse-to-absent on a docs site (expected; the synthetic gate
  exercises those). Tool: `fixtures/css_style/validate_realsite.py` (one-off, NOT in the
  committed suite — nondeterministic).
- **Honest ceilings:** `outline-style: auto` (the visible UA focus-ring style) over-drops
  the outline group — `outline-style` is judged by the universal noop set (which contains
  `auto`) and gates the group, so an authored `outline:auto` reads as unset. (The similar
  `overflow:auto` / `object-fit:none` cases are NOT lost: those props carry `_STYLE_DEFAULTS`
  entries and the map is authoritative over the noop set — a review-found fix, commit
  `cf022e3` — so their meaningful noop-looking values survive.) Accepted as a narrow ceiling
  (focus rings rarely surface in a static snapshot), not force-handled. Resolved values stay
  faithful but UNPARSED (gradient/shadow/text-shadow structured decomposition deferred,
  reproduction-side). Defaults are Chrome's single-engine resolved strings.

**§C9 ladder + roadmap status:** §C9 ladder + P4 component + P5 transition + P6 Regime-1
CSS (cut 1) + P7 Regime-1 CSS (cut 2) landed. Remaining: Regime 2 pseudo-elements;
Regime 3 responsive/theme/interactive; G2/G3/G7-remaining; iOS/Android/Flutter native.

## §C9-R-P8 — Results: Regime-2 pseudo-element capture LANDED (2026-05-31)

`::before`/`::after`/`::marker` resolved box-style + a content-free `content` value, as an
additive per-node `pseudo` field on the ORIGINATING element's skeleton node.

- **Premise inversion (load-bearing finding, de-risked before design):** `DOMSnapshot.
  captureSnapshot` DOES enumerate pseudo-elements — `nodes.pseudoType` (sparse
  RareStringData `{index:[node_idx], value:[strIdx]}`), each pseudo node has its own
  `nodeName` (`::before`/`::after`/`::marker`), a populated parallel `layout.styles` row,
  and `parentIndex` → the originating element. So Regime 2 is a Regime-1-style EXTENSION,
  NOT a separate `getComputedStyle(el, "::pseudo")` pass + join (the css-capture-
  completeness doc's earlier "needs a separate JS pass per node per pseudo" was wrong).
- **Reachable set:** before/after/marker (the kinds a static `captureSnapshot` enumerates).
  `::placeholder`/`::selection`/`::first-line`/`::first-letter`/`::backdrop` are NOT
  enumerated (need forced state / live input) — documented ceiling; other pseudo kinds are
  DROPPED, never emitted as junk nodes.
- **Content vector + redaction:** `content` is the ONE new content vector (a token list:
  `"label" counter(x) url(...) open-quote / "alt"`). New tokenizing redactor
  `_style.redact_content_value` classifies per token — quoted strings (incl. attr()-resolved
  literals) → `"<text>"` (empty `""` kept); external/data `url()` → `url("<asset>")` (reuses
  cut-1 `redact_style_value`); same-doc `url(#frag)`, `counter()/counters()`, the `/` alt
  separator, and quote keywords kept as mechanism; `none`/`normal` pass through. Idempotent.
  The tokenizer keeps a CSS function WHOLE (`image-set(...)`/`cross-fade(...)`/gradient) so a
  `url()` Chrome resolves INSIDE one — `content: image-set(url("https://x") 1dppx)`, no space
  before `url(`, **verified reachable** by host probe — is redacted IN PLACE rather than split
  at its slashes; this closed a silent leak the naive per-token bareword arm would otherwise
  create (the redactor's fragmented output evaded even the firewall's url backstop).
- **Sparse-drop + join:** `_collect_pseudo` reuses `_collect_style` for box props, then adds
  the fg/bg/border-top-color the `_node_colors` model excludes (inline as resolved rgb()) +
  `content`. `color` INHERITS, so it is emitted ONLY when it differs from the originating
  element's resolved fg (`node_colors[nid]["fg"] == st.get("color")`, same raw rgb()
  serialization) — a default `::marker` matching its list's text color does NOT land on every
  `<li>`. Each pseudo attaches to its origin via a DIRECT `parentIndex → id` lookup, DROP on
  miss (never reattach to an ancestor). Also FIXES a latent bug: pseudo records previously
  reached `classify` and were emitted as junk `text`/`unknown_box` nodes; now skipped.
- **Architecture:** `web_skeleton.py` (`WANT_STYLES += "content"` append-only;
  `parse_snapshot` reads `pseudoType`; `_collect_pseudo`; `to_skeleton` → `_node_pseudo`
  sidecar, now a 4-tuple) + `_style.py` (`redact_content_value` + `redact_pseudo`) +
  `bundle_writer.py` (`apply_node_pseudo`, threaded through `assemble`/`main`).
  `content_firewall.py` UNCHANGED — `pseudo` is not a `CONTENT_KEYS` entry, so `redact_node`
  keeps it (the already-redacted nested values survive) and `audit_bundle` scans every nested
  string as the independent backstop.
- **Verified:** 330 unit tests pass (tokenizer incl. idempotence + mixed url/string + alt-
  text; `pseudoType` parse; `_collect_pseudo` color parent-diff + bg/border gating + content
  drop; `to_skeleton` attach-to-origin + drop-orphan; bundle apply + disk round-trip; firewall
  clean + un-redacted-url-in-pseudo CANARY trips) + extended synthetic host gate
  (`fixtures/css_style/run_css_style.py`: `::before` string → `"<text>"` + custom color,
  `::after` `url()` content → `url("<asset>")`, custom `li::marker` color; raw authored string
  absent on disk; GATE PASS).
- **Real-site validation (content-free host run):** `en.wikipedia.org` — 7333 nodes / 7332
  styled / **232 with-pseudo**, **bundle audit CLEAN at scale** (`write_bundle` did not raise
  on real `content()` values). Pseudo populated (selector:count): `::before` 80, `::after` 73,
  `::marker` 91 — native enumeration + redaction held on real data. Tool:
  `fixtures/css_style/validate_realsite.py` (one-off, extended; prints selector NAMES +
  COUNTS only — never a content value, resolved string, or url).
- **Honest ceilings:** pseudo GEOMETRY (bbox/size/display) NOT captured — `STYLE_PROPS`
  excludes width/height/display; deferred follow-on. `counter()/counters()` NAMES kept
  symbolic (mechanism, content-free). Short (<25-char ASCII) authored `content` strings rely
  solely on the Task-1 redactor; prose ≥25 ASCII / ≥4 non-ASCII is caught by the firewall
  `_PROSE`/`_NONASCII_PROSE` backstop. Resolved colors are Chrome's single-engine strings.

**§C9 ladder + roadmap status:** §C9 ladder + P4 component + P5 transition + P6 Regime-1
CSS (cut 1) + P7 Regime-1 CSS (cut 2) + P8 Regime-2 pseudo-elements landed. Remaining:
Regime 3 responsive/theme/interactive; pseudo-element GEOMETRY follow-on; G2/G3/G7-
remaining; iOS/Android/Flutter native.

## §C9-R-P9 — Results: Regime-3a theme/preference capture LANDED (2026-05-31)

Per-node resolved-style DELTA under three emulated-media conditions —
`prefers-color-scheme:dark`, `forced-colors:active`, `prefers-contrast:more` — as an
additive per-node `theme` field `{condition: {prop: raw rgb/value}}` on the element's
skeleton node. Recapture-and-diff, not a parser.

- **Join key (load-bearing finding, host-probe-verified before design):** two
  `DOMSnapshot.captureSnapshot` calls cannot be joined by skeleton node id — that id is
  POSITIONAL (`node["id"] = len(emitted)`; `_states.diff_skeletons` matches geometrically
  precisely because the id is not stable), so a dark-mode show/hide shifts every later id.
  `captureSnapshot` returns `nodes.backendNodeId`, a DENSE array PARALLEL to `nodeName`,
  STABLE across a base→condition recapture, and persisting in the node list even when a
  node leaves the layout set under a condition's `display:none`. So the base and each
  condition are joined by `backendNodeId`, re-keyed to the positional node id for emission.
  `backendNodeId` is INTERNAL — used only to join in-process, then dropped; it is NEVER
  written to disk (`main` pops `_node_backend`).
- **Capture flow:** the base is pinned to DEFAULT media (`prefers-color-scheme:light` /
  `forced-colors:none` / `prefers-contrast:no-preference`) via `Emulation.setEmulatedMedia`
  so the delta is environment-independent, not a function of ambient OS/headless defaults.
  Each condition flips EXACTLY ONE feature off that base (single-axis delta), recaptures
  with NO navigate, and diffs full resolved styles over a fixed `THEME_PROPS` universe
  (the Regime-1 visual set + `color`/`background-color`/`border-top-color`). Base and every
  condition use IDENTICAL capture params (same `WANT_STYLES`, `dpr`, rects) — the phantom-
  diff guard, so a plain `base[prop] != cond[prop]` fires on a real change, not on rgb-
  serialization noise, and catches BOTH directions (a reset is just a value change).
  Emulation is cleared in a `finally` so the operator's tab is left unpolluted.
- **No new content vector:** theme deltas are resolved styles, redacted by the existing
  `redact_style_value` (external/data `url()` → `url("<asset>")`; same-doc `url(#frag)`,
  gradients, raw `rgb()` kept). `content` (which resolves to `normal` on element nodes, so
  never actually appears) is routed through `redact_content_value` as a belt. The style-
  path image-set form (`background-image: image-set(url("https://…"))`) was verified to
  redact in place with no host surviving (the same class as the P8 content-side leak).
- **Drop-on-miss:** a node present in base but absent under a condition (display:none, or a
  theme-triggered DOM mutation) is DROPPED for that condition, never reattached — the
  documented style-only ceiling.
- **Architecture:** new `_theme.py` pure diff core (`styles_by_backend`/`diff_theme`/
  `rekey_by_node_id`/`build_node_theme`, no browser/I-O, unit-tested); `web_skeleton.py`
  (`parse_snapshot` reads `backendNodeId`; `to_skeleton` → 5-tuple `node_backend`;
  `--themes` flag; `capture_with_themes` CDP orchestration); `_style.redact_theme` (mirrors
  `redact_pseudo`); `bundle_writer.apply_node_theme` threaded through `assemble`/`main`,
  run BEFORE `cf.redact_node`. `content_firewall.py` UNCHANGED — `theme` is not a
  `CONTENT_KEYS` entry, so `redact_node` keeps the already-redacted nested map and
  `audit_bundle`'s key-aware walk recurses into `node.theme[label][prop]` as the
  independent backstop (a prose canary proves the walk actually reaches that path).
- **Verified:** 358 unit tests pass (backendNodeId parse; `node_backend` map + unpack
  migration; `_theme` diff direction-safety + drop-on-miss + rekey None-safety + transpose;
  `redact_theme` incl. style-path image-set canary; bundle apply round-trip; firewall clean +
  un-redacted-url + image-set + PROSE canaries). Synthetic host gate
  (`fixtures/theme/run_theme.py`) proves JOIN CORRECTNESS, not merely "deltas appear":
  `#known`'s dark delta = the exact resolved dark color, contrast = the exact contrast
  color, forced-colors non-empty; and PER-CONDITION ISOLATION — `#static` (no author
  `@media` rule) receives NEITHER a dark NOR a contrast delta (they land only on the node
  whose rule fired), while legitimately carrying a forced-colors delta. GATE PASS.
- **Real-site validation (content-free host runs, prop NAMES + COUNTS only):**
  `developer.mozilla.org` — 622 nodes, audit CLEAN; **dark 288/622 (46.3%, 7 color props)**
  confirms the dark path fires on real `@media`-driven data; forced-colors 620/622 (99.7%).
  `github.com` — 1613 nodes, audit CLEAN; forced-colors 1612/1613 (99.9%, 12217 changed-prop
  occurrences, 11 distinct props); dark 0 (GitHub pins logged-out users to a fixed color-mode
  via `data-color-mode`, so `@media` dark never fires — an explained site characteristic, not
  a pipeline defect, corroborated by forced-colors firing through the same machinery). Tool:
  `fixtures/theme/validate_realsite.py`.
- **forced-colors DENSITY (design §9 confirmed + measured):** `forced-colors:active` is a
  UA-level override that restyles essentially EVERY element (~99.7–99.9% of nodes on both
  sites), so the `forced-colors` delta is dense BY CONSTRUCTION. It is nonetheless BOUNDED —
  ~8–11 distinct props per node (color/border-*/outline/background + `font-variant`), i.e.
  the bundle grows linearly in node count, not pathologically. Audit stayed CLEAN at 1613
  nodes; the dense map does not balloon or leak.
- **Honest ceilings:** style-only (no geometry/`display` diffing — a toggle is handled by
  drop-on-miss). `prefers-reduced-motion`, `@container`, multi-viewport responsive, and
  palette-token clustering of dark deltas are DEFERRED. `prefers-contrast` author rules are
  rare in the wild (0 on both real sites); the gate proves contrast capture WHEN a rule
  exists. Resolved colors are Chrome's single-engine strings. Interactive pseudo-states
  (`:hover`/`:focus` via `CSS.forcePseudoState`) and viewport-driven responsive deltas are
  the NEXT cuts (Regime-3b / 3c), not this one.

## §C9-R-P10 — Results: Regime-3b interactive-states capture LANDED (2026-05-31)

Per-node resolved style DELTA under three forced interactive pseudo-classes — `:hover`,
`:focus`, `:active` — captured as an additive per-node `pseudo_state` sidecar
(`{node_id: {state_label: {prop: raw_value}}}`), content-free, no reproduction-side
parser. Structural clone of Regime-3a: same `backendNodeId` join (reused `node_backend`),
the pure diff core (`_theme.diff_theme`/`rekey_by_node_id`/`build_node_theme`) reused
UNCHANGED, `redact_pseudo_state = redact_theme` alias, `content_firewall.py` UNCHANGED.

- **Join key (reused):** `backendNodeId`, DOMSnapshot-stable across base→forced
  recapture; already threaded by Regime-3a. 3b adds a transient `backendNodeId → CDP
  nodeId` map (`DOM.pushNodesByBackendIdsToFrontend`) needed only to issue
  `forcePseudoState`; neither key reaches disk (gate-asserted).
- **Mechanism (the one new axis):** `CSS.forcePseudoState` is PER-NODE (not global like
  `setEmulatedMedia`). Force the pseudo-class on EVERY element node, take ONE recapture
  per state, diff over `THEME_PROPS`, clear. A throwaway host probe de-risked the
  architecture before design: a forced flag SURVIVES a fresh `DOMSnapshot` (F1);
  `pushNodesByBackendIdsToFrontend` round-trips the join key (F2); descendant-combinator
  restyle works (F3); a no-rule node gets NO delta (F4 isolation); ~0.21 ms/force call so
  force-all is cheap (F5); hover/focus/active/focus-visible all forcible (F6); clearing
  restores base (F7).
- **Prop universe:** `THEME_PROPS` verbatim — already covers color/bg/box-shadow/
  `outline-*`/`text-decoration-line` (probe F1/F1b; real-site confirmed text-decoration-line
  hover deltas). `cursor` deferred (append-only future add).
- **Ceilings (honest):** force-all co-occurrence chimera (a multi-node combinator —
  `.a:hover .b:hover`, or `:focus-within` on a force-focused ancestor — can yield a style
  no single real interaction would; low-frequency, documented); currentColor ride-along
  (changing `color` cascades to `border-*-color`/`outline-color`; faithful, benign);
  drop-on-miss (display:none under a state); single-engine. NAMING: the per-node
  `pseudo_state` field is DISTINCT from the bundle-level `states.json` (G4 click-reveal
  affordances, `web_states.py`) — do not conflate.
- **Host gate** (`fixtures/pseudo-state/run_pseudo_state.py`): join correctness (#known
  hover/focus/active deltas correct; #child descendant-combinator hover delta; #static
  per-state isolation — NO delta even under forced focus, empirically confirming forced
  `:focus` paints no UA outline on a no-rule div), `_node_backend`/`_node_pseudo_state` +
  per-node `backend` never on disk, bundle audit CLEAN. **GATE PASS.** Regime-3a theme
  gate re-run PASS (shared `_styles_by_backend` refactor regression-clear). Full suite 366.
- **Real-site (content-free, github.com, 1613 nodes):** hover 28.9% of nodes (color +
  currentColor-driven border-color + text-decoration), focus 38.7% (dominated by
  `outline-width/color/style/offset` — focus rings), active 1.0%; bundle audit CLEAN at
  scale; coverage healthy (push-drop did not bite). Only content-free signal (prop NAMES
  + counts + host netloc) printed/persisted.

**§C9 ladder + roadmap status:** §C9 ladder + P4 component + P5 transition + P6 Regime-1
CSS (cut 1) + P7 Regime-1 CSS (cut 2) + P8 Regime-2 pseudo-elements + P9 Regime-3a
theme/preference style-delta + P10 Regime-3b interactive pseudo-states
(`CSS.forcePseudoState`) + P11 Regime-3c responsive multi-viewport deltas landed.
Remaining: Regime-4 authored-rule/keyframe parse; pseudo-element GEOMETRY follow-on;
reduced-motion; form-state pseudo-classes (`:checked`/`:disabled`); fixed-width
@container; G2/G3/G7-remaining; iOS/Android/Flutter native.

## §C9-R-P11 — Results: Regime-3c responsive multi-viewport capture LANDED (2026-05-31)

Per-node resolved-style DELTA across narrower viewport widths — `768px` and `390px` vs
a base wide capture — as an additive per-node `responsive` field
`{width_label: {prop: value}}`, content-free. Structural clone of Regime-3a/3b: same
`backendNodeId` join, the pure diff core (`_theme.py`) reused UNCHANGED,
`redact_responsive = redact_theme` alias, `content_firewall.py` UNCHANGED.

- **Mechanism:** `web_skeleton --breakpoints` navigates ONCE at the widest width (base),
  then for each narrower width applies `Emulation.setDeviceMetricsOverride` with NO
  re-navigate, recaptures a DOMSnapshot over a curated `RESPONSIVE_PROPS` set, and diffs
  resolved styles vs base. Join key = stable `backendNodeId` (internal, never on disk).
  Output = additive per-node `responsive` sidecar via `_node_responsive`; `redact_responsive`
  is an alias of the theme redactor.
- **RESPONSIVE_PROPS (curated discrete-layout set):** `display`, `flex-direction`,
  `flex-wrap`, `grid-template-columns`, `grid-template-rows`, `gap`, `column-gap`,
  `row-gap`, `position`, `font-size`, `text-align`. Continuous px properties
  (width/height/margin/padding/inset) deliberately EXCLUDED — bbox carries rendered size;
  they'd delta on nearly every node (anti-chimera).
- **DISTINCT from `--viewports`:** the existing `--viewports` flag re-navigates per width,
  joins positionally, and emits coarse fill/fixed `sizing` inference on a single merged
  skeleton. `--breakpoints` is a separate flag with a per-node delta sidecar; both retained.
- **Ceilings (honest):** style-only drop-on-miss (a node `display:none` at a width is absent
  for that width); fixed-width `@container` NOT captured (only viewport-tracking containers
  ride free); JS-resize-listener DOM mutations are a style-only ceiling.
- **Host gate PROVEN** (`fixtures/responsive/run_responsive.py`): synthetic page — `@media`
  node carries narrow-width `display→block` / `flex-direction→column` / `font-size→12px`
  delta; `clamp()` node `font-size` re-resolved to `20px` at `400`; viewport-tracking
  `@container` node re-evaluated only at `280` (container dropped below 300) and was isolated
  at `400`; a no-rule node got NO delta (per-width isolation); grid named-line track-list
  flowed through the firewall with NO leak; `backendNodeId` never on disk; bundle audit
  CLEAN. **GATE PASS.**
- **Real-site (content-free, developer.mozilla.org):** 622 nodes, 32 carrying responsive
  deltas (5.1%) at both `768px` and `390px`; audit CLEAN; deltas dominated by
  `grid-template-columns/rows` + `gap` + `text-align` + `flex-direction` (the discrete
  RESPONSIVE_PROPS) — grid track-lists passed the firewall on a real site.
- **Commits:** 7e731bb (redact_responsive alias), 164618b (RESPONSIVE_PROPS + _snapshot_recs
  generalize), b04f38d (bundle threading), bd65613 (firewall canary), fffa059 + 91c776e
  (capture_with_breakpoints + --breakpoints flag + clarifying comment), 6f913b4 (host gate),
  1e17936 (real-site harness).

**§C9 ladder + roadmap status:** §C9 ladder + P4 component + P5 transition + P6 Regime-1
CSS (cut 1) + P7 Regime-1 CSS (cut 2) + P8 Regime-2 pseudo-elements + P9 Regime-3a
theme/preference style-delta + P10 Regime-3b interactive pseudo-states
(`CSS.forcePseudoState`) + P11 Regime-3c responsive multi-viewport deltas landed.
Remaining: Regime-4 authored-rule/keyframe parse; pseudo-element GEOMETRY follow-on;
reduced-motion; form-state pseudo-classes (`:checked`/`:disabled`); fixed-width
@container; G2/G3/G7-remaining; iOS/Android/Flutter native.

## §C9-R-P12 — Results: Regime-4a CSS @keyframes capture LANDED (2026-05-31)

Per-node additive `keyframes` sidecar — the time-driven CSS `@keyframes` animation
timeline each element references — as `[{timing:{duration,easing,iterations,direction,
delay,fill}, frames:[{offset, props:{prop:value}}]}]`, content-free, joined by
`backendNodeId`. This is the intermediate animation CURVE the R1–R3 computed-snapshot
regimes structurally cannot see (they capture only static states).

- **Mechanism (authored path, coverage MEASURED):** `CSS.getMatchedStylesForNode.
  cssKeyframesRules`, keyed off the computed `animation-name`. Probe PR2 + the host
  gate's `#oneshot`/`#delayed` nodes MEASURED coverage of ALL play states: finished
  fill:none entrance one-shots (captured), not-yet-started (captured), and running
  (captured) — unlike `getAnimations()`, which is running-only and systematically
  misses finished fill:none entrance one-shots (probe PR1). Candidate nodes = computed
  `animation-name != none`, found via the 3c-generalized `_snapshot_recs(ev,
  ANIM_CANDIDATE_PROPS)`; per-candidate `DOM.pushNodesByBackendIdsToFrontend` (R3b
  plumbing) → `getMatchedStylesForNode` → `_keyframes.parse_keyframes` over the curated
  `ANIMATABLE_PROPS` whitelist. Zero new CDP wiring (CSS domain already enabled; push
  plumbing already threaded by R3b).
- **Content-free invariants (gate-asserted):** the `@keyframes` author NAME is used only
  TRANSIENTLY to pair a rule with its `animation-name` slot, then DROPPED (never
  persisted); `backendNodeId` / frontend `nodeId` stay internal (never on disk). Gate-
  locked: on-disk skeleton contains no `_node_keyframes`/`_node_backend`/per-node
  `backend`, and used `@keyframes` names never appear on disk. `content_firewall.py`
  UNCHANGED — its key-aware walker already recurses through the new `keyframes` list;
  proven by a prose-canary TDD-inversion test.
- **New code:** pure core `scripts/_keyframes.py` (mirrors `_theme.py`);
  `_style.redact_keyframes` (a GENUINE walker, not an alias — the `[{timing,frames}]`
  shape differs from the flat `{label:{prop}}` redactors);
  `bundle_writer.apply_node_keyframes` (mirrors `apply_node_responsive`);
  `web_skeleton.capture_with_keyframes` + `--keyframes` flag.
- **Two bugs the gates caught (value of the host/real-site gates):** (1) CDP
  `CSSKeyframeRule.keyText` is a `Value` dict `{text, range}`, NOT a bare string —
  the unit-test mock had the wrong shape; the host gate caught it; fixed by unwrapping
  `.text` (same as `animationName.text` was always handled). (2) On a real site
  (animate.style), a candidate backendNodeId can push to a NON-Element node, making
  `getMatchedStylesForNode` raise "Node is not an Element" and abort the whole capture;
  fixed with a per-candidate drop-on-error guard. (Also: the gate's synthetic page
  switched its two infinite anims from rotate/scale to translateX so the rendered AABB
  stays at the authored size and nodes remain bbox-identifiable mid-animation.)
- **Ceilings (documented, not silently dropped):** authored keyframe values leave
  `var()`/`calc()` UNRESOLVED (the computed `getAnimations().getKeyframes()` path would
  resolve them but is running-only) — a noted follow-on, out of R4a scope. CSS
  transitions and JS/scroll-driven motion are out of scope (separate rungs / `web_anim`
  domain).
- **Verified:** host CDP gate PASS (`#spin` infinite transform [0,1]; `#pulse` 3-stop
  opacity [0,0.5,1]; `#oneshot` finished fill:none one-shot CAPTURED; `#delayed` not-
  started CAPTURED; `#static` isolated; name never on disk; audit CLEAN). Full unit
  suite 391 passed. Regime-3a/3b/3c regression gates all PASS (shared `_snapshot_recs`
  path unregressed). Content-free real-site harness against animate.style: audit CLEAN,
  on-disk gate CLEAN, content-free signal only (host netloc + counts + prop NAMES).

**§C9 ladder + roadmap status:** §C9 ladder + P4 component + P5 transition + P6 Regime-1
CSS (cut 1) + P7 Regime-1 CSS (cut 2) + P8 Regime-2 pseudo-elements + P9 Regime-3a
theme/preference style-delta + P10 Regime-3b interactive pseudo-states
(`CSS.forcePseudoState`) + P11 Regime-3c responsive multi-viewport deltas + P12
Regime-4a CSS @keyframes capture landed.
Remaining: Regime-4b authored cascade [blocked on matched-vs-inactive content-free wall]; pseudo-element GEOMETRY follow-on;
reduced-motion; form-state pseudo-classes (`:checked`/`:disabled`); fixed-width
@container; G2/G3/G7-remaining; iOS/Android/Flutter native.

## §C9-R-P13 — Results: Reduced-motion computed-style delta capture LANDED (2026-06-01)

Per-node additive `reduced_motion` sidecar — the computed-style DELTA each element
exhibits under emulated `prefers-reduced-motion: reduce` — as `{"reduce": {prop:value}}`,
content-free, joined by `backendNodeId`. This is the DECLARED accessibility-variant
adaptation (which motion props the design suppresses/shortens) the R1 static snapshot
structurally cannot see. A standalone rung (sibling to Regime-3a, NOT part of Regime-4);
independent of R4a (keyframes) and R4b (cascade).

- **Mechanism (zero new CDP wiring):** `Emulation.setEmulatedMedia` with
  `prefers-reduced-motion: no-preference` (base) then `reduce` (condition) — the SAME
  emulated-media path Regime-3a already uses for `prefers-color-scheme`/`forced-colors`.
  One navigate: capture base skeleton (+ `node_backend` map), snapshot `MOTION_PROPS`
  under each condition, diff via the `_theme` pure core
  (`diff_theme` → `rekey_by_node_id` → `build_node_theme`), rekey `backendNodeId` →
  `node_id`. `MOTION_PROPS` is snapshotted EXPLICITLY (`_snapshot_recs(ev, MOTION_PROPS)`,
  the `capture_with_breakpoints` pattern) because it is NOT a subset of `WANT_STYLES`.
  Emulation cleared in a `finally` so the operator's tab is left unpolluted.
- **`MOTION_PROPS` (6, curated, probe-MEASURED to move under reduce):** `animation-name`,
  `animation-duration`, `animation-iteration-count`, `transition-duration`,
  `transition-property`, `scroll-behavior`. Probe PR3 MEASURED that
  `animation-play-state` does NOT move (turning an animation off via `animation: none`
  removes the animation; the no-animation default play-state is still `running`) — so it
  carries no signal and is EXCLUDED. Layout/size props excluded (bbox carries size).
- **Content-free invariants (gate-asserted):** only changed CSS keyword/duration values
  on disk; `backendNodeId` / frontend `nodeId` stay internal. Gate-locked: on-disk
  skeleton contains no `_node_reduced_motion`/`_node_backend`/per-node `backend`.
  `content_firewall.py` UNCHANGED — the delta is the flat `{label:{prop:value}}` theme
  shape, so its redactor `redact_reduced_motion` is a true ALIAS of `redact_theme` (like
  `redact_pseudo_state`/`redact_responsive`; contrast `redact_keyframes`, a genuine walker
  for the `[{timing,frames}]` shape), and the firewall's key-aware walker already recurses
  the new `reduced_motion` key; proven by a prose-canary TDD-inversion test.
- **New code (near-clone of the R3a single-condition flow):**
  `_style.redact_reduced_motion` (alias); `bundle_writer.apply_node_reduced_motion`
  (mirrors `apply_node_keyframes`) + `_node_reduced_motion` threading through
  `assemble`/`main`; `web_skeleton.MOTION_PROPS` + `capture_with_reduced_motion` +
  `--reduced-motion` flag (its own `elif` branch, CDP-transport guarded).
- **Ceilings (documented, not silently dropped):** DECLARED variant only — whether JS
  honors `matchMedia('(prefers-reduced-motion: reduce)')` to suppress JS-driven motion is
  out of scope (`web_anim` domain). No R4a `@keyframes` re-capture under reduce (the
  `animation-name → none` delta already records the suppression for the common case).
  Single condition (`reduce` vs `no-preference`). The transition family is watched on
  `transition-property` + `transition-duration` only — `transition-delay` and
  `transition-timing-function` are intentionally omitted: the dominant reduce pattern is a
  global `transition: none` (measured on github: 1609 nodes), under which
  `transition-duration → 0s` already records the suppression, making the delay/timing
  deltas redundant. A measured follow-on only if sites are found to shorten (not zero)
  transitions under reduce.
- **Verified:** host CDP gate PASS (`#known` carries `animation-name`→`none`,
  `animation-duration`→`0s`, `transition-duration`→`0s`, `scroll-behavior`→`auto` — with
  `scroll-behavior` declared ON `#known` since it is not inherited, and a `translateX`
  animation so the AABB stays bbox-identifiable [the R4a lesson]; `#static` isolated — no
  field; `backendNodeId` never on disk; audit CLEAN). Full unit suite **400 passed**.
  Regime-3a/3b/3c/4a regression gates all PASS (shared `_snapshot_recs` path unregressed).
  Content-free real-site harness against github.com: 1609/1613 nodes carry a reduce delta
  (transition suppression dominant — a global `transition` rule flipped to `none`), audit
  CLEAN, on-disk gate CLEAN, content-free signal only (host netloc + counts + prop NAMES).

## §C9-R-P14 — Results: Form-state (`:checked`/`:disabled`) capture LANDED (2026-06-01)

Per-node additive `form_state` sidecar — the computed-style DELTA each FORM CONTROL exhibits
when forced into `:checked` / `:disabled` — as `{state_label: {prop:value}}`, content-free,
joined by `backendNodeId`. The interactive-state sibling of Regime-3b (which covered
hover/focus/active), extended to the DOM-state form pseudo-classes. Probe-grounded
(`research/capture-gap-probes/probe_form_states.py`, commits `06aa81b`/`65277e6`; FS1-FS5 facts).

- **Mechanism:** combines the R3b force/clear discipline with the R3a/P13 sidecar build, with
  ONE deliberate divergence: the force-set is RESTRICTED to state-eligible elements via
  `DOM.querySelectorAll` per state — NOT R3b's force-all. Per state: querySelectorAll →
  `CSS.forcePseudoState [state]` on the eligible nodeIds → `time.sleep(0.2)` settle → snapshot
  `FORM_PROPS` → `diff_theme` vs base → `rekey_by_node_id` → clear. `build_node_theme` transposes
  to `{node_id: {state: delta}}`. `forced`-set bookkeeping + `finally` clear leave the tab clean.
  New `--form-states` flag (its own `elif`, CDP-transport guarded).
- **Force-set targeting (the FS3 finding — why force-all is WRONG here):** the probe MEASURED
  that force-all smears a bare `:disabled{}` rule onto ~9 non-disableable nodes (divs/html/body),
  because `forcePseudoState` ignores the "form-associated only" restriction. `DOM.querySelectorAll`
  with `"input[type=checkbox], input[type=radio], option"` (checked) /
  `"input, button, select, textarea, fieldset, optgroup, option"` (disabled) encodes eligibility
  EXACTLY — incl. input `type`, which snapshot recs (tag-only) cannot express — so a bare rule
  matching a real `<button>` is faithful, while a `<div>`/text-input is never forced. The diff is
  over the WHOLE snapshot, so CSS-toggle combinator deltas (`:checked ~ .panel`, FS5 — the dominant
  real `:checked` use) land on the NON-forced sibling's own `backendNodeId`.
- **`FORM_PROPS` (probe-MEASURED to move, FS4):** `THEME_PROPS` + `opacity` (dimming) +
  `accent-color` (checkbox tint) + `cursor` (`not-allowed` — the canonical `:disabled` affordance).
  `cursor` is a USER-APPROVED deliberate break of the project-wide cursor deferral. Snapshotted
  explicitly (NOT a subset of `WANT_STYLES`).
- **Content-free invariants (gate-asserted) — `content_firewall.py` was REVISED (unlike P13):**
  only changed CSS color/keyword/number values on disk; `backendNodeId` / frontend `nodeId` stay
  internal (gate-locked: no `_node_form_state`/`_node_backend`/per-node `backend`). The delta is the
  flat `{label:{prop:value}}` theme shape, so `redact_form_state` is a true ALIAS of `redact_theme`.
  **BUT:** the `cursor` url() canary (TDD inversion) surfaced that the firewall's url() detector was
  EXTENSION-ALLOWLISTED (`_CONTENT_URL` only fired on media/font extensions), so `cursor:url(x.cur)`
  AND any external asset URL without a recognized extension inside a delta value (e.g.
  `background-image:url(https://cdn/x)`) leaked — a PRE-EXISTING gap, since delta redactors are
  passthrough and the firewall is the sole backstop. Fix: `_CSS_URL_REF = url\(\s*\\?["']?https?://`
  (extension-agnostic, `url(`-wrapper; tolerates the json-escaped quote; doesn't fire on the bundle's
  bare top-level `url` field or `url(#fragment)` refs; single `\s*` to avoid ReDoS). Two canaries
  (prose + cursor url()) prove coverage; the url() canary uses the REAL serialized shape
  (`probe_url_shape.py`) to avoid a false green.
- **New code:** `_style.redact_form_state` (alias); `bundle_writer.apply_node_form_state` +
  `_node_form_state` threading through `assemble`/`main`; `web_skeleton.FORM_PROPS` +
  `FORM_STATE_SELECTORS` + `capture_with_form_states` + `--form-states`;
  `content_firewall._CSS_URL_REF` (the url() fix). Firewall prose path unchanged.
- **Ceilings (documented, not silently dropped):** states limited to `checked`/`disabled` (the rest
  of the form-state family — `:enabled`/`:indeterminate`/`:required`/`:invalid`/`:placeholder-shown`/
  `:read-only` — deferred; `:invalid` would need its own DOM-validity probe). `DOM.querySelectorAll`
  does NOT pierce shadow DOM / iframes → form controls in web components or cross-frame get no delta.
  Radio-group mutual exclusion NOT modeled (each radio's checked appearance captured in isolation —
  the intent). A button-internal box may carry the button's own `:disabled` delta (faithful,
  button-internal). `cursor` INCLUDED (deferral-break) — custom-cursor `url()` now caught by
  `_CSS_URL_REF`; protocol-relative `url(//cdn/x)` is a residual ceiling but Chrome absolutizes
  computed url() to `http(s)` before capture, so a raw `//` never reaches disk.
- **RESIDUAL FIREWALL GAP (pre-existing, NOT form-state-specific — flagged for a dedicated
  hardening pass):** `_DATA_URI` matches only `;base64,` data URIs and `_CSS_URL_REF` only
  `http(s)://`, so a URL-ENCODED inline-SVG `url(data:image/svg+xml,<svg…>)` in ANY delta value
  (theme/responsive/form_state alike) would escape both. NOT observed to manifest — a content-free
  scan of forced-`:checked` Bootstrap 5.3 form controls (the canonical checkbox framework, 46
  `:checked` nodes) found 0 `data:` and 0 `http(s)://` in on-disk `form_state` deltas (the
  `background-image` deltas resolved to gradients/`none`, not URIs). Borderline by intent (an
  inline-SVG UI glyph is design-system iconography, the thing probe-runner EXTRACTS, not site
  content), so the disposition is a deliberate user call, not a silent omission. A dedicated
  firewall rung should decide whether to broaden `_DATA_URI` to non-base64 + add a `url(data:`
  detector.
- **Verified:** host CDP gate PASS (`#cb` checked opacity/accent-color; `#panel` combinator
  background-color on the NON-forced sibling [FS5]; `#btn` disabled opacity/cursor; `#plain` div NO
  field [FS3 smear-negative — targeting proven]; `#txt` text-input no `checked` field [type-targeted];
  `backendNodeId` never on disk; audit CLEAN). Full unit suite **408 passed** (400 + 8 new).
  Regime-3a/3b/3c/4a/P13 regression gates all PASS (shared paths unregressed; firewall fix no
  false-positive). 32-test firewall suite green. Content-free real-site harness against github.com:
  55/1613 nodes carry a delta (checked=0 — no checkboxes on the landing page; disabled=55, the
  UA-greying signature: color+4 borders+outline on ~36 nodes), on-disk gate CLEAN, audit CLEAN
  (the url() fix did not false-positive on a real bundle), content-free signal only.

## §C9-R-P15 — Results: Fixed-width `@container` capture LANDED (2026-06-01)

Per-node additive `container` sidecar — the computed-style restyle a node takes when its
FIXED-WIDTH inline-size `@container` query container is forced to representative absolute widths —
as `{"<container_node_id>@<width>": {prop:value}}`, content-free, joined by `backendNodeId`. Closes
the Regime-3c ceiling §C9-R-P11 ("fixed-width @container NOT captured"): R3c re-evaluates
`@container` only for VIEWPORT-TRACKING containers (inline-size = viewport, resized by
`setDeviceMetricsOverride`); a fixed-width container's size is viewport-independent so its rules
never fire under viewport emulation. Probe-grounded
(`research/capture-gap-probes/probe_container_query.py`, commit `b320ed1`; CQ1-CQ7 facts).

- **Mechanism (the divergence — first rung to MUTATE the DOM):** there is NO CDP primitive to
  emulate CONTAINER size (unlike `setDeviceMetricsOverride`/`forcePseudoState`), so we mutate the
  container element's own inline width. Capture base at a FIXED wide viewport (1440); discover
  inline-size containers by computed `container-type`; per container
  `pushNodesByBackendIdsToFrontend` → `resolveNode` → objectId; per absolute width `W < base_w`:
  `callFunctionOn` set `width:Wpx !important` (SAVING the prior inline width), `time.sleep(0.25)`
  settle, snapshot `CONTAINER_PROPS`, `diff_theme` vs base, `rekey_by_node_id`, then RESTORE the
  saved width. `build_node_theme` transposes to `{node_id: {"<cid>@<W>": delta}}`. New
  `--container-queries` flag (its own `elif`, CDP-transport guarded).
- **CQ2 — the kill-shot (probe-MEASURED):** a non-navigate inline-width mutation that reflows the
  page caused ZERO `backendNodeId` churn (base/cond backend sets identical), so the base↔condition
  join survives mutation — R2's stability-across-viewport-override does not automatically transfer;
  the probe proved it holds for mutation. CQ3: the `@container` rule re-evaluates in the CAPTURED
  styles after the mutation. CQ6: clearing the inline width restores base exactly, so a
  per-container sweep is reusable on ONE navigate.
- **SAVE/RESTORE (NOT `removeAttribute`):** revert reads+restores the element's prior inline `width`
  value+priority (`removeProperty` if none) — NEVER `removeAttribute('style')`, which would clobber
  a real element's author inline styles and corrupt every subsequent capture in the sweep (advisor
  correctness blocker; the probe's `removeAttribute` masked this on a clean synthetic element).
- **`CONTAINER_PROPS == RESPONSIVE_PROPS`:** `@container` is `@media`'s size-threshold sibling, so it
  reuses the proven breakpoint-restyle vocab (display/flex/grid/gap/position/font-size/text-align).
  `width`/`height`/`margin`/`padding` are deliberately EXCLUDED (anti-chimera, R3c §2.1) — which ALSO
  drops the induced-mutation geometry (the container's own forced width + %-sized descendant reflow,
  CQ5), so the captured delta is genuine CQ-rule restyle, not geometry we forced. `container-type` is
  read for discovery but never enters the diff universe.
- **Composite key `"<container_node_id>@<width>"`:** a descendant under nested containers receives a
  delta from BOTH its own container's sweep and an ancestor's transitive re-eval (CQ5); the composite
  key keeps them distinct. The container node_id is bundle-internal (content-safe); the width is the
  swept integer. No containment-tree logic (YAGNI).
- **Content-free invariants (gate-asserted) — `content_firewall.py` UNCHANGED (verified, not
  assumed):** CONTAINER_PROPS values are layout keywords/lengths/grid track-lists (no url, no color);
  the firewall's key-aware prose walker already covers author-named grid lines. A canary feeding
  unredacted prose through a `container` delta was added and PASSES against the unchanged firewall
  (the P14 lesson: PROVE "firewall unchanged" with a canary, don't assert it). `backendNodeId` /
  frontend `nodeId` stay internal (gate-locked: no `_node_container`/`_node_backend`/per-node
  `backend`). `redact_container` is a true ALIAS of `redact_theme`.
- **New code:** `_style.redact_container` (alias); `bundle_writer.apply_node_container` +
  `_node_container` threading through `assemble`/`main`; `web_skeleton.CONTAINER_PROPS` +
  `DEFAULT_CONTAINER_WIDTHS` (`240,480,720`) + `CONTAINER_BASE_VIEWPORT` (1440) +
  `_cq_container_backends`/`_cq_resolve_object`/`_cq_call` + `_CQ_SET_WIDTH`/`_CQ_RESTORE_WIDTH`/
  `_CQ_BASE_WIDTH` JS + `capture_with_container_queries` + `--container-queries`. NO firewall change.
- **Ceilings (documented, not silently dropped):** `container-type: size` (2D) SKIPPED — fires on
  height but drags page-root (HTML/BODY) height artifacts + auto-dimension collapse (CQ7); inline-size
  only. VIEWPORT-TRACKING inline-size containers are ALSO swept (cannot distinguish from computed
  style) → their deltas OVERLAP R3c's — documented, no detect-and-exclude (advisor). Swept widths are
  OFF-render states BY DESIGN (the component-adaptive sweep intent — a fixed-width container renders at
  one width; we deliberately probe others). `getBoundingClientRect` (border-box) vs
  `setProperty('width')` (content-box) differ on a content-box site, so swept widths are approximate
  there (gate is border-box, exact). Authored `@container (max-width:Npx)` thresholds NOT recovered
  (regime-4b). Push-resolve drop-on-miss; shadow/iframe not pierced; color/bg/continuous-px excluded.
- **Verified:** host CDP gate PASS (`#cqc` fired ONLY @180 not @300 [per-width isolation]; `#cqc2`
  carries TWO distinct composite labels — transitive [via ancestor `#cqi`] + direct [`#cqi2`] nested
  re-eval; `#cqs` `container-type:size` SKIPPED; `#plain` isolated; `backendNodeId` never on disk;
  audit CLEAN). The gate is the first real test of the discover→push→resolve→mutate→revert path (unit
  tests fake the CDP session). Full unit suite **416 passed** (408 + 8 new). Regime-3a/3b/3c/4a/P13/P14
  regression gates all PASS (shared `_capture_one`/`_snapshot_recs`/`_theme`/`bundle_writer` paths
  unregressed). Content-free real-site survey (10 sites): **ishadeed.com** (the canonical
  container-queries author) CORROBORATED the headline path — 4 inline-size containers discovered +
  swept, 4 deltas at width 240 (`grid-template-rows` restyle), one descendant carrying all 4 DISTINCT
  composite labels (the nested multi-container path, on real data), on-disk gate CLEAN, audit CLEAN on
  real delta values; the other 9 (github/tailwindcss/developer.chrome/polaris/web.dev/chakra-ui/nextjs/
  apple/smashing) found 0 inline-size containers — genuine sparsity of `container-type: inline-size` in
  production — with the pipeline robust + on-disk gate CLEAN throughout (tailwindcss's base-content
  audit-fail is pre-existing firewall behavior on a content-rich page, unrelated: 0 containers there).

## §C9-R-G3a — Results: Multi-route site capture LANDED (2026-06-01)

- **What landed.** `site_capture.py` — the first MULTI-ROUTE orchestrator. Given an EXPLICIT route
  list (`--urls-file` / `--urls`, deduped, order-preserved), it subprocess-chains the already-gated
  per-route pipeline (`web_skeleton` → `web_tokens` → `bundle_writer`) into `routes/<id>/` and emits a
  content-free `site.json` manifest. First rung of the G3 ladder; the committed target is full
  cross-route synthesis (tokens + components + layout), staged as G3a (this) → recurrence probe → G3b
  token merge → G3c component synthesis → G3d layout reconciliation.
- **`site.json` is the merge contract.** `{schema, hosts[], route_count, ok_count, routes[]}` where
  each route row = `{route_id "r%02d", url, bundle, ok, node_count? | error_kind?}`. Stable positional
  ids + self-locating bundle paths + a cheap `node_count` recurrence hint are the interface G3b/c/d
  consume; no speculative merge fields (YAGNI — JSON extends non-breaking).
- **Captures NOTHING itself ⇒ zero new extraction surface.** Every page-derived byte is produced by
  the already-firewall-gated `web_*`/`bundle_writer` tools. `content_firewall.py` UNCHANGED.
- **`site.json` is a NEW persistence surface — PROVEN content-free, not asserted (the P14 lesson).**
  `audit_bundle` rglobs a whole dir, so `site_capture` calls it on the SITE ROOT after writing — one
  backstop re-audits `site.json` AND every per-route bundle. A canary feeding prose through a manifest
  field trips the unchanged firewall. `site.json` carries only positional ids, input urls (= `meta.url`),
  netlocs, integer counts, booleans, and categorical `error_kind`s — never page content, never
  subprocess stderr (a `ContentLeak` message can embed a sample).
- **`bundle_writer` exit-3.** `bundle_writer.main()` now catches `ContentLeak` → exit 3 (reserved
  audit-fire code) so the orchestrator classifies a content-suspicious bundle vs a generic failure
  WITHOUT reading stderr.
- **Failure isolation.** One bad route never aborts the run: each is recorded with a categorical
  `error_kind` (`skeleton_failed` / `tokens_failed` / `bundle_audit_failed` / `bundle_failed` /
  `skeleton_unreadable`) and the run continues. On ANY route failure the route's `routes/<id>/` dir is
  removed so no partial/flagged files persist.
- **Real-site finding (why we validate on real data): raw scratch must stay OUTSIDE the audited tree.**
  The first cut colocated the raw pre-redaction `_sk.json`/`_tok.json` inside `routes/<id>/`;
  `bundle_writer` audits its whole `--out` dir, so on iana.org the raw `_sk.json` (legitimate content
  URLs) tripped the firewall → spurious `bundle_audit_failed` → the leftover raw file then re-tripped
  the site-root backstop → whole run aborted. The REDACTED bundle was clean (redaction works); only the
  raw handoff in the audited dir was the problem. Fix: scratch in a system tempdir OUTSIDE `<out>`;
  rmtree the route dir on any failure. The synthetic host gate PASSED while this bug was live (synthetic
  scratch has no flaggable content), so a deterministic gate guard now asserts each bundle dir holds
  ONLY the known bundle files (no raw scratch) every run.
- **Verified.** Pure units (`_site` manifest/dedupe; `site_capture` row-classification / transport
  forwarding / exit-3 mapping / audit-die / failure isolation / rmtree / scratch-outside, all with
  subprocess + firewall monkeypatched) — full unit suite **433 passed** (416 + 17 new). Host CDP gate
  PASS (3-route synthetic mini-site: 2 real routes complete + bundle-dir allow-list clean, 1 no-host URL
  isolated as `skeleton_failed` with its dir removed, schema/counts correct, site-root audit CLEAN, no
  stderr in `site.json`). Sibling regression: container-query gate PASS (the `bundle_writer` exit-3
  change did not regress the bundle path). Content-free real-site corroboration: **iana.org** (3
  same-host routes, shared template) → `route_count 3 / ok_count 3`, no errors, node_counts
  [158,171,268], on-disk gate CLEAN (no `_node_backend`/`_node_container`/`node.backend`), site-root
  firewall audit CLEAN, rc 0 — three same-host bundles, exactly the recurrence-probe seed G3b/c/d need.
- **Ceilings (documented).** Cross-route MERGE deferred (G3b–G3d); auto-crawl deferred (explicit list
  only); capture depth = skeleton + tokens (motion/states/regime-flags per route deferred); positional
  `route_id` stable within a run but shifts on list reorder across re-captures; cross-route cookie /
  localStorage / sessionStorage bleed in the reused browser is NOT reset by navigation (a consent/AB
  cookie on r00 can skew r01) — per-route storage isolation deferred, and a factor the recurrence probe
  must account for; `url` query/fragment kept as-is (existing firewall governs).

## §C9-R-G3a-probe — Results: Cross-route recurrence probe (G3b de-risk) LANDED (2026-06-01)

Empirical probe on G3a output to ground the **G3b** token-merge model before its spec.
Script `research/capture-gap-probes/probe_token_recurrence.py`; plan
`docs/plans/cross-route-recurrence-probe.md`. Content-free: reads `tokens.json`/`skeleton.json`,
reports only counts / ratios / booleans / role-key names; per-target site-root
`audit_bundle` CLEAN; never echoes subprocess stderr. Not a gated CLI, not in the unit suite.

**Method.** Per token category across the N ok-routes: `distinct` / `core` (in ALL routes)
/ `shared_ge2` / `unique` (one route) / mean pairwise Jaccard. Palette measured three ways
— by **role key**, by **exact value**, by **clustered value** (Chebyshev ΔRGB≤8). Structural
hint = ARIA-**role** SET presence (the content-free skeleton node carries `role`, not `tag`;
raw tag is internal/stripped) — sets not multisets (node counts are content-volume sensitive).

**Noise floors (the advisor blocker, resolved — sub-1.0 is real, not extraction noise).**
- *Floor A* (www.python.org captured twice, identical input): EVERY category jac=1.000,
  core==distinct, zero unique, node_counts [744,744] → `web_skeleton`/`web_tokens` are
  **deterministic**; no extraction-nondeterminism confound.
- *Floor B* (synthetic byte-identical CSS, different body content): every category jac=1.000
  → different content did not perturb extraction on a small page.

**Real sites (same-host, audit CLEAN, rc 0).**
- **www.python.org**, 4 routes (`/`,`/about/`,`/downloads/`,`/community/`), nodes [744,540,4851,448]:
  palette role-KEY **6/6, jac 1.000** (role vocabulary fully stable); palette VALUE core 3/9,
  uniq 3, **jac 0.592**, and **clustered IDENTICAL to exact** (ΔRGB≤8 merged nothing) → the value
  spread exceeds the cluster tol, so it is not sub-threshold jitter (consistent with genuine
  per-section accents). Scalars: weights
  2/2 (1.000); type_scale core 7/12 (0.743); families 5/8 (0.776); spacing 15/29 (0.690); radii
  3/4 (0.875); shadows 5/7 (0.857) — large shared CORE + real per-route TAIL. role_presence 4/4 (1.000).
- **www.iana.org**, 3 routes, nodes [158,171,121]: palette role-KEY core 5/6 (0.889); VALUE exact
  core 3/8 (**0.538**) BUT **clustered core 4/6 (0.778)** — clustering MERGED (distinct 8→6,
  jac 0.538→0.778) → some values lie within ΔRGB≤8 of each other. Floor A shows extraction is
  deterministic, so this gap is NOT capture noise; but the probe CANNOT tell whether the merged
  pairs are a true shared color (sub-threshold sampling jitter) or genuinely-distinct near colors
  wrongly collapsed. radii 0/6 (0.000) and shadows 0/2 (0.333) genuinely don't recur on iana.

**Findings → G3b merge model (the deliverable).**
1. **Correlate on ROLE KEYS (palette) / CATEGORY (scalars), not raw value identity** — keys recur
   ≈1.0 while values drift.
2. **Treat value-clustering as a TUNABLE, not a baked-in correction.** Role keys recur ≈1.0 but
   raw VALUES drift. On iana, ΔRGB≤8 clustering raised measured recurrence (distinct 8→6); on python
   it merged nothing (values far apart, so clustering was inactive there). The probe canNOT decide
   whether iana's merges reflect a true shared color or wrongly collapse genuinely-distinct near
   colors — and python's "merged nothing" says nothing about over-merge behaviour in the regime where
   clustering actually acts. ⇒ G3b should expose the cluster tolerance as a tunable and report BOTH
   exact and clustered recurrence (Finding #4), surfacing the ambiguity rather than committing to one.
3. **Emit a CORE (present across all/most routes) + per-route DELTAS with frequency** — NOT
   intersection-only (discards real per-route tokens), NOT flat union (loses the core/delta signal
   that makes a design system). Per palette role: one representative core value + the per-route variant set.
4. **Report recurrence at BOTH exact and clustered**; the gap bounds the value-drift that clustering
   would absorb. Its attribution (sampling jitter vs genuinely near-distinct design) is unresolved by
   this probe (see ceilings) — report it, do not silently pick one.
4b. **Measure value recurrence PER ROLE / per scalar category, not over the pooled value set.** This
   probe's value-level metric flattens roles: a hex counts as "shared" even if it fills `accent` on one
   route and `border` on another, and clustering can merge near-values from different roles within a
   route. G3b must align values within the same role slot before judging recurrence.
5. **Structural (G3c preview):** ARIA-role set presence is FULLY recurrent (jac 1.000 every target)
   → role vocabulary is shared site-wide, promising for content-free component signatures. node_counts
   vary wildly (python 448→4851) → multiset/count structural metrics WOULD mislead; set-presence is correct.

**Ceilings / honesty.** Floor B is weak (tiny synthetic page, 12–14 nodes); the residual "does rich
different content perturb sampling on a real page?" is NOT directly isolated. The exact-vs-clustered
gap (visible on iana) conflates two unattributed causes — content-perturbation AND genuinely
near-distinct design colors — and the probe cannot separate them. A richer synthetic Floor B
(many nodes/colors, differing content on byte-identical CSS) is the cheap next step to narrow this;
not run here to keep the probe cheap. Cross-route cookie/storage bleed (G3a ceiling) was not
controlled (fresh-nav reuse); a consent overlay on one route could shift its tokens — flagged for
G3b. Two real hosts only (cheap by design), not a population study. The probe's clusterer is a
Chebyshev ΔRGB≤8 approximation of `web_tokens.cluster_colors` (different signature) — G3b should
reuse the real clusterer. Verification: probe pure-core self-checked (recurrence invariants,
cluster merge/non-merge, 3-view palette); 4 captures rc 0; metrics internally consistent
(core≤shared_ge2≤distinct; jac∈[0,1]); floors at 1.000 validate the metric. No production code; nothing pushed.

## §C9-R-G3b — Results: Cross-route token merge LANDED (2026-06-01)

First cross-route SYNTHESIS rung (the probe's findings, realized). A separate pass over a
G3a capture emits one content-free unified design system. Spec
`docs/plans/cross-route-token-merge-g3b-design.md`; plan `…-g3b.md`. Pure core
`scripts/_merge.py` + thin CLI `scripts/site_merge.py` → `design_system.json`
(schema `probe-runner/design-system@1`); host harness `fixtures/site/validate_merge.py`.
`site_capture.py` and **`content_firewall.py` UNCHANGED**.

**Merge model (per §C9-R-G3a-probe).** Per palette role: exact distinct values AND a
**clustered** view (reuses the real `web_tokens.cluster_colors`, `--cluster-tol` default 8).
Per scalar category: exact distinct values. Every token frequency-annotated
`{routes, route_ids, core}` (`core` = present in ALL N). Descriptive, not prescriptive —
the consumer (generator / G3c / G3d) thresholds. N=1 valid; 0 mergeable → exit 2.

**★ Content-free finding — the families exempt-key fix.** `content_firewall._walk_strings`
keys a string by its IMMEDIATE dict key, and the firewall exempts `{family, families, font,
font_family, fontFamily}` from prose detection (font stacks legitimately look prose-like).
The merge nests each token in a freq-entry dict, so a families value under a `"value"` key
would lose that exemption — a long keyword-less stack (e.g. `"Helvetica Neue, Arial,
Liberation Sans"`: `_PROSE` matches, `_is_font_value` False) would **false-positive** the
audit (exit 3) though it passes in `tokens.json`. This is a false-POSITIVE (spurious failure
on valid input), NOT a leak — security invariant intact. Fix: families freq-entries use the
exempt key **`"family"`**; palette (hex) and numeric scalars keep `"value"`. Firewall
untouched; clean-in→clean-out parity with `tokens.json` restored. (Surfaced when an
implementer subagent STOPPED rather than weaken the canary — its conclusion misread the
dict-wrapper, but the instinct exposed a genuine fragility.)

**Content-free posture (PRIME, proven not asserted).** `design_system.json` is the same
token surface `tokens.json` already persists. `site_merge` re-audits the output via the
unchanged `audit_bundle`; on violation it **removes the flagged artifact** (mirrors G3a's
remove-on-failure), exits 3, prints violation COUNT only — never a sample, never subprocess
stderr. Two CLI tests pin it: a **canary** (prose in a PALETTE value → under non-exempt
`"value"` → exit 3, artifact deleted, no sample) proving the new surface is scanned, and a
**families regression** (long keyword-less stack → exit 0) locking the exempt-key fix.

**Empirical validation (real sites, host CDP).** `validate_merge.py` on **python.org** (4
routes) and **iana.org** (3 routes): both GATE PASS, site-root audit CLEAN, rc 0, with real
`families` entries present (8 / 4 distinct) — proving the exempt-key fix on REAL font stacks,
not just the synthetic regression. Merge stats corroborate the probe: python type_scale
core 7/12, spacing 15/29, families 5/8; iana radii 0/6; iana fg-primary clustered 2→1 (core)
— clustering recovering sub-threshold recurrence exactly as the probe predicted.
Consistency held: clustered distinct ≤ exact distinct per role.

**Verification.** Full suite **452 passed** (433 prior + 19 new: `_merge` 12, `site_merge`
7). Two real-site gates PASS, audit CLEAN. No existing file modified → 452-green covers
sibling regression. Built via subagent-driven-development (fresh implementer per task,
two-stage review each); final whole-feature review: Ready to merge. Nothing pushed.

**Ceilings.** Schema asymmetry: `families` entries name their value field `"family"`, all
others `"value"` (consumers read `entry.get("family") or entry["value"]`). Clustered
assignment maps each value to the nearest representative; equidistant ties resolve to the
higher-frequency rep (deterministic; exact view always reported alongside). Cross-route
cookie/storage bleed (G3a ceiling) is reflected, not corrected. `route_id` positional.
Default `--out` audits the whole site dir (intended defense-in-depth; `--out` to an isolated
path to scope it). Two-host empirical grounding; descriptive model does not over-fit.

**§C9 ladder + roadmap status:** §C9 ladder + P4 component + P5 transition + P6 Regime-1
CSS (cut 1) + P7 Regime-1 CSS (cut 2) + P8 Regime-2 pseudo-elements + P9 Regime-3a
theme/preference style-delta + P10 Regime-3b interactive pseudo-states
(`CSS.forcePseudoState`) + P11 Regime-3c responsive multi-viewport deltas + P12
Regime-4a CSS @keyframes capture + P13 reduced-motion computed-style delta + P14 form-state
(`:checked`/`:disabled`) computed-style delta + P15 fixed-width `@container` computed-style delta
+ G3a multi-route site capture + G3a recurrence probe (G3b de-risk) + G3b cross-route token merge landed.
Remaining: Regime-4b authored cascade [blocked on matched-vs-inactive content-free wall];
pseudo-element GEOMETRY follow-on; broader form-state family
(`:enabled`/`:indeterminate`/`:required`/`:invalid`/`:placeholder-shown`/`:read-only`);
the G3 cross-route synthesis ladder — recurrence probe DONE (§C9-R-G3a-probe) → **G3b token
merge DONE (§C9-R-G3b; `design_system.json`, role-key + clustered, families exempt-key)** →
**G3c** recurring-component synthesis (next) → G3d layout reconciliation; G2 virtualization; G7a wrapper-virtualized scroll;
iOS/Android/Flutter native; plus the flagged firewall-hardening pass for non-base64
(URL-encoded inline-SVG) data URIs.

## §C9-R-G3c-calib — Cross-route component synthesis DE-RISKED; G3c DEFERRED pending ARIA-role enrichment (2026-06-01)

In-brainstorm calibration (NOT a gated rung; throwaway evidence
`research/capture-gap-probes/calib_component_signature.py`, content-free: emits counts +
role/design-token-tree strings only, never site content; every capture re-audited CLEAN).
Tested a candidate content-free COMPONENT SIGNATURE before committing a G3c spec: subtree
fingerprint swept over abstraction policy {ordered/collapse/multiset} × depth {1,2,3} ×
anchor {landmark/internal/styled}, role-tree first then ENRICHED with stable design axes
(layout-mode, sizing fixed/fill/hug, `token_ref` palette-role, font-class). Targets
python.org (4 routes, 6583 nodes) + iana (3 routes, 597 nodes); Floor A determinism =
same URL captured twice, compared.

**Findings.**
1. **`web_skeleton.classify()` emits 5 GEOMETRY buckets** `{box, unknown_box, text, image,
   svg}`, NOT ARIA. Role-tree signatures therefore collapse: CORE = generic trivia
   (`box(text)`, `unknown_box(text)`), distinctive structures are large + page-unique. The
   §C9-R-G3a-probe "ARIA-role set FULLY recurrent (jac 1.000)" was **trivially true** (4–5
   buckets present on every page) and is **not** evidence of component recurrence —
   correcting that probe's G3c-preview overclaim.
2. **Enriching the per-node token with stable content-free DESIGN axes** (layout-mode,
   sizing, `token_ref` palette-role, font-class) makes the signature **deterministic**
   (Floor A identical, jac 1.000; audit CLEAN) and **distinctive** (readable: accent CTA
   `b:accent+f:fg-primary`, surface+border card) — but recurrence stays **WEAK**:
   python.org best case 17 core / 165 distinct, **jac 0.34**; ~**66% of depth-2 signatures
   page-unique** (160/240). iana **core=1, jac 0.08–0.14** (small site → almost nothing on
   all routes). The CORE remains mostly generic colored text-boxes; the genuinely
   distinctive components recur on SOME routes (`shared` 2/4), not all.
3. **YAGNI / overlap with G3b.** The recurring signal's VALUES (palette roles, font,
   layout) already ship in `design_system.json`; G3c's only marginal add is COMPOSITION
   (co-occurring roles + layout), which is shallow and mostly generic on these targets.

**Decision — G3c (recurring-component synthesis) DEFERRED.** The root limiter is the coarse
geometry role vocabulary, not the signature design. Next on the cross-route ladder becomes
an **ARIA-role-enrichment rung**: enrich `web_skeleton.classify()` to emit content-free
ARIA landmark/widget roles (its own brainstorm/design). The calibration evidences that
enrichment would improve component **distinctiveness/anchoring** (semantic roots), and it
benefits every downstream skeleton consumer (G3d included). It does **not** prove
enrichment improves cross-route **recurrence** — recurrence is a separate axis limited by
content-volume variance in subtrees, which a richer role vocabulary does not obviously fix
(don't repeat the §C9-R-G3a-probe overclaim). So that rung must **re-run this calibration to
confirm recurrence actually improves** before any G3c build. Revisit G3c after enrichment
lands.

**Ceilings.** Two-host empirical grounding. "core" (present-in-all-N) is strict on small
sites — the real recurring-component signal lives across the core+shared frequency
spectrum, not core alone. The enriched specificity ↔ recurrence trade-off is a tunable.
A sizing-axis encoding bug (fill/fixed both started `"f"`) was found and fixed mid-calibration;
corrected counts were unchanged (sizing was never the sole discriminator — nearly all nodes
`fixed/fixed`), confirming the recurrence numbers are real, not inflated.

**§C9 ladder + roadmap status:** §C9 ladder + P4–P15 + G3a multi-route + G3a recurrence
probe + G3b cross-route token merge landed. The G3 cross-route synthesis ladder — recurrence
probe DONE (§C9-R-G3a-probe) → **G3b token merge DONE (§C9-R-G3b)** → **G3c component synthesis
DEFERRED (§C9-R-G3c-calib; blocked on coarse geometry role vocab → needs ARIA-role
enrichment first)** → G3d layout reconciliation (also benefits from enrichment). Remaining:
**ARIA-role enrichment of `web_skeleton.classify()` (new prerequisite rung)**; Regime-4b
authored cascade [blocked]; pseudo-element GEOMETRY follow-on; broader form-state family
(`:enabled`/`:indeterminate`/`:required`/`:invalid`/`:placeholder-shown`/`:read-only`); G2
virtualization; G7a wrapper-virtualized scroll; iOS/Android/Flutter native; firewall
non-base64 (URL-encoded inline-SVG) data-URI hardening.

## §C9-R-aria-probe — ARIA-role enrichment DE-RISKED; build justified, win narrower than premise (2026-06-01)

Probe-first de-risk of the ARIA-enrichment rung (NOT a gated rung; throwaway
`research/capture-gap-probes/probe_aria_recurrence.py`). The open axis was RECURRENCE —
§C9-R-G3c-calib already showed distinctiveness was fine. Approach: capture DOMSnapshot +
`Accessibility.getFullAXTree` in ONE CDP session; join the computed role onto each node
IN-MEMORY via the internal `backendNodeId` (`node_backend`, dropped at emit → impossible
post-hoc from disk bundles); canonicalize the role to a fixed W3C set (author-custom →
`other`; `name`/`description` NEVER read = content); re-run the G3c signature machinery.
Targets python.org (4) + iana (3). Content-free: in-memory enriched `skeleton.json` written
to a tempdir and `audit_bundle`-checked.

**Findings (confound-controlled — the headline is NOT "recurrence doubled").**
1. **Deterministic** (Floor A: same URL ×2, aria signatures identical, jac 1.000).
   **Content-free**: audit CLEAN — the canonicalized `aria_role` field does not trip the
   firewall (the new-field safety check the rung needs).
2. **Coverage** high (py 78%, iana 96% of nodes get a computed role) but **`other`/generic
   dominates** (py 3056/5165 ≈ 59%); meaningful semantic roles ≈ 41%.
3. **The all-aria-anchor "recurrence doubled" reading is CONFOUNDED** (anchor AND token both
   changed vs the G3c baseline). Strip-prefix control (aria anchor, `aria@` label removed):
   core DROPS (py d1 32→19) but jac RISES (0.50→0.58). So the all-aria anchor's core is
   driven mostly by the ANCHOR selecting trivially-recurrent `link`/`listitem` nodes (which
   recur on any site), not by the aria label. The label adds *specificity* (more distinct
   components), not jac-recurrence.
4. **The real, defensible win: aria roles enable a LANDMARK anchor**
   (navigation/banner/main/contentinfo/region/article) → a small, clean, high-recurrence set
   of genuine site-chrome components — py landmark d1 distinct=9, **core=5, jac=0.71**, core =
   `navigation@(menubar)` / `contentinfo` / `menubar` (real chrome). The geometry role vocab
   (§C9-R-G3c-calib) could not express this at all.
5. **Site-size caveat**: landmark-anchor recurrence scales with landmark count — iana (3
   pages, few landmarks) gives landmark core=1, jac 0.22. The all-aria anchor "recovers" iana
   to core 8–14, but the control shows that is the anchor (links/listitems), not the label.

**Decision — BUILD the ARIA-enrichment rung JUSTIFIED.** Deterministic + content-free, and it
unlocks landmark-anchored cross-route component recurrence that geometry roles cannot. HOW
(settled): additive `aria_role` field (NOT overwrite — geometry role is load-bearing for
`bundle_writer.derive_slots`/`web_vectors`/firewall), sourced from `getFullAXTree` computed
role at the DOMSnapshot REST state, canonicalized, joined via the internal backendNodeId.
**Design refinement for the eventual G3c**: anchor on LANDMARK aria roles, not all-aria nodes
(avoids per-link/listitem trivia inflation — finding #3).

**Ceilings.** `other`/generic is the dominant computed role. Landmark recurrence is
site-size-dependent. `getFullAXTree` adds a second CDP call (same REST state). The probe used
RAW (unbundled) skeletons, so `token_ref` (palette role) was absent; adding it in production
would — per §C9-R-G3c-calib's specificity↑⇒recurrence↓ — more likely LOWER core/jac than
raise it, so it is a tunable, not a free gain (correcting an earlier wrong-signed "conservative
lower bound" framing).

**§C9 ladder + roadmap status:** §C9 ladder + P4–P15 + G3a multi-route + G3a recurrence probe
+ G3b token merge landed. Cross-route ladder: recurrence probe → **G3b DONE** → G3c component
synthesis DEFERRED (§C9-R-G3c-calib) → **ARIA-role enrichment rung de-risked & BUILD-JUSTIFIED
(§C9-R-aria-probe; additive `aria_role` via getFullAXTree, landmark anchor)** → then revisit
G3c → G3d. Remaining: build the ARIA-role-enrichment rung; Regime-4b authored cascade
[blocked]; pseudo-element GEOMETRY follow-on; broader form-state family; G2 virtualization;
G7a wrapper-virtualized scroll; iOS/Android/Flutter native; firewall non-base64 data-URI
hardening.

## §C9-R-aria — ARIA landmark-role enrichment LANDED (2026-06-01)

Built the rung §C9-R-aria-probe justified. Spec `docs/plans/aria-landmark-role-enrichment-design.md`;
plan `docs/plans/aria-landmark-role-enrichment.md`. Subagent-driven (6 tasks, fresh implementer
+ two-stage review each).

**What landed.** An additive, optional `aria_role` skeleton-node field — emitted ONLY when a
node's browser-computed ARIA role is in a fixed 13-role landmark/composite allowlist
(`banner`/`navigation`/`main`/`contentinfo`/`complementary`/`region`/`search`/`form`/`article`
+ `menubar`/`tablist`/`toolbar`/`dialog`). Sourced from CDP `Accessibility.getFullAXTree` and
joined to the DOMSnapshot via the internal `backendNodeId` inside `web_skeleton._snapshot_skeleton`
(CDP/chrome-only; non-CDP engines no-op). Geometry `role` is **untouched** — `aria_role` is a
parallel additive axis. Pure cores `landmark_roles()` (AX-tree → `{backend: role}`, allowlist
filter, reads ONLY `role.value`) + `apply_aria_roles()` (backend join, key absent when no
landmark); guarded `enrich_aria()` is the only transport-touching code (two try blocks: `enable`
best-effort→continue, `getFullAXTree`→swallow+return so an AX failure can NOT break the shared
base capture). `content_firewall` **unchanged** (`aria_role` is a mechanism key preserved by
`redact_node`; distinct from `aria_label`, which stays a CONTENT_KEYS entry and is stripped).

**Verified.** Full unit suite **464 passed** (12 new `test_aria_roles.py` covering allowlist
drop, absent-not-null, enable-failure AND getFullAXTree-failure resilience, fake-session join +
1 firewall characterization). Host gate `fixtures/aria/run_aria.py` (controller-run, CDP :9222)
**GATE PASS** on the COMPOSED `site_capture → bundle_writer → redact_node → routes/<id>/skeleton.json`
artifact (the one a G3c consumer reads): bundled nodes carry `aria_role` on
banner/contentinfo/main/navigation/region, `audit_bundle` CLEAN, two-run determinism. Final
whole-feature review: **READY TO MERGE** (no Critical/Important). `redact_node`-survival through
the bundle pipeline is thus **empirically verified, not inferred**.

**Content-free.** Only `role.value` is read (never `name`/`description`/accessible-name); the
fixed allowlist means arbitrary author `role="..."` text can never reach disk; allowlisted
tokens are ≤13 chars, structurally below the `_PROSE` ≥25-char threshold.

**Process catch (the discipline paying off).** The controller's gate run caught a repo-root path
bug (`parents[1]`→`parents[2]`; the gate file is two levels deep at `fixtures/aria/`) that both
the implementer's `ast.parse` static check AND a spec reviewer's path-count had missed — exactly
why the host gate is **controller-run against live CDP**, not implementer-run. Two other
review-driven fixes landed in their own commits: an `apply_aria_roles` None/empty guard
(apply_* family idiom) and the graceful-`getFullAXTree`-degradation reversal (an additive
enrichment must not be able to fail the base capture — Task 3 had judged `enrich_aria` in
isolation, before Task 4 surfaced that `_snapshot_skeleton` gates every capture path).

**Ceilings (documented, honest).** CDP/chrome-only (graceful absence on safari/android).
`getFullAXTree` fires once **per snapshot**, so multi-snapshot `capture_with_*` variants make
several AX calls (documented in design §1; harmless — variant skeletons are discarded, only the
base per-route skeleton is written). Main-frame AX only (cross-frame/OOPIF landmarks absent).
`aria_role` is guaranteed only on the base single-snapshot path `site_capture`/G3a emit; merge
variants are out of scope. **This rung delivers the capture PRIMITIVE only** — whether it lifts
G3c cross-route component RECURRENCE is unproven (§C9-R-aria-probe: aria aids
distinctiveness/anchoring; recurrence is a separate axis). The G3c consumer must **re-run the
component calibration with a landmark anchor to confirm recurrence** before any G3c build.

**`finishing-a-development-branch` is N/A** (master-direct, no-push) — noted rather than silently
skipped.

**§C9 ladder + roadmap status:** §C9 ladder + P4–P15 + G3a multi-route + G3a recurrence probe +
G3b token merge landed. Cross-route ladder: recurrence probe → **G3b DONE** → G3c component
synthesis DEFERRED (§C9-R-G3c-calib) → **ARIA-role enrichment LANDED (§C9-R-aria)** → next: revisit
G3c (re-run the calibration with a LANDMARK anchor to confirm recurrence) → G3d. Remaining:
revisit G3c on the landmark anchor; Regime-4b authored cascade [blocked]; pseudo-element GEOMETRY
follow-on; broader form-state family; G2 virtualization; G7a wrapper-virtualized scroll;
iOS/Android/Flutter native; firewall non-base64 data-URI hardening.

## §C9-R-G3c-revisit — VERDICT: DEFER (landmark anchor fails strict cross-site recurrence bar) (2026-06-01)

Revisit of G3c (recurring-component synthesis), DEFERRED at §C9-R-G3c-calib because the 5
geometry buckets are too coarse a root vocabulary. The ARIA rung (§C9-R-aria) landed the
landmark `aria_role` capture primitive; this revisit's open question — UNPROVEN per
§C9-R-aria/§C9-R-aria-probe — is whether anchoring component signatures on the now-PRODUCTION
landmark `aria_role` lifts cross-route RECURRENCE enough to justify building the synthesizer.

Throwaway calibration: `research/capture-gap-probes/probe_g3c_revisit.py`. Reuses calib's
`signature`/`recurrence`/`_is_styled`/`_children` (§C9-R-G3c-calib); roots anchored on
`web_skeleton.LANDMARK_ROLES` (real computed aria_role, NOT the old tag heuristic); captures
through the PRODUCTION `site_capture` path (analyzes the bundled redacted `skeleton.json` a
real G3c consumer reads — token_ref populated post-bundle, which the in-memory aria probe
lacked). Content-free: reads mechanism keys only; audits every bundle; prints counts / jaccard
/ role NAMES / netloc / returncodes only — never node content, never subprocess stderr.

**PRE-REGISTERED BAR (committed before any capture — the fix for this session's 3× recurrence
over-read; the bar is not to be bent after the numbers are seen).** Fixed knobs: depth=3,
policy="collapse". Sweep axis = enrichment level {0:role, 1:+layout/sizing, 2:+token_ref},
reported PER SITE (never averaged — a landmark-rich site must not mask a sparse one). Per-site
metrics: recurrence = |core| (signatures in ALL ok routes) + jac (mean pairwise Jaccard);
distinctiveness = |core_nontrivial|/|core|, nontrivial = exemplar depth≥2 AND root styled
(flex/grid OR token_ref). **VERDICT RULE (strict cross-site):** BUILD iff some single
enrichment level clears core≥3 ∧ jac≥0.5 ∧ distinctiveness≥0.3 on EVERY site with data (≥2 ok
routes); else DEFER (documented). Needs ≥3 sites with data else INCONCLUSIVE. Sites (6,
landmark-bearing, multi-route): python.org, iana.org, djangoproject.com, w3.org, gnu.org,
apache.org. A DEFER is a legitimate honest outcome — the strict bar will likely be dominated
by sparse sites (iana landmark≈1 ⇒ core<3 ⇒ fail), which is itself the finding: landmark-
anchored synthesis pays off only on landmark-rich sites. RESULTS appended after the run.

**RESULTS (2026-06-01) — VERDICT: DEFER (pre-registered strict cross-site bar NOT cleared).**
All 6 sites captured, ok_routes=4 each, every bundle audited CLEAN; floor_a_determinism=TRUE.
Per-site (core / jac / distinct):

| site | L0 role | L1 +layout | L2 +token_ref |
|---|---|---|---|
| python.org | 3 / .51 / 1.00 ✓ | 3 / .51 / 1.00 ✓ | 1 / .27 / 1.00 |
| w3.org | 4 / .64 / 1.00 ✓ | 4 / .62 / 1.00 ✓ | 1 / .34 / 1.00 |
| djangoproject.com | 3 / .46 / 1.00 | 3 / .46 / 1.00 | 0 / .05 / 0 |
| gnu.org | 3 / .36 / 1.00 | 3 / .36 / 1.00 | 0 / .23 / 0 |
| iana.org | 1 / .30 / 1.00 | 1 / .30 / 1.00 | 0 / .02 / 0 |
| apache.org | 0 / .22 / 0 | 0 / .22 / 0 | 0 / .07 / 0 |

No enrichment level clears core≥3 ∧ jac≥0.5 ∧ distinct≥0.3 on EVERY site (`✓` = that site clears
at that level). role-only/+layout clears only python.org & w3.org (landmark-rich); django & gnu
miss jac (0.46/0.36); iana too sparse (core=1); apache has ZERO recurring landmark component at
depth=3 even role-only.

Findings (honest): (1) **The distinctiveness metric was VACUOUS** — distinct=1.00 in EVERY
core>0 cell (both clauses, depth≥2 and styled, held for every landmark root), so distinct≥0.3 is
subsumed by core≥3 and added zero constraint: the effective bar was core≥3 ∧ jac≥0.5. No
"recurring components are design-bearing" claim is drawn — the metric never discriminated, so
asserting one would repeat this session's over-read pattern. The blocker is RECURRENCE (core /
jac). (2) **token_ref (L2) collapses
recurrence everywhere** (core→0–1, jac→.02–.34) — re-confirms §C9-R-G3c-calib's
specificity↑⇒recurrence↓, now on the REAL production token_ref the in-memory aria probe could
not test; any future G3c MUST NOT key cross-route matching on token_ref. (3) **Cross-route
landmark recurrence is site-structure-dependent, not universal** (apache core=0 even role-only);
the strict bar is dominated by sparse/divergent sites exactly as pre-registered.

Decision: **G3c stays DEFERRED**, now with STRONGER evidence than §C9-R-G3c-calib — the landmark
anchor (the hypothesized rescue) still fails a strict cross-site recurrence bar. A general G3c
synthesizer is NOT justified. A future G3c would need a per-site richness/structure gate
(synthesize only on landmark-rich, structurally-stable sites — python/w3 clear) OR an explicitly
RE-REGISTERED looser bar (role-only/+layout; core≥3 alone, no jac floor ⇒ 4/6 clear
python/w3/django/gnu; core≥3 ∧ jac≥0.4 ⇒ 3/6 python/w3/django); bending the CURRENT bar is out. The §C9-R-aria `aria_role` primitive stays valuable for single-route
distinctiveness/anchoring regardless. Probe: `research/capture-gap-probes/probe_g3c_revisit.py`.

**§C9 ladder + roadmap status:** §C9 ladder + P4–P15 + G3a multi-route + G3a recurrence probe +
G3b token merge + ARIA-role enrichment landed. Cross-route ladder: recurrence probe → **G3b
DONE** → G3c component synthesis **DEFERRED (×2: §C9-R-G3c-calib coarse-vocab; §C9-R-G3c-revisit
landmark anchor fails strict cross-site recurrence bar)** → **ARIA-role enrichment LANDED
(§C9-R-aria)** → next candidates: G3d layout reconciliation, OR a richness-gated/re-registered-bar
G3c if pursued. Remaining: G3d; Regime-4b authored cascade [blocked]; pseudo-element GEOMETRY
follow-on; broader form-state family; G2 virtualization; G7a wrapper-virtualized scroll;
iOS/Android/Flutter native; firewall non-base64 data-URI hardening.

## §C9-R-G3d-dedup — VERDICT: DEFER (exact-lossless chrome dedup; gross median 6.1% < 12% bar) (2026-06-02)

G3d resolved (brainstorm) to its genuine §A0 G3 meaning — **shared-chrome dedup** (header/nav/
footer/aside recaptured per route), NOT G3c-style component synthesis. Dedup is **per-site and
opportunistic**, so it is NOT under the strict cross-site recurrence bar that DEFERRED G3c
(§C9-R-G3c-revisit) — that bar does not carry over. Open question: does identical landmark chrome
recur across a site's routes enough that storing it once (and referencing per route) yields
meaningful LOSSLESS node savings? G3c-revisit supplies the prior (role-only landmark core 3–4 on
landmark-rich sites = the chrome that would dedup).

Phase-1 throwaway calibration: `research/capture-gap-probes/probe_g3d_dedup.py` (reuses calib
`_children`; captures through PRODUCTION `site_capture`; content-free — mechanism keys only, every
bundle audited, prints counts/%/role-names/netloc/returncodes, never content/stderr). Phase-2
(the actual dedup into the pipeline: site-level `chrome.json` + per-route `chrome_ref`; downstream
resolve/expand the main risk) is a SEPARATE gated brainstorm→spec→plan→build cycle, only if this
clears.

**PRE-REGISTERED BAR + EXACT KEY (committed before any capture; not to be bent, and the key not
to be loosened, after the numbers are seen).** Sites: the 6 G3c-revisit sites. CHROME landmarks
(dedup-eligible) = aria_role ∈ {banner, navigation, contentinfo, complementary} (excludes main =
content + widget composites). **Exact-lossless subtree key** (recursive, full depth; equal key ⇒
design-identical ⇒ safe to store once), fixed field order per node: role | aria_role | layout.
{mode,direction,gap,pad,justify,align,grid_cols,grid_rows} | sizing.{w,h} | token_ref.{bg,fg,
border} | font.{family,weight} | text_len | pseudo(0/1) | substrate. EXCLUDED (volatile/positional,
restored on the reference): id, parent, bbox, z, sizing.confidence. **Savings = non-overlapping
TILING** (select the OUTERMOST chrome landmark whose key recurs occ≥2, don't descend into it;
descend elsewhere — avoids the banner⊃nav double-count), then Σ_key (m−1)·size for m≥2 selected
instances ÷ total nodes across routes; reported per-site. bbox-excluded ⇒ savings are GROSS (net
subtracts one stored bbox per reference — a Phase-2 detail). **VERDICT (opportunistic, NOT strict
cross-site):** BUILD iff median per-site pct ≥ 12 ∧ ≥3 sites ≥ 15%; else DEFER (legitimate honest
outcome). Needs ≥4 sites with data else INCONCLUSIVE. The strict key may mismatch on per-route
active state (aria-current/active-nav/breadcrumb); if that drives a DEFER, the honest next step is
a SEPARATELY-registered structural+deltas bar, not a quiet key relaxation. RESULTS appended after
the run.

**RESULTS (2026-06-02) — VERDICT: DEFER (pre-registered bar NOT cleared).** All 6 sites captured,
ok_routes=4 each, every bundle audited CLEAN; floor_a_determinism=TRUE. Per-site GROSS node-savings
(recurring chrome keys / deduped / saved / pct):

| site | recurring | deduped | saved | pct |
|---|---|---|---|---|
| w3.org | 5 | 3 | 266/1354 | 19.6% ✓ |
| apache.org | 2 | 2 | 236/1501 | 15.7% ✓ |
| python.org | 3 | 3 | 570/6583 | 8.7% |
| gnu.org | 3 | 3 | 102/2849 | 3.6% |
| iana.org | 0 | 0 | 0/864 | 0.0% |
| djangoproject.com | 0 | 0 | 0/3476 | 0.0% |

median_pct=6.1 (bar median≥12 ✗); sites≥15% = 2/6 (w3, apache) (bar ≥3 ✗) ⇒ DEFER (`✓` = site
clears the 15% floor).

Findings (honest; ablation = per-site recurring chrome-keys under full / token_ref-dropped /
text_len-dropped key): (1) **Blocker on the zero-savings sites = token_ref per-route ASSIGNMENT
instability, NOT chrome content variation.** iana 0/2/0 and django 0/2/0 — dropping token_ref alone
takes both 0→2 recurring keys; dropping text_len does nothing. Their banner/contentinfo ARE
structurally identical across routes but get DIFFERENT palette-role labels per route, because
token_ref is assigned post-bundle via `_nearest_role` against EACH route's OWN palette — a
capture-pipeline artifact that poisons the exact key. (An earlier "active-nav/breadcrumb variation"
reading was WRONG — advisor-caught; the evidence is token_ref, not nav state.) text_len is a minor
secondary factor (w3 5→6, gnu 3→4 when dropped) = genuine small content variation. python/w3/apache
are unaffected by either ablation — their dedup is bounded by chrome size vs route-content weight,
not key instability. **Cross-ref (scoped — checked against the ablation, not assumed):** on the
sparse, token_ref-unstable sites (iana/django) this assignment artifact MAY also contribute to
§C9-R-G3c-revisit's L2 collapse. It does NOT generalize: on landmark-rich python the G3d ablation is
3/3/3 (token_ref STABLE for its chrome) yet python's G3c-revisit L2 still collapsed (core 3→1) —
that collapse is GENUINE specificity↑⇒recurrence↓, not the artifact. So stabilizing token_ref would
NOT rescue G3c component recurrence on rich sites; the §C9-R-G3c-revisit specificity finding stands.
(2) **Savings shrink with
route content weight** — python.org 2-route smoke 23.1% → 4-route 8.7%: chrome is a smaller fraction
of node count on content-heavy routes, so exact-dedup % is route-mix-dependent, not a pure
chrome-identity property. (3) bbox excluded ⇒ figures are GROSS (net subtracts one stored bbox per
reference). (4) Floor-A deterministic.

Decision: **G3d exact-lossless shared-chrome dedup DEFERRED** — gross median 6.1% (<12%); only
w3.org & apache.org clear the 15% floor. Honest evidence-based next-step ranking (none is loosening
the pre-registered key here; each separately registered if pursued): (a) FIRST lever =
**cross-route token_ref assignment stability** (the artifact above — stabilize palette-role labels
site-wide, or exclude token_ref from a dedup key); but the ablation shows it yields only MODEST
recurrence (iana/django rescue to just 2 small keys), so it removes an artifact WITHOUT clearing the
bar on its own. **[2026-06-02 follow-up — token_ref stability investigated as its own rung and
DEFERRED:** `grep token_ref scripts/` shows NO live cross-route node-level consumer — slots.py reads
it per-route only (→ theme_ref, no cross-route compare); G3b merges per-route PALETTES (role→hex),
not per-node token_ref; only the DEFERRED G3c/G3d probes compare it cross-route. Floor-A=TRUE ⇒
token_ref is deterministic and route-relative BY DESIGN, not a bug. Reassigning against the site
palette is a semantic CHANGE with no consumer to benefit until G3c/G3d un-defer; parked until
then.]** (b) **structural+deltas** dedup (the §A0 "structural" path) remains the
higher-savings option. The exact-lossless floor is now known: it pays off only where chrome is
byte-stable (modulo the token_ref artifact) AND routes are chrome-heavy (w3/apache). Probe (with the
field-ablation diagnostic): `research/capture-gap-probes/probe_g3d_dedup.py`.

**§C9 ladder + roadmap status:** §C9 ladder + P4–P15 + G3a multi-route + G3a recurrence probe + G3b
token merge + ARIA-role enrichment landed. Cross-route ladder: recurrence probe → **G3b DONE** →
G3c component synthesis **DEFERRED ×2** → **ARIA-role enrichment LANDED (§C9-R-aria)** → G3d
shared-chrome dedup **DEFERRED (exact-lossless; §C9-R-G3d-dedup: gross median 6.1% < 12% bar — chrome
not byte-stable across routes)**. Cross-route MERGE ladder now exhausted at the exact/strict tier
(G3b token merge is the one landed win; G3c components and G3d chrome both DEFER under
strict/lossless bars). Open continuations (each needs its OWN pre-registered bar if pursued):
structural+deltas chrome dedup; richness-gated G3c; nav/site graph (§A0 other half). Remaining:
Regime-4b authored cascade [blocked]; pseudo-element GEOMETRY follow-on; broader form-state family;
G2 virtualization; G7a wrapper-virtualized scroll; iOS/Android/Flutter native; firewall non-base64
data-URI hardening.

## §C9-R-G3-wire — Cross-route post-processors wired into site_capture (opt-in) (2026-06-02)

`site_capture.py` gains `--merge` / `--dedup` (default OFF): after the capture + site-root
firewall backstop, it subprocess-invokes the shipped `site_merge.py` (→ design_system.json)
and/or `site_chrome.py` (→ chrome_dedup.json) over the finished dir. Applicability is gated on
`ok_count` (merge ≥1, dedup ≥2) — too-few-routes → `skipped` WITHOUT invoking; once invoked,
ANY nonzero child exit is loud (`leak` exit-3 firewall → site_capture exit 3, `error` otherwise
— incl. site_chrome's exit-2 losslessness gate — → site_capture exit 1). Stops on first leak;
clean route bundles + site.json are preserved. `capture_site()` is unchanged; each
post-processor's own `audit_bundle` re-covers the whole tree (no firewall gap). Realizes the
value of the G3b/G3d CLIs from the orchestrator without changing default behavior.
Tests: `scripts/test_site_capture_post.py` (8 tests). Function: `run_post_processors`.

## §C9-R-G2 — Virtualization de-risk: BUILD-JUSTIFIED, scoped to APPEND-class (2026-06-02)

Pivoted off the exhausted cross-route dedup ladder to the standout open MAJOR gap (§B #2): a single
REST `DOMSnapshot` misses content that lazy-mounts on scroll. Bar PRE-REGISTERED before any data
(`docs/plans/g2-virtualization-derisk.md`), measured on the basis a content-free BUILD would ship —
a per-step UNION over the project's content-free **shape-key** (`probe_g3d_dedup._node_key`), counting
`new_shapes` = distinct shapes the sweep reveals that REST lacks (NOT raw node growth: a feed of
identical items is one shape, and a content-free engine dedups instances anyway). Probe:
`research/capture-gap-probes/probe_g2_virtualization.py` (HOST CDP :9222, bounded 8-step scroll-settle
sweep, RE-RUN AFTER A FRESH `navigate()` for true cross-load reproducibility, every per-step skeleton
firewall-audited AFTER `cf.redact_node` = the shipped artifact). Results (`out/g2_virt.json`, run 3 —
the methodologically clean run):

| site | class | sh/ih | peak×rest | new/rerun | frac | repro | fw | gate |
|---|---|---|---|---|---|---|---|---|
| youtube home | virt | 4601/913 | ×1.75 | **51**/44 | 0.34 ✓ | 0.137 ✓ | 0 | PASS |
| reddit `/r/popular` | virt | 3014/913 | ×4.22 | 90/36 | 0.709 | **0.60 ✗** | 0 | fail-repro |
| infinite-scroll demo | virt | 3420/913 | ×1.30 | **27**/27 | 0.474 ✓ | 0.0 ✓ | 0 | PASS |
| wikipedia/Cat (neg) | neg | 35453/913 | ×1.23 | 5/5 | 0.009 ✓ | 0.0 | 0 | discriminates |

**Verdict: BUILD-JUSTIFIED** — 2/2 in-class pass-sites (youtube home + append demo) clear
`new_shape_frac≥0.30 ∧ new_shapes≥25 ∧ repro≤0.20`; negative control discriminates (`0.009 < 0.10` —
raw nodes grew ×1.23 from lazy images but new STRUCTURE ~0); 0 firewall violations. The append-class
GAP IS ROBUST: across 3 runs the sweep always recovered substantial new content-free shapes (youtube
51–76, demo 27, reddit 16/4/90), content-free and firewall-clean. **Honest thinness (stated once):**
only 1 of the 2 pass-sites is a real-world app (youtube home, frac 0.34, intermittent consent); the
other is a synthetic demo — the de-risk's question ("real, capturable, content-free gap?") is robustly
YES, but real-world breadth is thin and is carried forward to the BUILD bar below. Scope facts the de-risk surfaced
(real BUILD constraints, NOT gap refutations):
1. **Reproducibility is the live discriminator, not append-vs-windowed.** Once the repro leg used a
   real reload (not a `scrollTo(0)` reset — see integrity note), repro_delta SPREAD (0.0 / 0.137 /
   0.60). The synthetic append demo is deterministic (0.0); youtube intermediate (0.137); the **Reddit
   feed is non-reproducible load-to-load** (0.60; new 90 vs 36 same session, 16/4/90 across runs) — so
   there is **no honest fixed-step sweep contract for live feeds**, regardless of mechanism. (Reddit's
   peak swung ×1.02→×4.22 between runs, which is exactly that non-determinism — superseding an earlier
   single-load "windowed, gains nothing" read.) Feed content variability is the BUILD's central risk.
2. **Consent gating is real but NONDETERMINISTIC.** youtube.com home was `sh==ih==913` (consent overlay
   locks scroll → out-of-class) in two earlier runs but scrollable here. The default capture path
   (`site_capture`→`web_skeleton`→`navigate`) does NOT dismiss overlays (`_consent` is used ONLY by the
   separate `web_states` G6 verb — code-confirmed), so a G2 sweep wired there inherits the lock whenever
   it fires. Realized BUILD value on consent-gated feeds is gated on G6 consent being wired first.

The BUILD bar (sweep-merge engine: realized faithful-skeleton gain on append-class routes, NET of
cross-snapshot merge cost + the content-free node-identity the merge must solve under scroll-shift, AND
robust to per-load feed variability) is a SEPARATE pre-registration if pursued — it does not carry over.
It MUST require ≥2 **stable real-world** append sites (not synthetic, not consent-flaky) to clear —
closing the real-world-breadth thinness this de-risk leaves open.

**Integrity notes (two corrections made DURING the de-risk, neither moved a threshold):**
- Run 1 DEFERRED (1/2) because a probe bug returned on YouTube-home's out-of-class skip without trying
  the PRE-REGISTERED watch fallback; fixing the fallback iteration let the canonical site be measured.
- Run 2's `repro 0.0` was a TAUTOLOGY — the repro leg reset with `scrollTo(0)`, leaving sweep-1's append
  content mounted, so the rerun re-saw everything. Run 3 re-navigates between sweeps, making repro
  measure real cross-load stability (the same proxy-validation trap as the G3d `.keys()` gate). The
  verdict held (append gap real, margin adequate) but the evidence is now honest, not self-confirming.

### §C9-R-G2 BUILD ship-test — DEFER (engine faithful; de-risked gain did not reproduce) (2026-06-02)

The BUILD engine was implemented TDD against the locked ship bar (`docs/plans/g2-virtualization-build.md`)
and landed behind an opt-in `--sweep` flag (commits `701d391`→`e027e65`; canonical `_shape_key` single
source `f1c6d60`). All DETERMINISTIC conditions hold: content-free by closed whitelist (adversarial probe
drops text/href/src/style), idempotent/deterministic merge, firewall canary trips, **default contract
byte-identical (condition 6), full suite 513 green**. The LIVE payoff legs (cond 1 realized gain ≥25 on
the produced on-disk artifact; cond 5 neg control) were run on a debug Chrome.

**Decisive same-session probe-vs-engine test** — isolates engine gain-collapse from capture regime (both
use canonical `_node_key` + union-minus-rest), demo `infinite-scroll.com/demo/full-page/`, ONE headless
`--headless=new` Chrome, back-to-back (`/tmp/g2_decisive.py`):

| leg | load | new_shapes | rest_shapes | repro |
|---|---|---|---|---|
| probe (de-risk path) | 1 | **31** | 57 | — |
| probe re-run (fresh navigate) | 2 | **17** | 57 | **repro_delta 0.452** (locked max 0.20 ✗) |
| engine (`web_skeleton --sweep`, on-disk artifact) | 3 | **17** | 57 | — |

youtube `/watch` cleared cond1 (≥25) this headless run; wikipedia neg `new_shapes=1`; firewall 0 all 3 sites.

**Engine collapse REFUTED (high-value):** the engine's on-disk `below_fold.new_shapes` (17) EQUALS the
probe's same-regime re-run (17) — the `sweep_skeletons` port + `merge_skeletons` faithfully carry the
probe's exact in-regime gain. The 31→17 swing is LOAD-TO-LOAD variance WITHIN the probe, not an
engine-vs-probe gap. So the DEFER clause's *example* ("merge dedups the gain away / shape-key parity
breaks") is refuted.

**But the DEFER clause's DEFINITION is met** — "measured gain not realizable on the produced artifact":
the artifact shows `new_shapes=17 < 25` (cond1 ✗) AND the underlying gain fails the locked
`REPRO_MAX=0.20` (`repro_delta=0.452`). The de-risk's recorded demo `27 / repro 0.0` (run-3 "clean") DID
NOT REPRODUCE here (`17 / 0.452`). The de-risk capture REGIME is **undocumented** (no headed/headless
record in the de-risk doc or probe; presumed a manual debug tab per memory `cdp-capture-needs-open-tab`,
**UNVERIFIED**) — so the gain is regime-fragile, confirming the **thin real-world stability the de-risk
explicitly carried forward**. The demo is also synthetic — the de-risk itself required ≥2 STABLE
REAL-WORLD append sites, which the BUILD bar's demo+youtube choice never met.

**VERDICT: DEFER** — engine does not ship as a validated capability; finding recorded, per
pre-registration (no goalpost-move from 25→17, no headed variance-fishing for a favorable draw). The
engine code remains LANDED but DORMANT behind opt-in `--sweep` (default off; zero effect on the default
contract — condition 6 proven). It is NOT a claimed capability.

**Reopen criteria (pre-committed — a single favorable draw is NOT a pass):** (1) VERIFY the de-risk
capture regime (headed vs headless) and explain the `repro 0.0 → 0.452` divergence; (2) PRE-COMMIT the
full criterion — `new_shapes ≥ 25` AND `repro_delta ≤ 0.20` over N predefined loads — on **≥2 stable
real-world append sites** (not the synthetic demo, not consent-flaky youtube), BEFORE measuring.

**Harness bug (fixed `c106e84`, not verdict-affecting):** `scripts/livesmoke_g2.py` `_new_shapes`
computed the neg denominator as distinct ROLES (wikipedia=4) not distinct shape-keys (=57) — a spurious
cond5 fail. The decisive verdict above used the probe's correct `len(rest_shapes)` denominator (57).

**Reframe (not a re-run of the sweep):** the DEFER motivated a pivot from *counting* below-fold shapes
(variance-prone) to a STATIC *scroll-region flag* derived from `scrollRects`/`clientRects` already in the
captured snapshot (verified populated 2026-06-03). Pre-registered: `docs/plans/scroll-region-flag-prereg.md`.

## §C9-R-G4 — Hover / non-ARIA trigger de-risk: DEFER (real triggers are ARIA-covered; non-ARIA ones aren't content-free-findable) (2026-06-02)

The §C9-R(P1) G4 `web_states` writeup named the follow-up verbatim: the trigger scan is
explicit-ARIA-affordance only (`[aria-haspopup],[aria-expanded],summary,[role=menu]` + `el.click()`);
**hover-only menus and JS-custom no-ARIA triggers are not scanned**. De-risked it. Bar PRE-REGISTERED
before any data (`docs/plans/g4-hover-trigger-derisk.md`), on the basis a content-free BUILD ships: the
`_states.diff_skeletons` APPEARED unit + the shape-key (`probe_g3d_dedup._node_key`). `new_shapes` =
distinct content-free shapes a detector reveals that REST AND the existing ARIA scan do NOT. Two
detectors measured separately (advisor-sharpened): **L** = drive only candidates whose CDP
`DOMDebugger.getEventListeners` shows a click/hover listener (content-free-clean; a plain `<a href>` has
no listener → excluded → honest precision); **H** = brute CDP `Input.dispatchMouseEvent` hover-sweep over
every `cursor:pointer` candidate (catches pure-CSS `:hover` menus L misses — the hard tail). Probe:
`research/capture-gap-probes/probe_g4_hover.py` (HOST CDP :9222; CSS `:hover` driven via CDP Input NOT a
JS dispatch — the pinned anti-tautology; every per-state skeleton firewall-audited AFTER `cf.redact_node`
= the shipped artifact). Results (`out/g4_hover.json`):

| site | kind | rest | ARIA trig/appeared | cursor:ptr cand | L drv/hit/new | H drv/hit/new | fw | read |
|---|---|---|---|---|---|---|---|---|
| R1 bootstrap (dropdowns/navbar) | real | — | **50** / **21** (all ARIA-drivable) | 531 / 511 (>cap) | direct-listener ~4% only† | **sweep timeout (900s)** | — | **ARIA-covered**; brute sweep doesn't scale |
| R2 mdn | real | 622 | 9 / 472 | 96 | 1/0/**0** | 96/0/**0** | 0 | **ARIA-covered**; extension adds nothing |
| R3 hn | real | 1240 | 0 / 0 | 284 | 0/0/**0** | 284/0/**0** | 0 | **empty**; no interaction state to reveal |
| F1 hover-menu | fixture | 13 | 0 / 0 | 6 | 2/2/1 | 6/4/1 | 0 | detectors fire (existence-proof only) |
| N1 static-neg | neg | 18 | 0 / 0 | 5 | 0/0/0 | 5/0/0 | 0 | discriminates (`< NEG_MAX=10`) |

†Bootstrap fast-characterization (navigate + `_AFFORD_JS` count + per-candidate `getEventListeners`, no
full sweep): of 200 non-ARIA `cursor:pointer` candidates, only 3 click + 5 hover direct listeners
(dropdowns) / 10 click + 6 hover (navbar). The rest are href-nav or **event-delegated** (handler on a
container/`document`, invisible to per-node `getEventListeners`).

**Verdict: DEFER** — 0 of `MIN_REAL_PASS_SITES=2` real pass-sites (needed `new_shapes_L ≥ 25 ∧
precision_L ≥ 0.20`). Determined independently of Bootstrap: MDN and HN are clean `new_shapes_L=0`
measurements, so no pass is reachable regardless of the Bootstrap timeout. **NOT the G2 run-1 trap** (that
was a probe bug inverting a *real* pass; here two clean zeros foreclose any pass). The two PRE-REGISTERED
crux risks BOTH fired — this is the load-bearing finding, do not collapse it to one:

1. **Prevalence.** a11y adoption put real interaction triggers behind ARIA, which the *existing* scan
   already captures. MDN: 9 ARIA triggers reveal 472 nodes. Bootstrap: 50 (dropdowns) + 21 (navbar) ARIA
   triggers, ALL drivable by `_AFFORD_JS` (its toggles carry `aria-expanded`/`aria-haspopup` at rest). HN
   has none at all. The pre-registered "strongest positive" (Bootstrap) is itself ARIA-covered.
2. **Content-free findability + cost (the deeper reason).** The precise per-node detector
   (`getEventListeners`) is defeated by **event delegation + href-nav**: ~1–4% of non-ARIA
   `cursor:pointer` candidates have ANY direct listener (MDN 1/96, HN 0/284, Bootstrap ~8/200). The brute
   hover-all fallback that doesn't need listeners found **0 new reveals on every real site** AND **does
   not scale** — Bootstrap's 531 candidates × (hover-settle + listener probe + reveal-snapshot) exceeded
   900s. A content-free engine cannot cheaply find these triggers without reading class/text semantics (a
   firewall violation) — the named blocker, analogous to G2 instance-identity. Precision was never the
   binding constraint (it stayed undefined/0 because the detector found almost nothing to drive).

**Logged limitation (NOT a silent drop):** R1-bootstrap's full candidate sweep timed out (330s in the
batch, then 900s standalone) — its non-ARIA reveal count is unmeasured by the full probe. It is
characterized instead by the fast ARIA-coverage + direct-listener count above, which is sufficient to
place it in the "ARIA-covered" column; the timeout cannot change the verdict (already 0 pass-sites from
MDN+HN). The timeout is itself crux-(2) evidence: brute hover-all is too costly on candidate-heavy pages.

**Honest scope:** the de-risk's question ("is there a real, content-free-capturable hover/non-ARIA
trigger gap the ARIA scan misses?") is robustly **NO** on the measured real cohort — the gap the §C9-R
follow-up note anticipated has largely been closed by a11y adoption (real triggers carry ARIA) and what
remains (delegated/href interactivity, pure-CSS hover) is not content-free-findable per-node and not
worth a brute sweep that itself doesn't scale. The fixture proves the *mechanism* works when the pattern
is present (CDP-Input hover drives CSS `:hover`; `getEventListeners` finds JS listeners), so a future
BUILD is not blocked by mechanism — it is DEFERRED for lack of a real-world target population. If
revisited, the BUILD bar MUST first show ≥2 real sites with a material non-ARIA reveal population (this
de-risk found none), and must solve content-free trigger detection under event delegation.

**Cohort caveat (stated once):** the 3 real sites skew developer-docs / a11y-modern / static
(Bootstrap-docs, MDN, HN) and under-sample the habitat where hover-mega-menus most plausibly still live —
e-commerce / marketing nav. The primary reason ("largely closed by a11y adoption") generalizes from a
sample that under-represents the gap's natural home; carried forward, not re-measured (expanding the
locked cohort post-hoc would corrupt the pre-registration). Crux-(2) — delegation + brute-sweep cost —
would bite an e-commerce cohort too, but a BUILD-revisit should sample that habitat first. And the 900s
timeout indicts the *brute probe* (hover every `cursor:pointer`), NOT a targeted BUILD that hovered only
nav-region elements — "doesn't scale" ≠ "a faithful BUILD can't."

## §C9-R-G3c-rg — VERDICT: DEFER (richness-gated rescue falsified; rich-but-not-recurrent, and recurrence that survives is 100% chrome) (2026-06-03)

The richness-gate rescue that §C9-R-G3c-revisit explicitly named ("a future G3c would need a per-site
richness/structure gate — synthesize only on landmark-rich, structurally-stable sites") — built,
pre-registered, and run. This re-registers a *stricter, value-anchored* bar (novelty ∧ coverage), NOT a
looser one. Pre-registration: `docs/plans/richness-gated-g3c-design.md` (+ spec `…-design.md`, plan
`docs/plans/richness-gated-g3c.md`). Probe: `research/capture-gap-probes/probe_g3c_richness_gated.py`
(+ 17-test unit suite). Reuses calib `signature`/`recurrence`/`_is_styled`/`_children`; landmark-anchored
roots; captures through the PRODUCTION `site_capture` path. Content-free: mechanism keys only; every bundle
audited; prints counts / jaccard / role NAMES / netloc / returncodes only.

**PRE-REGISTERED BAR (committed before any capture; not bent after the numbers).** Fixed knobs: depth=3,
policy="collapse", signature levels {0:role, 1:+layout} — **token_ref EXCLUDED** (proven recurrence-collapsing
in §C9-R-G3c-revisit). GATE (per site): gated-in iff best of {role,+layout} clears core≥3 ∧ jac≥0.5. RICHNESS
predicate (home, at-rest): ≥4 distinct landmark roles ∧ ≥8 repeated styled subtrees. composition-NOVEL: a
recurring (≥2 routes) landmark subtree, styled root, ≥2 styled children spanning ≥2 DISTINCT roles, generic
wrapper excluded (depth-bounded to the signature window so novelty = f(signature)). COVERAGE: styled
main-content (minus chrome-landmark subtrees) attributable to a novel component, **median** over a site's
gated routes. VERDICT: validity (≥4 rich gate in, else DEFER-as-finding) → neg-control (0 of 6 docs controls
clear novel≥5 ∧ cov≥0.15, else DEFER) → positive (≥3 rich clear, else DEFER) → BUILD. Frozen cohort: 6 docs
controls (python/iana/django/w3/gnu/apache) + 8 rich (mui/ant/getbootstrap/carbon/primer/chakra/stripe/vercel),
4 routes each. No cohort expansion. **Pre-data correction (legit, before any capture):** a final code-vs-SPEC
review caught the plan transcribing coverage as a MEAN (spec §5 = MEDIAN; mean biases toward BUILD) and an
unbounded novelty scan vs the depth-3 signature key (route-order non-determinism); both fixed pre-capture —
see memory `subagent-review-code-vs-spec-not-just-plan`.

**Capture regime (recorded per memory `derisk-must-record-capture-regime`).** Isolated fresh-profile Chrome
on **:9333** (`--user-data-dir=/tmp/g3c-rg-chrome`, throwaway), NOT the user's browser. The first attempts hit
`skeleton_failed` because the launched instance had ZERO page targets (only service_workers) — the
`cdp-capture-needs-open-tab` gotcha; resolved by creating a page target via CDP `/json/new?about:blank`.
**floor_a_determinism = TRUE** (mui.com, |A|=|B|=5, identical). Every bundle audited CLEAN. Two captures came
back incomplete — **ant.design 3/4, chakra-ui.com 2/4** (home-route warning fired; §3c richness scored on the
first ok route). The verdict is **robust to both**: ant gated out far from the bar (core=1/jac=0.18), chakra was
excluded on the richness predicate (lm=3<4) — neither could have gated in with a complete capture, so DEFER is
not a capture artifact.

**RESULTS (2026-06-03) — VERDICT: DEFER (DEFER-as-finding on the validity clause).** Per site —
rich(lm,rep) · gated(level,core,jac) · novel · coverage:

| site | richness (lm / rep) | gated (L,core,jac) | novel | cov |
|---|---|---|---|---|
| **controls** | | | | |
| python.org | rich (5 / 27) | **IN** (L0, 3, .51) | 3 | 0.000 |
| w3.org | rich (5 / 19) | **IN** (L0, 4, .64) | 2 | 0.000 |
| djangoproject.com | rich (5 / 15) | out (L0, 3, .46) | 0 | 0.000 |
| gnu.org | rich (6 / 19) | out (L0, 3, .36) | 0 | 0.000 |
| iana.org | not rich (2 / 8) | out (L0, 1, .30) | 0 | 0.000 |
| apache.org | not rich (3 / 25) | out (L0, 0, .22) | 0 | 0.000 |
| **rich candidates** | | | | |
| mui.com | rich (5 / 52) | out (L0, 1, .39) | 0 | 0.000 |
| ant.design ⚠3/4 | rich (5 / 60) | out (L0, 1, .18) | 0 | 0.000 |
| getbootstrap.com | rich (5 / 70) | out (L0, 6, .44) | 0 | 0.000 |
| carbondesignsystem.com | rich (4 / 45) | out (L0, 2, .40) | 0 | 0.000 |
| stripe.com | rich (5 / 98) | out (L0, 3, .33) | 0 | 0.000 |
| vercel.com | rich (4 / 55) | **IN** (L1, 4, .56) | 0 | 0.000 |
| primer.style | not rich (3 / 22) | excl (richness) | — | — |
| chakra-ui.com ⚠2/4 | not rich (3 / 32) | excl (richness) | — | — |

`controls_clearing = 0 · rich_gated = 1 · rich_clearing = 0.`

Findings (honest): **(1) Rich-but-not-recurrent (the verdict).** Of the 8 frozen rich candidates, **6 passed
at-rest richness** (rep 52–98 repeated styled subtrees — these ARE component-dense pages), yet **only 1
(vercel) gated in** on cross-route recurrence (validity threshold ≥4). Pre-selected, component-rich
design-system sites do not exhibit cross-route landmark-component recurrence — at-rest density and cross-route
recurrence are different things, and the value thesis needs the latter. This is the §C9-R-G3c-revisit "the
blocker is RECURRENCE" result, now confirmed on the habitat hand-picked to beat it. **(2) The recurrence that
DOES survive the gate is 100% chrome (MEASURED, not inferred).** The 3 gated-in sites' novel components are
ALL chrome landmarks: python.org 3/3 (banner, contentinfo, navigation), w3.org 2/2 (banner, navigation), 0
main-content either — so cov=0.000 because coverage deliberately excludes chrome (header/nav/footer = G3d's
turf). And vercel, the lone rich site that gated in (core=4, jac=.56), yields **novel=0** outright — no
main-content composition at all. Coverage is 0.000 on EVERY site in the cohort. There is no main-content
recurring-component population for a G3c synthesizer to capture on top of G3b's flat tokens. **(3)
Discrimination held.** `controls_clearing=0`: no docs control false-cleared the value bar (the metric did not
mistake chrome-recurrence for value). **(4) High core ≠ pass.** getbootstrap had core=6 but jac=0.44 — a shared
docs skeleton plus route-unique component bodies; recurrence as a *ratio* (jac) is the discriminator, not raw
shared count. token_ref stays excluded per the revisit.

Decision: **G3c stays DEFERRED (×3)** — §C9-R-G3c-calib (coarse vocab), §C9-R-G3c-revisit (landmark anchor
fails strict cross-site recurrence), and now §C9-R-G3c-rg (the richness-gate rescue itself falsified). The two
escape hatches the revisit left are now closed by data: the per-site richness gate does NOT find a
BUILD-qualifying habitat even among hand-picked component-rich sites, and the only cross-route recurrence that
exists is chrome — already G3d's domain. A general OR richness-gated G3c synthesizer is **NOT justified**; its
marginal value over G3b's flat `design_system.json` is unmeasurable (coverage 0 everywhere). The sole remaining
theoretical path — an explicitly RE-REGISTERED looser recurrence bar — is noted, not pursued; bending the
current bar is out. The G3c Phase-2 synthesizer is **not opened.**

**§C9 ladder + roadmap status:** §C9 ladder + P4–P15 + G3a multi-route + G3a recurrence probe + G3b token merge
+ ARIA-role enrichment + structural chrome-delta dedup (G3d structural-deltas) landed. Cross-route ladder:
recurrence probe → **G3b DONE** → G3c component synthesis **DEFERRED ×3 (§C9-R-G3c-calib coarse-vocab;
§C9-R-G3c-revisit landmark-anchor recurrence; §C9-R-G3c-rg richness-gate rescue falsified — rich-but-not-
recurrent, recurrence-that-survives is 100% chrome)** → G3d shared-chrome dedup (exact-lossless DEFERRED
§C9-R-G3d-dedup; structural-deltas BUILT). The G3 cross-route ladder is now **closed at the component rung**:
G3b (tokens) ships, G3c (components) is thrice-deferred with converging evidence, G3d (chrome) handled by
structural-deltas. Remaining roadmap (not started): nav/site graph; G2 virtualization; G4 hover/non-ARIA
triggers [DEFERRED §C9 G4-hover]; iOS/Android/Flutter native.

## §C9-R-G2b — Sharpened static scroll-region flag: DEFER ×3 (falsified at the pre-code gate; the only static separator is anti-correlated with the target) (2026-06-03)

Second, SHARPENED attempt at the static scroll-region flag (the first, §C9-R-G2 reframe →
`scroll-region-flag-prereg.md`, DEFERRED on the wikipedia false-positive). The prior doc prescribed the
retry: a fresh discriminator + multiple neg controls + multiple real feeds. Chosen discriminator
(brainstorm): **composed-item ∧ homogeneity** — flag a node iff its direct children are dominated by one
repeated STRUCTURAL-only shape-key (text-blind: role+layout+sizing, no `text_len`) AND the repeated item is
a composed subtree (`_has_composition`: ≥2 styled children spanning ≥2 distinct roles, not text-only).

**Falsify-FIRST (the prereg's own gate; orientation, BEFORE any code).** Throwaway characterization
(`/tmp/g2sr_characterize.py`) on an isolated fresh-profile Chrome `:9333` (page target via CDP
`/json/new`), captured through the PRODUCTION redacted `site_capture` path (every skeleton firewall-audited
CLEAN). Per site, the dominant ≥3-child item-list: `frac` = maxgroup/total over direct children (structural
key), `composed` = `_has_composition` on the dominant template, `dom` = item-list bbox-height / page-height
(a static dominance proxy — no scrollRects needed for the falsification). Content-free: fractions / counts /
role NAMES only.

| site | class | top item-list (frac / composed / dom) | read |
|---|---|---|---|
| books.toscrape (grid) | POS | 1.00 / **False** / 0.80 | strongest real grid — composed MISSES it (cards = `unknown_box`) |
| quotes.toscrape (list) | POS | 0.91 / False / 0.21 | uniform list; composed also False |
| infinite-scroll demo | POS (real feed) | 0.50 / 0.26 (best) | heterogeneous posts — LOW homogeneity |
| news.ycombinator (rows) | NEG/feed | 0.34 / False / 0.88 | real story list — LOW homogeneity |
| wikipedia/Cat | NEG-doc | hi-frac lists dom≈0.00; dom=0.40 content frac=0.07 | no node has high frac AND high dom |
| docs.python tutorial | NEG-docs | 0.60 / 0.12 (best) | low dominance |

**VERDICT: DEFER ×3 — the static reframe is closed.** Two independent failures, both structural (not
threshold misses):

1. **composed-by-role is defeated by the sparse role vocabulary.** Real product cards (div-soup) enrich to
   `role=unknown_box`, so `_has_composition`'s ≥2-DISTINCT-roles test returns **False on the strongest real
   positive** (books grid, frac 1.00). The same "everything is `unknown_box`" wall that bounded G3c
   (§C9-R-G3c-rg). A role-diversity composition test cannot run where the engine assigns no roles.
2. **The only surviving separator (homogeneity) is ANTI-CORRELATED with the target.** `frac` is HIGHEST on
   fully server-rendered uniform catalogs (books 1.00, quotes 0.91 — which have **zero** below-fold gap, all
   items already in the DOM) and LOWEST on the actual virtualized/feed cases (infinite-scroll demo 0.50/0.26,
   HN 0.34 — heterogeneous real feeds). The signal **fires where there is no G2 gap and misses where there
   is one.** This is memory `g2-virtualization-append-vs-windowed` / `falsify-detection-signal-on-real-neg-controls-before-code`
   ("repeated-structure ≠ feed") confirmed empirically. No threshold rescues an anti-correlated signal; and
   `dom≥0.2` would be eyeballed from this very data (post-hoc tuning the prereg forbade).

**Structural root cause (the durable, threshold-independent finding):** a single static snapshot **cannot
observe "content missing below fold"** — that property is DYNAMIC by definition. Every static proxy tried
across both attempts (scroll-rect ratio §C9-R-G2 reframe; homogeneity + composed here) ends up selecting for
uniform static *structure*, which is the opposite of the heterogeneous, partially-mounted feeds G2 targets.
The static reframe cannot escape this; it is not a signal-tuning problem.

**Discipline note (this is the good outcome):** the falsify-before-code gate did its job — **zero feature
code written**, DEFER decided from one content-free characterization read. No spec, no `parse_snapshot`
change, no classifier. Honest thinness (recorded, not hidden): positives skew to `toscrape` scraping
sandboxes + a synthetic demo, and `dom` is a render-height proxy not `scrollRects` — but the two failures are
structural (role-vocab absence; homogeneity anti-correlation; static-can't-see-dynamic), so no richer cohort
or real-rect measurement reverses them. Not pursued further.

**§C9 ladder + roadmap status:** G2 virtualization is now DEFERRED on ALL paths — sweep-merge recovery
(§C9-R-G2 ship-test: engine landed-but-dormant behind opt-in `--sweep`, regime-fragile gain) AND the static
flag (§C9-R-G2 reframe wikipedia false-positive; §C9-R-G2b sharpened signal anti-correlated). Reopening G2
would require either the sweep engine's pre-committed reopen criteria (≥2 STABLE real-world append sites,
which the evidence says don't exist) OR a fundamentally non-static virtualization observation (a live
mounted-vs-total probe — the variance that DEFERRED the sweep). Remaining roadmap (not started): nav/site
graph; G4 hover/non-ARIA triggers [DEFERRED §C9 G4-hover]; iOS/Android/Flutter native.

## §C9-R-NG — Nav/site graph: scoped to nav-link annotation (content site-graph empty by construction) (2026-06-03)

The last unbuilt G3 rung (§A4: "shared-chrome dedup + a nav/site graph"). Content-free characterization
read BEFORE any spec (G3c cohorts, MPA python/w3/django + SPA mui/stripe/vercel, 4 routes each; eval
`a[href]`, resolve to the captured route set, classify chrome-vs-content; counts only, no hrefs printed):

| site | anchors | resolved→other chrome | resolved→other CONTENT |
|---|---|---|---|
| python.org | 1610 | 45 | 0 |
| w3.org | 371 | 19 | 5 |
| djangoproject.com | 435 | 21 | 4 |
| mui.com (SPA) | 345 | 11 | 3 |
| stripe.com (SPA) | 1107 | 1 | 0 |
| vercel.com (SPA) | 489 | 12 | 0 |

**Finding (scope, not DEFER): the content-level site graph is empty BY CONSTRUCTION, but the
nav-annotation floor is real.** Intra-set is nav-dominated because users pick `--urls` = the nav
destinations → nav links resolve circularly while content cross-links point to un-enumerated pages and
drop as external (content cell: 12 edges / 24 routes, 0.5/route). The chrome cell is populated on every
site incl. SPAs (SPA `<a href>` resolve — no href sparsity). So there IS a content-free, reproduction-
useful deliverable — annotate the deduped G3d chrome nav's anchors with target `route_id`s (today those
links point nowhere, hrefs stripped) — but it is **nav annotation, not a site graph**. A real content
site map needs crawl-discovery (unbounded + ships discovered URLs = content-free tension) — out of scope.

**Decision: BUILD the nav-annotation floor** (not a DEFER — the content-free floor is real and measured).
Design: `docs/plans/nav-link-route-annotation-design.md`. Ships `nav_edges` in `site.json`
(`{src, dst, src_node, chrome}` — route_ids + the stable skeleton node id, lossless through G3d; NO URLs).
Join key verified: G3d structural-deltas dedup is lossless (reconstructs each route's nodes with original
ids), so `src_node` is a stable handle. Content-graph + crawl explicitly OUT. Memory `g2-static-flag-anticorrelated-defer`
sibling discipline (measure before speccing) applied.

**§C9 ladder + roadmap status:** G3 cross-route ladder — G3a multi-route + G3b token-merge + G3d
chrome-dedup DONE, G3c thrice-deferred, **nav/site graph scoped to nav-link annotation (BUILD, §C9-R-NG;
content graph empty)**. Remaining roadmap (not started): crawl-discovery site map; G2 virtualization
[deferred all paths]; G4 hover [deferred]; iOS/Android/Flutter native.

### §C9-R-NG-build — SHIP: nav-link route-annotation built + live-validated (2026-06-03)

Built TDD (plan `docs/plans/nav-link-route-annotation.md`, 8 commits): pure `scripts/_nav.py`
(`normalize_url`/`build_route_map`/`resolve_edges`/`classify_chrome`); `web_skeleton.parse_snapshot`
extracts anchor `href` from `nodes.attributes` + `to_skeleton` propagates it (under the `href`
`CONTENT_KEY`, so `redact_node` strips it on ship — default contract byte-identical); `site_capture`
builds the route_map upfront, resolves each route's raw `_sk.json` anchors in-process (hrefs confined to
the scratch tempdir outside the audited tree), converts integer indices → `route_id` strings; `_site`
emits `nav_edges` in `site.json`. Full suite **540 passed** (no regression to the capture path).

**Live smoke (isolated `:9333`, djangoproject.com 4 routes):** `site.json` carried **19 `nav_edges`**
(15 chrome, 4 content) keyed `{src, dst, src_node, chrome}` — `src/dst` = `route_id` strings, `src_node`
= the lossless skeleton node id; **10 distinct chrome `src→dst` pairs** (the shared nav now links every
route to the others — a navigable structure where before the links pointed nowhere). `audit_bundle == []`;
key-set carried NO url/text. **Content-free guarantee = construction, not audit:** `_nav.resolve_edges`
builds each edge from a literal `{src,dst,src_node,chrome}` dict and cannot place an href in it (pinned by
exact-equality + the `capture_site` end-to-end href-free test `test_site_capture_nav_e2e.py`); `audit_bundle`
is only a PARTIAL href backstop (catches media/font-extension URLs, NOT bare page hrefs like `/login` or
`?token=`), so the canary proves `nav_edges` is in audit scope, not that the audit gates arbitrary hrefs.
**Caveat:** the `chrome` flag needs the CDP transport (`aria_role` comes from `enrich_aria`, a no-op without
a CDP AX session); on a non-AX transport every edge degrades to `chrome=False` (degraded, not wrong). The content cell (4) matches the
de-risk characterization (§C9-R-NG django=4) — nav-dominated by construction, content graph sparse, as
predicted. The "green-units / silently-zero-edges" risk (real `_sk.json` shape vs synthetic fixtures) was
pre-empted by pinning the shape before coding (`to_skeleton` whitelist trap; anchors id'd by href-presence
not tag) and confirmed here. **Reproduction-join validated against the real artifact** (not a key-proxy):
re-captured and asserted all 19 edges' `src_node` ∈ `{n["id"]}` of the SHIPPED `routes/<src>/skeleton.json`
— 19/19 resolve, 0 misses (resolved roles `box`/`unknown_box`/`image` — `<a>` carries no dedicated "link"
role, which is why anchors are href-identified, not role-identified). SHIP — the nav/site-graph rung is
closed at nav annotation.

## §C9-R-FW-DURI — SHIP: firewall audit data-URI backstop made encoding-agnostic (2026-06-03)

The flagged firewall-hardening pass (anticipated §1149: "broaden `_DATA_URI` to non-base64"). Spec
`docs/plans/firewall-data-uri-backstop-design.md`. **Honest framing (de-risk read corrected the premise
BEFORE building):** this is NOT an active leak — it is a lagging audit backstop.

- **No active path to disk (verified against the real capture, not greps).** `web_skeleton.parse_snapshot`
  emits exactly `{dom_index, tag, bbox, z, style, text, substrate, pseudo, backend, href}`; the ONLY
  captured attribute is `href` (anchors), a `CONTENT_KEY` stripped by `redact_node`. No
  `src`/`srcset`/`poster`/`xlink`/custom-property/`cssText` capture exists. url()-wrapped `data:` in
  styles/pseudo-content/all deltas/keyframes is already redacted **encoding-agnostically** by
  `_style._is_external` (`startswith("data:")`) → `url("<asset>")`. A bare (non-url) `data:` is invalid
  CSS, never produced by CDP computed-style capture.
- **The real asymmetry fixed:** the audit signature `_DATA_URI` was base64-only (`data:…;base64,`) —
  weaker than the redactor it independently backs. Broadened to encoding-agnostic `data:[…]*,` (the
  mandatory post-metadata comma is the unambiguous discriminator; linear, no ReDoS; zero false-positive
  — `"data":` JSON keys, `metadata`, and `data: ` with a space all fail to match). Now the backstop
  MATCHES the redactor's coverage and, as a bonus, catches an un-redacted `url(data:…)` of any encoding
  too (the `data:…,` substring is present), so it backstops both the bare and the url()-wrapped vector.
- **What this guards:** a FUTURE capture path that emitted a bare/unwrapped non-base64 data: URI — today
  none exists, so this is defense-in-depth + future-proofing, not a plugged active hole. Caught the
  initial "active leak / ships arbitrary content" overstatement (the nav-review overselling lesson
  applied to our own framing) BEFORE building on it.

Build: one-line regex broaden in `content_firewall.py` + 2 audit tests (5 encoding cases incl. base64
regression + a zero-false-positive case). Full `scripts/` suite **526 passed**. No subagent pipeline —
a regex + tests, implemented inline TDD (scaled to the change, not process for its own sake).

**Review-driven hardening (real-artifact FP check, per [[validate-real-artifact-not-keys-proxy]]):** the
broaden widened the match surface (literal `;base64,` → a trailing `,`), so it was scanned against EVERY
committed bundle artifact, not just hand-picked strings. Result: **0 hits on any shipped/redacted
bundle**; the only `data:` in the repo is `fixtures/kasane-rebaseline/skeleton.json` — a RAW
pre-redaction capture input (already carried the `;base64,` the OLD regex flagged, has zero
`url("<asset>")` markers, fed to NO `audit_bundle` test), confirming the redacted shipped bundle
(`bundle/skeleton.json`) is data:-free by construction. Two refinements followed: (1) a `(?<![a-zA-Z])`
word-boundary anchor to kill the `metadata:foo,` / `somedata:x,` substring-FP class (a value-embedded
`data:` preceded by a letter is not a URI token start) with no real match lost; (2) the "zero
false-positive" comment softened to "no FP on realistic post-redaction values" — the same over-claim
flavor the reframe caught, softened not asserted absolute.

**§C9 ladder + roadmap status:** firewall non-base64 data-URI hardening SHIPPED; pseudo-element GEOMETRY
follow-on **SHIPPED §C9-R-P8-GEOM**. Remaining roadmap (not started/deferred): broader form-state family
[**DEFERRED §C9-R-FS-VALIDITY** — capability-yes but no real capture path]; G2 virtualization [deferred
all paths]; G3c recurring-component synthesis [deferred ×3]; G4 hover/non-ARIA [deferred];
crawl-discovery site map; iOS/Android/Flutter native. The web-CDP capture axis is otherwise exhausted at
the current honest ceiling.

## §C9-R-P8-GEOM — SHIP: pseudo-element GEOMETRY follow-on (2026-06-03)

§C9-R-P8 captured `::before`/`::after`/`::marker` content-free STYLE + `content` but deferred their
GEOMETRY (gaps:780). De-risk doc `docs/plans/pseudo-element-geometry-derisk.md`. Bar PRE-REGISTERED,
not bent.

**Diagnosis:** `parse_snapshot` already reads `bounds[i] → bbox` for EVERY layout row incl. pseudo
rows; the harvest path (`to_skeleton`) dropped it (`_collect_pseudo` kept only sparse style). So pseudo
geometry was captured-then-DISCARDED — not a new pass.

**Gate (real-artifact, not a fixture proxy — per [[forcepseudostate-on-only-validity-not-capturable]]):**
`scripts/derisk_pseudo_geometry.py` headless-captured 3 real sites and compared each pseudo row's OWN
bounds vs its originator's. Result: distinct&styled/styled = bootstrap 79% / wikipedia 56% / tailwind
71% — **≥30% on 3/3**. Index alignment proven (pseudo box ≠ parent box: `HEADER::after` 912×**1** vs
912×39.6; `::before` **2880**×1 on a 1360 parent — overflows, non-derivable). Real geometry = divider
bar thickness, caret offsets, 12×12 icon boxes — informative + not derivable from the originator bbox.

**Build (inline TDD):** `web_skeleton.py` attaches `sv = {**sv, "bbox": bb}` when sv non-empty AND
`w>0 AND h>0`; `_style.redact_pseudo` passes the `bbox` geometry DICT through (content→content-redactor,
other strings→style-redactor). 4 new tests; full `scripts/` suite **530 passed** (+4, zero regressions).
Real-artifact confirm: `fixtures/css_style/run_css_style.py` GATE PASS — on-disk bundle carries pseudo
bbox (`::before` 79.06×74, `::after` 1×1, `::marker` 16×18.5) and `audit_bundle` returns `[]`. Firewall a
non-issue as predicted (bbox floats are JSON numbers, never string-scanned). FIRST ship of the
"proceed-to-next" sequence (validity family DEFERRED at §C9-R-FS-VALIDITY just prior).

## §C9-R-FS-VALIDITY — DEFER: validity form-state family (forceable, but not a capturable path) (2026-06-03)

Candidate: extend the shipped `:checked`/`:disabled` form-state rung to the validity/attribute family
`:invalid`/`:valid`/`:required`/`:read-only`/`:placeholder-shown`. De-risk doc:
`docs/plans/form-state-validity-family-derisk.md`. Bar PRE-REGISTERED before any data; **not bent**.

**Gate 1 (mechanism) — capability yes, real path NO.** Harness `scripts/derisk_form_state_validity.py`
(manual headless, non-collected). On a PROXY fixture (base crafted NOT to match) all 5 force ON. But
that proxy false-passed (validate-real-artifact applied to self): a real form input ships its state at
BASE, and `CSS.forcePseudoState` forces a pseudo ON only — never OFF, never suppresses the natural
match. Re-run in the REALISTIC regime → force-on-natural-match is a **NO-OP for required/read-only/
valid/placeholder-shown** (the value is already in the base skeleton), and forcing the opposite on a
naturally-`:valid` input yields a `:valid`+`:invalid` **chimera** (impossible state). Unlike
`:checked`/`:disabled` (reliably OFF at base → clean forced delta), the validity family is static/
attribute-derived (already in base), naturally-ON (force = no-op, the interesting OFF transition is
unreachable), or mutually-exclusive (force = chimera). Capability ≠ capturable.

**Gate 2 (signal) — fails the ≥2-site bar.** Static CSS survey of distinct ecosystems + a real 1.2 MB
sample + neg-control: bootstrap@5.3.3 has `:invalid`/`:valid` rules but its dominant path is the
`.is-invalid` **CLASS** (static → already in base skeleton) gated behind JS-added `.was-validated`;
bulma / @primer (github) / foundation / stackoverflow-real-CSS(1.2 MB) = **zero** validity-pseudo
mechanism rules; normalize.css neg-control = zero (signal not vacuous). At most 1 site (Bootstrap)
clears, and it is class-redundant. Real-world form-state styling is class-based (`.is-invalid`/
`.is-danger`/`.error`, JS-toggled) — already captured by the base skeleton — not the CSS validity
pseudos this rung would force.

**Verdict: DEFER on both gates** (structural + prevalence, independently). Reopen criteria: ≥2 distinct
real non-Bootstrap sites whose SHIPPED CSS styles a validity pseudo on the element itself (or a captured
combinator sibling) with a mechanism prop, where the delta is NOT already in the base skeleton's
class-based computed style. Until then the validity family is forceable-but-not-worth-capturing; the
web-CDP axis stays at its honest ceiling. Memory: [[falsify-detection-signal-on-real-neg-controls-before-code]],
[[validate-real-artifact-not-keys-proxy]].

## §C9-R-CRAWL — Results: crawl-discovery yield de-risk → BUILD (2026-06-04)

Candidate: a **crawl-discovery route-expander** — follow same-origin content links to pages the user did
NOT enumerate, feed them into the content-free multi-route capture (ship more per-route skeletons +
extended `nav_edges`; URLs transient, never on disk). Spec `docs/plans/crawl-discovery-yield-derisk.md`;
harness `scripts/derisk_crawl_yield.py` (non-collected) + pure core `scripts/_crawl_yield.py` (13 tests);
plan `docs/plans/crawl-discovery-yield-harness-build.md`. Bar PRE-REGISTERED; **revised pre-data** after a
holistic cross-file review closed 3 false-BUILD paths (same-origin host-set gate, min-node floor F=20,
conclusive-site denominator) — NOT bent (the revision made BUILD strictly harder).

**Reconciliation with §C9-R-NG (no contradiction).** NG measured content links resolving WITHIN the seed
set (~0.5/route, circular → "content site-graph empty by construction"). This measures one-hop **escape to
un-enumerated same-origin pages** — a different, larger quantity NG never counted. Both hold.

**Regime** (per [[derisk-must-record-capture-regime]]): headless Chrome 1440×900, **single draw**, robots
honored, 2s rate-limit, T=0.5, floor F=20.

**Result — BUILD (4/4 conclusive, all 4 clear ≥2 novel):**

| site | seed-seed spread | frontier (same-origin) | cross-origin dropped | valid/subfloor/failed | novel @0.5 | strip {0.4,0.5,0.6} |
|---|---|---|---|---|---|---|
| python.org | 0.446 (0.025–0.472) | 4 | 345 | 4/0/0 | **2** | 2,2,2 |
| djangoproject.com | 0.125 (0.037–0.163) | 23 | 87 | 23/0/0 | 10 | 6,10,11 |
| mui.com | 0.209 (0.056–0.265) | 6 | 24 | 6/0/0 | **5** | 5,5,5 |
| vercel.com | 0.229 (0.015–0.244) | 13 | 0 | 13/0/0 | 10 | 6,10,12 |

**Caveats (recorded; do NOT change the verdict — advisor 2026-06-04):**
1. The discrimination control validated *spread* but never anchored the HIGH side the spec asked for ("same
   templates score HIGH"): no known-same seed pair was measured (max seed-seed similarity = python 0.472,
   django 0.163 — all < T). So **T=0.5 is a pre-guess the data only partially audits.**
2. BUILD survives this anyway: (a) frontier pages WERE excluded as non-novel (python 2/4, django 13/23) →
   ≥0.5 IS reachable and the metric discriminates; (b) **python.org (2) and mui.com (5) are FLAT across
   {0.4,0.5,0.6}** → those load-bearing novel pages sit <0.4 from all seeds (robustly distinct, not
   threshold artifacts). django/vercel are T-sensitive and NOT load-bearing for the ≥2-on-≥2 floor.
3. ~~Single headless draw — a repro run is required before the build cycle~~ **RESOLVED 2026-06-04:** a
   second headless draw (same regime) is **byte-identical** — all four sites reproduced exactly (python 2 /
   django 10 / mui 5 / vercel 10, identical spreads + drop counts). The G2 single-draw fragility scar
   ([[derisk-must-record-capture-regime]]) does NOT apply here; these are static/cached pages + a
   deterministic metric → the gate is reproducible, not a favorable draw.

**Decision: BUILD-justified.** Open a separate brainstorm → spec → plan for the crawler proper.
Carry-forward params: route-set expander; same-origin BFS frontier; template-saturation stop (loop-until-dry
+ max-page cap); similarity-threshold novelty on the content-region fingerprint; respect robots.txt +
rate-limit + opt-in `--crawl` flag (off by default, like `--sweep`). **FIRST-CLASS open question for that
spec: T-ANCHORING** — calibrate T on MEASURED near-dupe/paginated pairs, not a pre-guess (caveat 1).
Memory: [[nav-graph-shipped-as-nav-annotation]] (crawl-discovery was scoped out there; now BUILD-justified),
[[subagent-review-code-vs-spec-not-just-plan]] (holistic review caught the false-BUILD paths),
[[derisk-must-record-capture-regime]].

### §C9-R-CRAWL-BUILD — SHIPPED (2026-06-04): one-hop route-expander

Built per `docs/plans/crawl-discovery-route-expander.md` + `...-build-plan.md`. Pure
`scripts/_crawl.py` (frontier_targets / cap_frontier / reject_reason / accept; the 5
content-region primitives relocated out of the de-risk harness — `_crawl_yield.py` imports
them back). `site_capture --crawl` (off by default): seeds -> one-hop same-origin frontier ->
selection-skeleton -> novel+deduped capture -> combined `nav_edges` over seeds+discovered.

**Firewall:** discovered rows carry NO `url` (only `discovered`+`via` route_id); discovered
URLs in-memory only; `audit_bundle` backstop unchanged + a real-bytes "no discovered href in
site.json" test. **Fetch cost:** reject = 1 request, accept = 3 (re-fetch via untouched
`capture_route`; the split-scratch optimization is deferred). **T** demoted to a non-load-
bearing knob (`--crawl-threshold`, default 0.5) by the one-hop depth choice; T-anchoring is a
documented refinement, not a gate. Caveats carried (T partially audited; order-dependent
dedup under non-transitive similarity) — see spec §7.

Tests: `test_crawl.py` + `test_crawl_expand.py` (offline, injected fetchers) + non-collected
live smoke `crawl_expander_smoke.py`. Suite green (567).

**Live validation (2026-06-04, real spine — all 567 tests use fakes, so this is the
[[validate-real-artifact-not-keys-proxy]] gate):** headless Chrome, `--crawl --crawl-max 40
T=0.5`, django seed set. Real result: 4 seeds + **7 discovered kept**; ledger balances
(frontier_attempted 16 = kept 7 + dup 6 + failed 3; cross_origin_dropped 33; over_cap 0;
robots_blocked 0). **Real-artifact firewall CLEAN**: the on-disk `site.json` carries exactly
the 4 seed URLs (user input) and ZERO discovered URLs; discovered rows have no `url`;
`nav_edges` keys = {src,dst,src_node,chrome}. Confirms the real `web_skeleton`/`capture_route`/
robots spine runs end-to-end and the firewall holds on real bytes, not just fixtures.

**§C9 ladder + roadmap status:** crawl-discovery site map **BUILD-JUSTIFIED (§C9-R-CRAWL), repro-confirmed**
— first non-DEFER roadmap movement since the web-CDP ceiling. Remaining roadmap: **crawler proper one-hop expander SHIPPED (§C9-R-CRAWL-BUILD)**; multi-hop BFS remains DEFERRED (needs a T-anchoring de-risk — T becomes load-bearing); G2 virtualization
[deferred all paths]; G3c recurring-component synthesis [deferred ×3]; G4 hover/non-ARIA [deferred];
form-state validity [deferred §C9-R-FS-VALIDITY]; iOS/Android/Flutter native.

## §C9-R-T-ANCHOR — VERDICT: INCONCLUSIVE → DEFER (intended pagination measurement absent one-hop ⇒ T un-anchored; sibling proxy corroborative + site-variable, NOT a falsification) (2026-06-04)

The T-anchoring de-risk for multi-hop BFS (spec `docs/plans/t-anchoring-derisk.md`; cores
`scripts/_url_template.py` + `scripts/_t_anchor.py`, 24 offline tests; non-collected live harness
`scripts/derisk_t_anchor.py`). Goal: close §C9-R-CRAWL caveat 1 — anchor the same-template **HIGH**
side (never measured before) so T=0.5 is validated, not a pre-guess. Ground truth labeled by **URL
structure** (pagination Tier-1, siblings Tier-2), INDEPENDENT of the bag-Jaccard fingerprint →
non-circular. Bar PRE-REGISTERED (§3): conclusive site = ≥3 Tier-1 pagination pairs; ≥2 conclusive
sites; strict asymmetry HIGH=median / LOW=max; PASS iff clean gap with 0.5 strictly inside.

**Regime** (per [[derisk-must-record-capture-regime]]): headless Chrome 1440×900, robots honored,
2s rate-limit, F=20. **Two draws — BYTE-IDENTICAL** (deterministic metric on static/cached pages;
the G2 single-draw fragility scar does NOT apply). Cohort = the §C9-R-CRAWL four. Scalars only
(content-free; no URL persisted/printed — firewall ADR-0001 held end-to-end).

| site | frontier | paginated-urls (incl. singletons) | Tier-1 pairs / HIGH-T1 | HIGH-T2 sibling median (n) | seed-seed LOW median / max (n=6) |
|---|---|---|---|---|---|
| python.org | 4 | **0** | 0 / — | 0.362 (3) | 0.161 / **0.472** |
| djangoproject.com | 23 | **0** | 0 / — | 0.701 (31) | 0.135 / 0.163 |
| mui.com | 6 | **0** | 0 / — | 0.473 (2) | 0.175 / 0.265 |
| vercel.com | 13 | **0** | 0 / — | 0.412 (10) | 0.082 / 0.244 |

Note the honest read of the sibling proxy: HIGH-T2 sibling median **exceeds the seed-seed median on all
four sites** (e.g. python 0.362 > 0.161). The cross-site bar only "misses" on python because the strict
median-HIGH-vs-**max**-LOW asymmetry pits 0.362 against the single most-similar seed pair (0.472) — that
asymmetry is the bar for the Tier-1 DECISION tier, and Tier-2 is corroborative-only.

**Verdict — INCONCLUSIVE by the pre-registered bar (0/4 conclusive sites; the Tier-1 decision tier has
zero data) → DEFER multi-hop BFS.** Both findings reproduced across the two byte-identical draws:

1. **The intended HIGH-side signal (pagination) could not be measured — it is not reachable one-hop.**
   `paginated-urls=0` on ALL four diverse real sites (the diagnostic counts every pagination-form URL
   incl. singletons; the detector is 17-test-verified, so this is **true absence**, not a miss). One-hop
   frontiers from ordinary section/home seeds surface no `/page/N`/`?page=N` URLs → **HIGH-T1 has zero
   data**. The bar — which rides on Tier-1 — therefore returns **INCONCLUSIVE**. This is the load-bearing
   finding: T=0.5 stays **un-anchored** because its target measurement was un-takeable in this regime.

2. **The sibling proxy (Tier-2) is corroborative-only and site-variable — mildly ENCOURAGING, not a
   falsification.** By median, siblings score above the typical distinct-template seed pair on **all four
   sites** (django 0.701 vs 0.135, mui 0.473 vs 0.175, vercel 0.412 vs 0.082, python 0.362 vs 0.161). The
   cross-site median-HIGH-vs-max-LOW test does not clear (python's max seed pair 0.472 > python's sibling
   median 0.362), but that strict asymmetry is the bar for the **Tier-1 decision tier**; Tier-2 is
   corroborative-only (spec §3) and **cannot decide a verdict** — it can neither mint a PASS nor a FAIL.
   Read straight, Tier-2 neither confirms nor refutes; it hints the same-template signal MAY separate where
   such pages are reachable. (An earlier read of mine called this "siblings score below distinct seeds /
   signal falsified on a neg-control" — that was WRONG: it compared sibling median to the single
   most-similar seed *outlier*, and over-elevated a corroborative tier. Corrected here.)

**Why DEFER rather than extend the cohort (spec §7) in this session:** the honest reason is finding 1 —
the intended pagination measurement was **un-takeable** one-hop, so T is un-anchored (not validated, not
refuted). Taking it properly needs **pagination-reachable seeds** (list/index pages that expose ≥2
same-template `/page/N` URLs one-hop) across **≥2 sites** (the bar needs ≥2 conclusive sites for
cross-site generalization) — a pre-committed cohort redesign, specified by URL structure BEFORE running
(no try-until-pass), which is future scoped work, not a same-session re-run. The cheap de-risk already
delivered its value: it established that pagination is NOT reachable one-hop from ordinary seeds (a real
constraint any multi-hop design must account for), and that the sibling proxy is positive-but-site-variable.

**Consequence:** multi-hop BFS **stays DEFERRED** — because T=0.5 is **un-anchored** (the pagination
HIGH-side was unmeasurable one-hop), NOT because the signal was shown to fail. §C9-R-CRAWL caveat 1
(HIGH side never anchored) **remains open**, now sharpened: anchoring it needs pagination-reachable seeds
+ cross-site generalization. A future attempt: pre-commit pagination-reachable seeds across ≥2 sites and
re-run THIS SAME harness + bar (the cores `_url_template`/`_t_anchor` and the firewall hold as-is). The
shipped one-hop expander (§C9-R-CRAWL-BUILD) is unaffected — T is non-load-bearing there.

Memory: [[falsify-detection-signal-on-real-neg-controls-before-code]] (the discipline that kept the
corroborative Tier-2 proxy from being over-read into a false "falsification"), [[nav-graph-shipped-as-nav-annotation]]
(crawl lineage), [[derisk-must-record-capture-regime]] (byte-identical repro), [[subagent-review-code-vs-spec-not-just-plan]]
(final holistic review caught two spec-vs-code §3 wording bugs pre-run; an advisor pass caught the Tier-2
over-read pre-merge).

**§C9 ladder + roadmap status (updated):** T-anchoring de-risk **RAN → INCONCLUSIVE → DEFER**
(§C9-R-T-ANCHOR; pagination not reachable one-hop on 4 sites ⇒ HIGH side un-takeable ⇒ T un-anchored;
sibling proxy positive-but-site-variable, NOT a falsification). Multi-hop BFS DEFERRED — T un-anchored;
revival needs **pagination-reachable seeds + cross-site generalization** (re-run the same harness/bar),
NOT necessarily a new signal. Remaining roadmap: one-hop expander SHIPPED (§C9-R-CRAWL-BUILD); multi-hop
BFS DEFERRED (§C9-R-T-ANCHOR — T un-anchored, measurement un-takeable one-hop); G2 virtualization
[deferred all paths]; G3c recurring-component synthesis [deferred ×3]; G4 hover/non-ARIA [deferred];
form-state validity [deferred §C9-R-FS-VALIDITY]; iOS/Android/Flutter native — **every web-axis lane is now
SHIPPED or DEFERRED-with-evidence; native is the only un-probed axis.**
