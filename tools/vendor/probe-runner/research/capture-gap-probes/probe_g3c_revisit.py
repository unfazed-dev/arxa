#!/usr/bin/env python3
"""G3c REVISIT calibration -- does the now-PRODUCTION `aria_role` landmark field lift
cross-route component-signature recurrence enough to justify building the G3c synthesizer?

This re-runs the §C9-R-G3c-calib recurrence machinery, but:
  * roots are anchored on the REAL browser-computed landmark `aria_role`
    (web_skeleton.LANDMARK_ROLES) that `enrich_aria` now stamps at capture -- NOT the old
    geometry-bucket / tag heuristic (`_root_ids(root_policy="landmark")` used pre-aria).
  * captures go through the PRODUCTION `site_capture` path, so the analyzed artifact is the
    bundled, redacted `routes/<id>/skeleton.json` a real G3c consumer reads (token_ref is
    populated post-bundle; the in-memory aria probe lacked it).
  * the enrichment SWEEP (role-only -> +layout/sizing -> +token_ref) is reported PER SITE,
    never averaged -- so a landmark-rich site (python.org) cannot mask a sparse one (iana).

============================  PRE-REGISTERED BAR  ============================
Set BEFORE any capture (the fix for this session's 3x recurrence over-read). Fixed knobs:
depth=3, policy="collapse". Sweep axis = enrichment level in {0:role, 1:+layout/sizing,
2:+token_ref}. Per-site metrics:
    recurrence    = |core| (signatures present in ALL ok routes) and jac (mean pairwise
                    Jaccard of per-route signature sets).
    distinctiveness = |core_nontrivial| / |core|, where nontrivial = exemplar depth>=2 AND
                    exemplar root styled (flex/grid OR any token_ref). (depth>=2 holds for
                    every landmark root by selection; `styled` is the active discriminator.)

VERDICT RULE (strict cross-site):
    BUILD the G3c synthesizer IFF some single enrichment level clears
        core >= 3  AND  jac >= 0.5  AND  distinctiveness >= 0.3
    on EVERY site that yielded data (>= 2 ok routes). Otherwise DEFER (documented).
    Requires >= 3 sites with data for a valid verdict; else INCONCLUSIVE (re-run).
    A DEFER is a legitimate, honest outcome -- NOT a failure. The bar is not to be bent
    after the numbers are seen.
=============================================================================

Content-free: reads ONLY mechanism keys (role, aria_role, layout, sizing, token_ref) from
already-redacted bundles; audits every bundle (audit_bundle) before analysis; prints ONLY
counts / jaccard / role NAMES / host netloc / returncodes. NEVER node content, NEVER
subprocess stderr (a leak message can embed a content sample).

Runs on HOST Bash (CDP :9222, dangerouslyDisableSandbox=true) -- CDP is unreachable from the
ctx sandbox. Usage: python3 probe_g3c_revisit.py [--cdp-port 9222] [--sites N] [--routes N]
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]   # capture-gap-probes -> research -> repo root
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import calib_component_signature as C          # signature / recurrence / _children / _is_styled
import content_firewall as cf                  # audit_bundle
from web_skeleton import LANDMARK_ROLES        # the production 13-role allowlist

DEPTH = 3
POLICY = "collapse"
LEVELS = [(0, "role"), (1, "+layout"), (2, "+token_ref")]
THRESH = {"core": 3, "jac": 0.5, "distinct": 0.3}

# 6 landmark-bearing, multi-route, bot-friendly real sites (>=2 needed; "5+" requested).
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

_SZ = {"fill": "L", "fixed": "X", "hug": "H"}  # NOT [0]: fill/fixed both start "f"


def _lvl_base(n, level):
    """Geometry-role token at an enrichment level (mirrors calib.node_token's axes)."""
    role = n.get("role") or "?"
    if level == 0:
        return role
    parts = [role]
    lay = n.get("layout") or {}
    mode = lay.get("mode")
    if mode and mode != "block":
        parts.append(mode + ("-" + (lay.get("direction") or "")[:3] if mode == "flex" else ""))
    sz = n.get("sizing") or {}
    if sz.get("w") or sz.get("h"):
        parts.append(_SZ.get(sz.get("w"), "?") + _SZ.get(sz.get("h"), "?"))
    if level >= 2:
        tr = n.get("token_ref") or {}
        bits = [k[0] + ":" + v for k, v in (("bg", tr.get("bg")), ("fg", tr.get("fg")),
                                            ("border", tr.get("border"))) if v]
        if bits:
            parts.append("+".join(bits))
    return "·".join(parts)


def _lvl_token(n, level):
    """Landmark roots carry their aria_role as a semantic anchor prefix; others stay plain."""
    base = _lvl_base(n, level)
    ar = n.get("aria_role")
    return (ar + "@" + base) if ar else base


def _depth(node, by_parent, cap):
    kids = by_parent.get(node["id"], [])
    if not kids or cap <= 1:
        return 1
    return 1 + max(_depth(c, by_parent, cap - 1) for c in kids)


def _route_sigs(nodes, level, meta):
    """Set of landmark-anchored subtree signatures for one route; record sig->(styled,depth)."""
    by_parent = C._children(nodes)
    token_of = {n["id"]: _lvl_token(n, level) for n in nodes}
    roots = [n for n in nodes
             if n.get("aria_role") in LANDMARK_ROLES and by_parent.get(n["id"])]
    sigs = set()
    for r in roots:
        sg = C.signature(r, by_parent, token_of, DEPTH, POLICY)
        sigs.add(sg)
        if sg not in meta:
            meta[sg] = (C._is_styled(r), _depth(r, by_parent, DEPTH))
    return sigs


def _site_metrics(route_lists, level):
    meta = {}
    per = [_route_sigs(nl, level, meta) for nl in route_lists]
    rec = C.recurrence(per)
    core = rec["core"]
    if core:
        nt = sum(1 for s in core if meta[s][0] and meta[s][1] >= 2)
        distinct = nt / len(core)
    else:
        nt, distinct = 0, 0.0
    return {"routes": rec["routes"], "core": len(core), "jac": rec["jac"],
            "distinct": distinct, "nontrivial": nt}


def _capture(urls, port):
    """site_capture a route list through the PRODUCTION path -> (ok node-lists, audit_clean, rc).
    returncode ONLY on failure (never stderr)."""
    out = Path(tempfile.mkdtemp(prefix="g3c_"))
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


def _aria_summary(route_lists):
    roles = set()
    total = 0
    for nl in route_lists:
        for n in nl:
            ar = n.get("aria_role")
            if ar:
                roles.add(ar)
                total += 1
    return total, sorted(roles)


def _floor_a(url, port):
    """Determinism: capture one url twice in separate dirs -> identical level-2 sig set?"""
    a, ca, _ = _capture([url], port)
    b, cb, _ = _capture([url], port)
    if not a or not b or not ca or not cb:
        return None
    sa = _route_sigs(a[0], 2, {})
    sb = _route_sigs(b[0], 2, {})
    return sa == sb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    ap.add_argument("--sites", type=int, default=0, help="cap site count (0=all)")
    ap.add_argument("--routes", type=int, default=0, help="cap routes/site (0=all)")
    args = ap.parse_args()

    items = list(SITES.items())
    if args.sites:
        items = items[:args.sites]

    print("== G3c REVISIT :: depth=%d policy=%s thresh=%s ==" % (DEPTH, POLICY, THRESH))
    site_data = {}   # netloc -> {level: metrics}
    for netloc, urls in items:
        if args.routes:
            urls = urls[:args.routes]
        lists, clean, rc = _capture(urls, args.cdp_port)
        if not clean:
            print("  %-20s AUDIT NOT CLEAN -- excluded (firewall)" % netloc)
            continue
        if len(lists) < 2:
            print("  %-20s ok_routes=%d rc=%d -- insufficient (<2), no recurrence" % (netloc, len(lists), rc))
            continue
        ar_total, ar_roles = _aria_summary(lists)
        print("  %-20s ok_routes=%d  aria_nodes=%d  roles=%s" % (netloc, len(lists), ar_total, ar_roles))
        site_data[netloc] = {}
        for lv, name in LEVELS:
            m = _site_metrics(lists, lv)
            site_data[netloc][lv] = m
            print("      L%d %-11s core=%2d jac=%.2f distinct=%.2f (nt=%d/%d)"
                  % (lv, name, m["core"], m["jac"], m["distinct"], m["nontrivial"], m["core"]))

    print("\n== BAR EVALUATION (strict cross-site) ==")
    n_data = len(site_data)
    if n_data < 3:
        print("INCONCLUSIVE -- only %d site(s) with data (<3). Re-run." % n_data)
        return 2
    build_level = None
    for lv, name in LEVELS:
        fails = []
        for netloc, by_lv in site_data.items():
            m = by_lv[lv]
            why = []
            if m["core"] < THRESH["core"]:
                why.append("core<%d" % THRESH["core"])
            if m["jac"] < THRESH["jac"]:
                why.append("jac<%.1f" % THRESH["jac"])
            if m["distinct"] < THRESH["distinct"]:
                why.append("distinct<%.1f" % THRESH["distinct"])
            if why:
                fails.append("%s(%s)" % (netloc, ",".join(why)))
        if fails:
            print("  L%d %-11s FAILS on: %s" % (lv, name, "; ".join(fails)))
        else:
            print("  L%d %-11s CLEARS all %d sites" % (lv, name, n_data))
            if build_level is None:
                build_level = (lv, name)

    fa = _floor_a(SITES["python.org"][0], args.cdp_port)
    print("\n  floor_a_determinism=%s" % fa)

    if build_level is not None:
        print("VERDICT: BUILD G3c synthesizer (level %s clears every site)" % (build_level[1],))
        return 0
    print("VERDICT: DEFER G3c (no enrichment level clears the strict cross-site bar) -- honest outcome")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
