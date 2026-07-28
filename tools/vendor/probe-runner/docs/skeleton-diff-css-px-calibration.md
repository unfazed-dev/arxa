# skeleton_diff CSS-px floor calibration

Reproducible measurement backing the SKILL claim that `skeleton_diff` gates are
"calibrated to a self-diff floor." Run after the `web_skeleton` ÷dpr change
(device-px → CSS-px normalization) to re-derive the floor in CSS px and decide
whether the absolute-px gates (`pos`, `size`, `align radius`) needed to move.

**Verdict: gates unchanged — by judgment, not because the data forced it.**
`DEFAULT_GATES = {iou:0.98, pos:1.0, size:1.0, ...}` and `align radius=24` are kept.
The prior plan framed this as a *forced* recalibration ("2× too loose, must halve to
pos/size 0.5, radius 12"). The measurement corrects that premise: the **same-dpr**
floor is ≈0 px, so `1.0` produces **no false-fails** — but neither would `0.5`.
The value is therefore a free choice, not a measurement output. We keep `1.0` for
continuity with the pre-÷dpr value and because a sub-1-px center shift is
imperceptible; `0.5` would be equally defensible and would restore the finer
sensitivity the pre-÷dpr retina path happened to have. The cross-dpr numbers
(0.75 px pos / 1.5 px size) are **not** an argument for 1.0 — they are the reason
cross-dpr capture is excluded from certification (see contract); a cross-dpr capture
is rejected on `size` regardless of the `pos` value.

## How to reproduce

```
# 1. serve the deterministic fixture (host)
cd fixtures/skdiff-calib && python3 -m http.server 8137 --bind 127.0.0.1 &
# 2a. real-retina (dpr=2) calibration — NON-headless Chrome on a retina display
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --remote-debugging-port=9222 --user-data-dir=/tmp/sk/p \
  http://127.0.0.1:8137/fixture.html &
python3 fixtures/skdiff-calib/harness2.py        # noise floor + normalization check
# 2b. headless (dpr=1) cross-check — relaunch with --headless=new, re-run capture
```

`fixture.html` is content-independent (fixed-px boxes + text, system font, no
images/webfonts) so two captures at the same dpr are pixel-identical; only the
cross-dpr grid differs.

## Measured (2026-05-29, this device, dpr=2 retina)

| Quantity | Value | Note |
|---|---|---|
| DOMSnapshot raw bounds (real retina) | `2560` for a 1280-CSS page | = CSS × real devicePixelRatio → **device px**; ÷dpr is correct |
| Live-path normalization (dpr=2) | `2560 ÷ 2 = 1280` CSS ✓ | matches JS `getBoundingClientRect` (CSS) → T0b verified |
| **Same-dpr noise floor** (dpr2 vs dpr2, deterministic) | `pos 0.0 / size 0.0 / iou 1.0`, 26/26 | the floor the gates protect; ~0 |
| Cross-dpr **upper bound** (retina-headed dpr2 vs dpr1-headless) | `pos 0.75 / size 1.5 / iou 0.944 / tree 0.60`, 25/26 | see caveat |

**Cross-dpr caveat.** That row compares a *headed-retina* capture against a
*headless-dpr1* capture, so it conflates two effects: (a) the dpr quantization grid
(retina lands on a 0.5-px grid, dpr1 on a 1-px grid) and (b) headless-vs-headed
sub-pixel text layout. It is an **upper bound**, not pure quantization. The
`tree=0.60` is unexplained (likely one tiny text node re-matched under size
quantization) and is out of scope — see the same-dpr contract below.

## Contract (made explicit)

`skeleton_diff` certifies a **source vs clone captured the same way: same page, same
viewport, same devicePixelRatio** (SKILL: "same viewport"). Under same-dpr the floor
is ~0 and the tight gates are meaningful. Coordinates are uniformly CSS px after the
`web_skeleton` **live-path** ÷dpr normalization, so the gates are dpr-independent in
*value*. Cross-dpr capture is a degraded mode: it introduces the ~0.75-px pos /
~1.5-px size quantization floor above and can trip `size`/`iou`/`tree` — capture both
sides at the same dpr.

## `--viewports` on a headed retina display — FIXED (T10 / #56, 2026-05-29)

The multi-breakpoint path sets `Emulation.setDeviceMetricsOverride
{deviceScaleFactor:1}`. On a **headed retina** display the override drops JS
`devicePixelRatio` to 1 **but DOMSnapshot bounds stay at the real backing scale**
(raw `2560`, survives re-nav + settle) — so the old `÷1` (which trusted JS dpr) left
coordinates **2× too large**.

**Fix:** `_capture_one`'s `--viewports` branch now divides by
`web_skeleton._backing_scale(ev)`, which measures the true device→CSS ratio from
`Page.getLayoutMetrics` — `layoutViewport.clientWidth ÷ cssLayoutViewport.clientWidth`.
That metric keeps the real scale under the override exactly where JS dpr collapses
(proven live 2026-05-29: js dpr `1`, getLayoutMetrics ratio `2.0`; the real
`--viewports` capture's widest bbox came back `1280` CSS, not `2560`), snapped (±0.06)
to the nearest standard display scale {1, 1.25, 1.5, 1.75, 2, 2.5, 3} as a sub-pixel
guard. Unaffected: the **live** path
(no override; reads real dpr; correct) and any **headless**/non-retina capture (ratio
`1.0`; no-op). The T9 gate decision above is independent of this.

Reproduce on headed Chrome :9222 (direct Python — not the ctx sandbox, which can't
reach the host port): `fixtures/skdiff-calib/t10_measure.py` (the signal probe that
showed B=getLayoutMetrics survives the override while A=js-dpr does not) then
`fixtures/skdiff-calib/t10_gate.py` (end-to-end: runs the real `_capture_one` width
path, asserts 1280 not 2560).
