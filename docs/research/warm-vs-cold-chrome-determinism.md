# Warm vs cold Chrome determinism

Does a REUSED (warm) Chrome render a page byte-identically to a
FRESHLY-LAUNCHED (cold) one? This gates the `appbox lens` daemon plan, which
would hold one warm Chrome to save the ~1.4s per-invocation launch. `lens`
exists to compare pixels, so a speed win that changes pixels is worthless.
No official Chromium / CDP / Puppeteer / Playwright source documents this
either way, so it is measured here rather than looked up.

## VERDICT

YES, CONDITIONALLY — a warm Chrome is safe to reuse for pixel comparison, on the conditions actually held fixed by this run: the same Chrome build (Chrome/151.0.7922.170 (protocol 1.3, 15.1.206.21)), the same viewport (1280x800 @ dsf 1, headless=new), the same fixed 1500ms settle in every capture, and a warm window only as deep as THIS probe drove it — 15 captures over ~26s per warm arm. Those four were controlled, not proven invariant. Pin the build, viewport and settle, and re-run this probe on a Chrome upgrade.

The depth condition is NOT limited to the 15 captures above: it was measured separately and much deeper by `warm_depth_probe.dart`. See the "Depth" section further down this document for the depth actually verified, the drift-onset result, the memory curve and the recycle policy — that section, not this paragraph, is the authority on how long one warm Chrome may be reused.

## How to reproduce

```
cd appboxd && dart run tool/warm_vs_cold_probe.dart
```

Probe source: `appboxd/tool/warm_vs_cold_probe.dart` (self-contained; serves
its own pages from an in-process `HttpServer` on 127.0.0.1 — no network).

## Setup

- Source under measurement: `HEAD 4b80ab8b | lib/cdp.dart clean at HEAD, sha256 f1a94ed732522304`
  (`lib/cdp.dart` holds the capture path — `navigateAndSettle`, `setViewport`,
  `screenshot` — and is under concurrent edit by other work, so its content
  hash is recorded rather than assumed.)
- Chrome: `Chrome/151.0.7922.170 (protocol 1.3, 15.1.206.21)`
- GPU: `ANGLE (Apple, ANGLE Metal Renderer: Apple M4, Version 26.6.1 (Build 25G76)) | gpu_compositing=enabled rasterization=enabled webgl=enabled opengl=enabled_on`
- Viewport: 1280x800, deviceScaleFactor 1, `--headless=new`
- Settle: 1500ms, identical in every arm
- N: 5 samples per page per arm
- Machine state: no other Chrome work was running. For the deep run in the
  "Depth" section the team lead deliberately held off launching any captures,
  so both measurements were taken on an otherwise-quiet machine. This matters:
  CPU and GPU contention from a second browser is exactly the kind of thing that
  could manufacture a spurious "drift", and a determinism claim measured under
  unknown contention would be much weaker than one measured under known-quiet
  conditions.
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

Source:   HEAD 4b80ab8b | lib/cdp.dart clean at HEAD, sha256 f1a94ed732522304
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
text    COLD-A         5/5    1               1            83f4327eca34  1710     ok
text    WARM-SAME-TAB  5/5    1               1            83f4327eca34  1729     ok
text    WARM-NEW-TAB   5/5    1               1            83f4327eca34  1698     ok
text    COLD-B         5/5    1               1            83f4327eca34  1706     ok
css     COLD-A         5/5    1               1            35188c7443c4  1867     ok
css     WARM-SAME-TAB  5/5    1               1            35188c7443c4  1905     ok
css     WARM-NEW-TAB   5/5    1               1            35188c7443c4  1867     ok
css     COLD-B         5/5    1               1            35188c7443c4  1870     ok
static  COLD-A         5/5    1               1            5f46dca47862  1654     ok
static  WARM-SAME-TAB  5/5    1               1            5f46dca47862  1695     ok
static  WARM-NEW-TAB   5/5    1               1            5f46dca47862  1652     ok
static  COLD-B         5/5    1               1            5f46dca47862  1653     ok

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
YES, CONDITIONALLY — a warm Chrome is safe to reuse for pixel comparison, on the conditions actually held fixed by this run: the same Chrome build (Chrome/151.0.7922.170 (protocol 1.3, 15.1.206.21)), the same viewport (1280x800 @ dsf 1, headless=new), the same fixed 1500ms settle in every capture, and a warm window only as deep as THIS probe drove it — 15 captures over ~26s per warm arm. Those four were controlled, not proven invariant. Pin the build, viewport and settle, and re-run this probe on a Chrome upgrade.

The depth condition is NOT limited to the 15 captures above: it was measured separately and much deeper by `warm_depth_probe.dart`. See the "Depth" section further down this document for the depth actually verified, the drift-onset result, the memory curve and the recycle policy — that section, not this paragraph, is the authority on how long one warm Chrome may be reused.

Reproduce: cd appboxd && dart run tool/warm_vs_cold_probe.dart
```

## Operational hazards for a warm-Chrome daemon

Found the hard way while running these probes, not derived from theory. All
three bite a daemon specifically, because a daemon holds ONE browser for hours.

**1. The `appbox-cdp-` profile prefix is shared by every launch.**
`CdpClient.launch()` creates its profile with
`Directory.systemTemp.createTemp('appbox-cdp-')`, so every Chrome any code in
this repo starts carries that prefix. A `pkill -f "appbox-cdp-"` therefore kills
*every* such Chrome on the machine at once — a daemon's long-lived browser
included, and any colleague's capture along with it. This was done for real
during this work while reaping a killed probe's orphans, and it could have taken
out another worker's session.

**2. The correct reap is an ownership check, not a prefix match.**
`cdp.dart`'s `_pidsOwningProfile(dir, browserOnly: true)` matches on the exact
`--user-data-dir=<dir>` and guards the boundary explicitly — its comment reads
"Whole dir, not a prefix: `appbox-cdp-AB` must not claim `…-ABC`'s pid", so
someone has already been bitten by this class of bug. A daemon reaping orphans
at startup must ask *who owns this specific dir* and kill only those pids; a
profile dir with no owning pid is a genuine orphan and its directory can be
deleted on its own. `CdpClient` exposes `userDataDir` and `chromePid` for
exactly this purpose.

**3. A SIGKILLed run can never clean up after itself, so something else must.**
`close()` is what awaits profile release and deletes the dir; a hard kill skips
it entirely, leaving both a live browser and its profile behind. Orphan reaping
on daemon startup is therefore not optional — and it must be the scoped kind
from point 2, or the daemon's own cleanup becomes the thing that kills its
neighbours.

**4. Nothing tells a daemon its browser died.**
CDP has no event for full browser death — `Target.targetCrashed` covers
renderers only. The sole liveness signal is the transport: a closed WebSocket,
or a `Browser.getVersion` round-trip that throws. A daemon must treat socket
closure as browser death and relaunch, rather than assuming a browser it has not
heard from is still there. This probe uses exactly that round-trip as its
liveness check for the same reason.

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
- Warm-window depth is a condition, not a proven invariant *for this probe*:
  each warm arm here ran only 15 captures over roughly half a
  minute. Depth is answered by `warm_depth_probe.dart` in the "Depth" section
  below, which drives one warm browser far deeper and reports drift onset and
  the memory curve. Read that section for the depth actually verified; do not
  read a depth limit out of this one.
- What this probe does NOT cover: other viewports (only 1280x800), other device
  scale factors (only 1), `--visible` mode, `fullPage` captures, pages that load
  fonts or images over the network, and any Chrome build other than the one
  named above. A daemon reusing a warm browser should pin the viewport and
  settle it was measured at, and this file should be regenerated after a Chrome
  upgrade.
- The newer `cdp.dart` settle helpers (`freezeAnimations`, `settleUntilStable`,
  `settleForCapture`, `navigateAndSettleForCapture`) are deliberately NOT used
  here. This probe uses the plain fixed `navigateAndSettle(settleMs: 1500)`
  so its runs stay comparable to each other; the variable under test is the
  browser, not the settle. Their absence is a choice, not an oversight.

<!-- depth-probe-section -->

## Depth: how long can one warm Chrome be reused?

`warm_vs_cold_probe.dart` showed warm == cold, but only across 15
captures over ~26s. That was the weak condition in its verdict, since a
daemon holds one browser for hours. This section measures the two things
that condition leaves open: whether the warm browser ever diverges from
the cold baseline (and at which capture), and whether its memory grows.

### VERDICT (depth)

NO DRIFT WITHIN THE MEASURED DEPTH. One warm Chrome produced byte-identical output to the cold baseline across all 700 captures over 21m39s, on every page kind, with the negative control re-asserted throughout. This does NOT extend past 700 captures / 21m39s — that is the window measured, and the claim stops there.

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
  **Depth actually reached: 700 in 21m39s.**

### Q1 — drift onset

```
page    n     match  diverge  suspect  err  first-diverge   classification
text    234   234    0        0        0    —               no divergence
css     233   233    0        0        0    —               no divergence
static  233   233    0        0        0    —               no divergence
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
i=200 differ
i=250 differ
i=300 differ
i=350 differ
i=400 differ
i=450 differ
i=500 differ
i=550 differ
i=600 differ
i=650 differ
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
180    05m34s   252MB       1699MB      13        13
190    05m52s   253MB       1701MB      13        13
200    06m13s   253MB       1696MB      13        13
210    06m31s   253MB       1701MB      13        13
220    06m49s   253MB       1703MB      13        13
230    07m07s   253MB       1699MB      13        13
240    07m25s   253MB       1703MB      13        13
250    07m47s   253MB       1702MB      13        13
260    08m05s   253MB       1702MB      13        13
270    08m23s   253MB       1703MB      13        13
280    08m41s   253MB       1706MB      13        13
290    08m58s   253MB       1702MB      13        13
300    09m20s   253MB       1697MB      13        13
310    09m38s   254MB       1706MB      13        13
320    09m56s   253MB       1701MB      13        13
330    10m14s   253MB       1705MB      13        13
340    10m32s   254MB       1707MB      13        13
350    10m53s   254MB       1701MB      13        13
360    11m11s   254MB       1704MB      13        13
370    11m29s   254MB       1706MB      13        13
380    11m47s   254MB       1703MB      13        13
390    12m05s   254MB       1706MB      13        13
400    12m26s   254MB       1705MB      13        13
410    12m44s   253MB       1700MB      13        13
420    13m02s   253MB       1702MB      13        13
430    13m20s   253MB       1704MB      13        13
440    13m38s   253MB       1701MB      13        13
450    13m59s   253MB       1696MB      13        13
460    14m17s   253MB       1705MB      13        13
470    14m35s   253MB       1700MB      13        13
480    14m53s   253MB       1702MB      13        13
490    15m11s   253MB       1706MB      13        13
500    15m32s   253MB       1700MB      13        13
510    15m50s   253MB       1702MB      13        13
520    16m08s   252MB       1703MB      13        13
530    16m26s   252MB       1698MB      13        13
540    16m44s   252MB       1703MB      13        13
550    17m05s   252MB       1700MB      13        13
560    17m23s   252MB       1698MB      13        13
570    17m41s   252MB       1700MB      13        13
580    17m59s   252MB       1704MB      13        13
590    18m17s   252MB       1699MB      13        13
600    18m38s   252MB       1696MB      13        13
610    18m56s   252MB       1705MB      13        13
620    19m14s   252MB       1698MB      13        13
630    19m32s   254MB       1724MB      13        13
640    19m50s   254MB       1709MB      13        13
650    20m11s   254MB       1702MB      13        13
660    20m29s   254MB       1712MB      13        13
670    20m47s   254MB       1710MB      13        13
680    21m05s   254MB       1705MB      13        13
690    21m23s   255MB       1713MB      13        13
700    21m39s   255MB       1711MB      13        13
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

MEMORY: NO SUSTAINED GROWTH after warmup (oscillates within 16MB, no trend)
  steady range 252MB-268MB (band 16MB, noise threshold 5MB) 
  settling captures 0-170: 218MB -> 268MB, peaking at 320MB (processes coming up AND Chrome then releasing what it over-allocated — this segment both rises and falls, so read the table rather than these two endpoints; NOT a leak, and excluded from every growth number below)
  steady   captures 170-700: 268MB -> 255MB (-4.9%), 54 samples
  steady slope -0.26 MB per 100 captures  <- the number that matters
  (whole-arm slope -5.55 MB/100 is shown only to make the warmup artefact visible; do not use it)
  peak browserRSS 320MB
  labels are decided by TREND (the steady slope), not by the band: LINEAR GROWTH = >=+5MB/100 captures; NET DECLINE = <=-5MB/100; otherwise no sustained growth, reported as FLAT AND STABLE when the band is also inside the noise threshold and as oscillating-without-trend when it is not. A wide band alone is volatility, not growth, and only growth can force a recycle.

### Recycle policy

RECYCLE POLICY: memory does not require one within the measured window. After warmup, browserRSS moved -13MB across 530 captures (steady slope -0.26MB per 100 captures — no sustained upward trend), oscillating within a 16MB band and peaking at 320MB. Chrome both takes and releases memory across a run, so that band is volatility rather than growth, and volatility alone never forces a recycle — no memory threshold is reachable from this data. Recommend recycling every 700 captures or 22 minutes, whichever comes first — the deepest point actually verified. A larger number would be a claim that going further is safe, which this run cannot support: recycling AT the verified depth is the only recommendation the evidence carries. The honest statement is "no growth was observed through 700 captures / 21m39s", and nothing here licenses a claim past that.

### New-tab churn tail

A short WARM-NEW-TAB run (fresh tab per capture, closed after) follows
the deep arm to answer the separate question of whether per-capture tab
churn leaks. It is short on purpose: depth belongs to the arm above.

**It is too short to answer the leak question, and the number below should not
be read as if it did.** The same-tab arm did not reach steady state until around
capture 170; this tail stops at 100, so it never leaves its own settling phase
and its end-to-end delta cannot separate churn-driven growth from ordinary
warmup. What the tail DOES establish is the drift result — every tail capture is
compared against the same cold baseline, and that comparison is valid at any
depth. For a daemon that opens a fresh tab per capture, memory behaviour is
therefore NOT established here; raise `kTailDepth` past the settling point and
re-run before relying on it.

```
depth reached: 100 of 100, diverged 0, errors 0
i      elapsed  browserRSS  summedRSS*  ps-procs  cdp-procs
0      00m02s   219MB       870MB       7         7
10     00m20s   300MB       992MB       7         7
20     00m38s   300MB       758MB       5         5
30     00m56s   301MB       758MB       5         5
40     01m14s   320MB       781MB       5         5
50     01m32s   320MB       782MB       5         5
60     01m50s   320MB       782MB       5         5
70     02m09s   321MB       786MB       5         5
80     02m27s   322MB       786MB       5         5
90     02m45s   348MB       813MB       5         5
100    03m01s   325MB       920MB       6         6
browserRSS change over 100 new-tab captures: +106MB  (raw first-to-last, INCLUDES startup warmup — the browser and GPU processes coming up account for most of any early rise, so this is an upper bound on churn-driven growth, not a leak measurement)
```

### What this does NOT establish

- Nothing beyond 700 captures / 21m39s. A daemon
  running longer than that is outside the measured window.
- Only this Chrome build, this viewport (1280x800 @ dsf 1), this fixed
  1500ms settle, and these three page kinds.
- Every capture re-navigates via `about:blank`, so this measures
  process- and GPU-level cache reuse, not same-document state carryover.
- Memory was read from `ps` RSS; Chrome's own per-process memory
  accounting is not exposed by the CDP commands available on this build.


<!-- settle-rate-probe-section -->

## Settle rate: does memory stay flat at the daemon's real screenshot rate?

The depth section above measured 700 captures using the plain fixed
`navigateAndSettle(1500)` — ONE `Page.captureScreenshot` per capture. That
was correct for the drift question, and that result stands. It is the wrong
unit for the memory question: the daemon runs `settleForCapture`, whose two
stability loops each screenshot repeatedly until two frames match. A recycle
policy denominated in "captures" is denominated in the wrong unit for the
workload it governs.

### HEADLINE

NO DRIFT and MEMORY: FLAT AND STABLE at the real screenshot rate (whole steady segment inside a 4MB band vs a 7MB noise threshold)

### Screenshots per capture — measured, not assumed

```
samples  19 replication checkpoints, every 10 captures
min      5
median   5
max      5
non-converged checkpoints: 0
replica != real:           0
```

Reported as a distribution, never a mean: a converged loop costs ~2-3
shots, but a TIMED-OUT loop burns the full 8000ms at a 120ms poll —
roughly 66 shots — so one timeout would drag a mean badly and
silently. Counts include +1 for the caller's own final `screenshot()`,
which the settle itself does not take.

### Why the count needs a replication at all

`settleForCapture` (cdp.dart:819-865) computes `first.captures` and
`second.captures` from its two `settleUntilStable` calls and then DISCARDS
both — its return record is `(elapsedMs, converged, frozen)`. So the real
screenshot rate is not observable through `navigateAndSettleForCapture`.

The arm therefore runs the GENUINE method for every capture — the memory
curve is measured on the real code, not on a copy of it — and every
10 captures one EXTRA capture runs a replication of that exact
sequence, built only from public methods, purely to read the counts. Each
checkpoint also asserts the replication's PNG is byte-identical to the real
capture of the same page, so fidelity is verified continuously rather than
once in a cold browser where it is least likely to break.

**Suggested change to `lib/cdp.dart` (NOT made here — this probe does not
edit `lib/`):** propagate `first.captures + second.captures` in
`settleForCapture`'s return record. The screenshot rate then becomes
directly observable and no replication is needed by anyone.

### Drift (free by-product)

```
page    n     match  diverge  notConv  err  first-diverge
text    67    67     0        0        0    —
css     67    67     0        0        0    —
static  66    66     0        0        0    —
```

These captures were compared against FRESH cold baselines taken through the
same freeze path, not against the plain-settle baselines used elsewhere in
this document. `freezeAnimations` mutates the DOM (inline `!important`,
stripped `animation`), so a freeze-path capture cannot match a plain-settle
one; comparing across paths would read as 100% divergence and mean nothing.
This is a drift result at depth 200, independent of and additional to
the 700 in the depth section.

A `converged: false` capture is counted in its own `notConv` column and is
neither a match nor a divergence. `cdp.dart:842-846` is explicit that a
non-converged settle must not read as success, and a timed-out settle means
the capture is not reproducible at all.

### Memory vs screenshot rate

```
i      ~shots   elapsed  browserRSS  summedRSS*  ps-procs  cdp-procs
0      0        00m02s   233MB       1297MB      11        12
10     50       00m30s   303MB       1961MB      14        14
20     100      00m56s   303MB       1828MB      13        13
30     150      01m23s   323MB       1861MB      13        13
40     200      01m51s   323MB       1861MB      13        13
50     250      02m17s   324MB       1855MB      13        13
60     300      02m44s   324MB       1865MB      13        13
70     350      03m12s   324MB       1864MB      13        13
80     400      03m38s   327MB       1862MB      13        13
90     450      04m05s   327MB       1871MB      13        13
100    500      04m33s   327MB       1870MB      13        13
110    550      04m59s   327MB       1867MB      13        13
120    600      05m26s   328MB       1874MB      13        13
130    650      05m54s   328MB       1873MB      13        13
140    700      06m20s   328MB       1867MB      13        13
150    750      06m47s   328MB       1876MB      13        13
160    800      07m15s   328MB       1873MB      13        13
170    850      07m41s   328MB       1871MB      13        13
180    900      08m07s   328MB       1876MB      13        13
190    950      08m35s   328MB       1874MB      13        13
200    1000     08m58s   328MB       1874MB      13        13
```

`* summedRSS` double-counts shared pages across Chrome processes and is an
UPPER BOUND, not a measurement; `browserRSS` is the defensible curve.

MEMORY: FLAT AND STABLE at the real screenshot rate (whole steady segment inside a 4MB band vs a 7MB noise threshold)
  steady range 324MB-328MB (band 4MB, noise threshold 7MB), 16 samples
  max sustained rise 4MB  <- THE growth number: the largest increase from any earlier sample to any later one, which answers "does it grow" without assuming the curve is a line
  (fitted slope +5.29 MB per 1000 screenshots — shown for completeness only. DO NOT QUOTE IT as the growth number: in this design the growth test is the max sustained rise above, and a fitted slope has misread every real curve shape encountered here.)
  peak browserRSS 328MB over ~1000 screenshots in 08m58s
  RECYCLE: memory does not require one. At ~5 screenshots per capture, this arm drove ~1000 screenshots and the largest sustained rise anywhere in the steady segment was 4MB — below the 7MB noise threshold, so no growth. The daemon-convertible figure is ~1000 SCREENSHOTS verified flat; a workload with a different shots-per-capture converts through it, which is why it is reported in that unit. Do NOT read "200 captures" as a ceiling — that is only how far THIS arm ran. On the capture axis the Depth section above verified 700 captures drift-free and growth-free, which is the stronger capture-axis result. Neither arm found a ceiling: the binding limit is whichever axis a real workload reaches first, and no upper bound was observed on either.

### How the memory classifier was checked

"No growth" is only worth reading if the classifier can say the opposite,
so it was run against three curves before this result was accepted: the two
real curves this arm produced (one plateau, one plateau followed by a 72MB
release) and a synthetic linearly-growing curve. The first two classify as
NO GROWTH, the third as GROWTH with a sensible extrapolation — so the growth
branch fires and the negative result is falsifiable rather than decorative.

The growth test is `max sustained rise > noise threshold`, deliberately NOT
a fitted slope. Across this work a least-squares fit has misread three
different real curve shapes — startup warmup (reported +665MB/100 captures),
oscillation, and a step — and each time the fit described the shape rather
than any trend. The max-rise test makes no assumption about shape. The
fitted slope is still printed, but labelled not to be quoted when a step is
present.

Note also that the two runs of this arm produced DIFFERENT memory curves —
one released ~72MB partway through, the other did not. browserRSS is
therefore not reproducible run-to-run in its detail. Neither run grew, which
is the claim being made; a claim about the exact curve would not be
supportable.

### Limits

- Depth reached: **200 captures (~1000 screenshots) in 08m58s.**
  Nothing is claimed beyond that.
- The depth section measured settling running to ~capture 170 on the
  one-screenshot path. This arm is 200 captures, so its steady segment is
  short; where it is too short to carry a slope the classifier says
  INCONCLUSIVE rather than fitting one.
- Screenshot counts come from 19 checkpoints, not from all
  200 captures — the real method does not expose them.
- Same fixed conditions as the rest of this document: this Chrome build,
  1280x800 @ dsf 1, headless=new, and these three page kinds.
- **The freeze is a no-op on these pages, so its DOM-mutation cost is NOT
  covered.** `freezeAnimations()` reported
  `{finite: 0, infinite: 0, smil: 0, videos: 0, committed: 0}` on every
  capture — the probe pages are deliberately animation-free, so there was
  nothing to freeze and no inline `!important` was ever written. What this
  arm therefore measures is the cost of the higher SCREENSHOT rate, which is
  the question asked. It does NOT measure the cost of freezing a genuinely
  animated page, where the freeze walks the DOM and writes inline styles
  across many elements on every capture. Real daemon pages will have
  animations. To close that gap, add an animated page kind and re-run — it
  is a separate question from the one measured here, and it is not answered
  by this result.
- A side effect of the same fact: because the freeze mutated nothing, the
  fresh freeze-path baselines came out byte-identical to the plain-settle
  baselines used elsewhere in this document. Capturing them fresh was still
  the right precaution — it just turned out not to be needed on these
  particular pages, and it would be needed on any page with animation.


<!-- animated-pages-probe-section -->

## Animated pages: the case the settle protocol exists for

Every warm-Chrome result above this section was measured on pages where
`freezeAnimations()` reported `{finite: 0, infinite: 0, smil: 0,
videos: 0, committed: 0}` — the machinery under test did nothing. The lens
exists to capture animated pages, so "a warm Chrome is safe to reuse" was
proven only in the case where the protocol was not needed. This section
closes that hole.

There is a measured reason to expect a difference, from `cdp.dart:641-651`:
an element that merely HAS an animation is promoted to its own compositor
layer, and that layer rasters differently run to run — a page whose
animation was provably pinned still gave 3 distinct images of 4, worst case
13,345 pixels. Compositor promotion is exactly the GPU-side state a warm
browser might reuse differently, and no earlier arm touched it.

### Setup

- Probe: `appboxd/tool/warm_anim_probe.dart`
- Reproduce: `cd appboxd && dart run tool/warm_anim_probe.dart`
- Source: `HEAD d8717759 | lib/cdp.dart clean at HEAD, sha256 2a8cd7c1fb4f88a4`
- Chrome: `Chrome/151.0.7922.170`
- Path: the real `navigateAndSettleForCapture`, reading its own
  `screenshots` field (added in `d8717759`) — the replication harness the
  settle-rate section needed is gone.
- Pages: `anim-inf` (18 tiles, INFINITE gradient/transform/opacity
  animations → freeze pauses and pins `currentTime = 0`); `anim-fin`
  (24 cards, FINITE animations with `fill: both` holding non-default end
  states → freeze calls `finish()`, then commits inline and de-promotes);
  `control` (the animation-free static page, byte-identical to the one used
  throughout this document).
- Cold N: 10 per animated page, 5 for the control.
  Ten rather than five on the animated pages because the prior evidence was
  3-of-4 distinct; at N=5 an intermittent fault could show 1 distinct by
  luck, certify cold as stable, and make the warm arm's divergences look
  like warmth.
- Warm arm: 180 captures, one browser, one tab, three pages rotated.
  **Depth reached: 180 in 07m05s.**

The control's freeze-path hash was checked against `5f46dca47862`, the
hash the static page has produced on the plain-settle path through five
prior runs in this document: **MATCH** — the apparatus here is consistent with everything above.

### Q1 — does the freeze stay effective across a long warm session?

**`settleForCapture`'s `frozen` map cannot answer this, and using it
would have produced a false alarm.** The sequence is freeze -> floor ->
loop -> freeze -> loop, and the record returns the SECOND freeze
(`cdp.dart:835`). The first freeze has already written
`animation: none !important` onto every animated element, so the second
finds nothing left. Measured directly on these pages:

```
/anim-infinite   getAnimations()=18   1st {infinite:18, committed:18}   2nd all 0
/anim-finite     getAnimations()=24   1st {finite:24,   committed:24}   2nd all 0
/static-control  getAnimations()=0    1st all 0                         2nd all 0
```

So `frozen['committed'] > 0` is FALSE on every correctly-frozen page —
the assertion would fail exactly when the freeze is working. The field
reads zero whether the freeze did everything or nothing: its "all fine"
value equals its "did not run" value, which is the shape this document
exists to avoid. `freezeAnimations` documents that a caller seeing
`{finite: 0, infinite: 0}` on a page it believes is animated "has learned
something"; routed through `settleForCapture` every caller sees that
always, so the diagnostic is silently destroyed.

Q1 is therefore answered two ways, neither using `frozen`.

**(a) Every capture, on the real path** — after the settle, count live
animations. The freeze drops the `animation` property, so this must be 0;
if the freeze ever stops working, live animations remain.

```
page      n     liveAfter distribution                  freeze-lost
anim-inf  60    min 0, median 0, max 0, n=60            0
anim-fin  60    min 0, median 0, max 0, n=60            0
control   60    min 0, median 0, max 0, n=60            0
```

**(b) Periodically, by hand** — navigate fresh, count animations BEFORE
any freeze, then call `freezeAnimations()` directly to read the FIRST
pass. (a) catches the freeze failing; (b) catches the PAGE failing, which
(a) would pass trivially since a page that stopped animating also leaves
zero live animations.

```
page      preAnims (before freeze)          firstFreezeCommitted
anim-inf  min 18, median 18, max 18, n=2    min 18, median 18, max 18, n=2
anim-fin  min 24, median 24, max 24, n=3    min 24, median 24, max 24, n=3
control   min 0, median 0, max 0, n=3       min 0, median 0, max 0, n=3
```

**The freeze kept working for the whole arm.** Zero live animations after every settle, and the periodic probe kept finding live animations to freeze and committing them — so the pages never went inert either.

### Q2 — do animated pages stay byte-identical warm vs cold?

```
page      cold                    n     match  diverge  notConv  shape
anim-inf  stable (10 passes)      60    60     0        0        no divergence
anim-fin  stable (10 passes)      60    60     0        0        no divergence
control   stable (5 passes)       60    60     0        0        no divergence
```

**No drift.** Every page that could reproduce itself cold also matched
that cold baseline from a warm browser, for all 180 captures — the
animated pages included. The compositor-promotion effect quoted above
does not, on this evidence, survive the freeze's de-promotion pass, and
reusing a warm browser does not reintroduce it.

### Q3 — memory with the freeze doing real work

```
i      elapsed  browserRSS  summedRSS*  ps-procs  cdp-procs
0      00m03s   235MB       1444MB      11        11
10     00m26s   300MB       2060MB      15        15
20     00m49s   300MB       1814MB      13        13
30     01m13s   308MB       1827MB      13        13
40     01m37s   320MB       1849MB      13        13
50     02m00s   320MB       1840MB      13        13
60     02m24s   320MB       1849MB      13        13
70     02m48s   320MB       1854MB      13        13
80     03m11s   320MB       1846MB      13        13
90     03m35s   320MB       1846MB      13        13
100    03m58s   324MB       1862MB      13        13
110    04m22s   324MB       1848MB      13        13
120    04m46s   324MB       1857MB      13        13
130    05m09s   324MB       1860MB      13        13
140    05m33s   324MB       1853MB      13        13
150    05m57s   324MB       1854MB      13        13
160    06m20s   324MB       1865MB      13        13
170    06m44s   324MB       1850MB      13        13
180    07m05s   324MB       1852MB      13        13
```

`* summedRSS` double-counts shared pages — upper bound, not a measurement.

MEMORY: FLAT AND STABLE at the real screenshot rate (whole steady segment inside a 4MB band vs a 6MB noise threshold)
  steady range 320MB-324MB (band 4MB, noise threshold 6MB), 15 samples
  max sustained rise 4MB  <- THE growth number: the largest increase from any earlier sample to any later one, which answers "does it grow" without assuming the curve is a line
  (fitted slope +7.71 MB per 1000 screenshots — shown for completeness only. DO NOT QUOTE IT as the growth number: in this design the growth test is the max sustained rise above, and a fitted slope has misread every real curve shape encountered here.)
  peak browserRSS 324MB over ~900 screenshots in 07m05s
  RECYCLE: memory does not require one. At ~5 screenshots per capture, this arm drove ~900 screenshots and the largest sustained rise anywhere in the steady segment was 4MB — below the 6MB noise threshold, so no growth. The daemon-convertible figure is ~900 SCREENSHOTS verified flat; a workload with a different shots-per-capture converts through it, which is why it is reported in that unit. Do NOT read "180 captures" as a ceiling — that is only how far THIS arm ran. On the capture axis the Depth section above verified 700 captures drift-free and growth-free, which is the stronger capture-axis result. Neither arm found a ceiling: the binding limit is whichever axis a real workload reaches first, and no upper bound was observed on either.

Same max-sustained-rise test and same classifier as the settle-rate
section, which was validated against both real curves and a synthetic
growing curve before its negative result was accepted.

Screenshots per capture here: min 5, median 5, max 5, n=180
(read from `settleForCapture.screenshots`, +1 for the caller's own final
`screenshot()`).

### Limits

- Depth reached: **180 captures in 07m05s**. Nothing is claimed beyond it.
- Two animated page kinds, not an exhaustive set. GIF and APNG have no
  pause API at all — `cdp.dart` says so and Playwright has the same hole —
  so they are outside both the freeze and this measurement.
- Cross-origin iframes and `<video>` are likewise untested here.
- Same fixed conditions as the rest of this document: this Chrome build,
  1280x800 @ dsf 1, headless=new, machine otherwise quiet.

