#!/usr/bin/env python3
"""G3d SHARED-CHROME DEDUP calibration -- is landmark site-chrome (header/nav/footer/aside)
recaptured identically across routes worth deduping into a site-level store?

The §A0 G3 gap is "dedup of shared chrome (header/footer/nav re-captured per page)". Dedup is
PER-SITE and OPPORTUNISTIC -- NOT subject to the cross-site recurrence bar that DEFERRED G3c
(§C9-R-G3c-revisit). This measures the LOSSLESS node-savings achievable by storing each identical
landmark-chrome subtree once and referencing it per route, before any core-file build.

Captures go through the PRODUCTION `site_capture` path (bundled redacted skeleton.json carrying
aria_role + token_ref -- the real artifact). Reuses §C9-R-G3c-calib's `_children`.

============================  PRE-REGISTERED BAR + EXACT KEY  ============================
Set BEFORE any capture (the fix for this session's recurrence over-reads; not to be bent or the
key loosened after the numbers are seen). Sites: the 6 G3c-revisit sites.

CHROME landmarks (dedup-eligible): aria_role in {banner, navigation, contentinfo, complementary}
  -- recurring site chrome. EXCLUDES main (=page content) and widget composites.

EXACT-LOSSLESS subtree KEY (recursive, full depth; two subtrees with equal key are
design-identical ⇒ safe to store once). Per node, in this fixed field order:
  role | aria_role | layout.{mode,direction,gap,pad,justify,align,grid_cols,grid_rows} |
  sizing.{w,h} | token_ref.{bg,fg,border} | font.{family,weight} | text_len |
  pseudo(present 0/1) | substrate
EXCLUDED (volatile/positional, restored on the per-route reference): id, parent, bbox, z,
sizing.confidence. (bbox-excluded ⇒ reported savings are GROSS; net subtracts one stored bbox
per reference -- a Phase-2 build detail.) The strict key WILL mismatch on per-route active
state (aria-current, active-nav styling, breadcrumb text_len); if that drives a DEFER, the
honest next step is "structural+deltas needs its OWN bar", NOT a quiet key relaxation here.

SAVINGS (per site, non-overlapping TILING -- avoids the nested banner⊃nav double-count):
  pass 1: count global occurrences `occ[key]` over ALL chrome-landmark subtrees.
  tile each route top-down: SELECT the OUTERMOST chrome landmark whose key recurs (occ>=2) and
    do NOT descend into it; descend through everything else (so an inner nav whose outer banner
    is unique still gets selected).
  group selected instances by key; saved = Σ_key (m-1)*size_key for m>=2 selected;
  pct = 100 * saved / total_nodes_across_routes.   (m = total selected occurrences, not
  route-presence: a key repeated twice on one page dedups too.)

VERDICT (per-site/opportunistic -- NOT strict cross-site):
  BUILD iff median per-site pct >= 12  AND  at least 3 sites have pct >= 15.  Else DEFER
  (a legitimate, honest outcome). Needs >= 4 sites with data (>=2 ok routes) else INCONCLUSIVE.
=========================================================================================

Content-free: reads ONLY mechanism keys from already-redacted bundles; audits every bundle;
prints ONLY counts / percentages / role NAMES / netloc / returncodes. NEVER node content, NEVER
subprocess stderr. Runs on HOST Bash (CDP :9222, dangerouslyDisableSandbox=true).
Usage: python3 probe_g3d_dedup.py [--cdp-port 9222] [--sites N] [--routes N]
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]   # capture-gap-probes -> research -> repo root
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import calib_component_signature as C          # _children
import content_firewall as cf                  # audit_bundle

CHROME = frozenset({"banner", "navigation", "contentinfo", "complementary"})
BAR = {"median": 12.0, "site_pct": 15.0, "min_sites_at": 3, "min_data": 4}

SITES = {
    "python.org": ["https://www.python.org/", "https://www.python.org/about/",
                   "https://www.python.org/downloads/", "https://www.python.org/community/"],
    "iana.org": ["https://www.iana.org/", "https://www.iana.org/domains",
                 "https://www.iana.org/numbers", "https://www.iana.org/about"],
    "djangoproject.com": ["https://www.djangoproject.com/", "https://www.djangoproject.com/start/",
                          "https://www.djangoproject.com/download/", "https://www.djangoproject.com/community/"],
    "w3.org": ["https://www.w3.org/", "https://www.w3.org/standards/",
               "https://www.w3.org/participate/", "https://www.w3.org/about/"],
    "gnu.org": ["https://www.gnu.org/", "https://www.gnu.org/philosophy/philosophy.html",
                "https://www.gnu.org/software/software.html", "https://www.gnu.org/help/help.html"],
    "apache.org": ["https://www.apache.org/", "https://www.apache.org/foundation/",
                   "https://www.apache.org/licenses/", "https://www.apache.org/events/current-event.html"],
}


from _shape_key import _KEY_FIELDS, _node_key  # canonical; probe keeps these names for back-compat
DROP_TR = ("token_ref.bg", "token_ref.fg", "token_ref.border")  # ablation only (probe-local)
DROP_TXT = ("text_len",)                                         # ablation only (probe-local)


def _subtree(node, by_parent, drop=()):
    """(exact recursive key, node count) for the subtree rooted at `node`, full depth,
    children in document (emit) order. `drop` is ablation-only (default () = verdict key)."""
    kids = by_parent.get(node["id"], [])
    ck, sz = [], 1
    for c in kids:
        k, s = _subtree(c, by_parent, drop)
        ck.append(k)
        sz += s
    key = _node_key(node, drop) + ("(" + ",".join(ck) + ")" if ck else "")
    return key, sz


def _recurring_under(route_lists, drop):
    """ABLATION diagnostic: count chrome-landmark subtree keys recurring (occ>=2) when `drop`
    fields are blanked. Discriminates WHICH field's per-route instability blocks dedup. Does NOT
    touch the verdict."""
    occ = Counter()
    for nodes in route_lists:
        by_parent = C._children(nodes)
        for n in nodes:
            if n.get("aria_role") in CHROME:
                occ[_subtree(n, by_parent, drop)[0]] += 1
    return sum(1 for c in occ.values() if c >= 2)


def _roots(nodes):
    ids = {n["id"] for n in nodes}
    return [n for n in nodes if n.get("parent") not in ids]


def _tile(nodes, by_parent, occ):
    """Non-overlapping selection: outermost chrome landmark whose key recurs (occ>=2);
    do not descend into a selected subtree. -> list of (key, size)."""
    selected, stack = [], _roots(nodes)
    while stack:
        n = stack.pop()
        if n.get("aria_role") in CHROME:
            k, s = _subtree(n, by_parent)
            if occ[k] >= 2:
                selected.append((k, s))
                continue  # tile boundary: do not double-count nested chrome
        stack.extend(by_parent.get(n["id"], []))
    return selected


def _site_savings(route_lists):
    prepared = [(nodes, C._children(nodes)) for nodes in route_lists]
    occ, size_of = Counter(), {}
    for nodes, by_parent in prepared:
        for n in nodes:
            if n.get("aria_role") in CHROME:
                k, s = _subtree(n, by_parent)
                occ[k] += 1
                size_of[k] = s
    sel = Counter()
    for nodes, by_parent in prepared:
        for k, _s in _tile(nodes, by_parent, occ):
            sel[k] += 1
    saved = sum((m - 1) * size_of[k] for k, m in sel.items() if m >= 2)
    total = sum(len(nodes) for nodes in route_lists) or 1
    recurring = sum(1 for k, c in occ.items() if c >= 2)
    return {"saved": saved, "total": total, "pct": 100.0 * saved / total,
            "chrome_keys": len(occ), "recurring_keys": recurring,
            "deduped_keys": sum(1 for m in sel.values() if m >= 2)}


def _chrome_roles(route_lists):
    r = set()
    for nodes in route_lists:
        for n in nodes:
            if n.get("aria_role") in CHROME:
                r.add(n["aria_role"])
    return sorted(r)


def _capture(urls, port):
    out = Path(tempfile.mkdtemp(prefix="g3d_"))
    try:
        rc = subprocess.run(
            [sys.executable, str(SCRIPTS / "site_capture.py"),
             "--urls", ",".join(urls), "--out", str(out), "--cdp-port", str(port)],
            cwd=str(SCRIPTS), capture_output=True, text=True).returncode
        if rc != 0:
            return [], False, rc
        clean = not cf.audit_bundle(out)
        lists = []
        try:
            site = json.loads((out / "site.json").read_text())
            for row in site.get("routes", []):
                if row.get("ok"):
                    sk = out / "routes" / row["route_id"] / "skeleton.json"
                    lists.append(json.loads(sk.read_text()).get("nodes") or [])
        except (OSError, ValueError, KeyError):
            pass
        return lists, clean, rc
    finally:
        shutil.rmtree(out, ignore_errors=True)


def _median(xs):
    s = sorted(xs)
    n = len(s)
    if not n:
        return 0.0
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def _floor_a(url, port):
    a, ca, _ = _capture([url], port)
    b, cb, _ = _capture([url], port)
    if not a or not b or not ca or not cb:
        return None
    bpa = C._children(a[0])
    bpb = C._children(b[0])
    ka = Counter(_subtree(n, bpa)[0] for n in a[0] if n.get("aria_role") in CHROME)
    kb = Counter(_subtree(n, bpb)[0] for n in b[0] if n.get("aria_role") in CHROME)
    return ka == kb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    ap.add_argument("--sites", type=int, default=0)
    ap.add_argument("--routes", type=int, default=0)
    args = ap.parse_args()

    items = list(SITES.items())
    if args.sites:
        items = items[:args.sites]

    print("== G3d DEDUP :: chrome=%s bar=%s ==" % (sorted(CHROME), BAR))
    pcts = []
    for netloc, urls in items:
        if args.routes:
            urls = urls[:args.routes]
        lists, clean, rc = _capture(urls, args.cdp_port)
        if not clean:
            print("  %-20s AUDIT NOT CLEAN -- excluded (firewall)" % netloc)
            continue
        if len(lists) < 2:
            print("  %-20s ok_routes=%d rc=%d -- insufficient (<2)" % (netloc, len(lists), rc))
            continue
        m = _site_savings(lists)
        pcts.append(m["pct"])
        print("  %-20s ok_routes=%d roles=%s  chrome_keys=%d recurring=%d deduped=%d  "
              "saved=%d/%d  pct=%.1f%%"
              % (netloc, len(lists), _chrome_roles(lists), m["chrome_keys"],
                 m["recurring_keys"], m["deduped_keys"], m["saved"], m["total"], m["pct"]))
        print("      ablation recurring full/noTR/noTXT = %d/%d/%d"
              % (m["recurring_keys"], _recurring_under(lists, DROP_TR), _recurring_under(lists, DROP_TXT)))

    print("\n== BAR EVALUATION (per-site/opportunistic) ==")
    n_data = len(pcts)
    if n_data < BAR["min_data"]:
        print("INCONCLUSIVE -- only %d site(s) with data (<%d). Re-run." % (n_data, BAR["min_data"]))
        return 2
    med = _median(pcts)
    at = sum(1 for p in pcts if p >= BAR["site_pct"])
    fa = _floor_a(SITES["python.org"][0], args.cdp_port)
    print("  median_pct=%.1f  sites_ge_%.0f%%=%d/%d  floor_a_determinism=%s"
          % (med, BAR["site_pct"], at, n_data, fa))
    if med >= BAR["median"] and at >= BAR["min_sites_at"]:
        print("VERDICT: BUILD G3d dedup (median>=%.0f%% and >=%d sites>=%.0f%%)"
              % (BAR["median"], BAR["min_sites_at"], BAR["site_pct"]))
        return 0
    print("VERDICT: DEFER G3d dedup (savings below the pre-registered bar) -- honest outcome")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
