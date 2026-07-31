#!/usr/bin/env python3
"""Unit tests for _consent — the pure, browser-free core of G6 occluding-overlay
(consent-class) detection and content-blind Escape dismiss."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _consent import classify_overlay, overlay_dismissed, detect_and_dismiss

FULL = {"x": 0, "y": 0, "w": 1280, "h": 800}


def _cand(**kw):
    base = {"position": "fixed", "z": 1000, "coverage": 1.0,
            "role": None, "bbox": FULL}
    base.update(kw)
    return base


def test_full_bleed_fixed_high_z_is_an_overlay():
    o = classify_overlay(_cand())
    assert o is not None
    assert o["kind"] == "occluding_overlay"
    assert o["coverage"] == 1.0
    assert o["z"] == 1000
    assert o["bbox"] == FULL


def test_static_hero_is_not_flagged():
    # No positioning context above content -> under-detect (safe): page-behind
    # is still captured, we just don't mislabel a hero as a consent State.
    assert classify_overlay(_cand(position="static")) is None


def test_absolute_is_not_flagged():
    # Consent backdrops are conventionally position:fixed; absolute is usually
    # in-flow layout. Require fixed -> documented under-detect direction.
    assert classify_overlay(_cand(position="absolute")) is None


def test_low_coverage_edge_banner_is_not_flagged():
    # A bottom cookie strip covers little of the viewport -> not an OCCLUDING
    # overlay. §C7: low-coverage banners don't block capture anyway.
    assert classify_overlay(_cand(coverage=0.12, bbox={"x": 0, "y": 760, "w": 1280, "h": 40})) is None


def test_no_stacking_layer_is_not_flagged():
    # z None or <= 0 means it does not stack above content -> not occluding.
    assert classify_overlay(_cand(z=None)) is None
    assert classify_overlay(_cand(z=0)) is None


def test_min_coverage_threshold_is_the_boundary():
    assert classify_overlay(_cand(coverage=0.49)) is None
    assert classify_overlay(_cand(coverage=0.50)) is not None


def test_overlay_gone_after_rescan_is_cleared():
    before = classify_overlay(_cand())
    # post-dismiss re-scan finds no occluding overlay
    assert overlay_dismissed(before, []) is True


def test_overlay_still_present_is_not_cleared():
    before = classify_overlay(_cand())
    after = [classify_overlay(_cand())]  # same full-bleed overlay still there
    assert overlay_dismissed(before, after) is False


def test_match_is_by_top_left_corner_within_radius():
    # A DIFFERENT occluding overlay at a far corner is not the same overlay, so the
    # original counts as cleared (corner match within radius=24 is the identity rule).
    before = classify_overlay(_cand())
    far = classify_overlay(_cand(bbox={"x": 600, "y": 400, "w": 680, "h": 400}))
    assert overlay_dismissed(before, [far]) is True


def _scanner(*rounds):
    """Return a scan() that yields the next round's candidate list on each call."""
    seq = list(rounds)
    calls = {"n": 0}

    def scan():
        i = min(calls["n"], len(seq) - 1)
        calls["n"] += 1
        return seq[i]
    return scan


def test_no_overlay_returns_none():
    fired = {"dismiss": 0, "sleep": 0}
    out = detect_and_dismiss(
        _scanner([]),
        lambda: fired.__setitem__("dismiss", fired["dismiss"] + 1),
        lambda s: fired.__setitem__("sleep", fired["sleep"] + 1),
    )
    assert out is None
    assert fired["dismiss"] == 0  # no overlay -> no dismiss attempted


def test_escape_clears_overlay_records_cleared_true():
    # round 1: overlay present; round 2 (post-Escape): gone
    out = detect_and_dismiss(
        _scanner([_cand()], []),
        lambda: None, lambda s: None,
    )
    assert out["kind"] == "occluding_overlay"
    assert out["dismiss"] == "escape"
    assert out["cleared"] is True


def test_escape_ignored_records_cleared_false():
    # both rounds: the same overlay is still there (an Escape-ignoring wall)
    out = detect_and_dismiss(
        _scanner([_cand()], [_cand()]),
        lambda: None, lambda s: None,
    )
    assert out["dismiss"] == "escape"
    assert out["cleared"] is False


def test_dismiss_is_attempted_exactly_once_when_overlay_present():
    fired = {"dismiss": 0}
    detect_and_dismiss(
        _scanner([_cand()], []),
        lambda: fired.__setitem__("dismiss", fired["dismiss"] + 1),
        lambda s: None,
    )
    assert fired["dismiss"] == 1


def test_corner_match_radius_is_inclusive_boundary():
    before = classify_overlay(_cand())  # bbox top-left (0,0)
    # exactly radius px away on one axis -> still the SAME overlay (not cleared)
    on = {"kind": "occluding_overlay", "coverage": 1.0, "z": 999, "role": None,
          "bbox": {"x": 24, "y": 0, "w": 1280, "h": 800}}
    assert overlay_dismissed(before, [on]) is False
    # one px beyond radius -> a different overlay, original counts as cleared
    off = {"kind": "occluding_overlay", "coverage": 1.0, "z": 999, "role": None,
           "bbox": {"x": 25, "y": 0, "w": 1280, "h": 800}}
    assert overlay_dismissed(before, [off]) is True
