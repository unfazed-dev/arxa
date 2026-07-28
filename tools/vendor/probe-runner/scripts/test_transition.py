import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _transition import map_easing, _bind_node, build_transition  # noqa: E402


def test_map_easing_named_keyword_certifies():
    r = map_easing("ease-out", [])
    assert r == {"klass": "ease-out", "bezier": [0, 0, 0.58, 1],
                 "certified": True, "reason": None}


def test_map_easing_cubic_bezier_matches_named_within_tol():
    # cubic-bezier(.25,.1,.25,1) == the "ease" standard curve
    r = map_easing("cubic-bezier(0.25, 0.1, 0.25, 1)", [])
    assert r["klass"] == "ease" and r["certified"] is True


def test_map_easing_custom_cubic_bezier_kept_raw_and_certified():
    r = map_easing("cubic-bezier(0.1, 0.9, 0.2, 1)", [])
    assert r["klass"] == "cubic-bezier" and r["certified"] is True
    assert r["bezier"] == [0.1, 0.9, 0.2, 1.0]


def test_map_easing_prefers_nonlinear_keyframe_over_linear_timing():
    # CSS animations often report getTiming().easing == "linear" with the real
    # animation-timing-function on the keyframes.
    r = map_easing("linear", ["ease-out", "linear"])
    assert r["klass"] == "ease-out" and r["certified"] is True


def test_map_easing_all_linear_is_linear():
    r = map_easing("linear", ["linear"])
    assert r == {"klass": "linear", "bezier": [0, 0, 1, 1],
                 "certified": True, "reason": None}


def test_map_easing_steps_uncertified():
    r = map_easing("steps(4, end)", [])
    assert r == {"klass": "steps", "bezier": None,
                 "certified": False, "reason": "steps()"}


def test_map_easing_mixed_keyframe_easing_uncertified():
    r = map_easing("linear", ["ease-out", "ease-in"])
    assert r["certified"] is False and r["reason"] == "mixed-keyframe-easing"


def test_map_easing_none_declared_is_linear():
    r = map_easing(None, [])
    assert r == {"klass": "linear", "bezier": [0, 0, 1, 1],
                 "certified": True, "reason": None}


def test_map_easing_unknown_function_uncertified():
    # CSS linear()/spring() and other unrecognized timing functions must NOT be
    # silently certified as linear — honest ceiling.
    r = map_easing("spring(1, 100, 10, 0)", [])
    assert r == {"klass": "unknown", "bezier": None,
                 "certified": False, "reason": "unknown-easing"}


def _component():
    # Mirrors build_component output: re-rooted nodes with component-local ids.
    return {"n_nodes": 2, "nodes": [
        {"id": 0, "role": "region", "bbox": {"x": 40, "y": 40, "w": 320, "h": 180},
         "z": 0, "sizing": None, "layout": None,
         "colors": {"bg": "rgb(18, 52, 86)", "fg": None, "border": None},
         "parent": None, "mount": {"role": "box", "bbox": {"x": 0, "y": 0, "w": 1000, "h": 400},
                                   "colors": {"bg": "rgba(0,0,0,0)", "fg": None, "border": None}}},
        {"id": 1, "role": "text", "bbox": {"x": 50, "y": 50, "w": 300, "h": 24},
         "z": 0, "sizing": None, "layout": None,
         "colors": {"bg": None, "fg": "rgb(200,200,200)", "border": None},
         "parent": 0, "mount": None}]}


def test_bind_node_matches_nearest_component_node_by_bbox():
    c = _component()
    # bbox over node 0's box (center ~200,130)
    assert _bind_node({"x": 41, "y": 41, "w": 318, "h": 178}, c) == 0
    # bbox over node 1's box (center ~200,62)
    assert _bind_node({"x": 50, "y": 50, "w": 300, "h": 24}, c) == 1


def test_bind_node_returns_none_when_no_node_within_radius():
    c = _component()
    assert _bind_node({"x": 900, "y": 900, "w": 10, "h": 10}, c) is None


def test_build_transition_none_when_empty_or_no_component():
    c = _component()
    assert build_transition([], c) is None
    assert build_transition([{"duration": 240, "iterations": 1, "bbox": None,
                              "easing": "ease-out", "props": ["opacity"]}], None) is None


def test_build_transition_binds_and_maps_law():
    c = _component()
    raw = [{"duration": 240.0, "delay": 0, "easing": "linear",
            "kfEasings": ["ease-out", "linear"], "iterations": 1,
            "props": ["transform", "opacity"],
            "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}, "playState": "running"}]
    t = build_transition(raw, c)
    assert t["n_anims"] == 1
    a = t["anims"][0]
    assert a["node"] == 0
    assert a["props"] == ["opacity", "transform"]   # sorted
    assert a["duration_ms"] == 240.0 and a["delay_ms"] == 0
    assert a["easing"]["klass"] == "ease-out" and a["certified"] is True
    assert a["reason"] is None


def test_build_transition_skips_infinite_and_zero_duration():
    c = _component()
    raw = [{"duration": 240, "iterations": None, "easing": "ease-out",  # ambient loop
            "props": ["opacity"], "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}},
           {"duration": 0, "iterations": 1, "easing": "ease-out",        # no motion
            "props": ["opacity"], "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}}]
    assert build_transition(raw, c) is None


def test_build_transition_unbound_reason_when_no_node_match():
    c = _component()
    raw = [{"duration": 240, "delay": 0, "easing": "ease-out", "iterations": 1,
            "props": ["opacity"], "bbox": {"x": 900, "y": 900, "w": 10, "h": 10}}]
    t = build_transition(raw, c)
    assert t["anims"][0]["node"] is None
    assert t["anims"][0]["reason"] == "unbound"
    assert t["anims"][0]["certified"] is True   # easing law still exact


def test_build_transition_content_free_keys_only():
    c = _component()
    raw = [{"duration": 240, "delay": 0, "easing": "ease-out", "iterations": 1,
            "props": ["opacity"], "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}}]
    a = build_transition(raw, c)["anims"][0]
    assert set(a.keys()) == {"node", "props", "duration_ms", "delay_ms",
                             "easing", "certified", "reason"}
    assert set(a["easing"].keys()) == {"klass", "bezier"}


def test_bind_node_skips_node_missing_bbox():
    # _bind_node must not crash on a malformed node lacking a bbox.
    c = {"n_nodes": 1, "nodes": [{"id": 0}]}
    assert _bind_node({"x": 0, "y": 0, "w": 10, "h": 10}, c) is None


def test_build_transition_steps_easing_uncertified_but_bound():
    # A bound anim whose easing is steps() stays bound but uncertified (honest ceiling).
    c = _component()
    raw = [{"duration": 200, "delay": 0, "easing": "steps(4, end)", "iterations": 1,
            "props": ["opacity"], "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}}]
    a = build_transition(raw, c)["anims"][0]
    assert a["node"] == 0 and a["certified"] is False and a["reason"] == "steps()"
    assert a["easing"] == {"klass": "steps", "bezier": None}


def test_build_transition_multiple_anims_independent():
    c = _component()
    raw = [{"duration": 240, "delay": 0, "easing": "ease-out", "iterations": 1,
            "props": ["transform"], "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}},
           {"duration": 180, "delay": 20, "easing": "ease-in", "iterations": 1,
            "props": ["opacity"], "bbox": {"x": 50, "y": 50, "w": 300, "h": 24}}]
    t = build_transition(raw, c)
    assert t["n_anims"] == 2
    assert t["anims"][0]["node"] == 0 and t["anims"][0]["easing"]["klass"] == "ease-out"
    assert t["anims"][1]["node"] == 1 and t["anims"][1]["easing"]["klass"] == "ease-in"
    assert t["anims"][1]["delay_ms"] == 20


def test_build_transition_skips_anim_with_no_named_props():
    # An anim whose keyframes name no real CSS property carries nothing reproducible.
    c = _component()
    raw = [{"duration": 240, "iterations": 1, "easing": "ease-out", "props": [],
            "bbox": {"x": 41, "y": 41, "w": 318, "h": 178}}]
    assert build_transition(raw, c) is None
