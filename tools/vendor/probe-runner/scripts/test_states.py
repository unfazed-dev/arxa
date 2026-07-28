import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _states import classify_trigger, diff_skeletons, _matches_rest, build_component


def test_aria_haspopup_is_menu_click():
    rec = {"tag": "BUTTON", "role": None, "ariaHaspopup": "true",
           "ariaExpanded": "false", "hasOpen": False, "selector": "html > body > button:nth-of-type(1)"}
    assert classify_trigger(rec) == {"kind": "menu", "action": "click"}


def test_details_summary_is_disclosure():
    assert classify_trigger({"tag": "SUMMARY", "role": None, "ariaHaspopup": None,
                             "ariaExpanded": None, "hasOpen": False, "selector": "x"}) \
        == {"kind": "disclosure", "action": "click"}


def test_aria_expanded_false_is_disclosure():
    assert classify_trigger({"tag": "DIV", "role": "button", "ariaHaspopup": None,
                             "ariaExpanded": "false", "hasOpen": False, "selector": "x"}) \
        == {"kind": "disclosure", "action": "click"}


def test_already_expanded_is_skipped():
    # aria-expanded already true -> the state is open; nothing new to reveal.
    assert classify_trigger({"tag": "DIV", "role": "button", "ariaHaspopup": None,
                             "ariaExpanded": "true", "hasOpen": False, "selector": "x"}) is None


def test_plain_element_is_not_a_trigger():
    assert classify_trigger({"tag": "DIV", "role": None, "ariaHaspopup": None,
                             "ariaExpanded": None, "hasOpen": False, "selector": "x"}) is None


def _node(nid, role, x, y, w, h, z=0):
    return {"id": nid, "role": role, "bbox": {"x": x, "y": y, "w": w, "h": h}, "z": z}


def test_diff_flags_newly_appeared_nodes():
    rest = {"nodes": [_node(0, "box", 0, 0, 1280, 40)]}
    after = {"nodes": [
        _node(0, "box", 0, 0, 1280, 40),          # unchanged (matches rest)
        _node(1, "menuitem", 100, 200, 300, 60),  # NEW
        _node(2, "menuitem", 100, 270, 300, 60),  # NEW
        _node(3, "menuitem", 100, 340, 300, 60),  # NEW
    ]}
    d = diff_skeletons(rest, after)
    assert d["n_appeared"] == 3, d
    assert all(a["role"] == "menuitem" for a in d["appeared"])
    assert "bbox" in d["appeared"][0] and "z" in d["appeared"][0]


def test_diff_ignores_small_shifts():
    # a node that merely shifts a few px is the SAME node, not "appeared".
    rest = {"nodes": [_node(0, "box", 0, 0, 200, 50)]}
    after = {"nodes": [_node(0, "box", 3, 2, 200, 50)]}
    assert diff_skeletons(rest, after)["n_appeared"] == 0


def test_diff_accepts_bare_node_lists():
    rest = [_node(0, "box", 0, 0, 200, 50)]
    after = [_node(0, "box", 0, 0, 200, 50), _node(1, "box", 500, 500, 80, 80)]
    assert diff_skeletons(rest, after)["n_appeared"] == 1


def test_diff_role_change_at_same_spot_counts_as_appeared():
    # different role at the same geometry is a genuinely different node.
    rest = {"nodes": [_node(0, "box", 10, 10, 100, 100)]}
    after = {"nodes": [_node(0, "dialog", 10, 10, 100, 100)]}
    assert diff_skeletons(rest, after)["n_appeared"] == 1


def test_open_details_is_skipped():
    # native <details open> has no aria-expanded but hasOpen=True -> already open,
    # clicking would CLOSE it, so it is not a drivable reveal trigger.
    assert classify_trigger({"tag": "DETAILS", "role": None, "ariaHaspopup": None,
                             "ariaExpanded": None, "hasOpen": True, "selector": "x"}) is None


def test_expanded_guard_outranks_disclosure_tag():
    # a <summary> already in the expanded state must be skipped (guard wins over
    # the disclosure-tag branch that would otherwise fire).
    assert classify_trigger({"tag": "SUMMARY", "role": None, "ariaHaspopup": None,
                             "ariaExpanded": "true", "hasOpen": False, "selector": "x"}) is None


def test_diff_radius_boundary_inclusive_then_appears():
    from _states import diff_skeletons
    rest = {"nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 200, "h": 50}, "z": 0}]}
    # shifted 23px (<= radius 24) -> SAME node, not appeared
    after_in = {"nodes": [{"id": 0, "role": "box", "bbox": {"x": 23, "y": 0, "w": 200, "h": 50}, "z": 0}]}
    assert diff_skeletons(rest, after_in)["n_appeared"] == 0
    # shifted 25px (> radius 24) -> APPEARED
    after_out = {"nodes": [{"id": 0, "role": "box", "bbox": {"x": 25, "y": 0, "w": 200, "h": 50}, "z": 0}]}
    assert diff_skeletons(rest, after_out)["n_appeared"] == 1


def test_diff_ignores_reflowed_container():
    # When a panel opens, page-root containers (<html>/<body>) GROW in place: same
    # role, same top-left corner, larger size. That is reflow of an EXISTING node,
    # NOT revealed content -> it must not be counted as appeared (else every
    # interaction that grows the page over-counts by the container chain). A
    # genuinely-new node at a fresh corner still counts.
    rest = {"nodes": [_node(0, "box", 0, 0, 1000, 50)]}          # <body> at REST
    after = {"nodes": [
        _node(0, "box", 0, 0, 1000, 300),                        # <body> GREW (reflow, same corner)
        _node(1, "box", 8, 60, 300, 60),                         # NEW revealed item (fresh corner)
    ]}
    d = diff_skeletons(rest, after)
    assert d["n_appeared"] == 1, d
    assert d["appeared"][0]["bbox"]["y"] == 60                   # only the genuinely-new node


def test_diff_corner_rule_under_counts_origin_anchored_modal():
    # KNOWN LIMIT (documented): the corner-reflow rule cannot tell a grown <body>
    # from a NEW same-role node at the same corner. An origin-anchored full-bleed
    # overlay (role 'box', like <body>) is therefore EXCLUDED; its non-origin
    # children still count. This pins the trade-off as a recorded contract.
    rest = {"nodes": [_node(0, "box", 0, 0, 1000, 50)]}             # <body> at REST
    after = {"nodes": [
        _node(0, "box", 0, 0, 1000, 50),                            # body (unchanged)
        _node(1, "box", 0, 0, 1000, 800),                           # NEW full-bleed modal at origin -> missed
        _node(2, "box", 400, 380, 200, 60),                         # modal child at a fresh corner -> counted
    ]}
    d = diff_skeletons(rest, after)
    assert d["n_appeared"] == 1, d                                  # origin overlay under-counted (limit)
    assert d["appeared"][0]["bbox"]["x"] == 400


def _cn(nid, role, x, y, w, h, parent=None, z=0, sizing=None, layout=None, font=None):
    n = {"id": nid, "role": role, "bbox": {"x": x, "y": y, "w": w, "h": h}, "z": z,
         "parent": parent, "sizing": sizing, "layout": layout}
    if font is not None:
        n["font"] = font
    return n


def test_matches_rest_predicate():
    rest = [_node(0, "box", 0, 0, 1000, 50)]
    # same element, tiny shift -> matches (not revealed)
    assert _matches_rest(_node(9, "box", 2, 2, 1000, 50), rest, 24.0) is True
    # same role, same top-left corner, grown -> reflow match (not revealed)
    assert _matches_rest(_node(9, "box", 0, 0, 1000, 300), rest, 24.0) is True
    # fresh corner, different size -> NOT a match (revealed)
    assert _matches_rest(_node(9, "box", 400, 380, 200, 60), rest, 24.0) is False
    # role mismatch at the same spot -> NOT a match (revealed)
    assert _matches_rest(_node(9, "menuitem", 0, 0, 1000, 50), rest, 24.0) is False


def test_build_component_returns_none_when_nothing_revealed():
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 50)]}
    after = {"nodes": [_cn(0, "box", 0, 0, 1000, 50)], "_node_colors": {}}
    assert build_component(rest, after) is None


def test_build_component_reroots_subtree_with_local_ids_and_mount():
    # REST: body + header. AFTER: body, header unchanged; a panel (child of body)
    # with two children appears. The panel mounts on body (a REST node).
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 400), _cn(1, "box", 0, 0, 1000, 40)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 400),                  # body (matches REST)
        _cn(1, "box", 0, 0, 1000, 40),                   # header (matches REST)
        _cn(2, "box", 100, 200, 300, 180, parent=0),     # NEW panel, mounts on body(0)
        _cn(3, "text", 110, 210, 280, 24, parent=2),     # NEW label, child of panel
        _cn(4, "box", 110, 240, 280, 120, parent=2),     # NEW item, child of panel
    ], "_node_colors": {}}
    comp = build_component(rest, after)
    assert comp is not None
    assert comp["n_nodes"] == 3
    by_y = {n["bbox"]["y"]: n for n in comp["nodes"]}
    panel, label, item = by_y[200], by_y[210], by_y[240]
    assert panel["parent"] is None
    assert panel["mount"] is not None
    assert panel["mount"]["role"] == "box"
    assert panel["mount"]["bbox"]["h"] == 400          # the body it mounts on
    assert label["parent"] == panel["id"]
    assert item["parent"] == panel["id"]
    assert label["mount"] is None and item["mount"] is None


def test_build_component_carries_colors_and_font_none_safe():
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 400)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 400),                                  # body (matches)
        _cn(1, "box", 100, 200, 300, 180, parent=0,                      # NEW panel, HAS colors
            sizing={"w": "fixed", "h": "hug", "confidence": "high"},
            layout={"mode": "flex", "direction": "column"}),
        _cn(2, "text", 110, 210, 280, 24, parent=1,                      # NEW label, HAS font + colors
            font={"size": 16.0, "weight": 700, "family": "sans"}),
        _cn(3, "box", 110, 240, 280, 60, parent=1),                      # NEW item, NO color entry
    ], "_node_colors": {
        "1": {"bg": "rgb(20,20,28)", "fg": "rgb(240,240,240)", "border": None},
        "2": {"bg": None, "fg": "rgb(200,200,200)", "border": None},
        # id 3 deliberately absent -> None-safe
    }}
    comp = build_component(rest, after)
    by_y = {n["bbox"]["y"]: n for n in comp["nodes"]}
    panel, label, item = by_y[200], by_y[210], by_y[240]
    assert panel["colors"]["bg"] == "rgb(20,20,28)"
    assert label["colors"]["fg"] == "rgb(200,200,200)"
    assert item["colors"] == {"bg": None, "fg": None, "border": None}
    assert panel["sizing"]["w"] == "fixed"
    assert panel["layout"]["mode"] == "flex"
    assert label["font"]["weight"] == 700
    assert "font" not in panel


def test_build_component_multi_root():
    # One trigger reveals two DISJOINT subtrees (e.g. a menu + a tooltip), each
    # mounting on a different REST node -> two roots, each with its own mount.
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 400), _cn(1, "box", 800, 0, 200, 400)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 400),                  # body (matches)
        _cn(1, "box", 800, 0, 200, 400),                 # sidebar (matches)
        _cn(2, "menu", 100, 200, 200, 150, parent=0),    # NEW menu, mounts on body(0)
        _cn(3, "tooltip", 820, 50, 160, 40, parent=1),   # NEW tooltip, mounts on sidebar(1)
    ], "_node_colors": {}}
    comp = build_component(rest, after)
    assert comp["n_nodes"] == 2
    roots = [n for n in comp["nodes"] if n["parent"] is None]
    assert len(roots) == 2
    mounts = sorted(r["mount"]["bbox"]["x"] for r in roots)
    assert mounts == [0, 800]                             # body and sidebar


def test_build_component_modal_collapse_preserves_backdrop_via_mount():
    # Honest-ceiling case: an origin-anchored full-bleed modal container corner-
    # matches <body>, so _matches_rest treats it as REST (the mount), NOT a revealed
    # node. Its child at a fresh corner IS revealed. The modal's own backdrop colors
    # survive via the child's mount.colors -> near-zero information loss.
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 50)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 50),                   # body (unchanged)
        _cn(1, "box", 0, 0, 1000, 800, parent=0),        # NEW full-bleed modal at origin -> collapses to mount
        _cn(2, "box", 400, 380, 200, 60, parent=1),      # modal child at a fresh corner -> revealed
    ], "_node_colors": {
        "1": {"bg": "rgba(0,0,0,0.6)", "fg": None, "border": None},  # the modal backdrop
        "2": {"bg": "rgb(255,255,255)", "fg": None, "border": None},
    }}
    comp = build_component(rest, after)
    assert comp["n_nodes"] == 1
    child = comp["nodes"][0]
    assert child["parent"] is None
    assert child["bbox"]["x"] == 400
    assert child["mount"]["bbox"]["h"] == 800
    assert child["mount"]["colors"]["bg"] == "rgba(0,0,0,0.6)"


def test_n_nodes_equals_n_appeared_invariant():
    # build_component's `new` and diff_skeletons' `appeared` share the predicate
    # over the same after-nodes -> counts must agree for every input.
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 50)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 50),
        _cn(1, "box", 0, 0, 1000, 800, parent=0),        # collapses (matches body corner)
        _cn(2, "box", 400, 380, 200, 60, parent=1),      # revealed
        _cn(3, "text", 410, 390, 180, 20, parent=2),     # revealed
    ], "_node_colors": {}}
    comp = build_component(rest, after)
    d = diff_skeletons(rest, after)
    assert comp["n_nodes"] == d["n_appeared"] == 2


def test_build_component_root_with_none_or_dangling_parent_has_mount_none():
    # A revealed node whose after-parent is None (mounts at the document root) or
    # points at an id absent from the after-skeleton (dangling) is a root with
    # mount=None — must not raise. Pins the documented absent/unresolvable case.
    rest = {"nodes": [_cn(0, "box", 0, 0, 1000, 50)]}
    after = {"nodes": [
        _cn(0, "box", 0, 0, 1000, 50),                       # body (matches)
        _cn(1, "menu", 100, 200, 200, 150, parent=None),     # NEW, mounts at doc root
        _cn(2, "menuitem", 110, 210, 180, 30, parent=99),    # NEW, dangling after-parent id
    ], "_node_colors": {}}
    comp = build_component(rest, after)
    assert comp["n_nodes"] == 2
    assert all(n["parent"] is None and n["mount"] is None for n in comp["nodes"])
