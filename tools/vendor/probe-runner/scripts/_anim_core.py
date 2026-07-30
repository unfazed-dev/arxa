#!/usr/bin/env python3
"""Engine-agnostic scroll-animation certification core.

Shared by `web_anim.py` (Chrome CDP / Safari WebDriver / Android-web) and
`flutter_anim.py` (Dart VM service). The contract is identical regardless of
how the samples were captured: given per-step scroll offsets and the matching
6-channel transform vectors per element, emit an easing fit ONLY when the value
is proven to be a deterministic function of scroll (held position + reproduces
on revisit + monotonic + matches a standard curve). Anything else is reported
`certified: false` with a reason — the core never guesses.

A "vector" is [tx, ty, sx, sy, rot, op, tz, rotX, rotY]:
  tx,ty,tz px · sx,sy unitless scale · rot,rotX,rotY deg · op 0..1.
The first six are the original 2D channels; tz/rotX/rotY (depth translate + 3D
tilt) are APPENDED so legacy producers that emit a 6-vector (flutter_anim) keep
their exact indices — never reorder this list. A vector shorter than CHANNELS is
padded with channel identity (the appended depth channels read as inert).
"""

from __future__ import annotations

from typing import Optional

# Depth channels (tz/rotX/rotY) are appended, NOT inserted — flutter_anim._decompose
# emits a fixed 6-vec [tx,ty,sx,sy,rot,op] at indices 0..5 and would corrupt if these
# shifted. Web depth is exact-transform-only; the flipbook path can't recover depth.
CHANNELS = ["tx", "ty", "sx", "sy", "rot", "op", "tz", "rotX", "rotY"]
# channel identity value (what an absent/inert channel reads as): scale=1, op=1, else 0.
_IDENT = {"sx": 1.0, "sy": 1.0, "op": 1.0}
# per-channel "meaningfully varies" threshold (a channel below this is ignored).
VARY_THR = {"tx": 3.0, "ty": 3.0, "sx": 0.02, "sy": 0.02, "rot": 0.5, "op": 0.02,
            "tz": 3.0, "rotX": 0.5, "rotY": 0.5}
# convergence tolerance: two consecutive settled reads must match within this for
# the smooth-scroll driver (Lenis / Flutter physics) to be declared converged.
# tx/ty get headroom for sub-pixel scroll jitter amplified by a steep slope.
STABLE_THR = {"tx": 2.0, "ty": 2.0, "sx": 0.01, "sy": 0.01, "rot": 0.3, "op": 0.01,
              "tz": 2.0, "rotX": 0.3, "rotY": 0.3}
# reproducibility tolerance: revisiting a scroll offset must reproduce the value.
# Both reads are converged states, so this need only clear residual jitter; a
# real time-based prop drifts by orders more and still fails.
REPRO_THR = {"tx": 4.0, "ty": 4.0, "sx": 0.02, "sy": 0.02, "rot": 0.6, "op": 0.02,
             "tz": 4.0, "rotX": 0.6, "rotY": 0.6}
RMS_TOL = 0.06  # easing fit must match a standard curve this closely to certify.
# Integer scroll offsets hide a few px of float scroll residual in smooth-scroll
# libs; on a steep curve that becomes value-noise ∝ local slope, so the
# reproducibility tolerance is widened by slope*this. Time-based drift is
# slope-independent and far larger, so it still fails the test.
SCROLL_RESIDUAL = 8.0

# weights to compare channels of different units when picking the dominant one.
_DOM_W = {"tx": 1, "ty": 1, "sx": 200, "sy": 200, "rot": 3, "op": 200,
          "tz": 1, "rotX": 3, "rotY": 3}

# Standard easing library (easings.net cubic-bezier control points).
EASINGS = {
    "linear": (0, 0, 1, 1),
    "ease": (.25, .1, .25, 1),
    "ease-in": (.42, 0, 1, 1),
    "ease-out": (0, 0, .58, 1),
    "ease-in-out": (.42, 0, .58, 1),
    "easeInQuad": (.11, 0, .5, 0), "easeOutQuad": (.5, 1, .89, 1),
    "easeInOutQuad": (.45, 0, .55, 1),
    "easeInCubic": (.32, 0, .67, 0), "easeOutCubic": (.33, 1, .68, 1),
    "easeInOutCubic": (.65, 0, .35, 1),
    "easeInQuart": (.5, 0, .75, 0), "easeOutQuart": (.25, 1, .5, 1),
    "easeInOutQuart": (.76, 0, .24, 1),
    "easeInExpo": (.7, 0, .84, 0), "easeOutExpo": (.16, 1, .3, 1),
    "easeInOutExpo": (.87, 0, .13, 1),
    "easeInSine": (.12, 0, .39, 0), "easeOutSine": (.61, 1, .88, 1),
    "easeInOutSine": (.37, 0, .63, 1),
}


def _bez(t, c1, c2):
    return 3 * (1 - t) ** 2 * t * c1 + 3 * (1 - t) * t ** 2 * c2 + t ** 3


def _bez_y_at_x(x, x1, y1, x2, y2):
    lo, hi = 0.0, 1.0
    for _ in range(40):
        m = (lo + hi) / 2
        if _bez(m, x1, x2) < x:
            lo = m
        else:
            hi = m
    return _bez((lo + hi) / 2, y1, y2)


def _bez_rms(pf, x1, y1, x2, y2):
    return (sum((_bez_y_at_x(p, x1, y1, x2, y2) - f) ** 2 for p, f in pf) / len(pf)) ** 0.5


def fit_free_bezier(pf, start, rounds=40, step=0.25):
    """Coordinate-descent fit of a FREE cubic-bezier ease (control points
    P1=(x1,y1), P2=(x2,y2); fixed P0=(0,0), P3=(1,1)) to normalized (p,f) samples,
    starting from `start`=(x1,y1,x2,y2) (the nearest standard ease). Returns
    (params, rms). The x-coords stay clamped to [0,1] so _bez_y_at_x's x->t search
    remains monotonic; y-coords are free (overshoot eases allowed). stdlib only —
    no numpy. Certifies smooth CUSTOM eases that no standard-library entry matches:
    a smooth curve fits to a low residual; jagged/non-deterministic motion does
    not, so this does not certify noise."""
    P = [float(v) for v in start]
    best = _bez_rms(pf, *P)
    s = step
    for _ in range(rounds):
        improved = False
        for i in range(4):
            for d in (s, -s):
                q = P[:]
                q[i] += d
                if i in (0, 2):                       # x-coords: keep in [0,1]
                    q[i] = min(1.0, max(0.0, q[i]))
                r = _bez_rms(pf, *q)
                if r < best - 1e-9:
                    P, best, improved = q, r, True
        if not improved:
            s *= 0.5
            if s < 1e-3:
                break
    return P, best


def fit_easing(pf):
    """pf = list of (p, f) normalized samples. Return best easing name+rms."""
    best, best_rms = None, 1e9
    for name, (x1, y1, x2, y2) in EASINGS.items():
        rms = (sum((_bez_y_at_x(p, x1, y1, x2, y2) - f) ** 2 for p, f in pf) / len(pf)) ** 0.5
        if rms < best_rms:
            best, best_rms = name, rms
    if best is None:
        return {"name": "custom", "nearest": None, "bezier": None, "rms": 9.99}
    bz = EASINGS[best]
    if best_rms > RMS_TOL and len(pf) >= 10:
        # No standard-library ease is tight enough. Try a free cubic-bezier fit and
        # certify the smooth custom ease on its OWN residual (reverses the prior
        # "standard-eases-only" stance — see p1-real-site-scroll-certification).
        # The >=10-point guard matters: a free cubic-bezier has 4 DOF, so at <10
        # samples the fit INTERPOLATES rather than fits and a low sample-residual is
        # no evidence of a smooth ease (a deterministic kink would over-certify with
        # large between-sample error). >=10 leaves >=6 residual DOF.
        fp, frms = fit_free_bezier(pf, bz)
        if frms < best_rms:
            x1, y1, x2, y2 = (round(v, 4) for v in fp)
            return {"name": "custom-bezier", "nearest": best,
                    "bezier": f"cubic-bezier({x1},{y1},{x2},{y2})",
                    "rms": round(frms, 4)}
    label = best if best_rms <= 0.1 else "custom"
    return {"name": label, "nearest": best,
            "bezier": f"cubic-bezier({bz[0]},{bz[1]},{bz[2]},{bz[3]})",
            "rms": round(best_rms, 4)}


def vecs_close(ma, mb):
    """True when every mover/channel matches within STABLE_THR (a settled frame).

    Tolerates vectors shorter than CHANNELS: flutter_anim feeds 6-vectors
    [tx,ty,sx,sy,rot,op]; the appended depth channels (tz/rotX/rotY) read as
    channel identity (inert) so a missing depth channel never IndexErrors and
    never spuriously fails the close-match.
    """
    if len(ma) != len(mb):
        return False
    for va, vb in zip(ma, mb):
        for ci, c in enumerate(CHANNELS):
            a = va[ci] if ci < len(va) else _IDENT.get(c, 0.0)
            b = vb[ci] if ci < len(vb) else _IDENT.get(c, 0.0)
            if abs(a - b) > STABLE_THR[c]:
                return False
    return True


def monotonic(vals, eps):
    """True if vals never reverse direction by more than eps (noise-tolerant).
    Scroll-scrubbed eases are monotonic; a single standard easing can't describe
    an out-and-back curve, so non-monotonic channels are not easing-certified."""
    up = dn = False
    for a, b in zip(vals, vals[1:]):
        d = b - a
        if d > eps:
            up = True
        elif d < -eps:
            dn = True
    return not (up and dn)


def channel_active_range(ys, vals):
    """Return (i0, i1, v0, v1) bounding where the channel actually moves."""
    v0, v1 = vals[0], vals[-1]
    span = v1 - v0
    if span == 0:
        return None
    thr = abs(span) * 0.02
    i0 = 0
    for i, v in enumerate(vals):
        if abs(v - v0) > thr:
            i0 = max(0, i - 1)
            break
    i1 = len(vals) - 1
    for i in range(len(vals) - 1, -1, -1):
        if abs(vals[i] - v1) > thr:
            i1 = min(len(vals) - 1, i + 1)
            break
    if i1 <= i0:
        return None
    return i0, i1, v0, v1


def _split_monotonic(ys_sub, vals_sub, eps):
    """Split (ys_sub, vals_sub) at sign-changes of the first difference into
    monotonic runs of >= 4 samples. Returns list of (ys_seg, vals_seg).

    Runs shorter than 4 samples are silently discarded (there is nothing
    meaningful to fit an easing to below 4 points). If a coarse sweep ever
    drops below ~8 --steps, a real short turn could be lost here."""
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


def concentrate_steps(coarse_ys, motion_per_step, n, pad_frac=0.5):
    """Build a refined, non-uniform scroll-step list that packs samples into the
    bands where the coarse sweep saw motion. motion_per_step[i] is the peak
    per-channel transform-magnitude change at coarse step i (a band detector, not
    a true sum). Returns sorted unique offsets:
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


def concentrate_bands(coarse_ys, motion_per_channel, k_per_band=24,
                      max_total=200, pad_frac=0.5):
    """Refined non-uniform scroll-step list that guarantees ~k_per_band samples
    inside EACH uncertified channel's OWN active band — unlike concentrate_steps,
    which buckets the multi-mover union and dilutes narrow sub-bands on busy pages.

    motion_per_channel: list of per-step motion arrays (one per (mover,channel)
    that needs zoom); array[i] is |value(step i) - value(step i-1)| for that
    channel. A band = a maximal run of steps above 5% of THAT channel's own peak.
    Each band is padded by max(pad_frac*width, median coarse spacing) (a single
    coarse-hit band's true extent is unknown to within +/- one coarse step, so the
    neighborhood must be resampled), then packed with k_per_band evenly-spaced
    samples; all bands are unioned+deduped with the page endpoints, and the total
    is capped at max_total (highest-peak bands kept first to bound CDP cost).
    k_per_band must be high enough that a band W wide inside a ~2*spacing
    neighborhood still gets >=4 samples (>= ~4*2*spacing/W)."""
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


def analyze_movers(movers, ys, rows_m, mid_m, revisit_m, mid_idx,
                   drift_ok, max_drift, unsettled):
    """Run the certification gate over every mover.

    Args (all engine-agnostic):
      movers   : list of meta dicts (carry sel/txt/absY etc; merged into output).
      ys       : per-step target scroll offsets.
      rows_m   : per-step list of per-mover 6-vectors (rows_m[step][mover]).
      mid_m    : per-mover 6-vector at the mid step (first visit).
      revisit_m: per-mover 6-vector at the mid step (revisit) — reproducibility.
      mid_idx  : index of the mid step within ys.
      drift_ok : scroll/transform converged at every step (bool).
      max_drift: worst |actualY-targetY| seen (for the reason string).
      unsettled: count of steps that never converged (for the reason string).

    Returns out_movers: list of {**meta, dominant, channels}.
    """
    n = len(movers)
    out_movers = []
    for mi in range(n):
        ch_series = {c: [] for c in CHANNELS}
        for m in rows_m:
            vec = m[mi] if mi < len(m) else []
            for ci, c in enumerate(CHANNELS):
                # legacy producers emit a 6-vector; the appended depth channels
                # (ci>=len(vec)) read as channel identity (inert), never IndexError.
                ch_series[c].append(vec[ci] if ci < len(vec) else _IDENT.get(c, 0.0))
        repro_delta = {}
        mid_vec = mid_m[mi] if mi < len(mid_m) else []
        rev_vec = revisit_m[mi] if mi < len(revisit_m) else []
        for ci, c in enumerate(CHANNELS):
            va = mid_vec[ci] if ci < len(mid_vec) else _IDENT.get(c, 0.0)
            vb = rev_vec[ci] if ci < len(rev_vec) else _IDENT.get(c, 0.0)
            repro_delta[c] = abs(vb - va)

        channels = {}
        dominant, dom_var = None, 0.0
        for c in CHANNELS:
            vals = ch_series[c]
            var = max(vals) - min(vals)
            if var < VARY_THR[c]:
                continue
            # slope-scaled reproducibility (see SCROLL_RESIDUAL note).
            lo_i, hi_i = max(0, mid_idx - 1), min(len(ys) - 1, mid_idx + 1)
            dscroll = ys[hi_i] - ys[lo_i]
            slope = abs(vals[hi_i] - vals[lo_i]) / dscroll if dscroll else 0.0
            repro_ok = repro_delta[c] <= REPRO_THR[c] + slope * SCROLL_RESIDUAL

            ar = channel_active_range(ys, vals)
            entry = {"from": round(vals[0], 3), "to": round(vals[-1], 3),
                     "range": round(var, 3),
                     "scrollDeterministic": drift_ok and repro_ok}
            easing, mono = None, None
            if ar:
                i0, i1, v0, v1 = ar
                y0, y1 = ys[i0], ys[i1]
                span = v1 - v0
                sub = vals[i0:i1 + 1]
                mono = monotonic(sub, abs(span) * 0.02)
                if y1 > y0:
                    pf = [((ys[i] - y0) / (y1 - y0), (vals[i] - v0) / span)
                          for i in range(i0, i1 + 1)]
                    if len(pf) >= 4:
                        entry["activeScroll"] = [y0, y1]
                        easing = fit_easing(pf)
                        entry["easing"] = easing
            certified = bool(drift_ok and repro_ok and easing
                             and easing["rms"] <= RMS_TOL and mono)
            entry["certified"] = certified
            if not certified:
                if not drift_ok:
                    entry["reason"] = ("scroll/transform did not converge "
                                       "(maxDrift %.1fpx, %d unsettled step(s))"
                                       % (max_drift, unsettled))
                elif not repro_ok:
                    entry["reason"] = "not reproducible on revisit (time-based, not scroll-scrubbed)"
                elif easing is None:
                    entry["reason"] = "no resolvable active range at this sampling (try more --steps)"
                elif not mono:
                    entry["reason"] = "non-monotonic / multi-phase: not a single standard easing"
                else:
                    entry["reason"] = "curve does not match a standard easing (rms %.3f)" % easing["rms"]
            if not certified and drift_ok and repro_ok and (max(vals) - min(vals)) >= VARY_THR[c]:
                var2 = max(vals) - min(vals)
                seg_entries = []
                for ys_seg, vals_seg in _split_monotonic(ys, vals, var2 * 0.05):
                    # (A) Trim each monotonic run to its OWN active sub-range before
                    # fitting. Real ScrollTrigger timelines tween then HOLD the value;
                    # the held (flat) tail of a run would otherwise dominate the
                    # normalized fit and push rms past RMS_TOL (p1 bucket: 24 such
                    # non-monotonic channels on Ashley). Fitting only the active rise
                    # keeps us inside the standard-ease model (no guessing).
                    ar_seg = channel_active_range(ys_seg, vals_seg)
                    if not ar_seg:
                        continue
                    i0, i1, s0, s1 = ar_seg
                    yy0, yy1 = ys_seg[i0], ys_seg[i1]
                    if abs(s1 - s0) < VARY_THR[c] or yy1 <= yy0:
                        continue
                    sub_ys, sub_vals = ys_seg[i0:i1 + 1], vals_seg[i0:i1 + 1]
                    pf = [((yy - yy0) / (yy1 - yy0), (vv - s0) / (s1 - s0))
                          for yy, vv in zip(sub_ys, sub_vals)]
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
            if var * _DOM_W[c] > dom_var:
                dom_var, dominant = var * _DOM_W[c], c

        out_movers.append({**movers[mi], "dominant": dominant, "channels": channels})
    return out_movers
