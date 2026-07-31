"""Tests for _shape_key — the canonical content-free node fingerprint."""
import os
import sys

import _shape_key as sk

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "research", "capture-gap-probes"))

_NODE_A = {
    "id": 3, "role": "card", "bbox": {"x": 0, "y": 4000, "w": 320, "h": 180}, "z": 0,
    "parent": 1, "sizing": {"w": 320, "h": 180, "confidence": "high"},
    "layout": {"mode": "flex", "direction": "column", "gap": 8, "pad": 16,
               "justify": "start", "align": "stretch", "grid_cols": None, "grid_rows": None},
    "token_ref": {"bg": None, "fg": None, "border": None}, "text_len": 12,
}


def test_key_excludes_position_and_id():
    # Same structure, different position/id -> identical key.
    b = dict(_NODE_A, id=99, bbox={"x": 0, "y": 50, "w": 320, "h": 180}, parent=7)
    assert sk._node_key(_NODE_A) == sk._node_key(b)


def test_key_separates_distinct_structure():
    b = dict(_NODE_A, role="banner")
    assert sk._node_key(_NODE_A) != sk._node_key(b)


def test_parity_with_dedup_probe():
    # The probe must produce a byte-identical key (drift guard).
    from probe_g3d_dedup import _node_key as probe_key
    assert sk._node_key(_NODE_A) == probe_key(_NODE_A)
