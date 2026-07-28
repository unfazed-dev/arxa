#!/usr/bin/env python3
"""G3d STRUCTURAL+DELTAS chrome dedup calibration.

Exact-lossless G3d shared-chrome dedup DEFERRED at gross median 6.1% -- byte-identical-subtree
dedup is broken by two volatile fields (token_ref.{bg,fg,border} per-route artifact; text_len
content drift). This probe re-keys the dedup on the STRUCTURAL fields only and pays a LOSSLESS
per-instance DELTA for the volatile fields, then measures whether net savings clears the SAME bar.

Pre-registration: docs/plans/g3d-structural-deltas-chrome-dedup-design.md  (read it; the bar, the
node-basis accounting, the pinned schema weights, and the honest DEFER are committed THERE before
this runs). This file does NOT bend the key or denominator after the numbers are seen.

NODE BASIS (the bar's unit -- identical to the exact-lossless probe and the 6.1% baseline):
  denominator = total nodes across routes. The field counting enters ONLY as a per-node fractional
  weight, NEVER as the denominator.

Per node n of a non-template tiled instance i (template = first instance of the structural key):
  struct_leaves(n)   = # structural leaf scalars (always equal -- they ARE the structural key)
  volatile_leaves(n) = # volatile leaf scalars present (subset of tr.{bg,fg,border}+text_len, <=4)
  D(n)               = struct_leaves + volatile_leaves          (positional leaves excluded)
  matched_volatile   = # volatile leaves byte-equal to template's corresponding node
  flag_overhead(n)   = volatile_leaves / 64                     (1 equal/differ bit per vol leaf)
  saved_node(n,i)    = (struct_leaves + matched_volatile - flag_overhead) / D(n)
Byte-identical node -> ~1.0 (recovers exact). Structural-only match -> struct_leaves/D (~0.81).

POINTWISE DOMINATION (verified in-run, not assumed): occ_struct >= occ_exact pointwise (coarser
key) => structural tile boundary is at-or-outside exact's => every exact-saved node is structural-
saved at >= its exact per-node rate, plus extra structural-only matches. So struct_pct >= exact_pct
(modulo the pinned flag). The in-run assertion checks this on the real capture.

Content-free: reads ONLY mechanism keys from already-redacted bundles; audits every bundle; prints
ONLY counts / percentages / role NAMES / netloc / returncodes. Runs on HOST Bash (CDP :9222).
Usage: python3 probe_g3d_structural.py [--cdp-port 9222] [--sites N] [--routes N]
"""
import argparse
import sys
from collections import Counter, defaultdict

import probe_g3d_dedup as P  # same dir; reuse _capture, _subtree, _site_savings, SITES, CHROME, ...

# Structural verdict key = exact key with BOTH volatile ablation sets dropped (combined).
DROP_STRUCT = tuple(P.DROP_TR) + tuple(P.DROP_TXT)  # tr.bg, tr.fg, tr.border, text_len

# Leaf classification (pinned in design §4; positional cancels in both models).
_POS_TOP = {"id", "parent", "z", "confidence"}
_VOL_SET = {("token_ref", "bg"), ("token_ref", "fg"), ("token_ref", "border"), ("text_len", None)}
_VOL_KEYS = [("token_ref", "bg"), ("token_ref", "fg"), ("token_ref", "border"), ("text_len", None)]
_MISSING = object()
_FLAG_BITS_PER_LEAF = 1.0 / 64.0  # 1 equal/differ bit, 64-bit leaf -- PINNED


def _leaf_counts(n):
    """(struct_leaves, volatile_leaves) for ONE node -- identical logic to design §4 over the live
    serialized schema. Dict fields expand one level; positional leaves excluded from both."""
    struct = vol = 0
    for k, v in n.items():
        if isinstance(v, dict):
            for sk in v:
                if k == "bbox":
                    continue                      # positional
                if k == "sizing" and sk == "confidence":
                    continue                      # positional
                if (k, sk) in _VOL_SET:
                    vol += 1
                else:
                    struct += 1
        else:
            if k in _POS_TOP:
                continue                          # positional
            if (k, None) in _VOL_SET:
                vol += 1
            else:
                struct += 1
    return struct, vol


def _vol_val(n, top, sub):
    if sub is None:
        return n.get(top, _MISSING)
    d = n.get(top)
    if not isinstance(d, dict):
        return _MISSING
    return d.get(sub, _MISSING)


def _delta_saved(nt, bpt, ni, bpi):
    """Lock-step walk of template subtree (nt) and instance subtree (ni); structural keys match so
    children correspond by emit order. Returns (saved_float, flag_total) in node-equivalents."""
    struct, vol = _leaf_counts(ni)
    D = (struct + vol) or 1
    matched = 0
    for top, sub in _VOL_KEYS:
        iv = _vol_val(ni, top, sub)
        if iv is _MISSING:
            continue                              # leaf not stored on this instance node
        tv = _vol_val(nt, top, sub)
        if tv is not _MISSING and iv == tv:
            matched += 1
    flag = vol * _FLAG_BITS_PER_LEAF
    saved = (struct + matched - flag) / D
    ftot = flag
    kt = bpt.get(nt["id"], [])
    ki = bpi.get(ni["id"], [])
    for ct, ci in zip(kt, ki):                    # equal length by structural-key match
        s, f = _delta_saved(ct, bpt, ci, bpi)
        saved += s
        ftot += f
    return saved, ftot


def _tile_struct(nodes, by_parent, occ):
    """Outermost chrome landmark whose STRUCTURAL key recurs (occ>=2), non-overlapping.
    Returns list of (struct_key, root_node) -- root_node kept for per-node delta accounting."""
    selected, stack = [], P._roots(nodes)
    while stack:
        n = stack.pop()
        if n.get("aria_role") in P.CHROME:
            k, _s = P._subtree(n, by_parent, DROP_STRUCT)
            if occ[k] >= 2:
                selected.append((k, n))
                continue                          # tile boundary -- no double-count
        stack.extend(by_parent.get(n["id"], []))
    return selected


def _struct_savings(route_lists):
    prepared = [(nodes, P.C._children(nodes)) for nodes in route_lists]
    occ = Counter()
    for nodes, bp in prepared:
        for n in nodes:
            if n.get("aria_role") in P.CHROME:
                occ[P._subtree(n, bp, DROP_STRUCT)[0]] += 1
    groups = defaultdict(list)                     # struct_key -> [(root_node, by_parent), ...]
    for nodes, bp in prepared:
        for k, root in _tile_struct(nodes, bp, occ):
            groups[k].append((root, bp))
    saved = flags = 0.0
    deduped = 0
    for k, insts in groups.items():
        if len(insts) < 2:
            continue
        deduped += 1
        tmpl, tbp = insts[0]
        for root, bp in insts[1:]:
            s, f = _delta_saved(tmpl, tbp, root, bp)
            saved += s
            flags += f
    total = sum(len(nodes) for nodes in route_lists) or 1
    recurring = sum(1 for c in occ.values() if c >= 2)
    return {"saved": saved, "flags": flags, "total": total,
            "pct": 100.0 * saved / total, "pct_noflag": 100.0 * (saved + flags) / total,
            "flag_pct": 100.0 * flags / total, "struct_keys": len(occ),
            "recurring_keys": recurring, "deduped_keys": deduped}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    ap.add_argument("--sites", type=int, default=0)
    ap.add_argument("--routes", type=int, default=0)
    args = ap.parse_args()

    items = list(P.SITES.items())
    if args.sites:
        items = items[:args.sites]

    print("== G3d STRUCTURAL+DELTAS :: chrome=%s drop_struct=%s bar=%s =="
          % (sorted(P.CHROME), list(DROP_STRUCT), P.BAR))
    struct_pcts, violations = [], []
    for netloc, urls in items:
        if args.routes:
            urls = urls[:args.routes]
        lists, clean, rc = P._capture(urls, args.cdp_port)
        if not clean:
            print("  %-20s AUDIT NOT CLEAN -- excluded (firewall)" % netloc)
            continue
        if len(lists) < 2:
            print("  %-20s ok_routes=%d rc=%d -- insufficient (<2)" % (netloc, len(lists), rc))
            continue
        ex = P._site_savings(lists)               # in-run exact-lossless baseline (node basis)
        st = _struct_savings(lists)               # structural+deltas (node basis)
        struct_pcts.append(st["pct"])
        delta = st["pct"] - ex["pct"]
        # ONLY hard invariant: pointwise domination (modulo pinned flag). The flag is already
        # subtracted inside saved_node; flag_pct scales with the DEDUP RATE (not a fixed % of
        # total), so it is REPORTED, never gated -- gating it would wrongly withhold a high-saving
        # BUILD verdict. struct_noflag shows the flag drag transparently.
        dom_ok = st["pct"] >= ex["pct"] - 0.5
        if not dom_ok:
            violations.append((netloc, "DOMINATION", ex["pct"], st["pct"]))
        flag_rel = 100.0 * st["flags"] / (st["saved"] or 1)  # flag as % of structural saving
        print("  %-20s ok_routes=%d roles=%s  struct_keys=%d recurring=%d deduped=%d"
              % (netloc, len(lists), P._chrome_roles(lists), st["struct_keys"],
                 st["recurring_keys"], st["deduped_keys"]))
        print("      exact_pct=%.1f  struct_pct=%.1f  delta=%+.1f  struct_noflag=%.1f  "
              "flag/saved=%.1f%%  dom_ok=%s"
              % (ex["pct"], st["pct"], delta, st["pct_noflag"], flag_rel, dom_ok))
        print("      ablation recurring full/noTR/noTXT = %d/%d/%d"
              % (ex["recurring_keys"], P._recurring_under(lists, P.DROP_TR),
                 P._recurring_under(lists, P.DROP_TXT)))

    print("\n== BAR EVALUATION (per-site/opportunistic; node-fraction unit) ==")
    n_data = len(struct_pcts)
    if n_data < P.BAR["min_data"]:
        print("INCONCLUSIVE -- only %d site(s) with data (<%d). Re-run." % (n_data, P.BAR["min_data"]))
        return 2
    med = P._median(struct_pcts)
    at = sum(1 for p in struct_pcts if p >= P.BAR["site_pct"])
    fa = P._floor_a(P.SITES["python.org"][0], args.cdp_port)
    print("  struct_median_pct=%.1f  sites_ge_%.0f%%=%d/%d  floor_a_determinism=%s"
          % (med, P.BAR["site_pct"], at, n_data, fa))
    if violations:
        for v in violations:
            print("  !! INVARIANT %s on %-16s a=%.3f b=%.3f -- investigate accounting"
                  % (v[1], v[0], v[2], v[3]))
        print("VERDICT: WITHHELD -- pre-registered invariant violated; accounting must be fixed "
              "before the bar is read")
        return 3
    if med >= P.BAR["median"] and at >= P.BAR["min_sites_at"]:
        print("VERDICT: BUILD G3d structural+deltas dedup (median>=%.0f%% and >=%d sites>=%.0f%%)"
              % (P.BAR["median"], P.BAR["min_sites_at"], P.BAR["site_pct"]))
        return 0
    print("VERDICT: DEFER G3d structural+deltas dedup (net savings below the pre-registered bar) "
          "-- honest outcome (3rd straight DEFER in this lineage)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
