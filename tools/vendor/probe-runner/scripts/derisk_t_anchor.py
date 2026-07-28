# scripts/derisk_t_anchor.py
"""§C9-R-T-ANCHOR live de-risk harness (NON-COLLECTED — name is derisk_*, pytest skips it).
Anchors the same-template HIGH side: discovers the one-hop same-origin frontier, groups it by
URL structure (_url_template), fetches each page, and reports bag-Jaccard distributions
HIGH-T1 (within pagination) / HIGH-T2 (within siblings) / LOW-primary (seed-seed) /
LOW-secondary (across-group frontier), then the §3 verdict. FIREWALL: URLs live in memory only;
output is counts + bag-Jaccard scalars; nothing is written to disk. Manual run:
  python derisk_t_anchor.py            # from scripts/   (~minutes; live Chrome)
"""
from __future__ import annotations
import shutil
import subprocess
import tempfile
import time
from itertools import combinations

import _t_anchor as ta
import _url_template as ut
from _crawl import bag_jaccard, content_fingerprint, frontier_urls, passes_floor
from derisk_crawl_yield import (COHORT, DELAY_S, F, MAX_FRONTIER, UA,
                                _capture_nodes, _launch, _origin, _robots)

T = 0.5


def _seed_fps(seed_urls, port):
    """Capture each seed; return (nodes, fps): nodes = raw node-lists (for frontier
    discovery via frontier_urls), fps = content fingerprints. Only valid (>=F) seeds kept."""
    nodes, fps = [], []
    for u in seed_urls:
        n = _capture_nodes(u, port)
        time.sleep(DELAY_S)
        if n is None:
            continue
        fp = content_fingerprint(n)
        if not passes_floor(fp, F):
            continue
        nodes.append(n)
        fps.append(fp)
    return nodes, fps


def _fetch_frontier_fps(frontier, port):
    """Fetch each frontier page once; return {href: fp} for valid (>=F) captures only.
    robots-gated, rate-limited. URLs stay in memory; never printed."""
    fp_by, robots_cache = {}, {}
    n_robots = n_failed = n_subfloor = 0
    for _norm, href in frontier:
        origin = _origin(href)
        rp = robots_cache.get(origin)
        if rp is None:
            rp = _robots(origin); robots_cache[origin] = rp
        if not rp.can_fetch(UA, href):
            n_robots += 1; continue
        n = _capture_nodes(href, port)
        time.sleep(DELAY_S)
        if n is None:
            n_failed += 1; continue
        fp = content_fingerprint(n)
        if not passes_floor(fp, F):
            n_subfloor += 1; continue
        fp_by[href] = fp
    return fp_by, dict(robots_blocked=n_robots, failed=n_failed, subfloor=n_subfloor)


def _pair_jac(pairs, fp_by):
    return [bag_jaccard(fp_by[a], fp_by[b]) for a, b in pairs if a in fp_by and b in fp_by]


def run_site(site, seed_urls):
    print(f"\n=== {site} ===")
    proc = udd = None
    try:
        udd = tempfile.mkdtemp()
        proc, port = _launch(udd)   # inside try: a no-port _launch exit must not leak a populated profile
        seed_nodes, seed_fps = _seed_fps(seed_urls, port)
        if len(seed_fps) < 2:
            print(f"  INCONCLUSIVE: only {len(seed_fps)} valid seeds")
            return {"high_t1_median": None, "low_max": None, "n_t1_pairs": 0}

        frontier, n_cross = frontier_urls(seed_nodes, seed_urls)
        n_capped = max(0, len(frontier) - MAX_FRONTIER)
        frontier = frontier[:MAX_FRONTIER]
        hrefs = [h for _n, h in frontier]
        groups = ut.group_by_template(hrefs)
        # firewall-safe diagnostic: count frontier URLs that match ANY pagination form,
        # incl. singletons -> distinguishes "no pagination at all" (0) from "present but
        # unpaired" (>=1 yet tier1-groups=0). A count only; never a URL.
        n_paginated = sum(1 for h in hrefs if ut.paginate_key(h) is not None)
        print(f"  frontier={len(frontier)} (cross-origin {n_cross}, over-cap {n_capped}); "
              f"paginated-urls={n_paginated} "
              f"tier1-groups={len(groups['tier1'])} tier2-groups={len(groups['tier2'])}")

        fp_by, drops = _fetch_frontier_fps(frontier, port)
        print(f"  frontier captures valid={len(fp_by)} {drops}")

        high_t1 = _pair_jac(ut.within_group_pairs(groups["tier1"]), fp_by)
        high_t2 = _pair_jac(ut.within_group_pairs(groups["tier2"]), fp_by)
        low_sec = _pair_jac(ut.across_group_pairs(hrefs), fp_by)
        low_pri = [bag_jaccard(a, b) for a, b in combinations(seed_fps, 2)]

        for label, vals in (("HIGH-T1", high_t1), ("HIGH-T2", high_t2),
                            ("LOW-primary(seed-seed)", low_pri), ("LOW-secondary(across)", low_sec)):
            s = ta.summarize(vals)
            print(f"  {label:24} {s}")

        s1 = ta.summarize(high_t1)
        return {"high_t1_median": (s1[1] if s1 else None),
                "low_max": (max(low_pri) if low_pri else None),
                "n_t1_pairs": len(high_t1)}
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait()
        if udd is not None:
            shutil.rmtree(udd, ignore_errors=True)


def main():
    print(f"§C9-R-T-ANCHOR | T={T} F={F} | bar: HIGH-T1 median>0.5 & seed-seed max<0.5, "
          f">=3 T1 pairs/site, >=2 conclusive sites")
    per_site = [run_site(s, u) for s, u in COHORT.items()]
    decision, t_reco = ta.verdict(per_site)
    print("\n=== VERDICT (provisional; confirm on a repro draw) ===")
    print(f"conclusive sites (>=3 T1 pairs): "
          f"{sum(1 for s in per_site if s['n_t1_pairs'] >= 3)}/{len(per_site)}")
    print(f"{decision}  T_reco={t_reco}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
