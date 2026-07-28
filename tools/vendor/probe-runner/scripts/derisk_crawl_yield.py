#!/usr/bin/env python3
"""DE-RISK harness (NOT a pytest; manual, headless real-site). §C9-R-CRAWL crawl-discovery yield.

Does one-hop crawl-discovery surface content templates structurally NOVEL vs the seed routes?
Bar (pre-registered, spec docs/plans/crawl-discovery-yield-derisk.md): >=2 novel content-templates
on >=2 of 4 sites, bag-Jaccard T=0.5. Discrimination control runs first; aborts a site if the
fingerprint cannot separate same-vs-different seed templates.

URLs are used transiently to fetch only; NOTHING but counts/stats is printed. Never writes an href.

Run: python3 scripts/derisk_crawl_yield.py   (needs Chrome + websocket-client)
"""
from __future__ import annotations
import json
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.robotparser
from pathlib import Path
from urllib.parse import urlparse

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
import _crawl_yield as cy  # noqa: E402
from _web import chrome_binary  # noqa: E402

T = 0.5                 # pre-registered novelty threshold
T_STRIP = (0.4, 0.5, 0.6)  # diagnostic sensitivity strip (does NOT move the verdict)
DELAY_S = 2.0           # inter-request rate limit (politeness)
UA = "probe-runner-derisk/1.0"
MAX_FRONTIER = 40       # hard safety cap on one-hop fetches per site
F = 20                  # min content-region nodes for a capture to be VALID (spec §3)

# 4 seed routes per site (NG cohort). MPA + SPA mix.
COHORT = {
    "python.org": [
        "https://www.python.org/",
        "https://www.python.org/about/",
        "https://www.python.org/downloads/",
        "https://www.python.org/community/",
    ],
    "djangoproject.com": [
        "https://www.djangoproject.com/",
        "https://www.djangoproject.com/start/",
        "https://www.djangoproject.com/download/",
        "https://www.djangoproject.com/community/",
    ],
    "mui.com": [
        "https://mui.com/",
        "https://mui.com/core/",
        "https://mui.com/pricing/",
        "https://mui.com/blog/",
    ],
    "vercel.com": [
        "https://vercel.com/",
        "https://vercel.com/products/dev",
        "https://vercel.com/pricing",
        "https://vercel.com/templates",
    ],
}


def _launch(udd):
    """Headless Chrome on a blank page (so there IS a page target -- see cdp-capture-needs-open-tab).
    Returns (proc, port)."""
    bin_ = chrome_binary()
    if not bin_:
        print("FATAL no-chrome"); sys.exit(2)
    p = subprocess.Popen(
        [bin_, "--headless=new", "--remote-debugging-port=0", "--remote-allow-origins=*",
         "--no-first-run", "--no-default-browser-check", "--hide-scrollbars",
         "--window-size=1440,900", f"--user-data-dir={udd}", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pf = Path(udd) / "DevToolsActivePort"
    for _ in range(100):
        if pf.exists():
            t = pf.read_text().splitlines()
            if t:
                return p, int(t[0])
        time.sleep(0.1)
    p.terminate(); print("FATAL no-port"); sys.exit(2)


def _capture_nodes(url, port):
    """Drive web_skeleton.py against the launched Chrome; return its RAW node-list
    (pre-redaction, href intact) or None on failure. Scratch lives in a tempdir OUTSIDE
    any audited tree and is discarded."""
    with tempfile.TemporaryDirectory() as scratch:
        sk = Path(scratch) / "sk.json"
        r = subprocess.run(
            [sys.executable, "web_skeleton.py", "--url", url, "--cdp-port", str(port),
             "--out", str(sk)],
            cwd=str(SCRIPTS), capture_output=True, text=True)
        if r.returncode != 0 or not sk.exists():
            return None
        return json.loads(sk.read_text())["nodes"]


def _robots(origin):
    rp = urllib.robotparser.RobotFileParser()
    rp.set_url(origin + "/robots.txt")
    try:
        rp.read()
    except Exception:
        return rp  # fail-open is unsafe; treat unreadable robots as allow-all only for this manual de-risk
    return rp


def _origin(url):
    p = urlparse(url)
    return f"{p.scheme}://{p.netloc}"


def run_site(site, seed_urls):
    print(f"\n=== {site} ===")
    udd_root = tempfile.mkdtemp()
    proc, port = _launch(udd_root)
    try:
        seed_nodes, seed_fps = [], []
        for i, u in enumerate(seed_urls):
            n = _capture_nodes(u, port)
            time.sleep(DELAY_S)
            if n is None:
                print(f"  seed capture FAILED: route#{i}"); continue
            fp = cy.content_fingerprint(n)
            if not cy.passes_floor(fp, F):
                print(f"  seed SUB-FLOOR (<{F} content nodes): route#{i}"); continue
            seed_nodes.append(n); seed_fps.append(fp)
        if len(seed_fps) < 4:
            print(f"  INCONCLUSIVE: only {len(seed_fps)}/4 valid seeds (need 4/4)")
            return {"status": "inconclusive", "novel": 0}

        # --- discrimination control (runs FIRST) ---
        m = cy.discrimination_matrix(seed_fps)
        offdiag = [m[i][j] for i in range(len(m)) for j in range(len(m)) if i != j]
        lo, hi = min(offdiag), max(offdiag)
        spread = hi - lo
        print(f"  discrimination off-diagonal jaccard: min={lo:.3f} max={hi:.3f} spread={spread:.3f}")
        if spread < 0.10:
            print("  INCONCLUSIVE: fingerprint does not discriminate seed templates (vacuous signal)")
            return {"status": "inconclusive", "novel": 0}

        # --- one-hop frontier (same-origin) ---
        frontier, n_cross = cy.frontier_urls(seed_nodes, seed_urls)
        n_capped = max(0, len(frontier) - MAX_FRONTIER)
        frontier = frontier[:MAX_FRONTIER]
        print(f"  frontier (same-origin content links): {len(frontier)}  "
              f"(cross-origin dropped: {n_cross}; over-cap dropped: {n_capped})")
        robots_cache = {}
        n_subfloor = n_failed = n_robots = 0
        frontier_fps = []
        for norm, href in frontier:
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
            fp = cy.content_fingerprint(n)
            if not cy.passes_floor(fp, F):
                n_subfloor += 1; continue
            frontier_fps.append(fp)
        print(f"  frontier captures: valid={len(frontier_fps)} "
              f"subfloor={n_subfloor} failed={n_failed} robots-blocked={n_robots}")

        novel = cy.count_novel_templates(frontier_fps, seed_fps, T)
        strip = {t: cy.count_novel_templates(frontier_fps, seed_fps, t) for t in T_STRIP}
        print(f"  NOVEL templates @ T={T}: {novel}")
        print(f"  sensitivity strip {strip}  (diagnostic only)")
        return {"status": "conclusive", "novel": novel}
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait()
        shutil.rmtree(udd_root, ignore_errors=True)


def main():
    print(f"§C9-R-CRAWL yield de-risk | T={T} | F={F} | bar: >=2 novel on >=2 CONCLUSIVE sites")
    results = {}
    for site, urls in COHORT.items():
        results[site] = run_site(site, urls)
    conclusive = {s: r for s, r in results.items() if r["status"] == "conclusive"}
    cleared = [s for s, r in conclusive.items() if r["novel"] >= 2]
    print("\n=== VERDICT ===")
    print(f"conclusive sites: {len(conclusive)}/4 -> {sorted(conclusive)}")
    print(f"sites clearing >=2 novel: {len(cleared)} -> {sorted(cleared)}")
    if len(conclusive) < 2:
        print("INCONCLUSIVE")
    elif len(cleared) >= 2:
        print("BUILD")
    else:
        print("DEFER")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
