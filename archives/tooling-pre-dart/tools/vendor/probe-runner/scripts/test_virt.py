"""Tests for _virt — the pure G2 sweep-merge core (no CDP). Conditions 1-5 of the
locked ship bar (docs/plans/g2-virtualization-build.md) are proven here deterministically."""
import json

import _virt


def _node(role, y, **kw):
    """A minimal content-free skeleton node at vertical position y."""
    n = {"id": 0, "role": role, "bbox": {"x": 0, "y": y, "w": 100, "h": 40}, "z": 0,
         "parent": None, "sizing": {"w": 100, "h": 40, "confidence": "high"},
         "layout": {"mode": "flow", "direction": None, "gap": None, "pad": None,
                    "justify": None, "align": None, "grid_cols": None, "grid_rows": None},
         "token_ref": {"bg": None, "fg": None, "border": None}}
    n.update(kw)
    return n


def _sk(nodes):
    return {"schema": "probe-skeleton/2", "url": "x", "viewport": {}, "page": {}, "nodes": nodes}


def test_below_fold_holds_new_shapes_absent_from_rest():
    rest = _sk([_node("banner", 0), _node("nav", 50)])
    # Sweep mounts a 'card' shape (new) and another 'banner' (already seen -> not new).
    sweep = [_sk([_node("banner", 900), _node("card", 1200, text_len=12)])]
    merged = _virt.merge_skeletons(rest, sweep)
    keys = {r["role"] for r in merged["below_fold"]["shapes"]}
    assert keys == {"card"}
    assert merged["below_fold"]["new_shapes"] == 1


def test_addendum_carries_no_position_or_content():
    rest = _sk([_node("banner", 0)])
    leaky = _node("card", 1200, text_len=4)
    leaky["background_image"] = "url(https://evil.example/x.png)"  # a CONTENT_KEY value
    merged = _virt.merge_skeletons(rest, [_sk([leaky])])
    rec = merged["below_fold"]["shapes"][0]
    assert "bbox" not in rec and "background_image" not in rec and "id" not in rec
    assert "url(" not in json.dumps(rec)


def test_merge_is_idempotent_byte_identical():
    rest = _sk([_node("banner", 0)])
    sweep = [_sk([_node("card", 1200), _node("list", 1500)]),
             _sk([_node("list", 2000), _node("footer", 2400)])]
    a = json.dumps(_virt.merge_skeletons(rest, sweep), sort_keys=False)
    b = json.dumps(_virt.merge_skeletons(rest, sweep), sort_keys=False)
    assert a == b


def test_one_record_per_distinct_new_shape():
    rest = _sk([_node("banner", 0)])
    # Three 'card' instances at different y -> ONE shape; plus one 'footer'.
    sweep = [_sk([_node("card", 900), _node("card", 1200), _node("card", 1600),
                  _node("footer", 3000)])]
    merged = _virt.merge_skeletons(rest, sweep)
    assert merged["below_fold"]["new_shapes"] == len(merged["below_fold"]["shapes"]) == 2


def test_negative_control_static_page_empty_addendum():
    rest = _sk([_node("banner", 0), _node("nav", 50), _node("main", 100)])
    sweep = [_sk([_node("banner", 0), _node("nav", 50), _node("main", 100)])]  # nothing new
    merged = _virt.merge_skeletons(rest, sweep)
    assert merged["below_fold"]["new_shapes"] == 0
    assert merged["below_fold"]["shapes"] == []
