#!/usr/bin/env python3
"""Unit tests for adb_flipbook's pure logic: parsing uiautomator `bounds` +
resolving a view from the XML hierarchy dump, and the device-px region /
start-vs-end displacement-oracle math. No emulator needed.

DUMP mirrors the real `uiautomator dump` XML shape (bounds="[x1,y1][x2,y2]"
in device px, resource-id/text/class/content-desc attrs), verified against
the Android uiautomator dump format + adb_ui_tree.py.
"""
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import adb_flipbook as fb  # noqa: E402

# A minimal uiautomator hierarchy: root > [Counter box, Increment button, zero-area dup]
_DUMP_XML = """<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" resource-id="" class="android.widget.FrameLayout"
        content-desc="" bounds="[0,0][1080,2400]">
    <node index="0" text="0" resource-id="com.example:id/counter"
          class="android.widget.TextView" content-desc="Counter"
          bounds="[40,200][200,260]" />
    <node index="1" text="Increment" resource-id="com.example:id/btn"
          class="android.widget.Button" content-desc="Increment button"
          bounds="[440,1800][640,1900]" />
    <node index="2" text="0" resource-id="com.example:id/counter"
          class="android.widget.TextView" content-desc="Counter"
          bounds="[0,0][0,0]" />
  </node>
</hierarchy>"""

_ROOT = ET.fromstring(_DUMP_XML)


# ─── parse_bounds ─────────────────────────────────────────────────────────────

def test_parse_bounds_basic():
    assert fb.parse_bounds("[40,200][200,260]") == (40, 200, 160, 60)


def test_parse_bounds_is_device_px_not_scaled():
    # device px come through verbatim (no dpr fold) — Android parity point
    assert fb.parse_bounds("[0,0][1080,2400]") == (0, 0, 1080, 2400)


def test_parse_bounds_degenerate_returns_none():
    assert fb.parse_bounds("[0,0][0,0]") is None
    assert fb.parse_bounds("[10,10][10,10]") is None  # w=h=0
    assert fb.parse_bounds("[200,200][100,100]") is None  # inverted -> negative


def test_parse_bounds_empty_or_garbage_returns_none():
    assert fb.parse_bounds("") is None
    assert fb.parse_bounds("not bounds") is None
    assert fb.parse_bounds(None) is None


# ─── find_view ────────────────────────────────────────────────────────────────

def test_find_view_by_resource_id():
    el = fb.find_view(_ROOT, resource_id="com.example:id/btn")
    assert el is not None
    assert fb.bounds_of(el) == (440, 1800, 200, 100)


def test_find_view_by_text():
    el = fb.find_view(_ROOT, text="Increment")
    assert el is not None and fb.bounds_of(el) == (440, 1800, 200, 100)


def test_find_view_by_class():
    el = fb.find_view(_ROOT, cls="android.widget.Button")
    assert el is not None


def test_find_view_substring_match():
    el = fb.find_view(_ROOT, resource_id="btn")  # substring of the full id
    assert el is not None


def test_find_view_skips_degenerate_bounds():
    # two nodes share resource-id com.example:id/counter; the [0,0][0,0] one
    # must be skipped -> returns the real counter at (40,200).
    el = fb.find_view(_ROOT, resource_id="com.example:id/counter")
    assert fb.bounds_of(el) == (40, 200, 160, 60)


def test_find_view_by_desc():
    el = fb.find_view(_ROOT, desc="Increment button")
    assert el is not None


def test_find_view_missing_returns_none():
    assert fb.find_view(_ROOT, resource_id="nope") is None


def test_find_view_requires_a_selector():
    import pytest
    with pytest.raises(ValueError):
        fb.find_view(_ROOT)


def test_find_view_all_selectors_must_match():
    # text matches btn but class does not -> no match
    assert fb.find_view(_ROOT, text="Increment", cls="android.widget.TextView") is None


# ─── bounds_of / center_of ────────────────────────────────────────────────────

def test_bounds_of_reads_node_attr():
    el = fb.find_view(_ROOT, resource_id="com.example:id/btn")
    assert fb.bounds_of(el) == (440, 1800, 200, 100)


def test_center_of_is_device_px_center():
    assert fb.center_of((440, 1800, 200, 100)) == (540, 1850)
    assert fb.center_of((0, 0, 1080, 2400)) == (540, 1200)


# ─── displacement oracle ──────────────────────────────────────────────────────

def test_displacement_device_px():
    d = fb.displacement((40, 200, 160, 60), (340, 200, 160, 60))
    assert d == {"tx": 300, "ty": 0}


def test_displacement_diagonal():
    d = fb.displacement((0, 0, 10, 10), (100, 50, 10, 10))
    assert d == {"tx": 100, "ty": 50}


# ─── no-dpr-derivation parity point ───────────────────────────────────────────

def test_android_needs_no_dpr_derivation():
    # Unlike ios_flipbook.derive_dpr (screenshot_px / root_pts_w), Android's
    # uiautomator bounds are already device px == screenrecord space, so the
    # region is the raw bounds (dpr=1.0). This test documents that contract:
    # region_devpx == bounds_of, identity, no scaling.
    el = fb.find_view(_ROOT, resource_id="com.example:id/btn")
    region = fb.bounds_of(el)  # what main() passes straight to recover_from_video
    assert region == (440, 1800, 200, 100)
    # there is no adb_flipbook.derive_dpr function — parity with iOS is "simpler"
    assert not hasattr(fb, "derive_dpr")
