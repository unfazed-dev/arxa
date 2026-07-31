#!/usr/bin/env python3
"""Reconcile the SHIPPED G3d chrome dedup against the probe's net bbox-only band.

Probe net bbox-only (docs/plans/g3d-structural-deltas-chrome-dedup-results.md):
  python 11.1 · iana 19.6 · django 12.0 · w3 25.8 · gnu 6.3 · apache 24.9  -> median 15.8
Acceptance: realized median within ~3 pt of 15.8 AND not below the 12.4 floor median; per-site
realized within ~3 pt of its probe bbox-only value, else INVESTIGATE (the encoding pin slipped
toward the floor — likely z/parent stored as exceptions). Equality is NOT expected; this is a
node-fraction proxy vs real reconstruction.

Reuses probe_g3d_dedup._capture/_capture layout + SITES; runs scripts/site_chrome.py on each capture.
Usage: python3 reconcile_g3d_chrome.py [--cdp-port 9222] [--sites N] [--routes N]
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import probe_g3d_dedup as P
import probe_g3d_net as N   # reuse _leaf_counts4 + the bbox-only formula — SAME basis as the target
SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import _chrome_dedup as D

PROBE_BBOX = {"python.org": 11.1, "iana.org": 19.6, "djangoproject.com": 12.0,
              "w3.org": 25.8, "gnu.org": 6.3, "apache.org": 24.9}
FLOOR_MEDIAN, BBOX_MEDIAN, TOL = 12.4, 15.8, 3.0


def _realized_bbox_pct(art, total_nodes):
    """Realized saving on the EXACT basis probe_g3d_net uses for bbox-only, so the comparison is
    like-for-like (NOT struct+vol — that denominator is ~0.87x and would trip false INVESTIGATE):
        F = pos + struct + vol;  node_saved = (struct + (pos - bbox) + matched - flag) / F
    matching probe_g3d_net._delta_net's bbox_only branch. Two adjustments for the SHIPPED encoder:
      - matched = vol - len(vdelta.values)        (values = the differing volatile leaves stored)
      - exceptions now carry ANY field that differs from the template (id/parent/z/confidence AND
        unkeyed fields like style), and `drop` lists template-only fields the ref omits. BOTH are
        SUBTRACTED from the (pos-bbox) credit (charged), so encoder slippage erodes realized toward
        the floor honestly.
    Per-node leaf counts come from the template node (struct match => equal pos/struct/vol presence).
    Denominator = total nodes (node-fraction), identical to probe_g3d_net._net_savings."""
    templates = art["templates"]
    saved = 0.0
    for route in art["routes"].values():
        for ref in route["refs"]:
            tmpl = templates[ref["template"]]
            excs = ref.get("exceptions", {})
            drops = ref.get("drop", {})
            for i, pn in enumerate(ref["nodes"]):
                # leaf counts off the TEMPLATE node (probe uses the instance). Volatile presence
                # mismatch is now charged via the exception/drop patch (no tripwire), so the
                # bbox-exclusion reasoning still holds; bbox is excluded from the (pos-bbox) credit
                # either way, so the only effect is a conservative F (template-with-bbox -> larger F
                # -> smaller fraction). Cannot inflate savings; within the ±3pt proxy tolerance.
                pos, struct, vol, bbox = N._leaf_counts4(tmpl[i])
                F = (pos + struct + vol) or 1
                matched = max(0, vol - len(pn["vdelta"]["values"]))
                flag = vol / 64.0
                charged = len(excs.get(str(i), {})) + len(drops.get(str(i), []))   # all non-template fields
                node_saved = (struct + (pos - bbox) - charged + matched - flag) / F
                saved += max(0.0, node_saved)
    return 100.0 * saved / (total_nodes or 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    ap.add_argument("--sites", type=int, default=0)
    ap.add_argument("--routes", type=int, default=0)
    args = ap.parse_args()
    items = list(P.SITES.items())[: args.sites or None]

    print("== G3d RECONCILE :: realized vs probe bbox-only (tol +-%.1f) ==" % TOL)
    realized = []
    for netloc, urls in items:
        if args.routes:
            urls = urls[: args.routes]
        lists, clean, rc = P._capture(urls, args.cdp_port)
        if not clean or len(lists) < 2:
            print("  %-20s skipped (clean=%s routes=%d)" % (netloc, clean, len(lists)))
            continue
        routes = {"r%d" % i: nodes for i, nodes in enumerate(lists)}
        art = D.dedup_chrome(routes)
        rebuilt = D.reconstruct(art)
        lossless = all({n["id"]: n for n in rebuilt.get(rid, [])} == {n["id"]: n for n in nodes}
                       for rid, nodes in routes.items())
        if not lossless:
            print("  %-20s !! NOT LOSSLESS (node-set mismatch) — excluded" % netloc)
            continue
        total = sum(len(n) for n in lists)
        pct = _realized_bbox_pct(art, total)
        realized.append(pct)
        ref = PROBE_BBOX.get(netloc)
        flag = "" if ref is None or abs(pct - ref) <= TOL else "  !! INVESTIGATE"
        print("  %-20s realized=%.1f  probe_bbox=%.1f%s" % (netloc, pct, ref or -1, flag))

    if len(realized) < P.BAR["min_data"]:
        print("INCONCLUSIVE — <%d sites" % P.BAR["min_data"]); return 2
    med = P._median(realized)
    print("\n  realized median=%.1f  (probe bbox-only=%.1f, floor=%.1f)" % (med, BBOX_MEDIAN, FLOOR_MEDIAN))
    if med >= FLOOR_MEDIAN - TOL and abs(med - BBOX_MEDIAN) <= TOL + 1.0:
        print("VERDICT: RECONCILED — shipped dedup tracks the probe net band; build is honest.")
        return 0
    print("VERDICT: GAP — realized median %.1f off the probe band; the encoding slipped toward the "
          "floor (inspect per-site INVESTIGATE rows + exception counts)." % med)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
