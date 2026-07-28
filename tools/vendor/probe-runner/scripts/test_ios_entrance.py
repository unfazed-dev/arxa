#!/usr/bin/env python3
"""Tests for ios_entrance — pure logic only (no device, no cv2 at import).

Unit-tested here: classify (fade/pop/none), regions_from_tree (AX tree ->
ordered device-px regions, incl. --select filtering), parse_regions (literal
rect spec). The self-test exercises the synthetic-series classification path
end-to-end. Live-only (not tested here): main() CLI, simctl/idb I/O.
"""
from __future__ import annotations

import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))
import ios_entrance as ie


# ─── classify ────────────────────────────────────────────────────────────────

class TestClassify:
    def test_fade_gradual(self):
        # gradual rise across the middle frames -> fade
        lum = [0.10] * 6 + [0.20, 0.35, 0.50, 0.65, 0.80] + [0.90] * 6
        k, on, se, d = ie.classify(lum, fps=30.0)
        assert k == "fade"
        assert on is not None and se is not None
        assert se > on                       # gradual, not a step
        assert d > 0                         # rose

    def test_pop_step(self):
        # flat low then an instant step to high -> pop (settle within pop_frames)
        lum = [0.10] * 12 + [0.90] * 18
        k, on, se, d = ie.classify(lum, fps=30.0)
        assert k == "pop"
        assert on is not None and se is not None
        assert (se - on) * 30 <= 2           # within pop_frames
        assert d > 0

    def test_none_no_change(self):
        k, on, se, d = ie.classify([0.50] * 30, fps=30.0)
        assert k == "none"
        assert on is None and se is None
        assert d == 0.0

    def test_below_lum_thr_is_none(self):
        # a sub-threshold wiggle reads as none (no honest signal to certify)
        lum = [0.500, 0.503, 0.501, 0.504, 0.500] * 6
        k, on, se, d = ie.classify(lum, fps=30.0, lum_thr=0.012)
        assert k == "none"

    def test_short_series_is_none(self):
        # <3 frames: cannot classify; honest 'none'
        assert ie.classify([0.1, 0.1], fps=30.0)[0] == "none"

    def test_negative_delta_signed(self):
        # a fade-OUT (descending) -> kind fade, negative delta preserved
        lum = [0.90] * 6 + [0.80, 0.65, 0.50, 0.35, 0.20] + [0.10] * 6
        k, on, se, d = ie.classify(lum, fps=30.0)
        assert k == "fade"
        assert d < 0


# ─── regions_from_tree ───────────────────────────────────────────────────────

_TREE = [
    {"AXLabel": "WELCOME", "frame": {"x": 40, "y": 120, "width": 300, "height": 40}},
    {"AXLabel": "title", "frame": {"x": 40, "y": 180, "width": 300, "height": 60}},
    {"AXLabel": "", "frame": {"x": 0, "y": 0, "width": 0, "height": 0}},   # degenerate, dropped
    {"title": "subtitle", "frame": {"x": 40, "y": 260, "width": 300, "height": 30}},
    {"AXLabel": "footer", "frame": {"x": 40, "y": 700, "width": 300, "height": 24}},
]


class TestRegionsFromTree:
    def test_all_non_degenerate_kept_in_order(self):
        regions = ie.regions_from_tree(_TREE, dpr=3.0)
        # 4 non-degenerate elements (the 0x0 one dropped), in source order
        assert [r["label"] for r in regions] == ["WELCOME", "title", "subtitle", "footer"]
        # logical pts -> device px (x*dpr ...)
        assert regions[0]["x"] == 120.0 and regions[0]["w"] == 900.0

    def test_select_filters_by_label_preserving_order(self):
        regions = ie.regions_from_tree(_TREE, dpr=1.0, select=["WELCOME", "footer"])
        assert [r["label"] for r in regions] == ["WELCOME", "footer"]

    def test_select_no_match_yields_empty(self):
        assert ie.regions_from_tree(_TREE, dpr=1.0, select=["nonexistent"]) == []

    def test_title_fallback_when_no_axlabel(self):
        # 'subtitle' has no AXLabel but has title -> labeled by title
        regions = ie.regions_from_tree(_TREE, dpr=1.0)
        assert any(r["label"] == "subtitle" for r in regions)

    def test_unlabeled_gets_synthetic_label(self):
        tree = [{"frame": {"x": 0, "y": 0, "width": 10, "height": 10}}]
        regions = ie.regions_from_tree(tree, dpr=1.0)
        assert regions[0]["label"] == "el0"


# ─── parse_regions ───────────────────────────────────────────────────────────

class TestParseRegions:
    def test_single_rect(self):
        r = ie.parse_regions("10,20,30,40")
        assert r == [{"label": "region0", "x": 10.0, "y": 20.0, "w": 30.0, "h": 40.0}]

    def test_multiple_rects_colon_separated(self):
        r = ie.parse_regions("0,0,100,100:200,200,50,50")
        assert len(r) == 2
        assert r[1]["x"] == 200.0

    def test_bad_rect_count_exits(self):
        with pytest.raises(SystemExit):
            ie.parse_regions("10,20,30")


# ─── derive_dpr ──────────────────────────────────────────────────────────────

class TestDeriveDpr:
    def test_standard_iphone_dpr3(self):
        # 1170 px wide screenshot / 390pt root -> dpr 3
        assert ie.derive_dpr(1170.0, 390.0) == 3.0

    def test_snap_to_nearest_int(self):
        assert ie.derive_dpr(750.0, 375.0) == 2.0

    def test_zero_root_defaults_to_one(self):
        assert ie.derive_dpr(1170.0, 0.0) == 1.0


# ─── self-test (synthetic classification path) ───────────────────────────────

class TestSelfTest:
    def test_self_test_passes(self):
        # runs the synthetic fade/pop/none classification path; exits 0
        assert ie._self_test() == 0
