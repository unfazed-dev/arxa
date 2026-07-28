#!/usr/bin/env python3
"""Tests for flutter_skeleton — pure logic, no VM (hermetic).

Covers classify(), build_skeleton() (probe-skeleton/2 shape + parent topology +
zero-area drop), _parse_walk() (the VM CSV decoder), and a flutter→flutter
self-diff through skeleton_diff confirming the output is skeleton_diff-
compatible. The VM capture path (_capture/main) is live-only and lives in
derisk_flutter_skeleton.py.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flutter_skeleton as fs
import skeleton_diff as sd


# ─── classify ─────────────────────────────────────────────────────────────────

def test_classify_text_types():
    for t in ("Text", "RichText", "EditableText", "SelectableText"):
        assert fs.classify(t) == "text", t


def test_classify_image_types_exact():
    assert fs.classify("Image") == "image"
    assert fs.classify("FadeInImage") == "image"


def test_classify_box_types():
    # painting containers with bg/shape/elevation → "box"
    assert fs.classify("DecoratedBox") == "box"
    assert fs.classify("ColoredBox") == "box"
    assert fs.classify("Material") == "box"
    assert fs.classify("Card") == "box"
    assert fs.classify("CustomPaint") == "box"


def test_classify_structural_widgets_dropped():
    # purely-structural layout/gesture/semantics wrappers → None (dropped). They
    # paint no intrinsic visual and keeping them double-counts child geometry.
    # These dominated the live tree's 76/77 unknown_box count; dropping them is
    # the principled fix grounded in Flutter's render model.
    for t in ("Padding", "SizedBox", "Container", "Column", "Row", "Semantics",
              "RepaintBoundary", "GestureDetector", "Listener", "Focus",
              "Center", "KeyedSubtree", "Builder"):
        assert fs.classify(t) is None, t


def test_classify_unknown_is_unknown_box_not_none():
    # a genuinely-UNKNOWN painting widget (a bespoke canvas) still ships geometry
    # at confidence:low — the conservative default is to keep, not drop, so a
    # novel painting widget is never silently lost.
    assert fs.classify("SomeBespokeCanvas") == "unknown_box"
    assert fs.classify("") == "unknown_box"


# ─── build_skeleton: shape + schema ───────────────────────────────────────────

def _raw():
    return [
        {"type": "Material", "x": 0, "y": 0, "w": 400, "h": 800, "parentDepth": 0},
        {"type": "Text", "x": 16, "y": 24, "w": 200, "h": 24, "parentDepth": 1},
        {"type": "Image", "x": 16, "y": 60, "w": 100, "h": 100, "parentDepth": 1},
    ]


def test_schema_is_probe_skeleton_2():
    sk = fs.build_skeleton(_raw())
    assert sk["schema"] == "probe-skeleton/2", sk["schema"]
    assert sk["engine"] == "flutter"


def test_node_has_all_required_keys():
    sk = fs.build_skeleton(_raw())
    for n in sk["nodes"]:
        for k in ("id", "role", "confidence", "bbox", "z", "parent",
                  "sizing", "layout", "token_ref", "anim_ref"):
            assert k in n, (k, n)
        assert set(n["bbox"]) == {"x", "y", "w", "h"}, n["bbox"]


def test_zero_area_node_dropped():
    raw = _raw() + [{"type": "SizedBox", "x": 0, "y": 0, "w": 0, "h": 0, "parentDepth": 1}]
    sk = fs.build_skeleton(raw)
    # SizedBox is structural → None (dropped), zero-area is a second drop reason.
    assert len(sk["nodes"]) == 3, [n["role"] for n in sk["nodes"]]
    assert all(n["bbox"]["w"] > 0 and n["bbox"]["h"] > 0 for n in sk["nodes"])


def test_roles_assigned():
    sk = fs.build_skeleton(_raw())
    # Material → "box" (paints bg); Text → "text"; Image → "image".
    assert [n["role"] for n in sk["nodes"]] == ["box", "text", "image"]


def test_confidence_high_except_unknown_box():
    sk = fs.build_skeleton(_raw())
    conf = {n["role"]: n["confidence"] for n in sk["nodes"]}
    # box/text/image all paint visible content → high confidence.
    assert conf["box"] == "high"
    assert conf["text"] == "high"
    assert conf["image"] == "high"


def test_text_node_has_no_font_block_but_has_text_len():
    sk = fs.build_skeleton(_raw())
    text_node = next(n for n in sk["nodes"] if n["role"] == "text")
    # honest: no TextStyle read over the VM -> no font block (skeleton_diff
    # skips the font-size gate when "font" is absent, so it never false-fails).
    assert "font" not in text_node
    assert text_node.get("text_len") is None


def test_sizing_low_confidence_placeholder():
    sk = fs.build_skeleton(_raw())
    for n in sk["nodes"]:
        assert n["sizing"]["confidence"] == "low", n["sizing"]


# ─── build_skeleton: parent topology from depth ───────────────────────────────

def test_parent_chain_from_depth():
    # 3-deep nesting: A(root) > B > C
    raw = [
        {"type": "A", "x": 0, "y": 0, "w": 10, "h": 10, "parentDepth": 0},
        {"type": "B", "x": 0, "y": 0, "w": 10, "h": 10, "parentDepth": 1},
        {"type": "C", "x": 0, "y": 0, "w": 10, "h": 10, "parentDepth": 2},
    ]
    sk = fs.build_skeleton(raw)
    by_role = {n["role"]: n for n in sk["nodes"]}  # A/B/C all -> unknown_box
    # ids assigned in order; lookup by id
    nodes = sk["nodes"]
    assert nodes[0]["parent"] is None        # A
    assert nodes[1]["parent"] == 0           # B's parent is A
    assert nodes[2]["parent"] == 1           # C's parent is B


def test_sibling_branches_reparent_correctly():
    # A > [B, C]  (B and C are siblings, both children of A)
    raw = [
        {"type": "A", "x": 0, "y": 0, "w": 10, "h": 10, "parentDepth": 0},
        {"type": "B", "x": 0, "y": 0, "w": 10, "h": 10, "parentDepth": 1},
        {"type": "C", "x": 0, "y": 0, "w": 10, "h": 10, "parentDepth": 1},
    ]
    sk = fs.build_skeleton(raw)
    nodes = sk["nodes"]
    assert nodes[0]["parent"] is None
    assert nodes[1]["parent"] == 0 and nodes[2]["parent"] == 0  # both -> A


# ─── _parse_walk: the VM CSV decoder ──────────────────────────────────────────

_WALK_SAMPLE = (
    "Material\x1f\x1f0.0\x1f0.0\x1f400.0\x1f800.0\x1f3.0\x1f0"
    "\x1eText\x1f[<'hero' Key()]\x1f16.0\x1f24.0\x1f200.0\x1f24.0\x1f3.0\x1f1"
)


def test_parse_walk_decodes_rows():
    nodes, dpr = fs._parse_walk(_WALK_SAMPLE)
    assert dpr == 3.0, dpr
    assert len(nodes) == 2, nodes
    assert nodes[0]["type"] == "Material"
    assert nodes[0]["w"] == 400.0 and nodes[0]["h"] == 800.0
    assert nodes[0]["parentDepth"] == 0
    assert nodes[1]["type"] == "Text"
    assert nodes[1]["key"]  # non-empty key preserved
    assert nodes[1]["x"] == 16.0


def test_parse_walk_empty_returns_empty():
    nodes, dpr = fs._parse_walk("")
    assert nodes == [] and dpr is None


def test_parse_walk_skips_malformed_rows():
    raw = "Good\x1fk\x1f1.0\x1f2.0\x1f3.0\x1f4.0\x1f2.0\x1f0\x1ebad,row"
    nodes, dpr = fs._parse_walk(raw)
    assert len(nodes) == 1, nodes
    assert dpr == 2.0


def test_round_trip_parse_then_build():
    nodes, _ = fs._parse_walk(_WALK_SAMPLE)
    sk = fs.build_skeleton(nodes)
    assert sk["schema"] == "probe-skeleton/2"
    assert len(sk["nodes"]) == 2
    assert sk["nodes"][0]["bbox"] == {"x": 0.0, "y": 0.0, "w": 400.0, "h": 800.0}


# ─── skeleton_diff integration (the point: works unmodified) ──────────────────

def test_flutter_self_diff_passes():
    sk = fs.build_skeleton(_raw())
    result = sd.diff(sk, sk, sd.DEFAULT_GATES)
    assert result["pass"] is True, result


def test_flutter_diff_detects_geometry_change():
    sk_a = fs.build_skeleton(_raw())
    # clone: nudge the text node 50px right. Its center moves outside the
    # skeleton_diff align radius (24px), so it goes UNMATCHED rather than
    # registering a pos_err — either way the diff must FAIL (matched_frac drops
    # below the 0.99 gate). This proves flutter geometry flows through
    # skeleton_diff and a real change is caught.
    raw_b = [dict(r) for r in _raw()]
    raw_b[1] = {**raw_b[1], "x": 66}  # was 16
    sk_b = fs.build_skeleton(raw_b)
    result = sd.diff(sk_a, sk_b, sd.DEFAULT_GATES)
    assert result["pass"] is False, result
    assert result["matched_frac"] < sd.DEFAULT_GATES["matched_frac"], result
    assert result["unmatched_clone"] >= 1, result


def test_flutter_diff_detects_small_pos_err():
    # A sub-radius shift (5px) matches but exceeds the 1.0px pos gate -> fail
    # via max_pos_err. Covers the pos_err path the larger test does not.
    sk_a = fs.build_skeleton(_raw())
    raw_b = [dict(r) for r in _raw()]
    raw_b[1] = {**raw_b[1], "x": 21}  # was 16 -> +5px, within align radius
    sk_b = fs.build_skeleton(raw_b)
    result = sd.diff(sk_a, sk_b, sd.DEFAULT_GATES)
    assert result["pass"] is False, result
    assert result["measured"]["max_pos_err"] >= 5.0, result["measured"]
