# Frame-Based Motion Recovery ("flipbook") — probe-runner

## Goal
Content-independent, platform-universal animation certification. Derive an animation's
motion law (translate / scale / rotate / opacity over scroll or time) from a **sequence of
screenshots** — independent of *what* is shown — so that:
- a clone with different image content (forest) can be certified against the source (kasane)
  by motion **shape**, not pixels;
- native iOS / Android / Flutter (no DOM, no WAAPI) get the **same** certification as web,
  because the only input is a screenshot, which every platform can produce.

## Why (vs existing `web_anim`)
- `web_anim` reads exact transforms from the DOM via CDP — **web-only**, exact, sub-pixel.
- Frame-based works **anywhere a screenshot exists**; decouples certification from the
  platform's introspection API.
- **Fusion:** where both are available (web), cross-validate frame-derived vs DOM-derived
  curves → dual-source certification (high confidence).

## Pipeline
1. **Capture** — ordered frames + an index: `scrollY` for scroll-scrubbed, `timestamp` for
   time-based. Reuse existing shooters: `web_shot` / `multishot` / `web_record` (web),
   `ios_shot`, `adb_shot`, `flutter_shot` (native); `ffmpeg` splits video → frames at known fps.
2. **Localize movers** — inter-frame differencing → bounding boxes of changing regions
   (frame-based analog of `web_anim` auto-discovery).
3. **Per-region motion estimation** vs frame 0:
   - **Primary — template tracking (cv2 `matchTemplate`, normalized cross-correlation).**
     The common UI case is an object moving against a background; global phase
     correlation FAILS there (it assumes the whole frame shifts). The element's
     **frame-0 bbox is obtained free from introspection** (DOM `getBoundingClientRect`
     on web, UI-tree bounds on native); that bbox becomes the template, tracked across
     frames by pixels → trajectory. Validated on real browser screenshots: 0.00%
     amplitude error, easeOutCubic rms 0.0004, confidence 0.93. cv2 is therefore
     **recommended**, not merely optional (`opencv-python-headless`).
   - **Fallback — phase correlation (numpy + Pillow).** Only valid for *global* motion
     (whole frame shifts uniformly). Kept as the dep-light path; not for objects-on-bg.
   - **Scale / rotation:** cv2 ORB + `estimateAffinePartial2D` (preferred), or numpy
     log-polar FFT / Fourier-Mellin (content-sensitive fallback).
   - **Opacity:** region mean luminance / contrast vs static background (low-confidence
     channel; cross-check DOM on web).
   - **DPR:** divide image-px displacement by `devicePixelRatio` → CSS px.

   **Domain split (validated):** frame-based recovery's natural domain is
   **static-viewport, time/event motion** (menu, entrance, preloader) — exactly the gap.
   **Scroll-scrubbed** animations stay on `web_anim` (DOM read), because a fixed capture
   window on a scrolling page measures scroll-through, not the element transform.
4. **Fit** — feed trajectory tx(t)/ty(t)/scale(t)/opacity(t) into the existing **`_anim_core`**
   fitter (pure stdlib) → easing name + cubic-bezier + duration/amplitude + rms. Reuse, do not
   reinvent. This is "combine both techniques."
5. **Certify**
   - **Reproducibility:** re-capture, re-derive, same curve (replay gate). `t=0` aligned by
     **first-frame-difference onset**, not wall-clock (or by scrollY for scrubbed).
   - **Cross-method (web):** frame-derived ≈ DOM-derived (`web_anim`).
   - **Source-vs-clone (locked bar):** compare **normalized shape** — same easing + amplitude
     as **% of element/viewport**, NOT raw px (content + size differ). This is the acceptance
     definition.
6. **Scrub** — fitted curve f∈[0,1] evaluable forward/reverse on any content (the "flipbook"
   reconstructed as a parametric law).

## Dependencies
`numpy 2.4.6` ✓, `Pillow 12.2` ✓, `ffmpeg 8.1` ✓ already installed → **baseline ships now**.
`cv2` optional (heavy ~90 MB): lazy import with a pip recipe on failure (same pattern as the
Flutter VM bridge). `_anim_core` already pure stdlib — no new dep for the fit.

## Build order (spike-first; do NOT build all channels × platforms before one passes)
1. **Synthetic ground truth** — `about:blank` div driven by a KNOWN cubic-bezier; screenshot
   frames; confirm the pipeline recovers the known curve (validates the CV math exactly).
2. **kasane hero** — frame-derive translation; must match DOM `web_anim` ease-out tx ≈ ±720,
   low rms. Validates real-world.
3. **Expand channels** — scale (mid grid linear 5→1), opacity (fade), rotation.
4. **Time-based** — menu (real-input CDP click), wordmark / preloader entrance. **Measure
   `web_record` fps first**; use video + ffmpeg for high fps (Nyquist vs ~300 ms entrances).
5. **Native** — iOS-sim + Android-emu + Flutter frame capture → same pipeline (the universality
   payoff).
6. **Propagate** to 3 copies (scripts wholesale, SKILL.md targeted), commit single-line.

## Risks / honest limits
- **Capture fps binds time-based fidelity** (Nyquist). Measure before relying on it.
- **Opacity is the weakest channel** (content-dependent luminance) — flag low-confidence.
- **Low-texture / flat-solid regions** may be unrecoverable; phase-corr is the fallback.
- **Sub-pixel ~0.1–0.5 px** (coarser than DOM-exact) — acceptable for normalized-shape cert,
  so prefer DOM-exact where available (web), frame-derived where not (native), cross-validate
  where both.
- Screencast frame drops / compositor async → **timestamp each frame from source metadata**,
  don't assume uniform dt.

## Native validation (2026-05-28, Android emulator `probe_arm64`, API 37)

Built `_native_flipbook.recover_from_video` (shared core, TDD: synthetic ffmpeg
easeOutCubic video → recovered, + degenerate-plateau guard) and `flutter_flipbook.py`
(VM `localToGlobal`+`devicePixelRatio` → device-px region; real `adb input tap`
trigger; `adb screenrecord`; recover; VM `getTransformTo` start/end as an
independent amplitude oracle).

- **Flutter app, tap-triggered `Curves.easeOutCubic` translate** (live on emulator):
  smooth 31-distinct-level trajectory, tracking confidence 0.995+; amplitude
  283 logical px vs VM oracle 300 (−5.5%, from settled-tail trim). Shape is an
  unambiguous ease-OUT (rms 0.056 vs `linear`; ~0.033 vs Flutter's actual
  `Cubic(0.215,0.61,0.355,1)`).
- **Android Chrome, WAAPI scrub** (`web_flipbook --android`): `getAnimations`
  oracle EXACT (`cubic-bezier(0.33,1,0.68,1)`, 1000 ms); pixel recovery amp 272
  vs 300, easeOutQuart rms 0.031, tx reproducible across recaptures.

**Cousin-precision limit (honest).** On the EMULATOR, both pixel paths (native
video + web scrub) certify the motion **family** (ease-out) + amplitude but
cannot resolve ease-out **cousins** (easeOutCubic vs easeOutQuart, ~0.03 rms —
below their mutual separation). Root cause is emulator framebuffer/screenshot
fidelity, NOT the method: desktop-Chrome scrub is sub-pixel exact (rms 0.0001).
So: **family-universal everywhere; cousin-exact wherever an introspection oracle
exists** (web `getAnimations`, Flutter VM `getTransformTo`, desktop scrub). The
amplitude under-read is consistent across scrub-settle 0.03→0.18 (tracking/scale
noise, not a compositor race). `reproducible` now gates on the dominant moving
channel, not a global AND over noisy ty/opacity.

**Two robustness fixes shipped:** (a) `fit_easing_aligned` degenerate guard
(<4 distinct progress levels → `name=None`, refuses to certify an undersampled
capture instead of false-confident rms 0.0); (b) `web_flipbook` dominant-channel
reproducibility verdict + configurable `--scrub-settle`.

**Environment gotchas hit:** AVD `Pixel_9` system image missing → use
`probe_arm64`; `ndkVersion=flutter.ndkVersion` resolved to a malformed NDK
(28.2.13676358, no source.properties) → pin a valid one; `-gpu
swiftshader_indirect` renders animations at ~4 fps (source jank, not tracking
jank) → boot `-gpu auto`.

## iOS-sim native validation (2026-05-28, iPhone 17 sim, iOS 26.5)

Built `ios_flipbook.py` (native-iOS sibling of `flutter_flipbook`) and TDD'd
its pure logic in `test_ios_flipbook.py` (10 tests: idb `describe-all` element
resolution by type/label/text, frame extraction, dpr derivation, device-px
region, start/end displacement oracle). The iOS-native introspection oracle is
idb's accessibility tree: `idb ui describe-all` reports each element's `frame`
(logical points). Like Core Animation, that frame reads the model layer (final
value), so it is sampled only at REST and SETTLE → a start/end displacement
oracle, the role Flutter VM `getTransformTo` plays for `flutter_flipbook`.

Verb flow: resolve the tracked element's at-rest frame (points) → device-px
region (`x*dpr`…); real-input `idb ui tap` on the trigger; `xcrun simctl io …
recordVideo --codec=h264 --force`; `recover_from_video`; re-read the frame at
settle for the displacement cross-check. dpr is derived at runtime (screenshot
px width ÷ accessibility-root point width), with a guard that dies if the root
width < 100pt (no foreground app). `--auto` (pixel auto-locate) + `--tap-xy`
fall back when the mover is not an accessibility element.

**Reused the Flutter app cross-platform** — `flutter run -d <ios-sim>` builds
`/tmp/fbapp` on iOS with no hand-built `.xcodeproj` (avoids the Swift yak-shave).

- **idb visibility finding:** Flutter renders to one canvas; idb's a11y tree saw
  only the Material FAB (auto-semantic) + app root, NOT the bare `Container`
  box. Wrapping the box in `Semantics(label:'box')` (then a full restart — raw
  VM `reloadSources` re-runs the existing kernel, only the flutter_tool
  recompiles edited Dart) surfaced it as a `StaticText` with a live frame,
  enabling the full idb-frame oracle path.
- **Live result (4 captures, both directions):** idb displacement oracle
  260pt (ground truth) vs recovered tx **4–17px / 1.5–6%** match every run.
  Amplitude is reproducible and oracle-confirmed. dpr derived 3.0 correctly.

**Cousin-precision on the iOS sim (honest, falsification-tested).** Amplitude is
solid; the easing *family* certifies as ease-out-dominant (winner is always an
Expo ease curve — easeOutExpo/easeInOutExpo, never linear/easeIn) but the exact
ease label **wobbles between ease-out sub-families (out↔in-out) run-to-run**
(rms 0.04–0.08, cousins below the sim noise floor). I first hypothesised this
was a clipped-template artifact (box at left=320 spans 320–440 vs a 402pt
viewport → ~32% clipped); moving it to left=280 (fully on-screen) **falsified**
that — the family still wobbled and flipped direction, so it is noise-floor
cousin-ambiguity, not clipping. Consistent with the Android finding: family +
amplitude universal everywhere (amplitude oracle-confirmed via idb), cousins
(and on a sim even the ease sub-family) need an introspection oracle / desktop
scrub for exactness.

**No longer deferred:** the iOS verb is built, TDD'd, and live-validated. `_ios`
was not modified (idb wrappers unchanged).
