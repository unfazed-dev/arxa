# Deterministic screenshot capture — settle protocol research

Sources fetched and indexed directly (primary docs): MDN, W3C/WHATWG drafts, chromedevtools.github.io/devtools-protocol (tip-of-tree), Chrome for Developers, Playwright docs, Puppeteer docs. HOT = the cited page states this directly, quoted or closely paraphrased. WARM = inferred / cross-referenced / community consensus with primary-source support. COLD = unclear, conflicting, or unverifiable from primary sources (flagged explicitly, never asserted as fact).

---

## 1. Font loading — `document.fonts.ready`

**What it guarantees (HOT).** MDN: the `ready` promise "will only resolve once the document has completed loading fonts, layout operations are completed, and no further font loads are needed." https://developer.mozilla.org/en-US/docs/Web/API/FontFaceSet/ready

**The core documented gap (HOT — spec text, not inference).** CSS Font Loading Module Level 3, §3.4: *"Authors should note that a given ready promise is only fulfilled once, but further fonts may be loaded after it fulfills."* https://drafts.csswg.org/css-font-loading/#font-face-set-ready — This is the load-bearing limitation: an already-resolved `ready` promise does not "come back." If new DOM content needing a different font is inserted after you awaited it (icon glyph in a modal opened later, a component that renders after the initial paint, anything gated by a later layout pass), that font load is invisible to the promise you already awaited. You must re-access `document.fonts.ready` (a fresh await) after any subsequent DOM mutation that could introduce new font usage.

**`status` is binary and can cycle (HOT).** `FontFaceSet.status` is one of `"loading"` / `"loaded"` (https://developer.mozilla.org/en-US/docs/Web/API/FontFaceSet/status), and the `loading` event "fires when the document begins loading fonts" — i.e. can fire again later (https://developer.mozilla.org/en-US/docs/Web/API/FontFaceSet). This is the mechanism by which "further fonts loaded after ready fulfills" actually manifests: status flips back to `loading`, a fresh `ready` promise is needed.

**`font-display: swap` (HOT).** MDN: `swap` gives "an extremely small block period and an infinite swap period" — https://developer.mozilla.org/en-US/docs/Web/CSS/@font-face/font-display. During the (unbounded) swap period a fallback font renders until the real font arrives; on a slow network this can visibly change the page well after `load`/`fonts.ready` fired for other fonts, because `fonts.ready` only waits for fonts actually in use for rendered content — if the swap-period fallback is still showing at the moment `ready` is evaluated, the optional/late font is not "used" yet.

**Icon fonts (WARM — inferred, not spec-named).** Not called out as a special case anywhere in the spec/MDN. The gap is the general "used fonts ≠ declared fonts" problem (MDN's own note under `ready`: "the set of used fonts can be different from the set of declared fonts, e.g., if optional fonts... were not able to load in time"), applied to the icon-font-via-`::before`/`::after`-inserted-late scenario.

**Known cross-browser resolution-timing bugs (WARM).** github.com/w3c/csswg-drafts#1082 "document.fonts.ready promise resolution time does not match implementations," and WebKit Bugzilla #225790 "document.fonts.ready is sometimes still resolved too quickly" — both indicate implementations resolve earlier/differently than the spec text implies, depending on network conditions and browser. These are issue trackers on the primary spec/engine repos, not blog posts, but they document open/disputed behavior rather than settled fact.

---

## 2. Layout/paint settle

**Double `requestAnimationFrame` (WARM/COLD — not documented as a named pattern anywhere official).** I could not find "double rAF" as a named, documented idiom on MDN, Chrome for Developers, or any W3C spec. `Window.requestAnimationFrame()` is documented only as: the callback fires once, before the next repaint, and must re-request itself to run again — https://developer.mozilla.org/en-US/docs/Web/API/Window/requestAnimationFrame. The "double rAF runs after paint" behavior is an inference the community draws from that one-shot, pre-paint semantics (nest a second rAF inside the first; by the time the *inner* callback runs, the frame the *outer* callback scheduled has been painted) — real, but nowhere is it officially named or guaranteed as a "wait for paint" API. Treat it as a heuristic, not a contract.

**`requestIdleCallback` — not a paint signal at all (HOT, by exclusion).** MDN: it "queues a function to be called during a browser's idle periods... to perform background and low priority work... without impacting latency-critical events such as animation." https://developer.mozilla.org/en-US/docs/Web/API/Window/requestIdleCallback — Nothing in the doc ties it to paint/frame completion; it's scheduling priority, not a rendering guarantee. It's also explicitly **not Baseline** ("Limited availability... does not work in some of the most widely-used browsers") — a poor choice for a cross-browser settle gate on that ground alone.

**Long Animation Frames API (LoAF) — diagnostic, not a settle gate (HOT for what it is; WARM for unsuitability).** Chrome for Developers + shipped Chrome 123+ + W3C First Public Working Draft (2026): https://developer.chrome.com/docs/web-platform/long-animation-frames , https://www.w3.org/news/2026/first-public-working-draft-long-animation-frames-api/ . It reports rendering updates delayed beyond 50ms via `PerformanceObserver({type:'long-animation-frame'})`, with rich timing breakdown (`renderStart`, `styleAndLayoutStart`, per-script attribution). It is retrospective and conditional: it only fires an entry when a frame *was* long: a settled, idle page produces none, so "wait for a LoAF entry" cannot be used as a general-purpose settle gate — there is nothing to wait for on the common case.

**`first-contentful-paint` via `PerformanceObserver`/`PerformancePaintTiming` — fires once, useless after first render (HOT).** MDN: FCP is "Time when the first contentful paint... is rendered," and the interface's `name` is one of only `"first-paint"` or `"first-contentful-paint"` — https://developer.mozilla.org/en-US/docs/Web/API/PerformancePaintTiming. These entries are emitted once each, early in the page's life; they say nothing about later paints, animations, or post-interaction re-renders. Not a repeatable settle signal.

**CDP signals.**
- `Page.frameStoppedLoading` (Experimental event) — "Fired when frame has stopped loading" (HOT, https://chromedevtools.github.io/devtools-protocol/tot/Page/#event-frameStoppedLoading). Network/navigation-lifecycle signal, not a paint/compositor signal.
- `Page.screencastFrame` (Experimental) — pushes compressed frame images while `Page.startScreencast` is active (HOT, same domain page). Designed for live screencasting (DevTools/remote inspection), not for a one-shot deterministic capture pipeline; using it as a settle detector (diff consecutive screencast frames) is plausible but undocumented as a use case.
- `Page.captureScreenshot` — `fromSurface` "Capture the screenshot from the surface, rather than the view. Defaults to true" (HOT, https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-captureScreenshot). This means the call reads the actual compositor surface, so whatever was last committed there is what you get — but the docs do not state that the call itself *blocks until a new frame commits*; it just reads current surface state (WARM inference, not confirmed).
- `HeadlessExperimental.beginFrame` — the closest thing to a genuine, documented "frame-committed" primitive: "Sends a BeginFrame to the target and **returns when the frame was completed**. Optionally captures a screenshot from the resulting frame. Requires that the target was created with enabled BeginFrameControl." (HOT, https://chromedevtools.github.io/devtools-protocol/tot/HeadlessExperimental/#method-beginFrame). In the current tip-of-tree docs (fetched directly today), `beginFrame` itself is **not** flagged Deprecated — only the domain's `enable`/`disable` methods are — meaning the on/off toggle is gone but the frame-stepping call remains listed. **COLD / contested**: third-party project docs (a GitHub issue on `heygen-com/hyperframes` and a troubleshooting doc in `NousResearch/hermes-agent`) claim a specific Chromium version dropped `beginFrame` support and that tools must fall back to plain screenshot capture; I could not confirm any specific removal version against a primary Chromium/CDP source, and the live ToT protocol page still lists the method, so I am explicitly **not** asserting that removal as fact — only reporting that availability is disputed/inconsistent across builds per community reports, while the canonical spec still documents it as live. Also HOT: it requires the experimental `--run-all-compositor-stages-before-draw` launch flag and target creation with `BeginFrameControl`, so it is not something Playwright/Puppeteer's default `page.screenshot()` path uses.

**Verdict for §2:** there is no single official "screenshot ready" primitive. The documented building blocks (load-state events, `fonts.ready`, rAF-based heuristics, LoAF for diagnostics only) each cover a slice; none certifies "nothing is still moving." This is exactly why production tools (§ below) don't rely on one signal — they add a stability loop as the backstop.

---

## 3. Animation freezing

**Coverage matrix (grounded in fetched docs):**

| Mechanism | CSS Transitions | CSS Animations | WAAPI (`Element.animate()`) | SVG SMIL | GIF/APNG | `<video>` | Cross-origin iframe |
|---|---|---|---|---|---|---|---|
| `document.getAnimations()` | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| CSS override injection (`!important`) | ⚠️ only if injected before the transition starts (see below) | ✅ | ✅ (WAAPI runs at the same "animations" cascade tier, below `!important`) | ❌ | ❌ | ❌ | ❌ |
| `prefers-reduced-motion` emulation | opt-in only | opt-in only | opt-in only | ❌ | ❌ | ❌ | ❌ (per-frame) |
| `SVGSVGElement.pauseAnimations()` | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| `HTMLMediaElement.pause()` | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| — | — | — | — | — | **no documented API found** | — | — |

**`document.getAnimations()` — the broadest single net (HOT, exact quote).** MDN: returns "an array of all `Animation` objects currently in effect whose target elements are descendants of the document. This array includes CSS Animations, CSS Transitions, and Web Animations." https://developer.mozilla.org/en-US/docs/Web/API/Document/getAnimations — explicitly the three script-visible animation types in one list.

**`pause()` alone leaves an arbitrary phase (HOT).** MDN `Animation.pause()`: "suspends playback of the animation" at wherever it currently is — https://developer.mozilla.org/en-US/docs/Web/API/Animation/pause. `Animation.currentTime` is documented as settable ("The current time value of the animation in milliseconds, whether running or paused" — https://developer.mozilla.org/en-US/docs/Web/API/Animation) — so the deterministic pattern is `pause()` **then** explicitly assign `currentTime` to a fixed value; `pause()` by itself only stops further drift, it does not pin *which* frame you land on.

**CSS override injection vs. the cascade — a real, non-obvious limitation (HOT, primary source: MDN's cascade precedence table).** MDN "Introduction to the CSS cascade" gives the full 8-tier precedence order (low → high): user-agent normal, user normal, author normal, **CSS keyframe animations**, author `!important`, user `!important`, user-agent `!important`, **CSS transitions**. https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Cascade/Introduction — Consequence: an injected `!important` rule (e.g. `animation-duration:0s !important`) *does* outrank an in-progress CSS **animation**, because animations sit below `!important`. But **transitions sit above `!important`** — the highest tier in the entire cascade. An `!important` "kill transitions" rule injected *after* a transition has already started will **not** override its live interpolated value. The rule only works if it's in place *before* the state change that triggers the transition. This means CSS override injection must be part of the pre-navigation setup (step 1 of the sequence below), not a last-second "freeze now" action.

**`prefers-reduced-motion` — opt-in for the page author, not a browser kill switch (HOT).** MDN documents it purely as a CSS media feature / signal for authors to query — https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion. Nothing in the doc states browsers globally suppress animations when it's set; it only affects animations the site's own CSS/JS explicitly gates behind `@media (prefers-reduced-motion: reduce)` or `matchMedia()`. CDP exposes emulation of it via `Emulation.setEmulatedMedia({features:[{name:'prefers-reduced-motion', value:'reduce'}]})` (HOT, https://chromedevtools.github.io/devtools-protocol/tot/Emulation/#method-setEmulatedMedia + `MediaFeature` type `{name, value}`). Useful, but only as effective as the target site's own opt-in coverage.

**CDP Animation domain (HOT).** `Animation.setPlaybackRate` — "Sets the playback rate of the document timeline" (document-wide, not per-animation) — https://chromedevtools.github.io/devtools-protocol/tot/Animation/#method-setPlaybackRate . `Animation.setPaused` — per animation-id pause state. `Animation.seekAnimations` — "Seek a set of animations to a particular time within each animation." These require `Animation.enable` and tracking `animationCreated`/`animationStarted` events to get IDs — more machinery than `document.getAnimations()`, but they operate outside page JS, so a page that overrides `window.Animation` or fights back against script-level freezing can't evade the CDP-level controls.

**SVG SMIL — a genuinely separate mechanism (HOT).** `SVGSVGElement.pauseAnimations()` — "suspends... all currently running animations that are defined within the SVG document fragment... causing the animation clock... to stand still" — https://developer.mozilla.org/en-US/docs/Web/API/SVGSVGElement/pauseAnimations . Must be called per `<svg>` root; not reached by `getAnimations()`, CSS overrides, or `prefers-reduced-motion`.

**GIF/APNG — unsolved (negative finding).** No documented pause/seek API exists in any spec/MDN page I found for raster animated images. This is a real, currently-open hole in the platform for deterministic capture; the practical mitigation is excluding such assets from golden-tested surfaces or masking them, not stopping them in-browser.

**Cross-origin iframes — unreached by all of the above (WARM, structural inference).** Each cross-origin frame is its own browsing-context/CDP target; page-injected CSS/JS and `document.getAnimations()` don't cross that boundary. Reaching them requires attaching to each frame's own CDP target and repeating the freeze steps there — not documented as a single unified operation anywhere.

**Playwright's own `animations: "disabled"` — confirms the same coverage boundary (HOT, exact quote).** Playwright `page.screenshot()`/`toHaveScreenshot()` option: *"When set to `disabled`, stops CSS animations, CSS transitions and Web Animations. ... finite animations are fast-forwarded to completion, so they'll fire `transitionend` event. ... infinite animations are canceled to initial state, and then played over after the screenshot."* https://playwright.dev/docs/api/class-page#page-screenshot-option-animations — Notably scoped to exactly the same three types `getAnimations()` covers. Playwright — production, widely deployed — has the identical SVG SMIL / GIF-APNG / video / cross-origin-iframe gap as the raw platform APIs. This is strong corroborating evidence the gap is real and not just a documentation oversight on MDN's part.

---

## 4. Virtual time — CDP `Emulation.setVirtualTimePolicy`

**What it does (HOT, exact quote).** "Turns on virtual time for all frames (replacing real-time with a synthetic time source) and sets the current virtual time policy. Note this supersedes any previous time budget." Marked **Experimental**. https://chromedevtools.github.io/devtools-protocol/tot/Emulation/#method-setVirtualTimePolicy — it now lives in the **Emulation** domain (not `Page`, where older references sometimes place it).

**Policies (HOT, exact enum text):**
- `advance` — "If the scheduler runs out of immediate work, the virtual time base may fast forward to allow the next delayed task (if any) to run."
- `pause` — "The virtual time base may not advance."
- `pauseIfNetworkFetchesPending` — "The virtual time base may not advance if there are any pending resource fetches."
https://chromedevtools.github.io/devtools-protocol/tot/Emulation/#type-VirtualTimePolicy

**The tell: `maxVirtualTimeTaskStarvationCount` (HOT, exact quote).** "If set this specifies the maximum number of tasks that can be run before virtual is forced forwards to **prevent deadlock**." Its mere existence in the parameter list is the protocol's own documentation of the failure mode: unbounded virtual time can starve/deadlock a page's task queue, so the API ships a required escape hatch rather than guaranteeing clean behavior.

**Intended use (WARM, inferred from the parameter shape, not stated as a use-case in the doc).** `pauseIfNetworkFetchesPending` reads as purpose-built for "wait for network activity to go quiet, then act" workflows (e.g. deterministic PDF/screenshot generation without waiting on real wall-clock timeouts), rather than as a general "freeze the whole visual state" tool.

**Known limitations (WARM — I could not find a primary Chromium bug-tracker citation I was confident in; downgrading from HOT).** Community/tooling consensus (Puppeteer/Playwright issue trackers, not cited here as specific bug numbers because I could not verify them against primary sources in this pass) holds that virtual time interacts poorly with real async work (fetch/promise ordering, Service Workers, WebSockets) and remains flagged Experimental years after introduction — consistent with, but not proven solely by, the starvation-counter's existence.

**Critically: virtual time does not touch `requestAnimationFrame` or the compositor's frame-production loop.** rAF is tied to real vsync/compositor timing, not to the JS-timer virtual clock `setVirtualTimePolicy` manipulates. So it cannot substitute for the animation-freezing steps in §3 — it's a timers/network lever, not a visual-settle lever.

**Verdict:** viable for a narrow, well-scoped goal (deterministic `Date`/`setTimeout`/`setInterval`/network-quiescence at page-load time), not a general-purpose trap-avoider for visual determinism. **Prefer Playwright's Clock API where available** — it is non-Experimental, stable, and documented to override a strictly larger surface: `Date`, `setTimeout`, `clearTimeout`, `setInterval`, `clearInterval`, **`requestAnimationFrame`, `cancelAnimationFrame`**, `requestIdleCallback`, `cancelIdleCallback`, `performance`, `Event.timeStamp` (HOT, exact list, https://playwright.dev/docs/clock). Playwright explicitly warns: *"If you call `install` at any point in your test, the call MUST occur before any other clock related calls... Calling these methods out of order will result in undefined behavior."*

---

## 5. Other nondeterminism sources

**`Date.now()`/`Math.random()` (HOT).** Playwright `page.addInitScript()`: script "is evaluated after the document was created but before any of its scripts were run. This is useful to amend the JavaScript environment, e.g. to **seed `Math.random`**" — with the literal example `Math.random = () => 42;` — https://playwright.dev/docs/api/class-page#page-add-init-script . The CDP-level equivalent primitive is `Page.addScriptToEvaluateOnNewDocument`, present in the CDP Page domain method list (https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-addScriptToEvaluateOnNewDocument). Playwright Clock's `setFixedTime` is the documented fix for `Date.now()`/`new Date()` (https://playwright.dev/docs/clock).

**Lazy loading via `IntersectionObserver`/`loading="lazy"` (HOT).** `IntersectionObserver` asynchronously observes viewport intersection (https://developer.mozilla.org/en-US/docs/Web/API/IntersectionObserver); the `<img loading>`/`<iframe loading>` attribute uses this mechanism to defer fetch until near-viewport (https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/img). **This is the sharpest practical hazard for a screenshot tool that stitches a full page by scrolling**: each scroll step can trigger a fresh, asynchronous image fetch whose completion timing is not deterministic run-to-run. Puppeteer's `captureBeyondViewport` (default `true` when `clip` is set, `false` otherwise — https://pptr.dev/api/puppeteer.screenshotoptions) and CDP's own `Page.captureScreenshot` `captureBeyondViewport` (Experimental — https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-captureScreenshot) let you capture the full document surface **without scrolling**, sidestepping the race entirely.

**Scroll anchoring (HOT).** `overflow-anchor` — MDN: scroll anchoring "adjusts scroll position to minimize content shifts" and "is enabled by default in any browser that supports it" — https://developer.mozilla.org/en-US/docs/Web/CSS/overflow-anchor . Notably flagged **"Limited availability... not Baseline"** — behavior isn't guaranteed uniform across browsers/versions, which is itself a source of run-to-run and cross-browser divergence. `overflow-anchor: none` is the documented opt-out.

**`content-visibility` (HOT).** `content-visibility: auto` lets the UA skip layout/paint for off-screen content until needed, firing `contentvisibilityautostatechange` when that changes — https://developer.mozilla.org/en-US/docs/Web/CSS/content-visibility . `Element.checkVisibility({contentVisibilityAuto: true})` (Baseline 2024) can assert "is this element's content-visibility:auto content *currently* being skipped" — https://developer.mozilla.org/en-US/docs/Web/API/Element/checkVisibility — a documented, if narrow, way to verify actual-render-happened rather than trusting DOM presence.

**Scrollbar rendering / device pixel ratio (HOT).** `Emulation.setScrollbarsHidden` (Experimental, boolean `hidden`) and `Emulation.setDeviceMetricsOverride`'s `deviceScaleFactor` ("Overriding device scale factor value. 0 disables the override") are the CDP-level determinism levers — https://chromedevtools.github.io/devtools-protocol/tot/Emulation/ .

**Image decode timing (HOT, exact quote).** `HTMLImageElement.decode()` — "returns a Promise that resolves once the image is decoded and is safe to be appended to the DOM," explicitly motivated by MDN as the fix for "avoiding empty images" (contrasted with waiting on the `load` event, which only reflects network completion, not decode completion) — https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/decode . No documented equivalent exists for CSS `background-image` — a separate, real gap.

---

## Recommended ordered settle sequence

Each step names what it guarantees (grounded in the docs above) and what it still misses, so gaps are explicit rather than papered over.

**1. Pre-navigation determinism hooks** — via `Page.addScriptToEvaluateOnNewDocument` / Playwright `addInitScript` / Puppeteer `evaluateOnNewDocument`, run once per page before first navigation:
   - Seed `Math.random` to a fixed generator (Playwright-documented pattern).
   - Fix the clock (`page.clock.setFixedTime()` in Playwright, or manual `Date` override).
   - Inject a stylesheet forcing `animation-duration:0s !important; transition-duration:0s !important; transition-delay:0s !important;` (or Playwright's `animations:"disabled"` equivalent).
   *Guarantees:* no `Math.random`/`Date` drift between runs; CSS transitions/animations never start with visually-drifting timing, because the override is in place **before** any state change can trigger a transition — necessary given transitions outrank even `!important` once running (§3).
   *Misses:* WAAPI animations started imperatively via `Element.animate()`, SVG SMIL, GIF/APNG, `<video>` — none are CSS-cascade-driven, so this stylesheet doesn't touch them (handled in step 4).

**2. Navigate; wait for `load`, not `networkidle`.** Playwright explicitly marks `networkidle` **DISCOURAGED**: "consider operation to be finished when there are no network connections for at least 500ms. Don't use this method for testing, rely on web assertions to assess readiness instead" (https://playwright.dev/docs/api/class-page#page-screenshot).
   *Guarantees:* main document + parse-time subresources have a real completion signal.
   *Misses:* anything fetched by app JS after `load`, anything lazy-loaded on scroll, image *decode* completion (network completion ≠ decode completion, §5).

**3. `await document.fonts.ready` (fresh await, in-page).**
   *Guarantees:* all fonts known-needed at call time, plus dependent layout, have completed (spec: "layout operations completed").
   *Misses (spec-documented):* fonts whose need is discovered later — you must re-await after any subsequent DOM mutation that could introduce new font usage. Also: open cross-browser resolution-timing bugs (WebKit #225790, csswg-drafts #1082) mean this is not a perfectly interoperable guarantee.

**4. Explicitly freeze every remaining script-visible animation type, in-page:**
   ```js
   document.getAnimations().forEach(a => { // Document.getAnimations() takes no parameters (MDN) —
     a.pause();                            // it already covers all descendants.
     a.currentTime = 0;                    // pin to a fixed phase; see tradeoff note below.
   });
   document.querySelectorAll('svg').forEach(svg => svg.pauseAnimations());
   document.querySelectorAll('video').forEach(v => v.pause());
   ```
   *Guarantees:* `getAnimations()` covers CSS Animations + CSS Transitions + WAAPI together (MDN, confirmed); pinning `currentTime` explicitly (not just `pause()`) removes mid-flight-phase nondeterminism — `pause()` alone stops drift but leaves whichever phase it happened to catch, which is itself nondeterministic run-to-run.
   *Tradeoff, stated explicitly:* pinning `currentTime = 0` lands every animation at its **start** frame, which matches Playwright's own documented treatment of *infinite* animations ("canceled to initial state") but diverges from its treatment of *finite* ones ("fast-forwarded to completion"). Fast-forwarding to completion instead requires `a.currentTime = a.effect.getComputedTiming().endTime` **and** the animation's `fill` mode set to `forwards` (or `both`) — with the default `fill: none`, setting `currentTime` past the active phase reverts the animated value, which would silently pin to the *wrong* visual state. Pick one philosophy (start-frame is simpler and matches step 1's `animation-duration:0s` override in spirit) and hold to it consistently — don't mix "start" and "end" pinning across the same suite.
   *Misses:* GIF/APNG (no documented pause API — exclude such assets from golden surfaces or mask them); cross-origin iframes (each needs its own CDP-target attach and repeat of this step); `prefers-reduced-motion` still only helps for animations the target page itself gates behind that media query — set it via `Emulation.setEmulatedMedia` for defense in depth, but don't rely on it alone.

**5. Resolve lazy/async images deliberately, without racing scroll.** Prefer capturing the full document surface without scrolling (`captureBeyondViewport: true`), or explicitly scroll-and-`await img.decode()` every visible `<img>` before capture.
   *Guarantees:* avoids the IntersectionObserver-triggered-by-scroll race entirely, or closes it per-image via documented decode-completion semantics.
   *Misses:* no `decode()`-equivalent exists for CSS `background-image`.

**6. Double-`requestAnimationFrame`, then check `document.readyState` / `Element.checkVisibility({contentVisibilityAuto:true})` on the target surface.**
   *Guarantees (WARM — heuristic, not a spec'd contract):* code between the two nested rAFs runs after the browser has painted the previously-scheduled frame, per rAF's documented one-shot/pre-paint semantics. `checkVisibility` confirms `content-visibility:auto` content actually rendered rather than being DOM-present-but-skipped.
   *Misses:* no GPU-thread compositor/raster-completion guarantee; not an official "wait for paint" idiom; `requestIdleCallback` is **not** a substitute (it's a background-work scheduler, not Baseline everywhere, and says nothing about paint); `first-contentful-paint` is **not** a substitute (fires once, only for the page's first render).

**7. Stability loop — the documented production backstop.** Capture → short wait (fixed delay or another double-rAF) → capture again → repeat until two consecutive captures are byte-identical, bounded by a max-attempt count. This is exactly what Playwright's `toHaveScreenshot()` does: *"This method took a bunch of screenshots until two consecutive screenshots matched, and saved the last screenshot to file system."* https://playwright.dev/docs/test-snapshots
   *Guarantees:* the only signal-agnostic backstop in this sequence — catches whatever steps 1–6 missed, because it doesn't care *why* pixels were still changing, only that they've stopped.
   *Misses:* stable-but-wrong states pass it (e.g., an override injected too late leaving a transition parked mid-flight, or a symmetric SVG SMIL loop frame that repeats). It also cannot detect an external asset that never arrives within the retry budget — a documented, tracked community limitation of exactly this stopping condition. Bound the retries and fail loudly on exhaustion; don't loop unbounded.

**8. Pin session-level rendering knobs once, outside the per-capture loop.** `Emulation.setDeviceMetricsOverride` with a fixed `deviceScaleFactor`; `Emulation.setScrollbarsHidden(true)`; `overflow-anchor: none` alongside the step-1 stylesheet.
   *Guarantees:* removes DPI/scrollbar-chrome/scroll-anchoring as diff variables.
   *Misses:* does not address headless-vs-headed or cross-OS/cross-GPU rendering differences. Playwright's own docs open with the honest caveat that no in-page protocol substitutes for pinning the capture environment itself: *"Browser rendering can vary based on the host OS, version, settings, hardware, power source... For consistent screenshots, run tests in the same environment where the baseline screenshots were generated."* https://playwright.dev/docs/test-snapshots

**On virtual time (§4) — deliberately excluded from the sequence above.** `Emulation.setVirtualTimePolicy` is Experimental, doesn't touch `requestAnimationFrame`/compositor timing at all, and ships a required anti-deadlock parameter (`maxVirtualTimeTaskStarvationCount`) that documents its own failure mode. Use it only for a narrowly-scoped goal (fast-forwarding real network/timer waits for speed), and prefer Playwright's Clock API when available, since it's stable and documented to also override `requestAnimationFrame`/`requestIdleCallback` — the exact piece raw CDP virtual time misses. Do not treat it as a blanket determinism switch.

**On `HeadlessExperimental.beginFrame` — noted, not recommended as a foundation.** It is the most rigorously "frame-committed" primitive in the documented set (returns only once "the frame was completed"), but it's Experimental, requires a non-default launch flag and `BeginFrameControl`-enabled target creation, isn't used by Playwright/Puppeteer's default screenshot path, and its cross-version availability is disputed in community reports I could not verify against a primary Chromium source. Worth prototyping in isolation; not worth betting the pipeline's default path on given its status.
