#!/usr/bin/env python3
"""G3c signature calibration (throwaway, in-brainstorm). NOT a gated CLI, NOT in the
unit suite. Validates a candidate content-free COMPONENT SIGNATURE before the G3c spec
locks: does a role-tree-only subtree signature RECUR across a site's routes, and do the
recurring ones correspond to real structural landmarks (nav/header/footer) rather than
page-specific content?

Per advisor: counts alone can't validate (a nav that drops from 4->3 routes looks like
sane counts). So this prints the actual core/boundary signature STRINGS (role-tree only
= content-free) for an identity check, runs Floor A (one route captured twice ->
signatures must be identical, forcing a deterministic role-only signature), sweeps the
ABSTRACTION policy (ordered / collapse / multiset) as the dominant knob alongside depth,
and dumps the role-value distribution first (a starved landmark whitelist would misread
as "few components").

CONTENT-FREE: reads skeleton.json (role/parent/id are probe-runner structural vocabulary,
already on disk + firewall-clean). A signature string is a tree of ROLE names only -- no
bbox, no text, no values. audit_bundle asserts CLEAN before analysis. site_capture stderr
is NEVER echoed (a leak message can embed a sample); only its returncode is read.

Run on host Bash (CDP :9222 must be reachable):
  --site DIR             analyse an already-captured site dir
  --capture URLS         site_capture comma-list -> tempdir, audit, analyse
  --floor-a URL          capture URL TWICE -> assert per-root signatures identical
"""
import argparse
import importlib
import json
import shutil
import socket
import subprocess
import sys
import tempfile
from collections import Counter
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"

# ARIA-ish landmark / widget roles -- the candidate component anchors. Intersected with
# observed roles; the distribution dump reveals starvation.
LANDMARK = {
    "navigation", "banner", "contentinfo", "main", "complementary", "region",
    "form", "search", "list", "listitem", "article", "button", "link", "heading",
    "image", "textbox", "menu", "menuitem", "menubar", "tab", "tablist", "tabpanel",
    "dialog", "table", "row", "cell", "figure", "group", "section", "nav",
}
POLICIES = ["ordered", "collapse", "multiset"]
DEPTHS = [1, 2, 3]


def _trunc(s, n=160):
    return s if len(s) <= n else s[:n] + "...(+%d more roles)" % (s[n:].count(",") + 1)


# ------------------------------- pure signature core -------------------------------
def _children(nodes):
    by_parent = {}
    for n in nodes:
        by_parent.setdefault(n.get("parent"), []).append(n)
    return by_parent  # children kept in document (emit) order


def node_token(n, enrich):
    """The per-node label. enrich=False -> role only (baseline). enrich=True ->
    role + STABLE content-free DESIGN axes (advisor: layout-mode, sizing, token_ref
    palette-role, font-class -- NOT jittery raw style/bbox). All values are
    probe-runner vocabulary or palette ROLE names, never site content."""
    role = n.get("role") or "?"
    if not enrich:
        return role
    parts = [role]
    lay = n.get("layout") or {}
    mode = lay.get("mode")
    if mode and mode != "block":
        parts.append(mode + ("-" + (lay.get("direction") or "")[:3] if mode == "flex" else ""))
    sz = n.get("sizing") or {}
    _SZ = {"fill": "L", "fixed": "X", "hug": "H"}  # NOT [0]: fill/fixed both start "f"
    if sz.get("w") or sz.get("h"):
        parts.append(_SZ.get(sz.get("w"), "?") + _SZ.get(sz.get("h"), "?"))
    tr = n.get("token_ref") or {}
    trbits = [k[0] + ":" + v for k, v in (("bg", tr.get("bg")), ("fg", tr.get("fg")),
                                          ("border", tr.get("border"))) if v]
    if trbits:
        parts.append("+".join(trbits))
    f = n.get("font")
    if f:
        w = f.get("weight") or 400
        parts.append((f.get("family") or "?") + ("b" if w >= 600 else "l" if w < 400 else "n"))
    return "·".join(parts)


def _token_of(nodes, enrich):
    return {n["id"]: node_token(n, enrich) for n in nodes}


def signature(node, by_parent, token_of, depth, policy):
    """Fingerprint of the subtree at `node` to `depth`. `policy` abstracts the child
    sequence -- the dominant knob. Content-free (tokens are role + design vocabulary)."""
    tok = token_of.get(node["id"], "?")
    if depth <= 0:
        return tok
    kids = by_parent.get(node["id"], [])
    child_sigs = [signature(c, by_parent, token_of, depth - 1, policy) for c in kids]
    if not child_sigs:
        return tok
    if policy == "ordered":
        seq = child_sigs
    elif policy == "collapse":  # consecutive-identical-sibling collapse
        seq = [s for i, s in enumerate(child_sigs) if i == 0 or s != child_sigs[i - 1]]
    else:  # multiset
        seq = sorted(child_sigs)
    return "%s(%s)" % (tok, ",".join(seq))


def _is_styled(n):
    """A design-bearing container: an explicit flex/grid layout OR any palette token_ref.
    A sharper component-root anchor than 'any internal node'."""
    if (n.get("layout") or {}).get("mode") in ("flex", "grid"):
        return True
    tr = n.get("token_ref") or {}
    return any(tr.get(k) for k in ("bg", "fg", "border"))


def _root_ids(nodes, by_parent, root_policy):
    if root_policy == "landmark":
        return [n for n in nodes if (n.get("role") or "?") in LANDMARK]
    if root_policy == "styled":
        return [n for n in nodes if _is_styled(n) and by_parent.get(n["id"])]
    return [n for n in nodes if by_parent.get(n["id"])]  # "internal": >=1 child


def route_signatures(nodes, depth, policy, root_policy, enrich):
    by_parent = _children(nodes)
    token_of = _token_of(nodes, enrich)
    roots = _root_ids(nodes, by_parent, root_policy)
    return Counter(signature(n, by_parent, token_of, depth, policy) for n in roots)


# ------------------------------- recurrence metrics -------------------------------
def _jaccard(a, b):
    u = a | b
    return (len(a & b) / len(u)) if u else 1.0


def _mean_pairwise_jaccard(sets):
    pairs = list(combinations(range(len(sets)), 2))
    if not pairs:
        return 1.0
    return round(sum(_jaccard(sets[i], sets[j]) for i, j in pairs) / len(pairs), 3)


def recurrence(per_route_sets):
    n = len(per_route_sets)
    freq = Counter()
    for s in per_route_sets:
        for v in s:
            freq[v] += 1
    return {
        "routes": n,
        "distinct": len(freq),
        "core": [v for v, c in freq.items() if c == n],
        "shared_ge2_not_core": [v for v, c in freq.items() if 2 <= c < n],
        "unique": [v for v, c in freq.items() if c == 1],
        "jac": _mean_pairwise_jaccard(per_route_sets),
    }


def _load_skeletons(site_dir):
    site_dir = Path(site_dir)
    site = json.loads((site_dir / "site.json").read_text())
    out = []
    for r in site.get("routes", []):
        if not r.get("ok"):
            continue
        sk = site_dir / "routes" / r["route_id"] / "skeleton.json"
        if sk.exists():
            try:
                out.append((r["route_id"], json.loads(sk.read_text()).get("nodes") or []))
            except (OSError, ValueError):
                continue
    return out


def analyse(site_dir, enrich=False):
    routes = _load_skeletons(site_dir)
    if not routes:
        print("  NO ok routes with skeleton.json")
        return
    print("  routes analysed: %d (%s) ; ENRICH=%s"
          % (len(routes), ",".join(r for r, _ in routes), enrich))

    # (1) role distribution + anchor coverage (advisor #4)
    roles = Counter()
    total = 0
    for _, nodes in routes:
        total += len(nodes)
        for n in nodes:
            roles[n.get("role") or "?"] += 1
    print("  total nodes: %d ; distinct roles: %d" % (total, len(roles)))
    print("  top roles: %s" % ", ".join("%s=%d" % (r, c) for r, c in roles.most_common(15)))
    seen = set(roles)
    print("  landmark roles PRESENT: %s" % (sorted(seen & LANDMARK) or "NONE"))
    print("  non-landmark roles: %s" % (sorted(seen - LANDMARK) or "NONE"))
    lm_nodes = sum(c for r, c in roles.items() if r in LANDMARK)
    print("  landmark-anchor coverage: %d/%d nodes (%.0f%%)" %
          (lm_nodes, total, 100.0 * lm_nodes / max(total, 1)))

    # (2) sweep: root_policy x abstraction x depth -> recurrence COUNTS
    print("  -- sweep (distinct / core / shared / unique / jac) --")
    for root_policy in ("internal", "styled"):
        for policy in POLICIES:
            for depth in DEPTHS:
                sets = [set(route_signatures(nodes, depth, policy, root_policy, enrich))
                        for _, nodes in routes]
                m = recurrence(sets)
                print("  %-8s %-8s d%d: distinct=%-4d core=%-3d shared=%-3d unique=%-4d jac=%s"
                      % (root_policy, policy, depth, m["distinct"], len(m["core"]),
                         len(m["shared_ge2_not_core"]), len(m["unique"]), m["jac"]))

    # (3) IDENTITY CHECK (advisor): print the actual signature STRINGS so we can judge
    # whether the recurring (core) signatures are DISTINCTIVE recurring shapes or trivia
    # like box(text,text). The `internal` anchor is the one that actually recurs, so dump
    # IT (the landmark anchor is starved here). Role-tree strings are content-free.
    for cfg in (("styled", "collapse", 1), ("styled", "collapse", 2), ("internal", "collapse", 2)):
        sets = [set(route_signatures(nodes, cfg[2], cfg[1], cfg[0], enrich)) for _, nodes in routes]
        m = recurrence(sets)
        print("  -- identity check root=%s policy=%s depth=%d (core=%d shared=%d unique=%d) --"
              % (cfg[0], cfg[1], cfg[2], len(m["core"]),
                 len(m["shared_ge2_not_core"]), len(m["unique"])))
        print("  CORE (in all %d routes) [up to 40]:" % len(routes))
        for s in sorted(m["core"])[:40]:
            print("    %s" % _trunc(s))
        print("  SHARED (>=2, not all) [sample]:")
        for s in sorted(m["shared_ge2_not_core"])[:6]:
            print("    %s" % _trunc(s))
        print("  UNIQUE (1 route) [sample]:")
        for s in sorted(m["unique"])[:5]:
            print("    %s" % _trunc(s))


# ------------------------------- capture helpers (host CDP) -------------------------------
def _cdp_reachable(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=2):
            return True
    except OSError:
        return False


def _audit_clean(site_dir):
    sys.path.insert(0, str(SCRIPTS))
    cf = importlib.import_module("content_firewall")
    viol = cf.audit_bundle(Path(site_dir))
    return (not viol), len(viol)  # never the samples


def _capture(urls, out, port):
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "site_capture.py"),
         "--urls", ",".join(urls), "--out", str(out), "--cdp-port", str(port)],
        cwd=str(SCRIPTS), capture_output=True, text=True)
    return r.returncode  # never r.stderr


def _capture_to_tmp(urls, port):
    """Capture into a fresh tempdir. Returns (tmpdir|None, rc, clean, nviol). Caller
    rmtrees the dir. None tmpdir == capture/audit failed."""
    tmp = Path(tempfile.mkdtemp(prefix="calib_g3c_"))
    rc = _capture(urls, tmp, port)
    if rc != 0:
        shutil.rmtree(tmp, ignore_errors=True)
        return None, rc, False, 0
    clean, nviol = _audit_clean(tmp)
    if not clean:
        shutil.rmtree(tmp, ignore_errors=True)
        return None, rc, False, nviol
    return tmp, rc, True, nviol


def _capture_and_analyse(urls, port, enrich=False):
    if not _cdp_reachable(port):
        print("CDP_REACHABLE: False (Chrome :%d down) -- skipping capture" % port)
        return
    print("CDP_REACHABLE: True")
    tmp, rc, clean, nviol = _capture_to_tmp(urls, port)
    print("capture_rc: %d ; audit: %s (violations=%d)"
          % (rc, "CLEAN" if clean else "DIRTY/FAIL", nviol))
    if tmp is None:
        return
    try:
        analyse(tmp, enrich)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _floor_a(url, port, enrich=False):
    """Determinism floor: capture the SAME url into two SEPARATE dirs (site_capture
    dedupes a repeated URL within one run, so one run can't test this), compare per-root
    signatures. Identical => the signature is capture-deterministic."""
    if not _cdp_reachable(port):
        print("CDP_REACHABLE: False (Chrome :%d down) -- skipping" % port)
        return
    print("CDP_REACHABLE: True")
    t1, rc1, c1, _ = _capture_to_tmp([url], port)
    t2, rc2, c2, _ = _capture_to_tmp([url], port)
    try:
        print("capture rc: %s,%s ; audit: %s,%s" % (rc1, rc2, c1, c2))
        if t1 is None or t2 is None:
            print("FLOOR_A: capture failed")
            return
        r1, r2 = _load_skeletons(t1), _load_skeletons(t2)
        if not r1 or not r2:
            print("FLOOR_A: no ok route")
            return
        cfg = ("styled", "collapse", 2)
        a = set(route_signatures(r1[0][1], cfg[2], cfg[1], cfg[0], enrich))
        b = set(route_signatures(r2[0][1], cfg[2], cfg[1], cfg[0], enrich))
        print("FLOOR_A determinism (%s root, ENRICH=%s, same URL, 2 captures): identical=%s "
              "|A|=%d |B|=%d jac=%s" % (cfg[0], enrich, a == b, len(a), len(b), round(_jaccard(a, b), 3)))
        if a != b:
            print("  A-only [sample]: %s" % [_trunc(s, 80) for s in sorted(a - b)[:4]])
            print("  B-only [sample]: %s" % [_trunc(s, 80) for s in sorted(b - a)[:4]])
    finally:
        shutil.rmtree(t1, ignore_errors=True)
        shutil.rmtree(t2, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site")
    ap.add_argument("--capture")
    ap.add_argument("--floor-a")
    ap.add_argument("--enrich", action="store_true",
                    help="signature = role + design axes (layout/sizing/token_ref/font)")
    ap.add_argument("--cdp-port", type=int, default=9222)
    args = ap.parse_args()
    if args.site:
        analyse(args.site, args.enrich)
    elif args.floor_a:
        _floor_a(args.floor_a, args.cdp_port, args.enrich)
    elif args.capture:
        urls = [u.strip() for u in args.capture.split(",") if u.strip()]
        _capture_and_analyse(urls, args.cdp_port, args.enrich)
    else:
        ap.error("one of --site / --capture / --floor-a required")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
