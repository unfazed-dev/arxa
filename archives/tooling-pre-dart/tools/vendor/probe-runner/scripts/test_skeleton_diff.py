# test_skeleton_diff.py
import skeleton_diff as sd

def test_iou_and_node_delta():
    a = {"x": 0, "y": 0, "w": 100, "h": 100}
    b = {"x": 0, "y": 0, "w": 100, "h": 100}
    assert sd.iou(a, b) == 1.0
    c = {"x": 50, "y": 0, "w": 100, "h": 100}
    assert abs(sd.iou(a, c) - (50*100) / (2*100*100 - 50*100)) < 1e-9

def test_node_delta_flags_font_role_sizing():
    src = {"role": "text", "bbox": {"x": 0, "y": 0, "w": 100, "h": 20},
           "font": {"size": 16.0, "weight": 700},
           "sizing": {"w": "fill", "h": "hug", "confidence": "high"}}
    same = {"role": "text", "bbox": {"x": 0, "y": 0, "w": 100, "h": 20},
            "font": {"size": 16.0, "weight": 700},
            "sizing": {"w": "fill", "h": "hug", "confidence": "high"}}
    d = sd.node_delta(src, same)
    assert d["iou"] == 1.0 and d["role_ok"] and d["font_size_ok"]
    assert d["sizing_w_ok"] and d["sizing_h_ok"]
    bad_font = dict(same, font={"size": 16.16, "weight": 700})
    assert sd.node_delta(src, bad_font)["font_size_ok"] is False
    bad_sz = dict(same, sizing={"w": "fixed", "h": "hug", "confidence": "high"})
    assert sd.node_delta(src, bad_sz)["sizing_w_ok"] is False
    lowconf = dict(same, sizing={"w": "fixed", "h": "hug", "confidence": "low"})
    assert sd.node_delta(src, lowconf)["sizing_w_ok"] is True

def test_align_matches_nearest_and_reports_unmatched():
    src = [{"id": 0, "z": 1, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}},
           {"id": 1, "z": 2, "role": "text", "bbox": {"x": 100, "y": 0, "w": 10, "h": 10}}]
    clone = [{"id": 9, "z": 1, "role": "box", "bbox": {"x": 1, "y": 0, "w": 10, "h": 10}}]
    matches, un_src, un_clone = sd.align(src, clone, radius=20)
    assert len(matches) == 1 and matches[0][0]["id"] == 0 and matches[0][1]["id"] == 9
    assert [n["id"] for n in un_src] == [1] and un_clone == []

def test_tree_agreement_full_and_broken():
    src = [{"id": 0, "parent": None}, {"id": 1, "parent": 0}]
    clone = [{"id": 10, "parent": None}, {"id": 11, "parent": 10}]
    matches = [(src[0], clone[0]), (src[1], clone[1])]
    assert sd.tree_agreement(matches) == 1.0
    clone_bad = [{"id": 10, "parent": None}, {"id": 11, "parent": None}]
    matches_bad = [(src[0], clone_bad[0]), (src[1], clone_bad[1])]
    assert sd.tree_agreement(matches_bad) == 0.5

GATES = {"iou": 0.98, "pos": 1.0, "size": 1.0, "matched_frac": 0.99,
         "zrank": 0.99, "tree": 0.99}

def _sk(nodes):
    return {"nodes": nodes}

def _n(id, z, role, x, y, w, h, parent=None, font=None, sizing=None):
    d = {"id": id, "z": z, "role": role,
         "bbox": {"x": x, "y": y, "w": w, "h": h}, "parent": parent}
    if font:
        d["font"] = font
    if sizing:
        d["sizing"] = sizing
    return d

def test_diff_identical_pass():
    nodes = [_n(0, 1, "box", 0, 0, 50, 50),
             _n(1, 2, "text", 0, 60, 50, 20, parent=0, font={"size": 16.0})]
    r = sd.diff(_sk(nodes), _sk(nodes), GATES)
    assert r["pass"] is True
    assert r["measured"]["min_iou"] == 1.0 and r["measured"]["max_pos_err"] == 0.0
    assert r["measured"]["tree"] == 1.0

def test_diff_shift_role_sizing_tree_all_fail():
    base = [_n(0, 1, "box", 0, 0, 50, 50),
            _n(1, 2, "text", 0, 60, 50, 20, parent=0, font={"size": 16.0},
               sizing={"w": "fill", "h": "hug", "confidence": "high"})]
    shifted = [_n(0, 1, "box", 2, 0, 50, 50), base[1]]
    assert sd.diff(_sk(base), _sk(shifted), GATES)["pass"] is False
    swapped = [dict(base[0], role="image"), base[1]]
    assert sd.diff(_sk(base), _sk(swapped), GATES)["pass"] is False
    szswap = [base[0], _n(1, 2, "text", 0, 60, 50, 20, parent=0,
              font={"size": 16.0}, sizing={"w": "fixed", "h": "hug", "confidence": "high"})]
    assert sd.diff(_sk(base), _sk(szswap), GATES)["pass"] is False
    fbad = [base[0], _n(1, 2, "text", 0, 60, 50, 20, parent=0, font={"size": 16.16})]
    assert sd.diff(_sk(base), _sk(fbad), GATES)["pass"] is False
    treebad = [base[0], dict(base[1], parent=None)]
    assert sd.diff(_sk(base), _sk(treebad), GATES)["pass"] is False

def test_diff_unmatched_high_conf_fails_aggregate():
    base = [_n(0, 1, "box", 0, 0, 50, 50),
            _n(1, 2, "text", 500, 500, 50, 20, parent=0, font={"size": 16.0})]
    partial = [_n(0, 1, "box", 0, 0, 50, 50)]
    r = sd.diff(_sk(base), _sk(partial), GATES)
    assert r["pass"] is False
    assert 1 in r["unmatched_src_high_conf"]
