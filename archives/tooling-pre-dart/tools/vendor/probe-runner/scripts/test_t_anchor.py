# scripts/test_t_anchor.py
import _t_anchor as ta


def test_summarize_basic():
    assert ta.summarize([0.2, 0.4, 0.9]) == (0.2, 0.4, 0.9, 3)
    assert ta.summarize([0.2, 0.4]) == (0.2, 0.3, 0.4, 2)      # even -> mean of middle two
    assert ta.summarize([]) is None


def _site(high, low, n):
    return {"high_t1_median": high, "low_max": low, "n_t1_pairs": n}


def test_verdict_inconclusive_below_two_conclusive_sites():
    # only one site clears the >=3 Tier-1 pairs floor
    d, t = ta.verdict([_site(0.8, 0.3, 5), _site(0.8, 0.3, 2)])
    assert d == "INCONCLUSIVE" and t is None


def test_verdict_pass_05_in_band():
    d, t = ta.verdict([_site(0.7, 0.3, 5), _site(0.8, 0.45, 4)])
    assert d == "PASS" and t == 0.5


def test_verdict_reanchor_band_excludes_05():
    # clean gap (0.6, 0.75) above 0.5 -> re-anchor to the midpoint
    d, t = ta.verdict([_site(0.75, 0.55, 5), _site(0.85, 0.6, 4)])
    assert d == "RE-ANCHOR"
    assert t == round((0.6 + 0.75) / 2, 3)        # midpoint of (max_low, min_high)


def test_verdict_fail_on_overlap():
    # cross-site aggregate: max_low(0.6) >= min_high(0.5) -> overlap -> FAIL (not per-site)
    d, t = ta.verdict([_site(0.5, 0.6, 5), _site(0.8, 0.3, 4)])
    assert d == "FAIL" and t is None


def test_verdict_05_on_boundary_is_reanchor_not_pass():
    # PASS requires 0.5 STRICTLY inside the gap; 0.5 touching either edge -> RE-ANCHOR
    d_lo, t_lo = ta.verdict([_site(0.8, 0.5, 5), _site(0.9, 0.5, 4)])   # max_low == 0.5
    assert d_lo == "RE-ANCHOR" and t_lo == round((0.5 + 0.8) / 2, 3)
    d_hi, t_hi = ta.verdict([_site(0.5, 0.3, 5), _site(0.6, 0.2, 4)])   # min_high == 0.5
    assert d_hi == "RE-ANCHOR" and t_hi == round((0.3 + 0.5) / 2, 3)


def test_verdict_n_exactly_three_is_conclusive():
    # the >=3 Tier-1 pairs floor: n==3 counts as conclusive (boundary of the gate)
    d, t = ta.verdict([_site(0.7, 0.3, 3), _site(0.8, 0.45, 3)])
    assert d == "PASS" and t == 0.5
