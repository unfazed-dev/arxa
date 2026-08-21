# Warm vs cold Chrome determinism

Does a REUSED (warm) Chrome render a page byte-identically to a
FRESHLY-LAUNCHED (cold) one? This gates the `appbox lens` daemon plan, which
would hold one warm Chrome to save the ~1.4s per-invocation launch. `lens`
exists to compare pixels, so a speed win that changes pixels is worthless.
No official Chromium / CDP / Puppeteer / Playwright source documents this
either way, so it is measured here rather than looked up.

## VERDICT

YES, CONDITIONALLY — a warm Chrome is safe to reuse for pixel comparison, on the conditions actually held fixed by this run: the same Chrome build (Chrome/151.0.7922.170 (protocol 1.3, 15.1.206.21)), the same viewport (1280x800 @ dsf 1, headless=new), the same fixed 1500ms settle in every capture, and a warm window only as deep as this probe drove it — 15 captures over ~26s per warm arm. Those four were controlled, not proven invariant. In particular the depth condition is the one a daemon will exceed first: a daemon holds Chrome for hours across hundreds of pages, and this run does NOT extend to that. Pin the build, viewport and settle; re-run this probe on a Chrome upgrade; and if the daemon is to be long-lived, extend kN until the warm window matches the intended session length before trusting reuse at that depth.

## How to reproduce

```
cd appboxd && dart run tool/warm_vs_cold_probe.dart
```

Probe source: `appboxd/tool/warm_vs_cold_probe.dart` (self-contained; serves
its own pages from an in-process `HttpServer` on 127.0.0.1 — no network).

## Setup

- Source under measurement: `HEAD 83dd63e4 | lib/cdp.dart MODIFIED vs HEAD, sha256 9d12147176d45511`
  (`lib/cdp.dart` holds the capture path — `navigateAndSettle`, `setViewport`,
  `screenshot` — and is under concurrent edit by other work, so its content
  hash is recorded rather than assumed.)
- Chrome: `Chrome/151.0.7922.170 (protocol 1.3, 15.1.206.21)`
- GPU: `ANGLE (Apple, ANGLE Metal Renderer: Apple M4, Version 26.6.1 (Build 25G76)) | gpu_compositing=enabled rasterization=enabled webgl=enabled opengl=enabled_on`
- Viewport: 1280x800, deviceScaleFactor 1, `--headless=new`
- Settle: 1500ms, identical in every arm
- N: 5 samples per page per arm
- Page kinds:
  - `text` — 60 blocks across 6 web-safe families x 10 sizes x 6 weights,
    varying letter-spacing (exercises the font-shaping cache)
  - `css` — 24 tiles of linear/radial/conic gradients, box-shadow, blur,
    backdrop-filter, mix-blend-mode, rotate/scale transforms (GPU raster +
    shader cache)
  - `static` — 48 flat colour blocks, no text, no effects (control: must be
    identical in every arm)
- Arms: COLD-A (fresh launch + full dispose per capture), WARM-SAME-TAB (one
  launch, one tab), WARM-NEW-TAB (one launch, fresh tab per capture, same
  `--user-data-dir`), COLD-B (a second independent cold pass).
- Warm arms interleave the three pages across rounds rather than reloading one
  page, so every capture is a real cross-page navigation that forces a fresh
  layout + paint — and so the caches under test are genuinely exercised.

## Negative control

Two controls run through the exact capture path used by every measurement:

- **coarse** — the same page at 1280px vs 1281px wide; hashes must differ.
- **fine** — one 14px word recoloured by ONE step in the blue channel
  (`#202020` -> `#202021`) at an identical viewport; hashes must differ.

The fine control is the load-bearing one. Cache-driven drift, if it exists,
looks like a handful of antialiased glyph edges; an instrument that cannot see
a one-step recolour cannot see that either, and would report "identical" for
every arm regardless of the truth. A control failure aborts the run rather than
printing results.

Both controls are printed before any real result, in the raw output below.

## Render-richness gate

A page that rendered BLANK would be identical in every arm — the purest form of
a check whose pass outcome is also its did-not-run outcome. So each page must
clear a distinct-colour and non-white-coverage floor before its results are
allowed to count, and the measured richness is printed. The `GPU` line above
serves the same purpose for the `css` page: if headless had fallen back to CPU
raster, the shader cache that page exists to exercise would never have been in
play, and "css identical" would prove nothing about it.

## Results

```
# warm vs cold Chrome determinism probe

Source:   HEAD 83dd63e4 | lib/cdp.dart MODIFIED vs HEAD, sha256 9d12147176d45511
Chrome:   Chrome/151.0.7922.170 (protocol 1.3, 15.1.206.21)
GPU:      ANGLE (Apple, ANGLE Metal Renderer: Apple M4, Version 26.6.1 (Build 25G76)) | gpu_compositing=enabled rasterization=enabled webgl=enabled opengl=enabled_on
Viewport: 1280x800 @ dsf 1, headless=new, settle 1500ms
N:        5 samples per page per arm
Pages:    text (font-shaping) / css (GPU raster+shader) / static (flat control)

== NEGATIVE CONTROLS (instrument sensitivity) ==
NC-coarse  static @1280px vs @1281px  5f46dca47862 vs 39d4b937f253  => DIFFER (expected) PASS
NC-fine    one 14px word #202020 vs #202021  3a8f3b31ab90 vs 69f8b015da26  => DIFFER (expected) PASS
           magnitude: 123/1024000 px differ (0.0120%), max channel delta 1

== RENDER RICHNESS (did the pages draw anything?) ==
text    230 distinct colours, 14.5% non-white, 230252 PNG bytes  (floor: 40 colours, 3.0% non-white)  => PASS
css     246198 distinct colours, 100.0% non-white, 783269 PNG bytes  (floor: 5000 colours, 90.0% non-white)  => PASS
static  13 distinct colours, 84.4% non-white, 5126 PNG bytes  (floor: 8 colours, 50.0% non-white)  => PASS

CONTROL VERDICT: PASS — the instrument can see a difference, and the pages draw something to see it in

== PER-ARM STABILITY (distinct outputs within one arm) ==
page    arm            n/N    distinct-bytes  distinct-px  hash          ms/shot  status
text    COLD-A         5/5    1               1            83f4327eca34  1707     ok
text    WARM-SAME-TAB  5/5    1               1            83f4327eca34  1741     ok
text    WARM-NEW-TAB   5/5    1               1            83f4327eca34  1684     ok
text    COLD-B         5/5    1               1            83f4327eca34  1696     ok
css     COLD-A         5/5    1               1            35188c7443c4  1880     ok
css     WARM-SAME-TAB  5/5    1               1            35188c7443c4  1895     ok
css     WARM-NEW-TAB   5/5    1               1            35188c7443c4  1863     ok
css     COLD-B         5/5    1               1            35188c7443c4  1886     ok
static  COLD-A         5/5    1               1            5f46dca47862  1655     ok
static  WARM-SAME-TAB  5/5    1               1            5f46dca47862  1692     ok
static  WARM-NEW-TAB   5/5    1               1            5f46dca47862  1654     ok
static  COLD-B         5/5    1               1            5f46dca47862  1652     ok

== MACHINE DETERMINISM CHECK (COLD-A vs COLD-B) ==
text    IDENTICAL
css     IDENTICAL
static  IDENTICAL
MACHINE BASELINE: STABLE — cold is reproducible across two independent passes, so a warm difference would be attributable to warmth

== WARM == COLD ? (the question) ==
text    WARM-SAME-TAB  IDENTICAL to COLD-A
text    WARM-NEW-TAB   IDENTICAL to COLD-A
css     WARM-SAME-TAB  IDENTICAL to COLD-A
css     WARM-NEW-TAB   IDENTICAL to COLD-A
static  WARM-SAME-TAB  IDENTICAL to COLD-A
static  WARM-NEW-TAB   IDENTICAL to COLD-A

== VERDICT ==
YES, CONDITIONALLY — a warm Chrome is safe to reuse for pixel comparison, on the conditions actually held fixed by this run: the same Chrome build (Chrome/151.0.7922.170 (protocol 1.3, 15.1.206.21)), the same viewport (1280x800 @ dsf 1, headless=new), the same fixed 1500ms settle in every capture, and a warm window only as deep as this probe drove it — 15 captures over ~26s per warm arm. Those four were controlled, not proven invariant. In particular the depth condition is the one a daemon will exceed first: a daemon holds Chrome for hours across hundreds of pages, and this run does NOT extend to that. Pin the build, viewport and settle; re-run this probe on a Chrome upgrade; and if the daemon is to be long-lived, extend kN until the warm window matches the intended session length before trusting reuse at that depth.

Reproduce: cd appboxd && dart run tool/warm_vs_cold_probe.dart
```

## Notes and limits

- Distinct counts are computed by exact byte equality over the samples, not by
  hash bucketing, so they carry no collision risk. The printed hashes
  (FNV-1a 64, first 12 hex chars) are labels only; `package:crypto` is not an
  `appboxd` dependency.
- Both PNG-byte and decoded-RGBA distinct counts are reported. PNG encoding
  could in principle vary while pixels do not; the pixel column is what makes a
  "differs" result falsifiable.
- Sample counts are printed as `n/N` on every row, so a short arm cannot pass
  by trivially matching itself. Any throw, timeout, or zero-byte screenshot
  records an ERROR sample and marks the arm unhealthy.
- COLD-B exists to separate "warm drifts" from "this machine drifts". If the
  two cold passes ever disagree, no warm-vs-cold conclusion is available at all.
- The guards are checkable rather than decorative. To confirm the richness gate
  still bites, raise a floor in `kRichnessFloor` past what the page can render
  (e.g. `'static': (999999, 50.0)`) and re-run: the probe must print
  `FAIL — BLANK/TRIVIAL RENDER`, abort before any arm, and exit 3. This was run
  during development and behaved exactly so. The negative controls are checkable
  the same way — make the fine control's two colours equal and the run must
  abort.
- Every capture navigates to `about:blank` first, so the previous document is
  discarded. That is deliberate — it keeps the call sequence identical in all
  four arms — but it scopes the finding: this probe measures PROCESS- and
  GPU-level cache reuse (font shaping, raster, shader), not same-document state
  carryover. A daemon that reuses a live document rather than re-navigating is
  not covered by this result.
- Warm-window depth is a condition, not a proven invariant. Each warm arm ran
  15 captures over roughly half a minute. A real daemon holds
  Chrome for hours across hundreds of distinct pages; nothing here speaks to
  drift at that depth. Raise `kN` until the warm window matches the intended
  session length before relying on reuse for a long-lived daemon.
- What this probe does NOT cover: other viewports (only 1280x800), other device
  scale factors (only 1), `--visible` mode, `fullPage` captures, pages that load
  fonts or images over the network, and any Chrome build other than the one
  named above. A daemon reusing a warm browser should pin the viewport and
  settle it was measured at, and this file should be regenerated after a Chrome
  upgrade.

<!-- depth-probe-section -->

## Depth: how long can one warm Chrome be reused?

`warm_vs_cold_probe.dart` showed warm == cold, but only across 15
captures over ~26s. That was the weak condition in its verdict, since a
daemon holds one browser for hours. This section measures the two things
that condition leaves open: whether the warm browser ever diverges from
the cold baseline (and at which capture), and whether its memory grows.

### VERDICT (depth)

IN PROGRESS — depth reached so far: 171 of 700 (05m16s). This section is rewritten every 10 captures; if it still says IN PROGRESS the run did not finish, and nothing is claimed beyond the depth shown.

### Setup

- Probe: `appboxd/tool/warm_depth_probe.dart`
- Reproduce: `cd appboxd && dart run tool/warm_depth_probe.dart`
- Source under measurement: `HEAD aeba5dec | lib/cdp.dart clean at HEAD, sha256 f1a94ed732522304`
- Chrome: `Chrome/151.0.7922.170`
- Settle: the plain fixed `navigateAndSettle(settleMs: 1500)`.
  The newer `cdp.dart` helpers (`freezeAnimations`,
  `settleUntilStable`, `settleForCapture`,
  `navigateAndSettleForCapture`) exist and were deliberately NOT used,
  so this run stays comparable to the warm-vs-cold run above — the
  variable under test is the browser, not the settle. Their absence is
  a choice, not an oversight.
- Pages, hashing and the capture function are IMPORTED from
  `warm_vs_cold_probe.dart` rather than copied, so both probes drive
  byte-identical pages through a byte-identical capture path. Copying
  them would have broken the comparison the moment either changed.
- Arm: WARM-SAME-TAB, one browser, one tab, pages rotated. Same-tab was
  chosen over new-tab because font-shaping, GPU raster and shader caches
  live in the browser/GPU process and warm regardless of tab shape,
  while renderer-local state dies with the tab — so the same tab
  accumulates strictly more state and is the shape most likely to drift.
  Depth is the variable under test, so the budget went to one deep arm
  rather than two shallow ones.
- Target depth 700 captures, hard stop 30m.
  **Depth actually reached: 171 in 05m16s.**

### Q1 — drift onset

```
page    n     match  diverge  suspect  err  first-diverge   classification
text    57    57     0        0        0    —               no divergence
css     57    57     0        0        0    —               no divergence
static  57    57     0        0        0    —               no divergence
```

Divergence, if any, is classified rather than merely counted, because
the three shapes imply different fixes: TRANSIENT (diverges then returns
to baseline) suggests a settle race a retry would absorb; PERSISTENT
(never returns) is a real cache state change that caps reuse at the
onset index; WANDERING (several distinct outputs after onset) would kill
reuse outright.

### In-run negative control

The control is re-asserted every 50 captures, not just at the
start: a 25-minute run reporting "no drift" would be worthless if the
capture path had broken at minute 3 and every later hash were of an
error page. Each check re-renders the two one-RGB-step-apart variants and
requires them to differ; it also checks their hashes still match the cold
values, so drift on the control page itself is visible.

```
i=50 differ
i=100 differ
i=150 differ
```

The control cannot catch everything: it is its own page, so it would keep
passing even if the real pages began rendering blank. Every capture is
therefore also size-checked against its baseline PNG (a blank render
collapses to ~2KB against real pages of 5KB-783KB); anything more than
50% off is counted in the `suspect` column above and never as a match.

### Q2 — memory curve (WARM-SAME-TAB)

```
i      elapsed  browserRSS  summedRSS*  ps-procs  cdp-procs
0      00m02s   218MB       1172MB      9         9
10     00m19s   300MB       2069MB      15        15
20     00m37s   300MB       1831MB      13        13
30     00m55s   300MB       1831MB      13        13
40     01m13s   320MB       1859MB      13        13
50     01m34s   320MB       1851MB      13        13
60     01m52s   320MB       1857MB      13        13
70     02m10s   317MB       1838MB      13        13
80     02m28s   313MB       1814MB      13        13
90     02m46s   313MB       1818MB      13        13
100    03m07s   271MB       1715MB      13        13
110    03m25s   264MB       1707MB      13        13
120    03m43s   264MB       1710MB      13        13
130    04m01s   264MB       1713MB      13        13
140    04m19s   264MB       1708MB      13        13
150    04m40s   265MB       1711MB      13        13
160    04m58s   268MB       1718MB      13        13
170    05m16s   268MB       1713MB      13        13
```

`* summedRSS` sums `ps` RSS across every process holding the profile.
Chrome processes share large mappings, so that sum double-counts shared
pages — and the double-count grows with process count, which is the very
signal being read. It is an UPPER BOUND, not a measurement.
`browserRSS` (the browser process alone) is the defensible curve.
Chrome's own `SystemInfo.getProcessInfo` was checked on this build and
returns `type`, `id` and `cpuTime` only — no memory field — so it
contributes the process COUNT column and nothing more. That column is
still worth reading: `cdp-procs` (Chrome's own table) matching
`ps-procs` (this probe's reconstruction by `--user-data-dir` match) is
what licenses using `ps` for the memory numbers at all. Where the two
columns disagree, the `ps` rows are not the process set Chrome thinks
it has, and the RSS figures on that row should not be trusted.

MEMORY: NET DECLINE in steady state (Chrome releasing memory; not growth)
  steady range 264MB-320MB (band 56MB, noise threshold 5MB) 
  warmup   captures 0-40: 218MB -> 320MB (browser + GPU processes coming up; NOT a leak, and excluded from every growth number below)
  steady   captures 40-170: 320MB -> 268MB (-16.3%), 14 samples
  steady slope -55.23 MB per 100 captures  <- the number that matters
  (whole-arm slope -18.52 MB/100 is shown only to make the warmup artefact visible; do not use it)
  peak browserRSS 320MB
  labels are decided by TREND (the steady slope), not by the band: LINEAR GROWTH = >=+5MB/100 captures; NET DECLINE = <=-5MB/100; otherwise no sustained growth, reported as FLAT AND STABLE when the band is also inside the noise threshold and as oscillating-without-trend when it is not. A wide band alone is volatility, not growth, and only growth can force a recycle.

### Recycle policy

RECYCLE POLICY: memory does not require one within the measured window. After warmup, browserRSS moved -52MB across 130 captures (steady slope -55.23MB per 100 captures — no sustained upward trend), oscillating within a 56MB band and peaking at 320MB. Chrome both takes and releases memory across a run, so that band is volatility rather than growth, and volatility alone never forces a recycle. so no memory threshold is reachable from this data. Recommend recycling every 171 captures or 5 minutes, whichever comes first — the deepest point actually verified. A larger number would be a claim that going further is safe, which this run cannot support: recycling AT the verified depth is the only recommendation the evidence carries. The honest statement is "no growth was observed through 171 captures / 05m16s", and nothing here licenses a claim past that.

### New-tab churn tail

A short WARM-NEW-TAB run (fresh tab per capture, closed after) follows
the deep arm to answer the separate question of whether per-capture tab
churn leaks. It is short on purpose: depth belongs to the arm above.

```
not run
```

### What this does NOT establish

- Nothing beyond 171 captures / 05m16s. A daemon
  running longer than that is outside the measured window.
- Only this Chrome build, this viewport (1280x800 @ dsf 1), this fixed
  1500ms settle, and these three page kinds.
- Every capture re-navigates via `about:blank`, so this measures
  process- and GPU-level cache reuse, not same-document state carryover.
- Memory was read from `ps` RSS; Chrome's own per-process memory
  accounting is not exposed by the CDP commands available on this build.

