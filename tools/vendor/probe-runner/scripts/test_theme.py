import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _theme  # noqa: E402

U = ["color", "background-color", "box-shadow"]


def test_styles_by_backend_skips_pseudo_and_none_backend():
    recs = [
        {"backend": 10, "pseudo": None, "style": {"color": "rgb(0,0,0)"}},
        {"backend": 11, "pseudo": "before", "style": {"color": "rgb(9,9,9)"}},
        {"backend": None, "pseudo": None, "style": {"color": "rgb(1,1,1)"}},
    ]
    assert _theme.styles_by_backend(recs) == {10: {"color": "rgb(0,0,0)"}}


def test_diff_theme_emits_only_changed_props():
    base = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(255,255,255)",
                 "box-shadow": "none"}}
    cond = {10: {"color": "rgb(255,255,255)", "background-color": "rgb(255,255,255)",
                 "box-shadow": "none"}}
    assert _theme.diff_theme(base, cond, U) == {10: {"color": "rgb(255,255,255)"}}


def test_diff_theme_catches_both_directions():
    base = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(1,2,3)",
                 "box-shadow": "none"}}
    cond = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(1,2,3)",
                 "box-shadow": "rgb(0,0,0) 1px 1px 2px"}}
    assert _theme.diff_theme(base, cond, U) == {10: {"box-shadow": "rgb(0,0,0) 1px 1px 2px"}}
    base2 = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(1,2,3)",
                  "box-shadow": "rgb(0,0,0) 1px 1px 2px"}}
    cond2 = {10: {"color": "rgb(0,0,0)", "background-color": "rgb(1,2,3)",
                  "box-shadow": "none"}}
    assert _theme.diff_theme(base2, cond2, U) == {10: {"box-shadow": "none"}}


def test_diff_theme_drops_node_absent_in_condition():
    base = {10: {"color": "rgb(0,0,0)"}, 11: {"color": "rgb(0,0,0)"}}
    cond = {10: {"color": "rgb(9,9,9)"}}  # node 11 went display:none -> absent
    assert _theme.diff_theme(base, cond, U) == {10: {"color": "rgb(9,9,9)"}}


def test_diff_theme_no_change_emits_nothing():
    base = {10: {"color": "rgb(0,0,0)"}}
    cond = {10: {"color": "rgb(0,0,0)"}}
    assert _theme.diff_theme(base, cond, U) == {}


def test_rekey_by_node_id_maps_backend_to_node():
    delta = {101: {"color": "rgb(9,9,9)"}, 999: {"color": "rgb(1,1,1)"}}
    node_backend = {0: 101, 1: 102}  # backend 999 has no node -> dropped
    assert _theme.rekey_by_node_id(delta, node_backend) == {0: {"color": "rgb(9,9,9)"}}


def test_build_node_theme_transposes_label_to_node_keyed():
    per_condition = {
        "dark": {0: {"color": "rgb(255,255,255)"}},
        "contrast": {0: {"color": "rgb(0,0,0)"}, 1: {"color": "rgb(0,0,0)"}},
    }
    out = _theme.build_node_theme(per_condition)
    assert out == {
        0: {"dark": {"color": "rgb(255,255,255)"}, "contrast": {"color": "rgb(0,0,0)"}},
        1: {"contrast": {"color": "rgb(0,0,0)"}},
    }


def test_build_node_theme_skips_empty_delta():
    assert _theme.build_node_theme({"dark": {0: {}}}) == {}
