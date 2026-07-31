"""Z-axis (depth) channel tests for _anim_core.

Phase 2 of probe-runner-2d-motion-binding: tz/rotX/rotY are APPENDED to CHANNELS
(never reordered — flutter_anim emits a fixed 6-vec [tx,ty,sx,sy,rot,op] at those
indices). These tests feed analyze_movers VARYING depth values across steps (a
static matrix3d that happens to pass proves nothing) and assert the depth channel
certifies, plus that a legacy 6-vector still analyzes without IndexError.
"""
import _anim_core as ac

CH = ac.CHANNELS
N = len(CH)


def _vec(**kw):
    """Build a CHANNELS-length vector: identity defaults, override by channel name."""
    base = {c: (1.0 if c in ("sx", "sy") else (1.0 if c == "op" else 0.0)) for c in CH}
    base.update(kw)
    return [float(base[c]) for c in CH]


def _run(per_step_overrides, ys):
    """per_step_overrides: list of {channel: value} dicts, one per scroll step.
    One mover. Returns its analyzed channels dict."""
    mover = {"rank": 0, "sel": "div.card", "tag": "DIV", "absY": 500, "absX": 200, "txt": ""}
    rows_m = [[_vec(**ov)] for ov in per_step_overrides]
    mid_idx = len(ys) // 2
    mid_m = rows_m[mid_idx]
    revisit_m = rows_m[mid_idx]          # exact repro (settled-scrub)
    out = ac.analyze_movers([mover], ys, rows_m, mid_m, revisit_m, mid_idx,
                            drift_ok=True, max_drift=0.0, unsettled=0)
    return out[0]["channels"]


def test_channels_appended_not_reordered():
    # the original 6 keep their indices (flutter_anim depends on this); Z appended.
    assert CH[:6] == ["tx", "ty", "sx", "sy", "rot", "op"]
    assert set(CH[6:]) == {"tz", "rotX", "rotY"}


def test_threshold_dicts_cover_new_channels():
    for d in (ac.VARY_THR, ac.STABLE_THR, ac.REPRO_THR, ac._DOM_W):
        for c in ("tz", "rotX", "rotY"):
            assert c in d, f"{c} missing from a threshold/weight dict"


def test_tz_linear_ramp_certifies():
    # translateZ ramps 0..120 linearly with scroll -> certifies as "linear".
    ys = [i * 100 for i in range(8)]            # 0,100,...,700
    steps = [{"tz": 120.0 * i / 7} for i in range(8)]
    chans = _run(steps, ys)
    assert "tz" in chans, "tz channel not analyzed"
    assert chans["tz"]["certified"] is True
    assert chans["tz"]["from"] == 0.0
    assert round(chans["tz"]["to"]) == 120


def test_rotX_ramp_certifies():
    ys = [i * 100 for i in range(8)]
    steps = [{"rotX": 45.0 * i / 7} for i in range(8)]
    chans = _run(steps, ys)
    assert "rotX" in chans
    assert chans["rotX"]["certified"] is True


def test_inactive_depth_channels_absent():
    # a pure-ty mover: tz/rotX/rotY don't vary -> not reported (VARY_THR gate).
    ys = [i * 100 for i in range(8)]
    steps = [{"ty": -40.0 * (1 - i / 7)} for i in range(8)]
    chans = _run(steps, ys)
    assert "ty" in chans
    assert "tz" not in chans and "rotX" not in chans and "rotY" not in chans


def test_vecs_close_tolerates_six_vectors():
    # flutter_anim calls vecs_close([vec],[prev]) with 6-element _decompose vecs
    # [tx,ty,sx,sy,rot,op]. The appended Z channels must read as inert, not
    # IndexError, and two equal 6-vecs must compare close.
    v6a = [0.0, -40.0, 1.0, 1.0, 0.0, 1.0]
    v6b = [0.0, -40.3, 1.0, 1.0, 0.0, 1.0]   # within STABLE_THR(ty)=2.0
    assert ac.vecs_close([v6a], [v6b]) is True
    v6c = [0.0, -90.0, 1.0, 1.0, 0.0, 1.0]   # ty differs by 50 -> not close
    assert ac.vecs_close([v6a], [v6c]) is False
    # mixed lengths (6 vs 9) also tolerated: identity-padded depth matches
    v9 = [0.0, -40.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0]
    assert ac.vecs_close([v6a], [v9]) is True


def test_legacy_six_vector_still_analyzes():
    # flutter_anim emits a 6-vector [tx,ty,sx,sy,rot,op]. analyze_movers must not
    # IndexError on the 3 appended channels — they read as inert (no variation).
    mover = {"rank": 0, "sel": "w", "tag": "W", "absY": 0, "txt": ""}
    ys = [i * 100 for i in range(8)]
    rows_m = [[[0.0, -40.0 * (1 - i / 7), 1.0, 1.0, 0.0, 1.0]] for i in range(8)]  # 6-long
    mid_idx = len(ys) // 2
    out = ac.analyze_movers([mover], ys, rows_m, rows_m[mid_idx], rows_m[mid_idx],
                            mid_idx, drift_ok=True, max_drift=0.0, unsettled=0)
    chans = out[0]["channels"]
    assert "ty" in chans            # the real 2D channel analyzed
    assert "tz" not in chans        # appended channel inert, no crash
