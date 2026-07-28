#!/usr/bin/env python3
"""Unit tests for ios_flipbook's pure logic: parsing `idb ui describe-all`
JSON to resolve an element + its frame, and the dpr / device-px region /
start-vs-end displacement-oracle math. No simulator needed.

TREE mirrors the real `idb ui describe-all` element shape verified against
idb on 2026-05-28: each node has a `frame` dict (logical points), a string
`type`, `AXLabel`/`title`, `role`, etc.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ios_flipbook as fb  # noqa: E402

TREE = [
    {"AXFrame": "{{0, 0}, {393, 852}}", "AXLabel": None, "AXUniqueId": None,
     "AXValue": None, "content_required": False, "custom_actions": [],
     "enabled": True, "frame": {"x": 0, "y": 0, "width": 393, "height": 852},
     "help": None, "role": "AXApplication", "role_description": "application",
     "subrole": None, "title": None, "type": "Application"},
    {"AXFrame": "{{20, 700}, {56, 56}}", "AXLabel": "Increment",
     "AXUniqueId": None, "AXValue": None, "content_required": False,
     "custom_actions": [], "enabled": True,
     "frame": {"x": 20, "y": 700, "width": 56, "height": 56}, "help": None,
     "role": "AXButton", "role_description": "button", "subrole": None,
     "title": None, "type": "Button"},
    {"AXFrame": "{{20, 100}, {48, 48}}", "AXLabel": "box", "AXUniqueId": None,
     "AXValue": None, "content_required": False, "custom_actions": [],
     "enabled": True, "frame": {"x": 20, "y": 100, "width": 48, "height": 48},
     "help": None, "role": "AXImage", "role_description": "", "subrole": None,
     "title": None, "type": "Image"},
    # a degenerate (zero-area) node that must never be returned
    {"AXFrame": "{{0, 0}, {0, 0}}", "AXLabel": "box", "AXUniqueId": None,
     "AXValue": None, "content_required": False, "custom_actions": [],
     "enabled": True, "frame": {"x": 0, "y": 0, "width": 0, "height": 0},
     "help": None, "role": None, "role_description": "", "subrole": None,
     "title": None, "type": "Other"},
]


def test_find_element_by_label():
    el = fb.find_element(TREE, label="box")
    assert el is not None
    assert fb.frame_of(el) == (20.0, 100.0, 48.0, 48.0)


def test_find_element_by_type():
    el = fb.find_element(TREE, type_="Button")
    assert el is not None and el["AXLabel"] == "Increment"


def test_find_element_substring_match():
    el = fb.find_element(TREE, label="ncremen")  # substring, not exact
    assert el is not None and el["type"] == "Button"


def test_find_element_skips_degenerate_frame():
    # two nodes labelled "box"; the zero-area one must be skipped
    el = fb.find_element(TREE, label="box")
    assert fb.frame_of(el) == (20.0, 100.0, 48.0, 48.0)


def test_find_element_missing_returns_none():
    assert fb.find_element(TREE, label="nonexistent") is None


def test_find_element_requires_a_selector():
    import pytest
    with pytest.raises(ValueError):
        fb.find_element(TREE)


def test_region_devpx_scales_by_dpr():
    assert fb.region_devpx((20.0, 100.0, 48.0, 48.0), 3.0) == (60, 300, 144, 144)


def test_region_devpx_clamps_nonnegative():
    assert fb.region_devpx((-2.0, -2.0, 10.0, 10.0), 2.0) == (0, 0, 20, 20)


def test_displacement_points():
    d = fb.displacement((20.0, 100.0, 48.0, 48.0), (320.0, 100.0, 48.0, 48.0))
    assert d == {"tx": 300.0, "ty": 0.0}


def test_derive_dpr_rounds_to_common_scale():
    assert fb.derive_dpr(1179, 393) == 3.0
    assert fb.derive_dpr(750, 375) == 2.0
