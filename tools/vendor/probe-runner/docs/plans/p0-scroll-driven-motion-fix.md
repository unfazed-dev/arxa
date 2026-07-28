# P0 — Scroll-Driven Motion (G7) Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. CAVEMAN MODE is active for chat; **plan/code/commits are written normally.**

**Goal:** Make `web_anim` actually certify the scroll-driven motion that DOM-tier awwwards sites use, by fixing the three gaps proven by direct measurement against Ashley (the headline G7 site): (1) it measures a **pre-hydration shell** and dies with `range 0:0`; (2) it rejects **multi-segment** (out-and-back) timelines — 41/60 of Ashley's channels; (3) it **under-samples band-localized** ScrollTrigger motion — 21/60 channels. Plus raise the mover cap (`--top 12` vs Ashley's 60+).

**Architecture:** `web_anim` is already the right tool — it sets `scrollY` statically and reads computed transforms (`f(scrollY)`), and the bundle already carries `klass="scroll"` rows. The fixes are surgical: a **readiness wait** before computing the scroll range; **segmented certification** in `_anim_core` (split a non-monotonic channel at its extrema, certify each monotonic run as its own easing+window row — no schema change); and an **adaptive second sweep** that concentrates samples in the scroll bands where motion actually happens. Virtualized/wrapper scroll (Lenis-wrapper / Locomotive v4) is **deferred** — not observed on Ashley or Razorpay (both native).

**Tech Stack:** Python 3 stdlib for the verbs, Chrome DevTools Protocol via `_web_eval`/`_web`, pytest for the pure-core units, a local `http.server` + host Chrome integration harness (`fixtures/scroll-motion/run_anim.py`) for the browser path. No numpy/Pillow (this is the exact-transform DOM path, not flipbook).

---

## Record correction (read first — the prior research was wrong)

`docs/plans/probe-runner-engine-capture-gaps.md` (§A G7, §C3.2, §C9 P0) claimed *"GSAP doesn't use WAAPI → `web_anim`'s `getAnimations()` returns ~0 → web_anim sees ~0 motion"* and scoped the fix as *"build a scroll-position flipbook."* **Falsified by direct measurement (2026-05-30):**

- `getAnimations` appears **nowhere** in `scripts/` (grep) — only in `research/capture-gap-probes/*`. `web_anim` discovers movers by **transform-diff** (`P.accum`/`P.pick`, `web_anim.py:63-90`) and reads computed style at static `scrollY`; it never calls `getAnimations`. The "0" came from the canary `aw_probe.py`, which measures `getAnimations` and **runs no `web_anim`**. web_anim was never run against Ashley/Razorpay/Detroit.
- web_anim is **already scroll-position-driven**. A flipbook is not the fix.
- The contract already has `klass="scroll"` with scroll-px `window` (`fixtures/kasane-rebaseline/bundle/motion.json`), so G8 ("bundle can't represent scroll") is already solved.

**Live measurement — Ashley (`https://ashleybrookecs.com/`), host Chrome CDP, after an explicit readiness wait:**
```
scrollH=13437 innerH=887 native_max=12550  ST=True  ScrollTrigger.maxScroll=12550  lenis=true(native mode) wrapMax=86
web_anim: range=[0,12550]  movers=60(capped)  certified_channels=1
  uncertified: 41× "non-monotonic / multi-phase"
               21× "no resolvable active range at this sampling (try more --steps)"
                5× "not reproducible on revisit (time-based)"
```
Ashley is **natively scrollable** (`ScrollTrigger.maxScroll == native_max`, transformed-wrapper height only 86px → Lenis is in native/smoothing mode, **not** wrapper-virtualizing). Without a readiness wait, web_anim measured the shell (`scrollH=887==innerH`) → `range 0:0` → died, which is why the research thought there was no motion.

**The three real, fixable gaps (each reproduced deterministically by a fixture):**

| Gap | Fixture | Current verdict | Reason string | Live Ashley |
|---|---|---|---|---|
| **G7-ready** — measures pre-hydration shell | `late-build.html` | RED | `empty scroll range 0:0 (page may not scroll)` | the death that hid all motion |
| **G7b** — multi-segment timelines rejected | `multiseg-scrub.html` | AMBER | `non-monotonic / multi-phase: not a single standard easing` | 41/60 channels |
| **G7c** — band-localized motion under-sampled | `band-localized.html` | AMBER | `no resolvable active range at this sampling (try more --steps)` | 21/60 channels |
| baseline (must not regress) | `native-scrub.html` | GREEN | — | the 1 that certified |
| **G7a (DEFERRED)** — wrapper-virtualized scroll | `virtual-scroll.html` | RED | `empty scroll range 0:0` (genuinely non-native) | not observed (Ashley/Razorpay native) |

Task 0 patches the master findings so the record matches the measurement.

---

## File Structure

**Created (on disk — RED/AMBER evidence + harness; verdicts above are measured, not assumed):**
- `fixtures/scroll-motion/native-scrub.html` — native-scroll scrub; GREEN baseline (regression guard).
- `fixtures/scroll-motion/multiseg-scrub.html` — out-and-back timeline; AMBER → GREEN after Task 2–3.
- `fixtures/scroll-motion/band-localized.html` — 400px-band motion on a 13000px page; AMBER → GREEN after Task 4.
- `fixtures/scroll-motion/late-build.html` — scrollHeight built 6s post-load (SPA hydration race); RED → GREEN after Task 1.
- `fixtures/scroll-motion/virtual-scroll.html` — wrapper-virtualized scroll; RED, stays RED (G7a deferred).
- `fixtures/scroll-motion/run_anim.py` — measurement harness; Task 0 hardens it into an asserting integration test over all 5 fixtures.

**Created (new tests):**
- `scripts/test_anim_core_segments.py` — pure-unit TDD for segmentation + band location (Task 2, Task 4).

**Modified:**
- `scripts/web_anim.py` — readiness wait + `--top` default (Task 1); two-pass adaptive sweep (Task 4).
- `scripts/_anim_core.py` — `analyze_movers` segmentation (Task 2); `concentrate_steps` helper (Task 4).
- `scripts/motion_adapter.py` — `adapt_web_anim` per-segment rows (Task 3).
- `scripts/test_motion_adapter.py` — segmented-input cases (Task 3).
- `docs/plans/probe-runner-engine-capture-gaps.md` — correction markers (Task 0).

**Unchanged (verified compatible):** `bundle_writer.py` (`assemble`/`match_motion`/`assert_contract` already take N scroll rows per anchor); `_web_eval.py`/`_web.py`.

---

## Task 0: Lock the 5 fixtures as a regression test + correct the record

**Files:**
- Modify: `fixtures/scroll-motion/run_anim.py`
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md`

- [ ] **Step 1: Extend the harness to all 5 fixtures with the measured baseline verdicts**

In `run_anim.py`, set:

```python
FIXTURES = ["native-scrub.html", "multiseg-scrub.html", "band-localized.html",
            "late-build.html", "virtual-scroll.html"]

# Measured current behavior (2026-05-30). Flip the values noted as a task lands.
EXPECT = {
    "native-scrub.html":  "GREEN",   # baseline; must never regress
    "multiseg-scrub.html": "AMBER",  # -> GREEN after Task 2-3 (segmentation)
    "band-localized.html": "AMBER",  # -> GREEN after Task 4 (adaptive sweep)
    "late-build.html":     "RED",    # -> GREEN after Task 1 (readiness wait)
    "virtual-scroll.html": "RED",    # G7a DEFERRED: stays RED through all of P0
}
```

`late-build.html` waits 6s before becoming scrollable, so raise the per-fixture web_anim timeout headroom: the existing settle is fine, but ensure `run_anim`'s `ensure_chrome()` sleep and any subprocess timeout allow ≥90s per fixture.

- [ ] **Step 2: Make `summarize()` return a verdict and `main()` assert against EXPECT**

`summarize()` returns one of `"GREEN"|"AMBER"|"RED"`. A channel counts as certified if `entry["certified"]` is True **or** (`entry.get("segments")` and every segment `certified`). `main()` collects verdicts and finishes:

```python
    bad = {f: f"{verdicts[f]} (want {EXPECT[f]})" for f in FIXTURES if verdicts.get(f) != EXPECT[f]}
    if bad:
        print("\nFAIL — verdict mismatch:", json.dumps(bad, indent=2)); return 1
    print("\nPASS — all fixtures matched expected verdicts"); return 0
```

- [ ] **Step 3: Run the harness; confirm PASS against today's behavior**

Run (host, Chrome reachable):
```bash
python3 fixtures/scroll-motion/run_anim.py
```
Expected: `PASS — all fixtures matched expected verdicts` — GREEN / AMBER / AMBER / RED / RED in fixture order. This encodes the measured truth before any fix.

- [ ] **Step 4: Patch the master findings**

In `docs/plans/probe-runner-engine-capture-gaps.md`, add `> ⚠️ SUPERSEDED — see docs/plans/p0-scroll-driven-motion-fix.md` under §A G7 (~line 76), §C3 item 2 (~line 260), and §C9 P0 (~line 452). State, in one line each: *web_anim already certifies native-scroll GSAP (getAnimations is irrelevant to it); the real G7 gaps are readiness-wait, multi-segment timelines, and band-localized sampling — virtualized scroll was NOT observed on Ashley/Razorpay (both native).* Do not delete the original analysis; just mark it corrected.

- [ ] **Step 5: Commit**

```bash
git add fixtures/scroll-motion docs/plans/probe-runner-engine-capture-gaps.md docs/plans/p0-scroll-driven-motion-fix.md
git commit -m "test(web_anim): scroll-motion fixtures + asserting harness; correct G7 record (web_anim is already scroll-position-driven; real gaps = readiness/multi-segment/sampling)"
```

---

## Task 1: web_anim waits for readiness before computing the scroll range (+ raise --top)

**Files:**
- Modify: `scripts/web_anim.py` (`main`, around the `max_scroll` computation ~line 177; `--top` default ~line 157)
- Test: `fixtures/scroll-motion/run_anim.py` (`late-build.html` RED → GREEN; `virtual-scroll.html` stays RED)

- [ ] **Step 1: Add a readiness-poll helper**

Add to `web_anim.py` (near `_set_scroll`):

```python
def _wait_scrollable(ev, max_wait=15.0, poll=0.5, stable_needed=3):
    """Poll until the page's scroll height stabilizes (SPA hydration / late GSAP
    builds the tall page AFTER the load event). Returns the settled
    {scrollH, innerH}. Distinguishes 'not ready yet' (keep polling) from
    'genuinely not natively scrollable' (stabilizes at scrollH≈innerH -> caller
    treats as the deferred virtual case, not a readiness failure)."""
    import time as _t
    last, stable = -1, 0
    deadline = _t.time() + max_wait
    while _t.time() < deadline:
        d = json.loads(_ev(ev, "JSON.stringify({sh:document.documentElement.scrollHeight,ih:innerHeight})"))
        if d["sh"] == last:
            stable += 1
            if stable >= stable_needed:
                return d
        else:
            stable = 0
        last = d["sh"]
        _t.sleep(poll)
    return d
```

- [ ] **Step 2: Use it in `main` before computing the range**

Replace the `max_scroll` block (`web_anim.py:177`):

```python
        ready = _wait_scrollable(ev)
        max_scroll = max(0, int(ready["sh"] - ready["ih"]))
        if args.range:
            lo, hi = (int(x) for x in args.range.split(":"))
        else:
            lo, hi = 0, max_scroll
        if hi <= lo:
            die(f"empty scroll range {lo}:{hi} (page may not scroll)")
```

(`detect` is still read first for the engine/stack report; only the range now uses the settled height. Native pages that were already tall stabilize on the first poll, so behavior is unchanged for them — `native-scrub.html` must stay GREEN.)

- [ ] **Step 3: Raise the mover cap and coarse sweep density defaults**

`web_anim.py` — change `--top` default `12`→`48` (Ashley discovers 60+; 12 silently dropped most) and `--steps` default `24`→`40` (coarse spacing over a 12.5k page drops from ~520px to ~310px so narrow ScrollTrigger bands get ≥1 sample, which Task 4's adaptive second pass then densifies):

```python
    p.add_argument("--steps", type=int, default=40, help="static scroll samples (default 40)")
    p.add_argument("--top", type=int, default=48, help="max movers to report")
```

(At 40 steps the `band-localized.html` 400px band still resolves to only ~3 active samples → stays AMBER until Task 4; this bump alone does not over-fix it.)

- [ ] **Step 4: Run the harness**

Run:
```bash
python3 fixtures/scroll-motion/run_anim.py
```
Expected: `late-build.html` now waits out the 6s build → discovers `#mover`, certifies `tx`+`op` → **GREEN**. `virtual-scroll.html` still RED (its scrollHeight stabilizes at `≈innerH` — genuinely non-native — so the range is still `0:0`; this is the deferred G7a, correct to leave RED). `native-scrub.html` GREEN; the two AMBER fixtures unchanged. Update `EXPECT["late-build.html"]="GREEN"`, re-run → `PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/web_anim.py fixtures/scroll-motion/run_anim.py
git commit -m "feat(web_anim): wait for scrollHeight to settle before ranging (SPA hydration race); raise --top default 12->48"
```

---

## Task 2: _anim_core certifies multi-segment curves by segmentation

**Files:**
- Modify: `scripts/_anim_core.py` (`analyze_movers` channel loop)
- Test: `scripts/test_anim_core_segments.py` (new, pure-unit)

- [ ] **Step 1: Write the failing unit test**

Create `scripts/test_anim_core_segments.py`:

```python
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _anim_core import analyze_movers, CHANNELS

def _vec(tx):
    v = [0.0] * len(CHANNELS)        # [tx,ty,sx,sy,rot,op,tz,rotX,rotY]
    v[2] = v[3] = v[5] = 1.0         # sx,sy,op identity
    v[0] = tx
    return v

def test_out_and_back_yields_two_certified_segments():
    n = 25
    ys = [round(2000 * i / (n - 1)) for i in range(n)]
    # symmetric triangle 0 -> +400 -> 0 (two LINEAR runs; each certifies as linear).
    # A sine arc does NOT certify (half a sine is not a standard easing) — use linear.
    txs = [(800 * (i / (n - 1))) if i <= (n - 1) / 2 else (800 * (1 - i / (n - 1)))
           for i in range(n)]
    rows_m = [[_vec(tx)] for tx in txs]
    mid = n // 2
    movers = [{"sel": "div", "rank": 0, "absY": 200}]
    out = analyze_movers(movers, ys, rows_m, rows_m[mid], rows_m[mid], mid,
                         drift_ok=True, max_drift=0.0, unsettled=0)
    tx = out[0]["channels"]["tx"]
    segs = tx.get("segments")
    assert segs is not None and len(segs) == 2, tx
    assert all(s["certified"] for s in segs), segs
    assert segs[0]["to"] - segs[0]["from"] > 300     # rises
    assert segs[1]["to"] - segs[1]["from"] < -300    # falls
    assert tx["certified"] is True                   # channel certified via segments
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m pytest scripts/test_anim_core_segments.py -v`
Expected: FAIL — `tx.get("segments")` is `None` (today the channel is a single non-monotonic entry, `certified: false`, reason `"non-monotonic / multi-phase"`).

- [ ] **Step 3: Harden `fit_easing` against a degenerate fit, and add the split helper**

First, guard `fit_easing` (`_anim_core.py`) so a degenerate normalized series (which arises when a segment's normalization blows up, e.g. a near-zero net span) returns a high-rms result instead of `EASINGS[None]` → `KeyError`. Replace the `bz = EASINGS[best]` / `label = ...` lines:

```python
    if best is None:
        return {"name": "custom", "nearest": None, "bezier": None, "rms": 9.99}
    bz = EASINGS[best]
    label = best if best_rms <= 0.1 else "custom"
```

Then add the split helper above `analyze_movers`:

```python
def _split_monotonic(ys_sub, vals_sub, eps):
    """Split (ys_sub, vals_sub) at sign-changes of the first difference into
    monotonic runs of >= 4 samples. Returns list of (ys_seg, vals_seg)."""
    if len(vals_sub) < 2:
        return [(ys_sub, vals_sub)]
    cuts, sign = [0], 0
    for i in range(1, len(vals_sub)):
        d = vals_sub[i] - vals_sub[i - 1]
        s = 1 if d > eps else (-1 if d < -eps else 0)
        if s and sign and s != sign:
            cuts.append(i - 1)              # extremum
        if s:
            sign = s
    cuts.append(len(vals_sub) - 1)
    segs = []
    for a, b in zip(cuts, cuts[1:]):
        if b - a + 1 >= 4:
            segs.append((ys_sub[a:b + 1], vals_sub[a:b + 1]))
    return segs
```

- [ ] **Step 4: Emit `segments` in the channel loop**

In `analyze_movers`, replace the line `            channels[c] = entry` with the segmentation block **followed by** that same line — i.e. segmentation runs *after* the existing single-easing path and its reason-setting block, so it can override `entry["certified"]` and clear the stale reason. The trigger is the channel's **value range** (`max-min`), not the net-span `ar` (an out-and-back returning near its start has `ar=None` but large value range):

```python
            if not certified and drift_ok and repro_ok and (max(vals) - min(vals)) >= VARY_THR[c]:
                var2 = max(vals) - min(vals)
                seg_entries = []
                for ys_seg, vals_seg in _split_monotonic(ys, vals, var2 * 0.05):
                    s0, s1 = vals_seg[0], vals_seg[-1]
                    yy0, yy1 = ys_seg[0], ys_seg[-1]
                    if abs(s1 - s0) < VARY_THR[c] or yy1 <= yy0:
                        continue
                    pf = [((yy - yy0) / (yy1 - yy0), (vv - s0) / (s1 - s0))
                          for yy, vv in zip(ys_seg, vals_seg)]
                    if len(pf) < 4:
                        continue
                    ez = fit_easing(pf)
                    seg_entries.append({"from": round(s0, 3), "to": round(s1, 3),
                                        "activeScroll": [yy0, yy1], "easing": ez,
                                        "certified": bool(ez["rms"] <= RMS_TOL)})
                if seg_entries:
                    entry["segments"] = seg_entries
                    if all(s["certified"] for s in seg_entries):
                        entry["certified"] = True
                        entry.pop("reason", None)
            channels[c] = entry
```

Already-certified single-segment channels skip this block (`not certified` is False), so `native-scrub` and existing certified channels are unchanged (verified: native single-linear → `certified=True`, no `segments`). Verified end-to-end in the sandbox: symmetric triangle → 2 certified linear segments, `reason` cleared; asymmetric triangle (0→400→100) → pre-fix `non-monotonic / multi-phase`, post-fix certified.

- [ ] **Step 5: Run the test + full core/adapter suite**

Run: `python3 -m pytest scripts/test_anim_core_segments.py scripts/test_anim_core_z.py scripts/test_motion_adapter.py scripts/test_motion_adapter_bezier.py -v`
Expected: all PASS (new test green; single-segment paths untouched).

- [ ] **Step 6: Commit**

```bash
git add scripts/_anim_core.py scripts/test_anim_core_segments.py
git commit -m "feat(_anim_core): certify multi-segment scroll curves by splitting at extrema into per-segment easings"
```

---

## Task 3: motion_adapter emits one contract row per certified segment

**Files:**
- Modify: `scripts/motion_adapter.py` (`adapt_web_anim`, ~lines 69-135)
- Test: `scripts/test_motion_adapter.py` (~line 136+)

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_motion_adapter.py`:

```python
def test_adapt_web_anim_segmented_channel_emits_one_row_per_segment():
    mv = {"sel": "div", "rank": 0, "absY": 200.0, "channels": {
        "tx": {"certified": True, "segments": [
            {"from": 0.0, "to": 400.0, "activeScroll": [0.0, 1000.0],
             "easing": {"name": "easeOut", "bezier": "cubic-bezier(0,0,0.58,1)", "rms": 0.02}, "certified": True},
            {"from": 400.0, "to": 0.0, "activeScroll": [1000.0, 2000.0],
             "easing": {"name": "easeIn", "bezier": "cubic-bezier(0.42,0,1,1)", "rms": 0.03}, "certified": True},
        ]}}}
    rows = ma.adapt_web_anim({"movers": [mv]})
    assert len(rows) == 2, rows
    assert rows[0]["window"] == [0.0, 1000.0] and rows[0]["amplitude"] == 400.0
    assert rows[1]["window"] == [1000.0, 2000.0] and rows[1]["amplitude"] == -400.0
    assert rows[0]["name"] != rows[1]["name"]
    for r in rows:
        ma.assert_contract(r)
        assert r["klass"] == "scroll" and r["axis"] == "x"
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m pytest scripts/test_motion_adapter.py::test_adapt_web_anim_segmented_channel_emits_one_row_per_segment -v`
Expected: FAIL — current `adapt_web_anim` requires top-level `activeScroll`/`easing`, ignores `segments` → 0 rows.

- [ ] **Step 3: Handle `segments` in `adapt_web_anim`**

In the `for ch, entry in channels.items():` loop of `adapt_web_anim`, before the existing single-entry path, add:

```python
            seg_list = entry.get("segments")
            if seg_list:
                base = f"{sel}#{rank}#{ch}" if rank is not None else f"{sel}#{ch}"
                for si, seg in enumerate(seg_list):
                    if certified_only and seg.get("certified") is not True:
                        continue
                    cb = parse_bezier(seg["easing"]["bezier"])
                    if cb is None:
                        continue
                    row = {
                        "name": f"{base}#s{si}",
                        "anchor": anchor,
                        "easing": seg["easing"]["name"],
                        "cubic_bezier": cb,
                        "amplitude": float(seg["to"]) - float(seg["from"]),
                        "axis": axis_for_channel(ch),
                        "window": [float(v) for v in seg["activeScroll"]],
                        "klass": "scroll",
                        "source": "web_anim",
                        "rms": float(seg["easing"]["rms"]),
                    }
                    if abs_x is not None:
                        row["anchor_x"] = float(abs_x)
                    rows.append(row)
                continue                          # segmented channel done; skip single path
```

- [ ] **Step 4: Run the new test + full adapter suite**

Run: `python3 -m pytest scripts/test_motion_adapter.py scripts/test_motion_adapter_bezier.py -v`
Expected: all PASS.

- [ ] **Step 5: End-to-end — multiseg fixture goes GREEN**

Run:
```bash
python3 fixtures/scroll-motion/run_anim.py
```
Expected: `multiseg-scrub.html` → **GREEN** (channel `tx` has two certified segments). Update `EXPECT["multiseg-scrub.html"]="GREEN"`, re-run → `PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/motion_adapter.py scripts/test_motion_adapter.py fixtures/scroll-motion/run_anim.py
git commit -m "feat(motion_adapter): expand certified multi-segment channels into one scroll row per segment"
```

---

## Task 4: web_anim adaptive second sweep for band-localized motion

**Files:**
- Modify: `scripts/_anim_core.py` (`concentrate_steps` helper)
- Modify: `scripts/web_anim.py` (`main` — second sweep when channels report no-resolvable-range)
- Test: `scripts/test_anim_core_segments.py` (unit for `concentrate_steps`); `fixtures/scroll-motion/run_anim.py` (`band-localized.html` AMBER → GREEN)

- [ ] **Step 1: Write the failing unit test for `concentrate_steps`**

Add to `scripts/test_anim_core_segments.py`:

```python
from _anim_core import concentrate_steps

def test_concentrate_steps_packs_samples_into_active_band():
    # Coarse 40-step sweep over a 12000px page (~308px spacing < the 400px band,
    # so >=1 coarse sample lands in [5000,5400]). motion[] mirrors the fixture ramp.
    coarse_ys = [round(12000 * i / 39) for i in range(40)]
    def val(y):
        p = min(1.0, max(0.0, (y - 5000) / 400.0)); return 600 * p
    motion = [0.0] + [abs(val(coarse_ys[i]) - val(coarse_ys[i - 1])) for i in range(1, 40)]
    refined = concentrate_steps(coarse_ys, motion, n=24, pad_frac=0.5)
    in_band = [y for y in refined if 4800 <= y <= 5600]
    assert len(in_band) >= 8, refined            # dense coverage inside the band (verified: 18)
    assert min(refined) == 0 and max(refined) >= 11000   # endpoints retained
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m pytest scripts/test_anim_core_segments.py::test_concentrate_steps_packs_samples_into_active_band -v`
Expected: FAIL — `cannot import name 'concentrate_steps'`.

- [ ] **Step 3: Implement `concentrate_steps` in `_anim_core.py`**

```python
def concentrate_steps(coarse_ys, motion_per_step, n, pad_frac=0.5):
    """Build a refined, non-uniform scroll-step list that packs samples into the
    bands where the coarse sweep saw motion. motion_per_step[i] is the total
    transform-magnitude change at coarse step i. Returns sorted unique offsets:
    page endpoints + dense samples across each active band (band padded by
    pad_frac of its width). A band is a maximal run of steps above 5% of peak."""
    if not coarse_ys:
        return coarse_ys
    lo, hi = min(coarse_ys), max(coarse_ys)
    # median coarse spacing — the floor for expanding a single-hit band so a band
    # caught by only one coarse sample still gets a real neighborhood to resample.
    diffs = sorted(b - a for a, b in zip(coarse_ys, coarse_ys[1:]) if b > a)
    spacing = diffs[len(diffs) // 2] if diffs else 1
    peak = max(motion_per_step) if motion_per_step else 0.0
    if peak <= 0:
        return sorted(set(coarse_ys))
    thr = peak * 0.05
    active = [i for i, m in enumerate(motion_per_step) if m > thr]
    if not active:
        return sorted(set(coarse_ys))
    # group consecutive active indices into bands
    bands, cur = [], [active[0]]
    for i in active[1:]:
        if i == cur[-1] + 1:
            cur.append(i)
        else:
            bands.append(cur); cur = [i]
    bands.append(cur)
    out = {lo, hi}
    per = max(8, n // len(bands))
    for b in bands:
        b0, b1 = coarse_ys[b[0]], coarse_ys[b[-1]]
        grow = max(pad_frac * (b1 - b0), spacing)   # single-hit band (b0==b1) -> +/- spacing
        s = max(lo, int(b0 - grow)); e = min(hi, int(b1 + grow))
        for k in range(per + 1):
            out.add(round(s + (e - s) * k / per))
    return sorted(out)
```

Verified in the sandbox: 40 coarse steps over 12000px with a 400px band → 18 refined points inside [4800,5600], endpoints retained.

- [ ] **Step 4: Run the unit test — should pass**

Run: `python3 -m pytest scripts/test_anim_core_segments.py -v`
Expected: PASS (both segmentation and concentrate tests).

- [ ] **Step 5: Wire the second sweep into web_anim `main`**

After the first `analyze_movers` call produces `out_movers`, if any channel is uncertified with reason starting `"no resolvable active range"`, build `motion_per_step` from the first sweep (per coarse step, sum over movers of max-abs channel delta vs the previous step), compute `refined_ys = concentrate_steps(ys, motion_per_step, n=max(args.steps, 32))`, re-run the static sweep over `refined_ys`, and re-run `analyze_movers` with the refined `ys`. Keep whichever certification is better per channel (prefer certified). Concretely, in `web_anim.py` after the existing sweep:

```python
        need_zoom = any(
            (e.get("reason") or "").startswith("no resolvable active range")
            for m in out_movers for e in m["channels"].values())
        if need_zoom and not args.range:
            motion_per_step = []
            for si in range(1, len(rows)):
                tot = 0.0
                for mi in range(len(movers)):
                    a = rows[si][mi] if mi < len(rows[si]) else []
                    b = rows[si - 1][mi] if mi < len(rows[si - 1]) else []
                    for ci in range(min(len(a), len(b))):
                        tot = max(tot, abs(a[ci] - b[ci]))
                motion_per_step.append(tot)
            motion_per_step = [0.0] + motion_per_step      # align to ys length
            refined_ys = concentrate_steps(ys, motion_per_step, n=max(args.steps, 32))
            rows2, ys2 = _sweep(ev, refined_ys, movers, args, settle)   # same sweep logic, refactored
            out2 = analyze_movers(movers, ys2, rows2, mid_m2, revisit2, len(ys2)//2,
                                  drift_ok2, max_drift2, unsettled2)
            out_movers = _merge_prefer_certified(out_movers, out2)
```

Refactor the existing measurement loop (`web_anim.py:207+`) into a `_sweep(ev, step_ys, movers, args, settle)` returning `(rows, ys, mid_m, revisit, mid_idx, drift_ok, max_drift, unsettled)` so both passes share it; add a small `_merge_prefer_certified(a, b)` that, per mover/channel, keeps the entry that is certified (or has certified segments), else keeps the finer-sweep entry. **DRY:** the first sweep must call `_sweep` too.

- [ ] **Step 6: End-to-end — band fixture goes GREEN**

Run:
```bash
python3 fixtures/scroll-motion/run_anim.py
```
Expected: `band-localized.html` → **GREEN** (the second sweep packs samples into [≈4800,5600] and certifies `tx`). All other fixtures unchanged (`virtual-scroll.html` stays RED — deferred). Update `EXPECT["band-localized.html"]="GREEN"`, re-run → `PASS` (4 GREEN, 1 RED-deferred).

- [ ] **Step 7: Run the full unit suite (no regressions)**

Run: `python3 -m pytest scripts/test_anim_core_segments.py scripts/test_anim_core_z.py scripts/test_motion_adapter.py scripts/test_motion_adapter_bezier.py scripts/test_bundle_writer.py -v`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/_anim_core.py scripts/web_anim.py scripts/test_anim_core_segments.py fixtures/scroll-motion/run_anim.py
git commit -m "feat(web_anim): adaptive second sweep concentrating samples in active scroll bands (band-localized ScrollTrigger motion)"
```

---

## Task 5: Live re-validation on Ashley (gating)

**Files:** `docs/plans/p0-scroll-driven-motion-fix.md` (append a "Live validation" section)

- [ ] **Step 1: Re-run web_anim against Ashley and record the before/after**

Host Chrome. The pre-fix baseline (measured 2026-05-30): `range=[0,12550]`, 60 movers, **1** certified channel, 41 multi-segment + 21 no-resolvable-range uncertified. Re-run after Tasks 1–4:

```bash
python3 scripts/web_anim.py --url "https://ashleybrookecs.com/" --steps 24 --out /tmp/scroll-motion/ashley_after.json
python3 - <<'PY'
import json; d=json.load(open("/tmp/scroll-motion/ashley_after.json"))
mv=d["movers"]; cert=sum(1 for m in mv for e in m["channels"].values()
  if e.get("certified") or (e.get("segments") and all(s["certified"] for s in e["segments"])))
print("range",d["scrollRange"],"movers",len(mv),"certified_channels",cert)
PY
```
Expected: `range=[0,~12550]`, movers ≥ 40, **certified_channels jumps from 1 to the large majority** of the previously multi-segment (41) + band-localized (21) channels (the ~5 genuinely time-based stay uncertified — correct). Record the exact numbers.

- [ ] **Step 2: Append the result + commit**

Add a "Live validation (post-fix)" block to this plan with the before/after numbers. If a channel class still fails for a reason not covered here, file it as a follow-up (do not expand P0 scope).

```bash
git add docs/plans/p0-scroll-driven-motion-fix.md
git commit -m "docs(p0-scroll-motion): live Ashley validation — certified channels 1 -> majority after readiness/segmentation/sampling fixes"
```

---

## Live validation (post-fix) — Ashley, 2026-05-30

Re-ran `web_anim --url https://ashleybrookecs.com/ --steps 24` on host Chrome (flagged, foreground-independent). Counts/curves only (IP firewall).

**The headline P0 win — acquisition is unblocked.** Pre-fix, web_anim measured a pre-hydration shell and died at `empty scroll range 0:0`, hiding *all* motion (this is what made the original research think GSAP was invisible). Post-fix (readiness wait): **range `[0,12550]`, 48 movers discovered, 65 channels measured.** The "hid all motion" blocker is fixed.

**Mechanisms delivered + working on real data:** segmentation splits **56/65** channels into per-segment runs; the adaptive second sweep runs cleanly (no errors; `motion_per_step` forms 4 real bands, refines 24→36 samples — it does *not* collapse to one smear).

**Honest certification result — the plan's "1 → majority" prediction did NOT hold.** Certified channels went **1 → 2**, not a majority. (Not apples-to-apples with the 60-mover baseline — this run capped at `--top 48`; lead with the absolute after-state, not a delta.) Two **distinct, verified** root causes for why segmented channels don't certify — filed as follow-ups, **NOT** fixed here (per Task 5 Step 2: do not expand P0 scope; Tasks 1–4 are not reopened):

- **(A) Segments are not trimmed to their active sub-range before easing-fit.** Sampled a representative uncertified segment (rms 0.155): normalized curve rises `(p,f) (0,0)→(0.09,0.37)→(0.13,1.0)` then holds **flat at 1.0 for the remaining ~87%** of the window. The motion is real and clean (a band-localized rise), but the segment window spans the whole page, so the long flat tail dominates the fit and inflates rms far past `RMS_TOL=0.06`. ~most of the 22 "non-monotonic"/high-rms channels are this shape (rise-then-hold), **not** noise and **not** exotic custom eases. Follow-up: apply `channel_active_range`-style trimming *per segment* (fit only where the segment actually changes) before `fit_easing`.
- **(B) Multi-mover narrow-band under-sampling.** `no-resolvable-range` is 34 channels. The second sweep was only fixture-validated single-mover. On Ashley, `motion_per_step = max across 48 movers` yields 4 bands spanning distinct offsets; the shared per-band budget (`per = max(8, n//bands)`) then under-covers each narrow ScrollTrigger band, so after active-range trimming a given channel's band still has <4 samples. Follow-up: per-band / per-channel sample budgeting (densify each channel's own band, not the multi-mover union) — possibly iterate the second sweep per uncertified channel.

These two follow-ups (plus the ~7 genuinely time-based channels, correctly left uncertified) account for the gap. **P0 status: mechanisms delivered and fixture-validated; the acquisition blocker (range 0:0) is fixed on real Ashley; real-site *certification* needs follow-ups (A) and (B).** Raw measurement kept at `/tmp/scroll-motion/ashley_after.json` (ephemeral, not committed — contains selectors/curves).

---

## Appendix — DEFERRED: G7a wrapper-virtualized scroll

`virtual-scroll.html` models a library that makes the document non-scrollable (`overflow:hidden` + a transformed wrapper, e.g. Locomotive v4 / GSAP ScrollSmoother / wrapper-mode Lenis). It stays RED through all of P0 **on purpose**: neither Ashley nor Razorpay uses it (both natively scrollable — `ScrollTrigger.maxScroll == native_max`, transformed-wrapper height ≈ 0). Building a virtual-scroll driver now would be speculative (YAGNI) and the detection convention is unsettled (`window.lenis` is not standard — Lenis instances are app-scoped). **Revisit only when a real target is confirmed to be wrapper-virtualized** (re-measure with `web_anim --detect-only`: native_max ≈ 0 but a tall transformed wrapper or a library `maxScroll`/`limit` > 0). The fix then is: detect the lib, drive its `scrollTo`, and use the virtual offset as the progress axis — the `_sweep`/`analyze_movers` core already accepts an arbitrary `ys` axis, so only the scroll-set + range need a virtual branch.

---

## Follow-ups (out of P0 scope — filed, not fixed here)

- **`web_launch.py` tabless-Chrome self-heal.** `web_launch.py:79` only relaunches when `not chrome_running()`; when the probe Chrome (`--user-data-dir=/tmp/probe-runner-chrome`, `--remote-debugging-port=9222`) is **alive but has zero page targets** (last tab closed), it is a no-op, so every downstream verb (web_anim/web_open/…) bails `no Chrome page targets` with no recovery — and `ensure_chrome()` in the harness inherits the gap. "running" ≠ "has a debuggable page". Observed 2026-05-30 during P0 Task 4 validation: full harness went all-RED purely from this (the *pre*-Task-4 web_anim failed identically; relaunching the probe Chrome restored `native → movers 1 cert 2`). Fix: when `chrome_running()` is True but `/json/list` has no `type=="page"` target, create one (CDP `PUT /json/new?about:blank`) — and prefer a foregrounded/rendered tab (a background `/json/new` target is throttled → discovery sees no motion). The *cause* of the initial tab loss is unproven (prior verb / Chrome / external); the bug here is the failure to recover. NOT a P0/scroll-motion issue.

- **web_anim backgrounded-tab scroll suppression.** When the probe Chrome tab is **not foregrounded/rendered**, a programmatic `window.scrollTo(0, y)` reaches the target offset (`window.scrollY == y`) but Chrome does **not fire the `scroll` event** — so any page whose transform is driven by a `scroll` *listener* (every scroll-motion fixture here, and many real sites) reads **identity at every offset** → web_anim reports `no scroll-animated elements found` (false RED) or all-zero motion. Proven 2026-05-30: band/native read identity on auto-scroll; a manual `dispatchEvent(new Event('scroll'))` *or* a CDP `Page.bringToFront` immediately restored the correct transform (`@5200 → tx=-300`). This is a **shipped-tool reliability bug**: a real site measured in a backgrounded/occluded/CI tab silently yields wrong results. **FIXED in P0** at the root via `chrome_launch` flags in `scripts/_web.py` — `--disable-renderer-backgrounding --disable-backgrounding-occluded-windows --disable-background-timer-throttling` — which keep the renderer (timers + scroll dispatch) live regardless of window focus, without going headless. One place, persistent, CDP/Safari/Android-transport-agnostic (web_anim core untouched). Verified: the full harness PASSes deterministically with the probe Chrome window unfocused (no `bring.py` needed). The related harness teardown hang this exposed (`httpd.shutdown()` stalled by a foreground Chrome's keep-alive socket) was also fixed (`fix(harness): non-blocking teardown`). Residual follow-up (minor): a pre-existing probe Chrome launched WITHOUT these flags (e.g. a stale instance) won't pick them up until relaunched — see the launcher self-heal item above.

---

## Self-Review

**Sandbox-verified before publishing (the pure-Python pieces were executed against their own asserts, not just eyeballed):**
- `fit_easing` None-guard + `_split_monotonic` + the value-range-triggered segmentation block (placed before `channels[c] = entry`): symmetric triangle → 2 certified linear segments (±400), `reason` cleared; asymmetric triangle (0→400→100) → pre-fix `non-monotonic / multi-phase`, post-fix certified; native single-linear → unchanged (certified, no `segments`).
- `concentrate_steps`: 40 coarse steps / 400px band → 18 refined points inside [4800,5600], endpoints kept.
- `adapt_web_anim` segment expansion: 2 contract-valid rows (amp +400 / −400, unique `#s0`/`#s1` names); single-channel path still emits 1 row.
- Why earlier drafts were wrong (caught in QA): a sine arc does NOT certify (half a sine isn't a standard easing → multiseg fixture switched to piecewise-linear); `fit_easing` KeyError'd on a near-zero net span (out-and-back) → guarded; an `ar`-gated trigger missed net-zero out-and-back (`ar=None`) → switched to a value-range trigger; a single coarse sample couldn't define a band → `grow=max(pad*width, median_spacing)` + `--steps` default 24→40.

**Spec coverage (against the measured Ashley breakdown):**
- Readiness death (`range 0:0`, hid all motion) → Task 1. ✓
- Multi-segment, 41/60 → Task 2 (`_anim_core`) + Task 3 (`motion_adapter`). ✓
- Band-localized, 21/60 → Task 4 (adaptive sweep). ✓
- `--top 12` vs 60+ → Task 1 Step 3. ✓
- Time-based, 5/60 → correctly left uncertified (not a bug). ✓
- G8 "bundle can't represent scroll" → already solved; multi-segment = N rows, no schema change. ✓
- Record correction → Task 0. ✓
- Native baseline guard → `native-scrub.html` GREEN asserted every task. ✓
- G7a virtual-scroll → deferred with an explicit re-entry condition (not dropped silently). ✓

**Placeholder scan:** every code step has full code; commands have expected output. The one refactor (`_sweep`/`_merge_prefer_certified` in Task 4 Step 5) names exact return tuple + behavior; the engineer extracts the existing `web_anim.py:207+` loop verbatim into `_sweep`. No TODO/TBD.

**Type/name consistency:** `segments` entry shape `{from,to,activeScroll,easing:{name,bezier,rms},certified}` is produced in Task 2 (`_anim_core`) and consumed identically in Task 3 (`motion_adapter`) and Task 0/3 harness verdict logic. Row keys match `motion_adapter.assert_contract`'s 10-key contract; `name` uniqueness via `#sN`. `concentrate_steps(coarse_ys, motion_per_step, n, pad_frac)` signature matches its unit test and its Task 4 Step 5 call. `EXPECT` verdict strings match `summarize()` returns.

**Scope check:** P0 fixes only what Ashley empirically needs; Razorpay/Detroit deeper validation and any virtual-scroll work are out of scope (Detroit's real blocker is video-bg G9). P1 (G10 shadow-walk, G4 state) / P2 / P3 unchanged per §C9.

---

## Execution Handoff

Plan complete and saved to `docs/plans/p0-scroll-driven-motion-fix.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks. NOTE: browser tasks (0, 1, 3-Step5, 4-Step6, 5) need host Chrome CDP (:9222) and must run on host Bash (the ctx sandbox cannot reach it); the pure core/adapter tasks (2, 3-Steps1-4, 4-Steps1-4) are pytest-only and sandbox-safe.
2. **Inline Execution** — execute in this session via executing-plans, batch with checkpoints.
