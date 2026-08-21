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
