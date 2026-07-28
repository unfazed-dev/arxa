#!/usr/bin/env python3
"""Tests for motion_adapter.motion_summary — pure logic, no I/O.

Asserts the summary lifts the BEST per-channel reading from both raw shapes:
  - klass "scroll" (web_anim / flutter_anim movers[]).channels[]
  - klass "time"  (web_flipbook recovery.channels / raw analyze_frames channels)
and surfaces a consistent {easing, amplitude, rms, window, confidence,
source_channel} per axis, with the honest two-model contract (scroll: no
duration, window = activeScroll; time: no window, confidence = reliable).
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import motion_adapter as ma


# ─── scroll (web_anim / flutter_anim shape) ───────────────────────────────────

def _scroll_payload(channels_per_mover):
    """movers[i] = {"sel":.., "absY":.., "channels": {ch: entry}}"""
    movers = []
    for ch_dict in channels_per_mover:
        movers.append({"sel": "div", "rank": 0, "absY": 100,
                       "channels": ch_dict})
    return {"movers": movers}


def test_scroll_lifts_certified_channel():
    p = _scroll_payload([{"ty": {
        "from": -40.0, "to": 0.0,
        "activeScroll": [200, 640],
        "easing": {"name": "easeOutCubic", "bezier": "x", "rms": 0.012},
        "certified": True}}])
    s = ma.motion_summary(p, "scroll")
    assert s["klass"] == "scroll", s
    assert "y" in s["channels"], s
    row = s["channels"]["y"]
    assert row["easing"] == "easeOutCubic", row
    assert row["amplitude"] == 40.0, row           # signed to - from
    assert row["rms"] == 0.012, row
    assert row["window"] == [200.0, 640.0], row
    assert row["confidence"] == "high", row         # certified -> high
    assert row["source_channel"] == "ty", row


def test_scroll_uncertified_marked_low_confidence():
    p = _scroll_payload([{"ty": {
        "from": 0.0, "to": 10.0, "activeScroll": [0, 100],
        "easing": {"name": "linear", "bezier": "x", "rms": 0.2},
        "certified": False}}])
    s = ma.motion_summary(p, "scroll")
    assert s["channels"]["y"]["confidence"] == "low", s


def test_scroll_segmented_channel_picks_best_segment():
    # a channel with two segments: one certified (low rms), one not.
    p = _scroll_payload([{"tx": {"certified": True, "segments": [
        {"from": 0.0, "to": 400.0, "activeScroll": [0.0, 1000.0],
         "easing": {"name": "easeOut", "rms": 0.02}, "certified": True},
        {"from": 400.0, "to": 0.0, "activeScroll": [1000.0, 2000.0],
         "easing": {"name": "easeIn", "rms": 0.30}, "certified": False},
    ]}}])
    s = ma.motion_summary(p, "scroll")
    row = s["channels"]["x"]
    assert row["confidence"] == "high", row          # best = certified segment
    assert row["easing"] == "easeOut", row
    assert row["amplitude"] == 400.0, row
    assert row["window"] == [0.0, 1000.0], row


def test_scroll_two_movers_same_axis_keeps_strongest():
    # two movers both on axis y: certified beats uncertified regardless of order
    p = {"movers": [
        {"sel": "a", "absY": 0, "channels": {"ty": {
            "from": 0.0, "to": 5.0, "activeScroll": [0, 10],
            "easing": {"name": "linear", "rms": 0.3}, "certified": False}}},
        {"sel": "b", "absY": 0, "channels": {"ty": {
            "from": 0.0, "to": 50.0, "activeScroll": [0, 100],
            "easing": {"name": "easeOut", "rms": 0.01}, "certified": True}}},
    ]}
    s = ma.motion_summary(p, "scroll")
    row = s["channels"]["y"]
    assert row["confidence"] == "high" and row["amplitude"] == 50.0, row


def test_scroll_empty_payload():
    s = ma.motion_summary({"movers": []}, "scroll")
    assert s == {"klass": "scroll", "channels": {}}, s


# ─── time (flipbook shape) ────────────────────────────────────────────────────

def test_time_lifts_reliable_channel():
    # web_flipbook shape: recovery.channels
    p = {"selector": ".menu", "recovery": {"channels": {
        "ty": {"from": -300.0, "to": 0.0, "amp": 300.0, "reliable": True,
               "easing": "easeInOutQuart", "bezier": "x", "rms": 0.008}}}}
    s = ma.motion_summary(p, "time")
    assert s["klass"] == "time", s
    row = s["channels"]["y"]
    assert row["easing"] == "easeInOutQuart", row
    assert row["amplitude"] == 300.0, row            # abs(amp) for time klass
    assert row["rms"] == 0.008, row
    assert row["window"] is None, row                # time klass: no scroll window
    assert row["confidence"] == "high", row           # reliable -> high
    assert row["source_channel"] == "ty", row


def test_time_raw_analyze_frames_shape():
    # recover_from_video / analyze_frames: top-level channels (no recovery wrapper)
    p = {"channels": {
        "scale": {"from": 0.5, "to": 1.0, "amp": 0.5, "reliable": True,
                  "easing": "easeOutCubic", "bezier": "x", "rms": 0.02}}}
    s = ma.motion_summary(p, "time")
    assert "scale" in s["channels"], s               # passthrough axis
    assert s["channels"]["scale"]["amplitude"] == 0.5, s


def test_time_null_easing_channel_skipped():
    p = {"recovery": {"channels": {
        "opacity": {"from": 0.0, "to": 1.0, "amp": 1.0, "reliable": True,
                    "easing": None, "bezier": "-", "rms": None}}}}
    s = ma.motion_summary(p, "time")
    assert "opacity" not in s["channels"], s


def test_time_amp_fallback_from_to_minus_from():
    p = {"recovery": {"channels": {
        "tx": {"from": 10.0, "to": 70.0, "reliable": True,   # no amp key
               "easing": "linear", "bezier": "x", "rms": 0.01}}}}
    s = ma.motion_summary(p, "time")
    assert s["channels"]["x"]["amplitude"] == 60.0, s


def test_time_empty_payload():
    s = ma.motion_summary({"recovery": {"channels": {}}}, "time")
    assert s == {"klass": "time", "channels": {}}, s


# ─── axis naming parity between the two models ────────────────────────────────

def test_both_models_map_ty_to_y_axis():
    scroll = ma.motion_summary(_scroll_payload([{"ty": {
        "from": 0.0, "to": 1.0, "activeScroll": [0, 1],
        "easing": {"name": "linear", "rms": 0.0}, "certified": True}}]), "scroll")
    time = ma.motion_summary({"recovery": {"channels": {"ty": {
        "from": 0.0, "to": 1.0, "amp": 1.0, "reliable": True,
        "easing": "linear", "bezier": "x", "rms": 0.0}}}}, "time")
    assert "y" in scroll["channels"] and "y" in time["channels"], (scroll, time)
