# P1 — Real-Site Scroll-Motion Certification (B-first) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. CAVEMAN MODE is active for chat; plan/code/commits are written normally.

**Goal:** Make `web_anim` actually *certify* the scroll-driven motion of a real multi-mover site (Ashley), closing the gap left open by P0 (`p0-scroll-driven-motion-fix.md` "Live validation": certified 1→2 of 65, not the predicted majority).

**Architecture:** Evidence says the dominant blocker is **multi-mover band under-sampling (B)**, not per-segment trimming (A). The single-easing path in `_anim_core.analyze_movers` *already* trims to the active range via `channel_active_range` (`_anim_core.py:273`) and only fails at the `len(pf) >= 4` gate (`_anim_core.py:287`): a narrow ScrollTrigger band gets <4 samples. P0's second sweep concentrates the **global** `motion_per_step` (max across all movers), so on a 48-mover page the shared per-band budget dilutes each channel's own narrow band. The fix is a **per-channel** band concentrator that guarantees ~K samples inside *each* uncertified channel's own band. Then we **re-measure Ashley and bucket the residuals from data** to pick the second fix (per-segment trim A / free-bézier fit / noise-reject) — we do NOT pre-build A (zero verified beneficiaries today).

**Tech Stack:** Python 3 stdlib; Chrome DevTools Protocol via `_web_eval`/`_web`; pytest for the pure core; the existing `fixtures/scroll-motion/run_anim.py` host-Chrome harness. No numpy.

---

## Why B-first (not A+B bundled) — read first

Per the P0 live-validation evidence + advisor review:
- The EVAL1 channel (`rot`, rms 0.155, rise-then-hold) is **monotonic** → it takes the *single* path, where `channel_active_range` already trims the flat tail. Its channel-level reason is **"no resolvable active range"** → it is a **B-case** (the 34 bucket), not an A-case. The 0.155 was the *segmentation* path's untrimmed artifact, irrelevant to why the channel is uncertifiable.
- **A** (per-segment active-range trim) only helps *genuinely non-monotonic* channels whose individual runs are well-sampled (≥4) yet fail solely on an untrimmed flat tail. **No such channel has been observed.** Building A now repeats the "fix an unverified failure" trap.
- **B is the diagnostic prerequisite:** until each band has ≥4 in-band samples you cannot classify a residual channel (standard ease / smooth custom bézier / noise). So B must run before the second fix can be chosen.

Sequence: **B (Task 1–3) → re-measure + bucket (Task 4) → choose second fix from data (Task 5, scoping only).**

---

## File Structure

**Created:**
- `fixtures/scroll-motion/multi-band.html` — multi-mover page, narrow bands at distinct offsets, each a *standard* ease + hold; calibrated RED under current code, GREEN after Task 2. Reproduces Ashley's multi-mover dilution.
- (Task 4 only) `/tmp/scroll-motion/ashley_p1.json` — ephemeral re-measurement (NOT committed; selectors/curves, IP-firewalled).

**Modified:**
- `scripts/_anim_core.py` — add `concentrate_bands()` (per-channel band concentrator).
- `scripts/web_anim.py` — second sweep uses per-channel motion → `concentrate_bands` (replaces the global `motion_per_step` path); import `CHANNELS`.
- `scripts/test_anim_core_segments.py` — unit test for `concentrate_bands`.
- `fixtures/scroll-motion/run_anim.py` — add `multi-band.html` to FIXTURES + EXPECT.
- `docs/plans/p1-real-site-scroll-certification.md` — Task 4 appends the Ashley bucketing; Task 5 appends the second-fix decision.

**Unchanged (verified compatible):** `motion_adapter.py`, `bundle_writer.py` (segment-row contract unchanged); `_anim_core.concentrate_steps` stays (used by nothing after Task 2 — remove only if no caller remains; see Task 2 Step 5).

**Environment note (from P0):** the probe Chrome must be launched with the P0 `chrome_launch` flags (already committed `6217781`) — renderer-backgrounding/throttling otherwise yields all-identity reads. If a stale probe Chrome is running without them, `pkill -f probe-runner-chrome` then let `ensure_chrome` relaunch. All host runs go on host Bash with `dangerouslyDisableSandbox: true` (sandbox can't reach CDP :9222). macOS has no `timeout`.

---

## Task 1: Realistic multi-mover fixture (RED under current code)

**Files:**
- Create: `fixtures/scroll-motion/multi-band.html`
- Modify: `fixtures/scroll-motion/run_anim.py` (FIXTURES + EXPECT)

- [ ] **Step 1: Write the fixture**

Create `fixtures/scroll-motion/multi-band.html` — N fixed movers, each animating with a **standard** ease inside its own narrow band then holding, bands spread across a long page so the coarse global sweep under-samples every band and the *global* second sweep (P0) dilutes the shared budget:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=1280, initial-scale=1">
<title>scroll-motion fixture: multi-mover distinct narrow bands (multi-mover dilution)</title>
<style>
  /* Reproduces Ashley's 21/60 "no resolvable active range" class at MULTI-MOVER
     scale: many movers, each animating only inside its own narrow band at a
     DISTINCT offset, then holding. A single coarse global sweep lands ~0-1
     samples per band; P0's GLOBAL second sweep buckets the union and the shared
     per-band budget dilutes each narrow band -> still <4 in-band samples -> still
     uncertified. concentrate_bands (per-channel) gives each band its own budget
     -> all certify. Each ease is STANDARD (linear) so post-fix certification is
     the proof; the failure is sampling, not the ease. */
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 1280px; background: #fff; font-family: Arial, sans-serif; }
  #spacer { height: 14000px; }                 /* long page, ashley-scale */
  .mv { position: fixed; left: 80px; width: 120px; height: 120px;
        background: #2b2d42; will-change: transform; }
</style>
</head>
<body>
  <div class="mv" id="m0" style="top:40px"></div>
  <div class="mv" id="m1" style="top:180px"></div>
  <div class="mv" id="m2" style="top:320px"></div>
  <div class="mv" id="m3" style="top:460px"></div>
  <div class="mv" id="m4" style="top:600px"></div>
  <div class="mv" id="m5" style="top:740px"></div>
<script>
  // 6 movers; band i = [B0,B0+W] at a distinct offset; linear rise then hold.
  // amplitudes differ so each channel's own peak differs (tests per-channel peak).
  var W = 360;
  var BANDS = [
    {el:'m0', b0:1500,  amp:300},
    {el:'m1', b0:3300,  amp:-260},
    {el:'m2', b0:5200,  amp:340},
    {el:'m3', b0:7400,  amp:-300},
    {el:'m4', b0:9600,  amp:280},
    {el:'m5', b0:11800, amp:-320},
  ].map(function(d){ d.node = document.getElementById(d.el); return d; });
  function apply() {
    var y = window.scrollY;
    for (var i=0;i<BANDS.length;i++){
      var d = BANDS[i];
      var p = Math.min(1, Math.max(0, (y - d.b0) / W));   // linear in-band, holds at 1
      d.node.style.transform = 'translateX(' + (d.amp * p) + 'px)';
    }
  }
  addEventListener('scroll', apply, { passive: true });
  apply();
</script>
</body>
</html>
```

- [ ] **Step 2: Add to the harness with a MEASURED baseline verdict**

In `fixtures/scroll-motion/run_anim.py`: append `"multi-band.html"` to `FIXTURES` and add to `EXPECT` with the value you actually MEASURE in Step 3 (do not assume). Start by adding it provisionally:

```python
    "multi-band.html":     "AMBER",  # measured in Step 3; -> GREEN after Task 2
```

- [ ] **Step 3: Measure the current verdict (must be AMBER, i.e. movers found, none certified)**

Host Chrome (flagged), on host Bash with `dangerouslyDisableSandbox: true`:
```bash
python3 fixtures/scroll-motion/run_anim.py; echo "rc=$?"
```
Read `multi-band.html`'s verdict. **Required:** it must be **AMBER** ("mover found, NOTHING certified") — movers discovered but no channel certifies, because each band is under-sampled by the current global second sweep. (If it comes up GREEN, the bands are too wide / too few — tighten `W` to ~300 and/or add more movers until the *current* code cannot certify them; the whole point is to reproduce the dilution. If RED, movers aren't discovered — widen amplitudes so discovery's lo/⅓/⅔/hi probe catches the held end.) Set `EXPECT["multi-band.html"]` to the measured `AMBER` and re-run → `PASS`.

- [ ] **Step 4: Commit**
```bash
git add fixtures/scroll-motion/multi-band.html fixtures/scroll-motion/run_anim.py
git commit -m "test(web_anim): multi-mover distinct-band fixture reproducing real-site sampling dilution (AMBER under current code)"
```

---

## Task 2: Per-channel band concentrator (`concentrate_bands`)

**Files:**
- Modify: `scripts/_anim_core.py` (add `concentrate_bands`)
- Modify: `scripts/web_anim.py` (second sweep uses it)
- Test: `scripts/test_anim_core_segments.py`

- [ ] **Step 1: Write the failing unit test**

Add to `scripts/test_anim_core_segments.py`:
```python
from _anim_core import concentrate_bands

def test_concentrate_bands_budgets_each_channel_band_independently():
    # 24 coarse steps over 14000px (~608px spacing). Two channels with narrow
    # 360px bands at DISTINCT offsets (1500 and 11800). The global union budget
    # would split thin; concentrate_bands must give EACH band >= 8 in-band samples.
    coarse_ys = [round(14000 * i / 23) for i in range(24)]
    def band(y, b0, w=360):
        p = min(1.0, max(0.0, (y - b0) / w)); return p
    def motion(b0):
        vals = [band(y, b0) for y in coarse_ys]
        return [0.0] + [abs(vals[i] - vals[i - 1]) for i in range(1, len(vals))]
    refined = concentrate_bands(coarse_ys, [motion(1500), motion(11800)],
                                k_per_band=12, max_total=200)
    in_lo = [y for y in refined if 1200 <= y <= 2100]
    in_hi = [y for y in refined if 11500 <= y <= 12400]
    assert len(in_lo) >= 8, refined            # each band densified independently
    assert len(in_hi) >= 8, refined
    assert min(refined) == 0 and max(refined) >= 13000   # endpoints retained
```

- [ ] **Step 2: Run, verify FAIL**

Run: `python3 -m pytest scripts/test_anim_core_segments.py::test_concentrate_bands_budgets_each_channel_band_independently -v`
Expected: FAIL — `cannot import name 'concentrate_bands'`.

- [ ] **Step 3: Implement `concentrate_bands` in `_anim_core.py`** (place next to `concentrate_steps`)

```python
def concentrate_bands(coarse_ys, motion_per_channel, k_per_band=12,
                      max_total=200, pad_frac=0.5):
    """Refined non-uniform scroll-step list that guarantees ~k_per_band samples
    inside EACH uncertified channel's OWN active band — unlike concentrate_steps,
    which buckets the multi-mover union and dilutes narrow sub-bands on busy pages.

    motion_per_channel: list of per-step motion arrays (one per (mover,channel)
    that needs zoom); array[i] is |value(step i) - value(step i-1)| for that
    channel. A band = a maximal run of steps above 5% of THAT channel's own peak.
    Bands are padded by max(pad_frac*width, median coarse spacing), packed with
    k_per_band samples each, unioned+deduped with the page endpoints, and the
    total is capped at max_total (highest-peak bands kept first to bound CDP cost).
    """
    if not coarse_ys or not motion_per_channel:
        return sorted(set(coarse_ys))
    lo, hi = min(coarse_ys), max(coarse_ys)
    diffs = sorted(b - a for a, b in zip(coarse_ys, coarse_ys[1:]) if b > a)
    spacing = diffs[len(diffs) // 2] if diffs else 1
    cand = []  # (peak, b0, b1) one per detected band
    for motion in motion_per_channel:
        if not motion:
            continue
        peak = max(motion)
        if peak <= 0:
            continue
        thr = peak * 0.05
        active = [i for i, m in enumerate(motion) if m > thr]
        if not active:
            continue
        runs, cur = [], [active[0]]
        for i in active[1:]:
            if i == cur[-1] + 1:
                cur.append(i)
            else:
                runs.append(cur); cur = [i]
        runs.append(cur)
        for r in runs:
            cand.append((peak, coarse_ys[r[0]], coarse_ys[r[-1]]))
    if not cand:
        return sorted(set(coarse_ys))
    cand.sort(key=lambda t: t[0], reverse=True)   # highest-peak bands first (cap priority)
    out = {lo, hi}
    for _peak, b0, b1 in cand:
        if len(out) >= max_total:
            break
        grow = max(pad_frac * (b1 - b0), spacing)
        s = max(lo, int(b0 - grow)); e = min(hi, int(b1 + grow))
        for k in range(k_per_band + 1):
            out.add(round(s + (e - s) * k / k_per_band))
    return sorted(out)
```

- [ ] **Step 4: Run the unit test — PASS**

Run: `python3 -m pytest scripts/test_anim_core_segments.py -v`
Expected: PASS (concentrate_bands + the existing segmentation/concentrate tests).

- [ ] **Step 5: Wire it into `web_anim.py`'s second sweep (replace the global path)**

In `scripts/web_anim.py`: import `CHANNELS` from `_anim_core` (extend the existing import). Inside the guarded `if need_zoom and not args.range:` block, REPLACE the global `motion_per_step`/`concentrate_steps` computation with per-(mover,channel) motion fed to `concentrate_bands`:

```python
            try:
                motion_per_channel = []
                for mi in range(len(movers)):
                    ch = out_movers[mi].get("channels", {})
                    for c, e in ch.items():
                        if e.get("certified"):
                            continue
                        ci = CHANNELS.index(c)
                        arr = [0.0]
                        for si in range(1, len(rows_m)):
                            a = rows_m[si][mi] if mi < len(rows_m[si]) else []
                            b = rows_m[si - 1][mi] if mi < len(rows_m[si - 1]) else []
                            arr.append(abs(a[ci] - b[ci]) if ci < len(a) and ci < len(b) else 0.0)
                        motion_per_channel.append(arr)
                refined_ys = concentrate_bands(ys, motion_per_channel,
                                               k_per_band=12,
                                               max_total=max(64, args.steps * 4))
                (rows_m2, ys2, mid_m2, revisit2, mid_idx2,
                 drift_ok2, max_drift2, unsettled2) = _sweep(ev, refined_ys, movers, args, settle)
                out2 = analyze_movers(movers, ys2, rows_m2, mid_m2, revisit2, mid_idx2,
                                      drift_ok2, max_drift2, unsettled2)
                out_movers = _merge_prefer_certified(out_movers, out2)
            except Exception as e:
                print("probe-runner: adaptive second sweep skipped (%s)" % e, file=sys.stderr)
```
(Keep the surrounding `need_zoom`/guard exactly as P0 left it. `concentrate_steps` may now be unused — grep `concentrate_steps` across `scripts/`; if no caller remains besides its test, leave the function + test in place, OR delete both in this commit. Do not break `test_anim_core_segments.py`.)

- [ ] **Step 6: End-to-end — multi-band fixture goes GREEN; no regression**

Host Chrome (flagged). On host Bash with `dangerouslyDisableSandbox: true`:
```bash
python3 fixtures/scroll-motion/run_anim.py; echo "rc=$?"
```
Expected: `multi-band.html` → **GREEN** (every band now gets its own ~12 samples → ≥4 after trim → certifies). `native/multiseg/band-localized/late-build` stay GREEN; `virtual-scroll` RED. Update `EXPECT["multi-band.html"]="GREEN"`, re-run → `PASS`. If `band-localized.html` regressed (single-channel path through `concentrate_bands`), fix `concentrate_bands` so a single motion array still yields ≥12 in-band samples (it should — one band, k_per_band samples).

- [ ] **Step 7: Full unit suite (no regression)**

Run: `python3 -m pytest scripts/test_anim_core_segments.py scripts/test_anim_core_z.py scripts/test_motion_adapter.py scripts/test_motion_adapter_bezier.py scripts/test_bundle_writer.py -q`
Expected: all PASS. Also `python3 -c "import ast; ast.parse(open('scripts/web_anim.py').read())"`.

- [ ] **Step 8: Commit**
```bash
git add scripts/_anim_core.py scripts/web_anim.py scripts/test_anim_core_segments.py fixtures/scroll-motion/run_anim.py
git commit -m "feat(web_anim): per-channel band concentrator so multi-mover narrow bands each get their own sample budget (real-site no-resolvable-range)"
```

---

## Task 3: Re-measure Ashley (gating) + capture residual data

**Files:** none committed except the writeup in Task 4 (raw JSON stays in /tmp, IP-firewalled).

- [ ] **Step 1: Re-run web_anim on Ashley with the per-channel second sweep**

Ensure the flagged probe Chrome is up (relaunch if a stale instance lacks the flags). Host Bash, `dangerouslyDisableSandbox: true`:
```bash
python3 /tmp/bring.py 2>/dev/null || true   # harmless; flags already make it foreground-independent
python3 scripts/web_anim.py --url "https://ashleybrookecs.com/" --steps 24 --out /tmp/scroll-motion/ashley_p1.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/scroll-motion/ashley_p1.json"))
def cert(e):
    if e.get("certified") is True: return True
    s=e.get("segments"); return bool(s) and all(x.get("certified") for x in s)
ch=[(m,c,e) for m in d["movers"] for c,e in m["channels"].items()]
print("range",d["scrollRange"],"movers",len(d["movers"]),"channels",len(ch),
      "certified",sum(1 for _,_,e in ch if cert(e)))
PY
```
Record range / movers / channels / certified. **Gate:** certified should rise materially above the P0 figure of 2. Record the exact number (counts only — IP firewall).

- [ ] **Step 2: Bucket the residual uncertified channels (this drives Task 5)**

For each STILL-uncertified channel that now has ≥4 in-band samples, reconstruct the trimmed normalized `(p,f)` from `series` (as the P0 EVALs did) and classify into exactly one bucket. Emit ONLY counts + a couple of anonymized normalized curves (no selectors/text):
```bash
python3 - <<'PY'
import json, sys; sys.path.insert(0,"scripts")
from _anim_core import CHANNELS, channel_active_range, monotonic, fit_easing, RMS_TOL
d=json.load(open("/tmp/scroll-motion/ashley_p1.json"))
ys=d["series"]["scrollY"]; pm=d["series"]["perMover"]; mv=d["movers"]
buckets={"certifies":0,"standard-just-over-tol":0,"smooth-custom":0,
         "non-monotonic-flat-tail":0,"noise/under-sampled":0}
samples=[]
for mi,m in enumerate(mv):
    for c,e in m["channels"].items():
        if e.get("certified"): continue
        ci=CHANNELS.index(c); vals=[pm[mi][si][ci] for si in range(len(ys))]
        ar=channel_active_range(ys,vals)
        if not ar: buckets["noise/under-sampled"]+=1; continue
        i0,i1,v0,v1=ar; y0,y1=ys[i0],ys[i1]; sub=vals[i0:i1+1]
        if i1-i0+1<4: buckets["noise/under-sampled"]+=1; continue
        mono=monotonic(sub, abs(v1-v0)*0.02)
        pf=[((ys[i]-y0)/(y1-y0),(vals[i]-v0)/(v1-v0)) for i in range(i0,i1+1)] if y1>y0 and v1!=v0 else None
        if not pf: buckets["noise/under-sampled"]+=1; continue
        ez=fit_easing(pf); rms=ez["rms"]
        if not mono: buckets["non-monotonic-flat-tail"]+=1
        elif rms<=RMS_TOL: buckets["certifies"]+=1
        elif rms<=0.12: buckets["standard-just-over-tol"]+=1
        elif rms<=0.30: buckets["smooth-custom"]+=1; samples.append((round(rms,3),[(round(p,2),round(f,2)) for p,f in pf]))
        else: buckets["noise/under-sampled"]+=1
print("residual buckets:", buckets)
for s in samples[:3]: print("  smooth-custom sample rms",s[0],"curve",s[1])
PY
```
This is the decision data for Task 5.

- [ ] **Step 3: (no commit — measurement only; data feeds Task 4 writeup)**

---

## Task 4: Append the P1 Ashley result to this plan + commit

- [ ] **Step 1:** Append a "## P1 live validation (post per-channel sweep)" section: before/after certified counts (P0=2 → P1=?), and the Task 3 Step 2 bucket histogram (counts only; ≤3 anonymized normalized curves). State plainly whether the gate (material jump) was met.

- [ ] **Step 2: Commit**
```bash
git add docs/plans/p1-real-site-scroll-certification.md
git commit -m "docs(p1-scroll-cert): per-channel band sweep — Ashley certified 2 -> N; residual bucket histogram drives the second-fix decision"
```

---

## Task 5: Choose the second fix FROM the bucket data (scoping only — do not pre-build)

- [ ] **Step 1:** Read the Task 3 buckets. Decide the next fix by which bucket dominates the residual:
  - **`non-monotonic-flat-tail` dominates** → fix **A** (per-segment active-range trim in the segmentation block: trim each monotonic run via `channel_active_range` before normalizing/fitting). NOW there are verified beneficiaries.
  - **`smooth-custom` dominates** → fix **free-bézier fit** (least-squares-fit the 4 control points per segment; certify if the *fit* residual is low — accept custom eases, not just the 20-entry library). NOT A.
  - **`standard-just-over-tol` dominates** → revisit `RMS_TOL` / settle quality (jitter), not A.
  - **`noise/under-sampled` dominates** → B's `k_per_band` too low, or genuinely time-based — raise budget or accept uncertified.
- [ ] **Step 2:** Append the decision (one paragraph: dominant bucket + chosen fix + why) to this plan and commit. Write the chosen fix as its own follow-up plan/tasks — do NOT implement it under this plan (keeps each fix evidence-gated).

```bash
git add docs/plans/p1-real-site-scroll-certification.md
git commit -m "docs(p1-scroll-cert): second-fix decision from residual buckets (<chosen fix>)"
```

---

## P1 live validation + second-fix decision (2026-05-30)

**Fixture (Task 1–2):** `multi-band.html` (six 200px standard-ease bands at distinct offsets) was **AMBER** (0/6 certified) under the global second sweep and **GREEN (5/6 certified)** after `concentrate_bands`. So the per-channel concentrator demonstrably resolves multi-mover narrow bands **when the eases are standard**. `concentrate_bands` unit test + full suite (107) green; harness PASS GREEN×5/RED (no regression).

**Ashley gate (Task 3) — NOT met.** `web_anim --steps 24` on `https://ashleybrookecs.com/`: range `[0,14003]`, 48 movers, 58 channels, **certified 2 (P0) → 4 (P1)**. A material jump did **not** materialise.

**Why — the decisive test.** The 54 uncertified channels yield **102 candidate bands**; the auto budget (192 samples) covers ~7. So I re-ran with **`--zoom-budget 800`** (covers the top ~32 bands by peak): **certified stayed 4.** The 4× budget — and the ~25 extra high-amplitude bands it densely sampled — produced **zero** new certifications (second sweep confirmed run, not guard-skipped, both runs). **Conclusion: sampling is NOT the real-site bottleneck.** Ashley's prominent (high-peak) motions do not certify *even when densely sampled* — they are **custom cubic-bézier and/or non-monotonic (out-and-back) eases** that the certification model rejects: `_anim_core` certifies only a match to the 20-entry **standard** easing library within `RMS_TOL=0.06`, and real GSAP eases fit at rms ~0.10–0.25. This refines the plan's premise: B (per-channel sampling) is necessary infrastructure (+ a `--zoom-budget` knob) but **not sufficient**; it only helps narrow *standard-ease* bands (the fixture), which real hero animations rarely are.

**Second-fix decision (Task 5) — bucketed on the REFINED second-sweep fits (`ashley_p1b.json`, `--zoom-budget 800`), not the coarse series:**

| Residual bucket (uncertified channel/segment) | Count | Implication |
|---|---|---|
| NON-MONOTONIC (has `segments`) | **24** | out-and-back timelines → candidate for **(A)** per-segment active-range trim (one sample segment rms **0.096**, just over the 0.06 tol → trimming a flat tail may certify it) |
| single-path fit, **jagged** (rms > 0.30) | **18** | sample rms **0.82 / 0.88 / 1.7 / 1.9** — genuinely non-deterministic / wild motion; **correctly rejected**, not fittable by any ease (free-bézier included) |
| no `easing` after refined sweep (still no-range) | **12** | coverage/resolvability — low yield |
| **smooth-custom (0.12–0.30)** — the free-bézier target | **0** | **free-bézier would certify nothing** |

**This REFUTES the earlier "blocker = certification model → free-bézier" inference** (which was made from the coarse series, before reading the refined fits). With **0** smooth-custom channels, free-bézier is **dropped**. The verified next fix is **(A) per-segment active-range trim** — it has **24 real beneficiaries**, and crucially it **stays inside the conservative "standard-eases-only" philosophy** (it trims where motion happens before fitting a *standard* ease; it does not "guess" a custom curve). **No philosophy change is required.**

**Honest outlook:** (A) targets the 24 non-monotonic channels but will not recover all of them (some of their segments are themselves jagged). The **18 jagged** (rms 0.8–1.9) are non-deterministic by web_anim's strict definition and stay uncertified by design. So even with (A), Ashley likely reaches *materially more than 4* but **not a "majority"** — a large share of its hero motion is genuinely non-deterministic/custom-timeline. B (sampling) is confirmed **not** the lever for real sites (budget-invariant); it needs no further investment beyond the delivered concentrator + `--zoom-budget` knob.

**Caveat:** `--zoom-budget 800` prioritises bands by peak amplitude (the prominent motions), so the 12 "coverage" residuals are low-amplitude channels that may be worth a certifiability-first prioritisation later — secondary to (A).

---

## (A) implemented — and it re-opens free-bézier *with data* (2026-05-30)

(A) per-segment active-range trim is DONE (`b563661`): a synthetic rise→hold→fall channel's rising segment certifies only after the held tail is trimmed (red→green); full suite 108 green; harness PASS (no regression).

**But (A) alone did NOT lift Ashley** — certified stayed **4**, and zero channels gained a certified segment. Re-bucketing the **(A)-trimmed** segment fits on Ashley is the key result: of the uncertified channels with segments, **all 13 trimmed segments now sit at rms 0.158–0.254 — i.e. 100% in the SMOOTH-CUSTOM (free-bézier) bucket, zero jagged, zero just-over.**

This **reverses the earlier "free-bézier refuted (0 smooth-custom)" call** — that bucketing was on *pre-(A)* data where flat tails inflated these same segments past 0.30 / mislabelled them. (A) trims the tails and reveals the residual's true nature: **smooth custom cubic-béziers**, not noise. So the corrected, data-verified picture is:

- **(A)** trims tails → necessary prerequisite; exposes the true shape. ✓ done.
- **free-bézier certification** is now the **data-justified** next fix (**13 verified smooth-custom segments**, rms 0.16–0.25): fit a custom cubic-bézier per (A)-trimmed segment and certify on the *fit's own* residual instead of a nearest-standard-library match. (A)+free-bézier together would certify those ~13.
- The ~18 single-path **jagged** channels (rms 0.8–1.9) stay uncertified — genuinely non-deterministic, correct.

**free-bézier IS a deliberate philosophy change** (`_anim_core` today "never guesses" — only standard-library eases certify; free-fit accepts arbitrary smooth béziers). It now has a verified basis (13 beneficiaries) but is a **USER decision**, not auto-continue. Honest ceiling even with it: ~13 more certified (→ ~17 of 58); the jagged/coverage remainder is non-deterministic by web_anim's strict definition — Ashley will not reach a "majority" of clean-certified channels because much of its motion genuinely is custom/non-deterministic.

---

## free-bézier IMPLEMENTED (Task 7, user-approved) — result (2026-05-30)

`32057f2`: `_anim_core.fit_free_bezier` (coordinate-descent 4-DOF cubic-bézier fit, stdlib) + `fit_easing` fallback — when no standard-library ease matches within `RMS_TOL` and there are ≥6 points, fit a free bézier and certify on **its own** residual, labelled `name="custom-bezier"`. This **reverses the "standard-eases-only" stance** (the approved philosophy change). A `fix(web_anim)` also makes the terminal summary handle segment-/custom-certified channels (it crashed on `ez["name"]` for a channel certified via segments). Tests: a custom bézier far from the library (lib rms 0.085) certifies via free fit (rms ~0.005, `custom-bezier`); a jagged sawtooth still does **not** free-fit under tol (no smooth bézier matches) — guards against certifying noise. Full suite 110 green; harness PASS (free-fit doesn't trigger on the standard-ease fixtures — no regression).

**Ashley result — honest:**
- **Reliable (auto-budget): certified 4 → 6–7** (run-to-run ±1; new certifications are `custom-bezier` smooth eases). Modest but real, `EXIT=0`.
- **Higher budget is environmentally unreliable, not a bigger win.** `--zoom-budget 800` (a ~5-min, ~800-sample second sweep) returned a **degraded** run (0/74 — channel count and zeros both signal the live page's render/scroll state drifted over the long sweep, despite the P0 chrome flags). So the projected "~13–17" is **not** reliably attainable on the live site: covering more bands needs a long high-budget sweep, and long live sweeps degrade.

**Final-review hardening (`73a62ef`).** A holistic review caught that the free-fit gate `len(pf) >= 6` was mathematically too weak: a free cubic-bézier has 4 DOF, so at 6 points it **interpolates** rather than fits — a deterministic piecewise-linear *kink* certified at n=6 (sample rms 0.047) with **15% held-out error**. Gate raised to **≥10 points** (≥6 residual DOF) + an n=8 boundary test. Re-measured Ashley with the honest gate: **6 certified** (4 standard eases + **2 `custom-bezier` now at ≥10 samples** — trustworthy, not interpolation), `EXIT=0`. So the count is stable (~6) AND the custom certifications are now well-determined. **Open follow-up (predates P1):** the *library* path can likewise coincidentally match a non-ease at small n (the kink matched `easeInQuad` at n=6) — harden ALL certification with a held-out/densified-replay residual check, not just free-bézier.

**Net P1 conclusion (honest):** the full stack — readiness wait (P0) + per-channel concentrator + `--zoom-budget` (B) + per-segment trim (A) + free-bézier with the ≥10 gate (Task 7) — is correct and each layer is fixture-validated. On real Ashley it lifts certified from the original **2 → ~6** reliably (incl. 2 well-sampled custom-bézier eases). It does **not** reach a majority: the dominant remainder is genuinely non-deterministic (jagged rms 0.8–1.9) or needs long high-budget sweeps that the live page won't sustain. The honest reproduction story for a site like Ashley is therefore: **acquisition + a faithful subset of certified scroll curves**, not 1:1 certification of every hero motion — consistent with the tiered-honest target in the handoff.

---

## Self-Review

**Spec coverage:** B implemented (Task 2) + reproduced-failure fixture (Task 1) + Ashley gate (Task 3–4) + evidence-gated second-fix choice (Task 5). A is NOT pre-built (advisor: zero verified beneficiaries; B is the diagnostic prerequisite). ✓

**Placeholder scan:** all code steps carry full code; the only deliberate "decide from data" is Task 5, which is scoping-by-design (the whole point of B-first). Fixture amplitudes/bands in Task 1 are starting values with an explicit calibrate-until-AMBER instruction (Step 3). ✓

**Type/name consistency:** `concentrate_bands(coarse_ys, motion_per_channel, k_per_band, max_total, pad_frac)` signature matches its unit test (Task 2 Step 1) and its web_anim call (Step 5). `motion_per_channel` = list of per-step `|delta|` arrays in both. `CHANNELS` imported where indexed. Merge/`_sweep`/guard reused verbatim from P0. ✓

**Scope check:** P1 fixes only the multi-mover sampling lever + chooses the next fix from data. It does not touch `motion_adapter`/`bundle_writer` (segment-row contract unchanged) and does not reopen P0 Tasks 1–4. The P0 follow-ups "launcher tabless self-heal" remain separate. ✓

**Environment risks called out:** flagged Chrome required; host Bash + `dangerouslyDisableSandbox`; no macOS `timeout`; CDP-cost bound via `max_total`. ✓

---

## Execution Handoff

Plan saved to `docs/plans/p1-real-site-scroll-certification.md`. Execute via superpowers:subagent-driven-development (browser tasks 1, 2-Step6, 3, 4 need host Chrome + the controller running them; pure tasks 2-Steps1-4 are pytest-only). Task 5 is a data-driven decision, not code.
