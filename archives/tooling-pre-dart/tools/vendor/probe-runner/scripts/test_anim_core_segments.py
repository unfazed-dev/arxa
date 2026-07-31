import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _anim_core import analyze_movers, CHANNELS
from _anim_core import concentrate_steps
from _anim_core import concentrate_bands
from _anim_core import fit_easing, _bez_y_at_x

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
    assert segs[0]["to"] - segs[0]["from"] > 350     # rises ~+400 (pin amplitude)
    assert segs[1]["to"] - segs[1]["from"] < -350    # falls ~-400 (pin amplitude)
    assert tx["certified"] is True                   # channel certified via segments

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


def test_concentrate_bands_resolves_narrow_multimover_bands():
    # Mirrors multi-band.html: six 200px bands at distinct offsets, 24 coarse steps
    # over ~13000px. concentrate_bands must place >=4 samples in EACH 200px band so
    # analyze_movers' channel_active_range trims to >=4 points -> fits -> certifies.
    coarse_ys = [round(13069 * i / 23) for i in range(24)]
    W = 200
    def motion(b0):
        vals = [min(1.0, max(0.0, (y - b0) / W)) for y in coarse_ys]
        return [0.0] + [abs(vals[i] - vals[i - 1]) for i in range(1, len(vals))]
    offsets = [1500, 3300, 5200, 7400, 9600, 11800]
    refined = concentrate_bands(coarse_ys, [motion(b0) for b0 in offsets],
                                k_per_band=24, max_total=200)
    for b0 in offsets:
        inb = [y for y in refined if b0 - 40 <= y <= b0 + W + 40]
        assert len(inb) >= 4, (b0, len(inb), len(refined))   # each band independently dense
    assert min(refined) == 0 and max(refined) >= 12000        # endpoints retained


def test_segment_active_range_trim_certifies_rise_then_hold():
    # Real ScrollTrigger timelines tween then HOLD the value, then later reverse.
    # tx: linear rise 0->400 over steps 0..7, hold 400 over 7..21, fall 400->0 to 29.
    # _split_monotonic yields run1=[rise+hold] and run2=[fall]. Without per-segment
    # active-range trim, run1 normalizes over its flat tail -> rms past tol -> the
    # rising segment fails to certify. With the (A) trim it fits the linear rise.
    n = 30
    ys = [round(3000 * i / (n - 1)) for i in range(n)]
    txs = []
    for i in range(n):
        if i <= 7:
            txs.append(400.0 * i / 7)
        elif i <= 21:
            txs.append(400.0)
        else:
            txs.append(400.0 * (1 - (i - 21) / (n - 1 - 21)))
    rows_m = [[_vec(tx)] for tx in txs]
    mid = n // 2
    movers = [{"sel": "div", "rank": 0, "absY": 200}]
    out = analyze_movers(movers, ys, rows_m, rows_m[mid], rows_m[mid], mid,
                         drift_ok=True, max_drift=0.0, unsettled=0)
    tx = out[0]["channels"]["tx"]
    segs = tx.get("segments")
    assert segs is not None, tx
    rise = [s for s in segs if s["to"] - s["from"] > 300]        # the rising segment
    assert rise and all(s["certified"] for s in rise), segs      # certifies after flat-tail trim


def test_fit_easing_free_bezier_certifies_smooth_custom():
    # Ground-truth from a custom cubic-bezier far from every standard-library entry
    # (smooth, monotonic, slow-start). No standard ease matches within RMS_TOL, but
    # a free cubic-bezier fit recovers it -> name "custom-bezier", rms <= tol.
    cx1, cy1, cx2, cy2 = 0.8, 0.0, 0.2, 0.6   # library best ~0.085 (> tol); free fit ~0.005
    pf = [(i / 19.0, _bez_y_at_x(i / 19.0, cx1, cy1, cx2, cy2)) for i in range(20)]
    ez = fit_easing(pf)
    assert ez["name"] == "custom-bezier", ez       # free fit engaged (no library match)
    assert ez["rms"] <= 0.06, ez                   # smooth custom -> certifiable


def test_fit_easing_free_bezier_gated_below_min_points():
    # Same smooth custom ease but only 8 samples (< the >=10 free-fit gate). A
    # 4-DOF bezier over <10 points interpolates rather than fits, so free-fit must
    # NOT engage -> the channel is not over-certified as "custom-bezier" on a thin
    # sample (guards the n=6 over-fit the final review caught).
    cx1, cy1, cx2, cy2 = 0.8, 0.0, 0.2, 0.6
    pf = [(i / 7.0, _bez_y_at_x(i / 7.0, cx1, cy1, cx2, cy2)) for i in range(8)]
    ez = fit_easing(pf)
    assert ez["name"] != "custom-bezier", ez


def test_fit_easing_free_bezier_does_not_certify_jagged():
    # A jagged / non-monotonic-ish sawtooth must NOT free-fit under tol (no smooth
    # bezier matches) -> stays uncertifiable. Guards against free-fit certifying noise.
    pf = [(i / 19.0, (0.9 if i % 2 else 0.1) * (i / 19.0)) for i in range(20)]
    ez = fit_easing(pf)
    assert ez["rms"] > 0.06, ez
