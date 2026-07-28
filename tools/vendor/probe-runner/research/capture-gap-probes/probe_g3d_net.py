#!/usr/bin/env python3
"""G3d structural+deltas chrome dedup — NET savings (Phase-2 gate), TWO bounds.

GROSS (probe_g3d_structural.py) counts a deduped non-template chrome node as a whole node saved and
never charges for re-storing positional fields. NET charges them. But how much positional is truly
per-instance depends on the encoding, and that choice straddles the 12% bar — so we report a RANGE,
not one number.

  pos,struct,vol = leaf-scalar counts of the instance node;  F = pos+struct+vol  (ALL leaves)
  bbox          = the 4 bbox leaves (x,y,w,h);  nonbbox_pos = pos - bbox  (id/parent/z/confidence/
                  sizing.confidence)
  matched_vol   = volatile leaves byte-equal to template;  flag = vol/64

Two pre-registered bounds (same tiling + volatile-matching as gross; node-count denominator, so both
read against the same node-fraction 12% bar):

  FLOOR  (pessimistic — every positional leaf re-stored per node, even internal structure):
      net_floor_node = (struct + matched_vol - flag) / F                ( ≈ gross × D/F ≈ ×0.65 )

  BBOX-ONLY (realistic — id re-baseable, parent/z/confidence/sizing.confidence are STRUCTURE → live
             in the template; only bbox genuinely varies per node):
      net_bbox_node  = (struct + nonbbox_pos + matched_vol - flag) / F  ( ≈ gross × (F-bbox)/F ≈ ×0.85 )

  pct = 100 * Σ_{(m-1) non-template instances} net_node / total_nodes.

Truth lies between FLOOR and BBOX-ONLY. The honest finding is a range; the build only needs to know
whether the realistic (bbox-only) bound clears 12% and how robust that is to the encoding.

Pre-registered VERDICT (asymmetric — gross already passed; this only tests robustness):
  - FLOOR median ≥12 ∧ ≥3 sites ≥15  → BUILD robustly confirmed (clears even worst-case encoding).
  - else BBOX-ONLY clears              → BUILD holds IF the encoding templates internal structure
                                         (id/parent/z/confidence) — the expected design; report range.
  - neither clears                     → net is weak even optimistically; genuinely reconsider.
  A sub-bar FLOOR alone is NOT a DEFER — it is encoding-dependent, by construction.

Schema pin (1983 nodes): pos 17847 / struct 27143 / vol 6451 → D/F=0.653, (F-bbox)/F≈0.85.
Usage: python3 probe_g3d_net.py [--cdp-port 9222] [--sites N] [--routes N]
"""
import argparse
import sys
from collections import Counter, defaultdict

import probe_g3d_structural as M
P = M.P


def _leaf_counts4(n):
    """(positional, structural, volatile, bbox) leaf counts. bbox ⊆ positional, returned separately
    so the bbox-only bound can charge it alone."""
    pos = struct = vol = bbox = 0
    for k, v in n.items():
        if isinstance(v, dict):
            for sk in v:
                if k == "bbox":
                    pos += 1; bbox += 1
                elif k == "sizing" and sk == "confidence":
                    pos += 1
                elif (k, sk) in M._VOL_SET:
                    vol += 1
                else:
                    struct += 1
        else:
            if k in M._POS_TOP:
                pos += 1
            elif (k, None) in M._VOL_SET:
                vol += 1
            else:
                struct += 1
    return pos, struct, vol, bbox


def _delta_net(nt, bpt, ni, bpi):
    """Returns (floor_saved, bbox_saved) summed over the instance subtree, lock-step with template."""
    pos, struct, vol, bbox = _leaf_counts4(ni)
    F = (pos + struct + vol) or 1
    matched = 0
    for top, sub in M._VOL_KEYS:
        iv = M._vol_val(ni, top, sub)
        if iv is M._MISSING:
            continue
        tv = M._vol_val(nt, top, sub)
        if tv is not M._MISSING and iv == tv:
            matched += 1
    flag = vol * M._FLAG_BITS_PER_LEAF
    floor = (struct + matched - flag) / F
    bbox_only = (struct + (pos - bbox) + matched - flag) / F
    for ct, ci in zip(bpt.get(nt["id"], []), bpi.get(ni["id"], [])):
        f, b = _delta_net(ct, bpt, ci, bpi)
        floor += f; bbox_only += b
    return floor, bbox_only


def _net_savings(route_lists):
    prepared = [(nodes, P.C._children(nodes)) for nodes in route_lists]
    occ = Counter()
    for nodes, bp in prepared:
        for n in nodes:
            if n.get("aria_role") in P.CHROME:
                occ[P._subtree(n, bp, M.DROP_STRUCT)[0]] += 1
    groups = defaultdict(list)
    for nodes, bp in prepared:
        for k, root in M._tile_struct(nodes, bp, occ):
            groups[k].append((root, bp))
    floor = bbox_only = 0.0
    for k, insts in groups.items():
        if len(insts) < 2:
            continue
        t, tbp = insts[0]
        for root, bp in insts[1:]:
            f, b = _delta_net(t, tbp, root, bp)
            floor += f; bbox_only += b
    total = sum(len(n) for n in route_lists) or 1
    return 100.0 * floor / total, 100.0 * bbox_only / total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    ap.add_argument("--sites", type=int, default=0)
    ap.add_argument("--routes", type=int, default=0)
    args = ap.parse_args()
    items = list(P.SITES.items())
    if args.sites:
        items = items[:args.sites]

    print("== G3d NET (positional charged) :: bounds=[floor, bbox-only]  bar=%s ==" % P.BAR)
    floors, bboxes = [], []
    for netloc, urls in items:
        if args.routes:
            urls = urls[:args.routes]
        lists, clean, rc = P._capture(urls, args.cdp_port)
        if not clean:
            print("  %-20s AUDIT NOT CLEAN -- excluded" % netloc); continue
        if len(lists) < 2:
            print("  %-20s ok_routes=%d -- insufficient (<2)" % (netloc, len(lists))); continue
        gross = M._struct_savings(lists)["pct"]
        floor, bbox = _net_savings(lists)
        floors.append(floor); bboxes.append(bbox)
        print("  %-20s gross=%.1f  net_floor=%.1f  net_bbox=%.1f" % (netloc, gross, floor, bbox))

    print("\n== NET BAR EVALUATION (node-fraction, same 12%%/15%% bar) ==")
    n = len(floors)
    if n < P.BAR["min_data"]:
        print("INCONCLUSIVE -- only %d site(s) (<%d)." % (n, P.BAR["min_data"])); return 2
    mf, mb = P._median(floors), P._median(bboxes)
    af = sum(1 for p in floors if p >= P.BAR["site_pct"])
    ab = sum(1 for p in bboxes if p >= P.BAR["site_pct"])
    print("  FLOOR    median=%.1f  sites_ge_15%%=%d/%d" % (mf, af, n))
    print("  BBOX-ONLY median=%.1f  sites_ge_15%%=%d/%d" % (mb, ab, n))
    bar = lambda med, at: med >= P.BAR["median"] and at >= P.BAR["min_sites_at"]
    if bar(mf, af):
        print("VERDICT: BUILD robustly confirmed on NET — clears the bar even at the pessimistic "
              "floor (all positional re-stored).")
        return 0
    if bar(mb, ab):
        print("VERDICT: NET clears under bbox-only encoding (median=%.1f) but NOT at the floor "
              "(median=%.1f). BUILD holds IFF the dedup templates internal structure "
              "(id/parent/z/confidence) and charges only bbox per node — the expected design. "
              "Encoding-dependent: pin the encoding before building." % (mb, mf))
        return 0
    print("VERDICT: NET below 12%% even optimistically (bbox-only median=%.1f). Gross BUILD does not "
          "carry to net — genuinely reconsider before build." % mb)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
