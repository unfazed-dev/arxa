#!/usr/bin/env python3
"""skeleton_diff — certify two web_skeleton outputs match on calibrated-tight
geometry/typography/sizing/tree gates (spec §6). Pure logic; main() is a thin CLI.

Units & contract: all bounds are CSS px (web_skeleton normalizes DOMSnapshot
device px by devicePixelRatio on the live path). `pos`/`size`/`align radius` gates
are therefore CSS px and dpr-independent in value. They are calibrated to the
SAME-dpr self-diff floor: source and clone must be captured the same way — same
page, same viewport, SAME devicePixelRatio — under which the measured floor is
~0 px (deterministic fixture: pos 0.0 / size 0.0 / iou 1.0). Cross-dpr capture is
a degraded mode (retina lands on a 0.5-px grid, dpr1 on a 1-px grid → ~0.75-px pos
/ ~1.5-px size floor) and is not certified at this tight bar. The gate values were
re-confirmed (kept, not halved) against this floor — see
docs/skeleton-diff-css-px-calibration.md + fixtures/skdiff-calib/."""
from __future__ import annotations
import argparse
import json
from _common import emit_json

DEFAULT_GATES = {"iou": 0.98, "pos": 1.0, "size": 1.0, "matched_frac": 0.99,
                 "zrank": 0.99, "tree": 0.99}


def iou(a, b):
    ax2, ay2 = a["x"] + a["w"], a["y"] + a["h"]
    bx2, by2 = b["x"] + b["w"], b["y"] + b["h"]
    ix = max(0.0, min(ax2, bx2) - max(a["x"], b["x"]))
    iy = max(0.0, min(ay2, by2) - max(a["y"], b["y"]))
    inter = ix * iy
    union = a["w"] * a["h"] + b["w"] * b["h"] - inter
    return inter / union if union > 0 else 0.0


def _sizing_ok(s, c, axis):
    """sizing on one axis matches IFF both nodes flag sizing high-confidence
    (spec §6: 'sizing.w/sizing.h exact where both are confidence:high')."""
    ss, cs = s.get("sizing"), c.get("sizing")
    if not ss or not cs:
        return True
    if ss.get("confidence") != "high" or cs.get("confidence") != "high":
        return True
    return ss.get(axis) == cs.get(axis)


def node_delta(s, c):
    sb, cb = s["bbox"], c["bbox"]
    sc = (sb["x"] + sb["w"] / 2, sb["y"] + sb["h"] / 2)
    cc = (cb["x"] + cb["w"] / 2, cb["y"] + cb["h"] / 2)
    pos_err = ((sc[0] - cc[0]) ** 2 + (sc[1] - cc[1]) ** 2) ** 0.5
    d = {"iou": iou(sb, cb), "pos_err": pos_err,
         "w_err": abs(sb["w"] - cb["w"]), "h_err": abs(sb["h"] - cb["h"]),
         "role_ok": s["role"] == c["role"], "font_size_ok": True,
         "sizing_w_ok": _sizing_ok(s, c, "w"),
         "sizing_h_ok": _sizing_ok(s, c, "h")}
    if s["role"] == "text" and "font" in s and "font" in c:
        ss, cs = s["font"].get("size"), c["font"].get("size")
        d["font_size_ok"] = (ss is not None and cs is not None and abs(ss - cs) < 1e-6)
    return d


def _center(n):
    b = n["bbox"]
    return (b["x"] + b["w"] / 2, b["y"] + b["h"] / 2)


def align(src, clone, radius=24):
    """Greedy nearest-center match, processed in paint (z) order. Returns
    (matches[(s,c)], unmatched_src, unmatched_clone)."""
    src_sorted = sorted(src, key=lambda n: n.get("z", 0))
    remaining = list(clone)
    matches, un_src = [], []
    for s in src_sorted:
        sc = _center(s)
        best, best_d = None, None
        for c in remaining:
            cc = _center(c)
            dist = ((sc[0] - cc[0]) ** 2 + (sc[1] - cc[1]) ** 2) ** 0.5
            if dist <= radius and (best_d is None or dist < best_d):
                best, best_d = c, dist
        if best is not None:
            matches.append((s, best))
            remaining.remove(best)
        else:
            un_src.append(s)
    return matches, un_src, remaining


def tree_agreement(matches):
    """Fraction of matched pairs whose parent edge agrees: src.parent maps
    (under the alignment) to clone.parent. Both-None counts as agreement."""
    if not matches:
        return 1.0
    src_to_clone = {s["id"]: c["id"] for s, c in matches}
    agree = 0
    for s, c in matches:
        sp, cp = s.get("parent"), c.get("parent")
        if sp is None and cp is None:
            agree += 1
        elif sp is not None and src_to_clone.get(sp) == cp:
            agree += 1
    return agree / len(matches)


def _spearman_ok(pairs, thresh):
    if len(pairs) < 2:
        return True, 1.0
    s_rank = {id(s): i for i, (s, _) in enumerate(sorted(pairs, key=lambda p: p[0].get("z", 0)))}
    c_order = sorted(pairs, key=lambda p: p[1].get("z", 0))
    concord = sum(1 for i, (s, _) in enumerate(c_order) if s_rank[id(s)] == i)
    corr = concord / len(pairs)
    return corr >= thresh, corr


def diff(src, clone, gates):
    matches, un_src, un_clone = align(src["nodes"], clone["nodes"])
    per, fails = [], []
    min_iou, max_pos, max_size = 1.0, 0.0, 0.0
    for s, c in matches:
        d = node_delta(s, c)
        per.append({"src": s["id"], "clone": c["id"], **d})
        min_iou = min(min_iou, d["iou"])
        max_pos = max(max_pos, d["pos_err"])
        max_size = max(max_size, d["w_err"], d["h_err"])
        if d["iou"] < gates["iou"]:
            fails.append((s["id"], "iou", d["iou"]))
        if d["pos_err"] > gates["pos"]:
            fails.append((s["id"], "pos", d["pos_err"]))
        if max(d["w_err"], d["h_err"]) > gates["size"]:
            fails.append((s["id"], "size", max(d["w_err"], d["h_err"])))
        if not d["role_ok"]:
            fails.append((s["id"], "role", c["role"]))
        if not d["font_size_ok"]:
            fails.append((s["id"], "font_size", c.get("font", {}).get("size")))
        if not d["sizing_w_ok"]:
            fails.append((s["id"], "sizing_w", c.get("sizing", {}).get("w")))
        if not d["sizing_h_ok"]:
            fails.append((s["id"], "sizing_h", c.get("sizing", {}).get("h")))
    total = len(src["nodes"]) or 1
    matched_frac = len(matches) / total
    hi_un = [n["id"] for n in un_src if n.get("confidence") != "low"]
    zrank_ok, zrank = _spearman_ok(matches, gates["zrank"])
    tree = tree_agreement(matches)
    tree_ok = tree >= gates["tree"]
    ok = (not fails and matched_frac >= gates["matched_frac"]
          and not hi_un and zrank_ok and tree_ok)
    return {"pass": ok, "matched": len(matches), "matched_frac": matched_frac,
            "unmatched_src_high_conf": hi_un, "unmatched_clone": len(un_clone),
            "failures": fails, "per_node": per,
            "measured": {"min_iou": min_iou, "max_pos_err": max_pos,
                         "max_size_err": max_size, "zrank": zrank, "tree": tree}}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("source")
    p.add_argument("clone")
    p.add_argument("--iou", type=float, default=DEFAULT_GATES["iou"])
    p.add_argument("--pos", type=float, default=DEFAULT_GATES["pos"])
    p.add_argument("--size", type=float, default=DEFAULT_GATES["size"])
    p.add_argument("--matched-frac", type=float, default=DEFAULT_GATES["matched_frac"], dest="mf")
    p.add_argument("--tree", type=float, default=DEFAULT_GATES["tree"])
    args = p.parse_args()
    gates = {"iou": args.iou, "pos": args.pos, "size": args.size,
             "matched_frac": args.mf, "zrank": DEFAULT_GATES["zrank"],
             "tree": args.tree}
    with open(args.source) as f:
        src = json.load(f)
    with open(args.clone) as f:
        clone = json.load(f)
    emit_json(diff(src, clone, gates))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
