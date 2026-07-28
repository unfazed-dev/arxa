#!/usr/bin/env python3
"""G3c RICHNESS-GATED de-risk probe (Phase-1, throwaway). Pre-registration:
`docs/plans/richness-gated-g3c-design.md`. NOT in the shipped unit suite.

QUESTION: does a richness-gated G3c synthesizer produce value design_system.json (G3b,
verified flat value-freq) does NOT already carry, on the sites where it fires?

============================  PRE-REGISTERED BAR (not bendable after numbers seen)  ===
Fixed knobs: depth=3, collapse policy, signature levels {0:role, 1:+layout} (token_ref
EXCLUDED -- proven recurrence-collapsing in §C9-R-G3c-revisit).
GATE (per site, runtime + eval filter): gated-in iff best of {role,+layout} clears
    core >= 3 AND jac >= 0.5  (landmark-aria-anchored roots).
RICHNESS predicate (home route, at rest): rich iff
    >= 4 distinct landmark roles AND >= 8 repeated styled subtrees (occ>=2, depth>=2, styled root).
composition-NOVEL component: recurring (>=2 routes) landmark-anchored subtree with depth>=2,
    styled root, >=2 styled children spanning >=2 DISTINCT roles, NOT a generic wrapper
    (excludes bare box>text / single-child / styled-child-roles subset of {text}).
COVERAGE: styled main-content nodes (minus chrome-landmark subtrees) attributable to a
    novel component / total styled main-content nodes, per gated route.
VERDICT: BUILD iff (0 of 6 docs controls clear novel>=5 AND cov>=0.15)  AND
    (>=3 rich candidates clear novel>=5 AND cov>=0.15)  AND (>=4 rich gate in).
    <4 rich gate in => DEFER-as-finding. Else DEFER. No cohort expansion.
=======================================================================================

Content-free: reads mechanism keys only from already-redacted bundles; audits every bundle
BEFORE analysis; prints counts / jaccard / role NAMES / netloc / returncodes only -- never
node content, never subprocess stderr. HOST Bash (CDP :9222; unreachable from ctx sandbox).
"""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import calib_component_signature as C       # _children, signature, _is_styled, recurrence, _jaccard, capture helpers
import content_firewall as cf               # audit_bundle
from web_skeleton import LANDMARK_ROLES     # production landmark allowlist

DEPTH = 3
POLICY = "collapse"
CHROME_LANDMARKS = {"banner", "navigation", "contentinfo", "complementary"}

# Pre-registered thresholds (frozen).
GATE_CORE, GATE_JAC = 3, 0.5
RICH_LANDMARKS, RICH_SUBTREES = 4, 8
K_NOVEL, COVERAGE_MIN = 5, 0.15
MIN_RICH_GATED, MIN_RICH_CLEAR = 4, 3

_SZ = {"fill": "L", "fixed": "X", "hug": "H"}  # NOT [0]: fill/fixed both start "f"

# FROZEN cohort (spec §3). 4 routes each.
CONTROLS = {
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


def _node_token(n, level):
    """level 0 = role; level 1 = role + layout-mode + sizing. token_ref EXCLUDED.
    Landmark aria_role prefixes as a semantic anchor (mirrors probe_g3c_revisit)."""
    role = n.get("role") or "?"
    base = role
    if level >= 1:
        parts = [role]
        lay = n.get("layout") or {}
        mode = lay.get("mode")
        if mode and mode != "block":
            parts.append(mode + ("-" + (lay.get("direction") or "")[:3] if mode == "flex" else ""))
        sz = n.get("sizing") or {}
        if sz.get("w") or sz.get("h"):
            parts.append(_SZ.get(sz.get("w"), "?") + _SZ.get(sz.get("h"), "?"))
        base = "·".join(parts)
    ar = n.get("aria_role")
    return (ar + "@" + base) if ar else base


def _token_of(nodes, level):
    return {n["id"]: _node_token(n, level) for n in nodes}


def _landmark_roots(nodes, by_parent, landmark_roles):
    return [n for n in nodes if n.get("aria_role") in landmark_roles and by_parent.get(n["id"])]


def _route_sigs_with_meta(nodes, level, landmark_roles, depth=DEPTH):
    """sig -> first exemplar node, plus the by_parent map. Collapse policy, landmark roots."""
    by_parent = C._children(nodes)
    tok = _token_of(nodes, level)
    sigs = {}
    for n in _landmark_roots(nodes, by_parent, landmark_roles):
        s = C.signature(n, by_parent, tok, depth, POLICY)
        sigs.setdefault(s, n)
    return sigs, by_parent


def _route_sig_set(nodes, level, landmark_roles, depth=DEPTH):
    return set(_route_sigs_with_meta(nodes, level, landmark_roles, depth)[0])


def gate(route_node_lists, landmark_roles, depth=DEPTH):
    """Best of {role(0), +layout(1)} clears core>=GATE_CORE AND jac>=GATE_JAC. Returns
    (gated_in: bool, best: {level, core, jac}). best = the strongest level seen (for reporting),
    preferring a passing level."""
    best = {"level": None, "core": 0, "jac": 0.0, "pass": False}
    for level in (0, 1):
        per = [_route_sig_set(nl, level, landmark_roles, depth) for nl in route_node_lists]
        rec = C.recurrence(per)
        core, jac = len(rec["core"]), rec["jac"]
        passes = core >= GATE_CORE and jac >= GATE_JAC
        better = (passes, core, jac) > (best["pass"], best["core"], best["jac"])
        if better:
            best = {"level": level, "core": core, "jac": jac, "pass": passes}
    return best["pass"], best


def _has_composition(node_, by_parent, depth=DEPTH):
    """∃ a node WITHIN THE SIGNATURE DEPTH WINDOW (<= `depth`, == the matching signature's
    depth) with >=2 styled children spanning >=2 DISTINCT roles whose styled-child role-set is
    not a subset of {text} -- a real, non-generic branch. Bounded to `depth` so novelty is a
    deterministic function of the recurring signature, not of below-window structure the
    signature key cannot see (an unbounded scan made novelty route-order-dependent via the
    first-exemplar pick). A landmark commonly wraps a single container, so the branch need not
    be at the root -- but it must lie inside the window the signature actually matches on."""
    stack = [(node_, depth)]
    while stack:
        cur, d = stack.pop()
        if d < 1:
            continue
        kids = by_parent.get(cur["id"], [])
        styled = [k for k in kids if C._is_styled(k)]
        roles = {(k.get("role") or "?") for k in styled}
        if len(styled) >= 2 and len(roles) >= 2 and not (roles <= {"text"}):
            return True
        stack.extend((k, d - 1) for k in kids)
    return False


def _is_novel_composition(node_, by_parent):
    """§4 clauses 2-4 on an exemplar (clause 1 = recurrence, handled by the caller): root
    styled, depth>=2 (>=1 child), AND the subtree contains a real non-generic composition
    branch. Excludes bare box>text chains, single-child wrappers, and text-only branches."""
    if not by_parent.get(node_["id"]):
        return False                          # depth>=2 needs >=1 child level
    if not C._is_styled(node_):
        return False                          # styled root
    return _has_composition(node_, by_parent)


def composition_novel_components(route_node_lists, level, landmark_roles, depth=DEPTH):
    """Signatures that (1) recur in >=2 routes AND (2-4) whose exemplar is a non-generic
    composed subtree. Returns the list of novel signature strings."""
    per_sets, exemplar = [], {}
    for nl in route_node_lists:
        sigs, bp = _route_sigs_with_meta(nl, level, landmark_roles, depth)
        per_sets.append(set(sigs))
        for s, n in sigs.items():
            exemplar.setdefault(s, (n, bp))
    rec = C.recurrence(per_sets)
    recurring = set(rec["core"]) | set(rec["shared_ge2_not_core"])
    return [s for s in recurring if _is_novel_composition(*exemplar[s])]


def _subtree_ids(node_, by_parent):
    out, stack = [], [node_]
    while stack:
        cur = stack.pop()
        out.append(cur["id"])
        stack.extend(by_parent.get(cur["id"], []))
    return out


def _chrome_ids(nodes, by_parent, landmark_roles):
    ids = set()
    for n in nodes:
        if n.get("aria_role") in CHROME_LANDMARKS:
            ids.update(_subtree_ids(n, by_parent))
    return ids


def _site_coverage(per_route_covs):
    """Per-site coverage = MEDIAN over the site's gated routes (spec §5; NEVER a mean -- a
    mean lets one component-dense route mask sparse ones and biases toward BUILD). Rounded
    to 3 dp; 0.0 on empty."""
    if not per_route_covs:
        return 0.0
    vs = sorted(per_route_covs)
    n = len(vs)
    mid = n // 2
    med = vs[mid] if n % 2 else (vs[mid - 1] + vs[mid]) / 2
    return round(med, 3)


def coverage(nodes, novel_sigs, level, landmark_roles, depth=DEPTH):
    """styled main-content nodes (minus chrome subtrees) attributable to a novel component
    / total styled main-content nodes. Rounded to 3 dp."""
    by_parent = C._children(nodes)
    tok = _token_of(nodes, level)
    chrome = _chrome_ids(nodes, by_parent, landmark_roles)
    styled_main = {n["id"] for n in nodes if C._is_styled(n) and n["id"] not in chrome}
    if not styled_main:
        return 0.0
    novel = set(novel_sigs)
    covered = set()
    for n in _landmark_roots(nodes, by_parent, landmark_roles):
        if C.signature(n, by_parent, tok, depth, POLICY) in novel:
            covered.update(i for i in _subtree_ids(n, by_parent) if i in styled_main)
    return round(len(covered) / len(styled_main), 3)


def richness_predicate(home_nodes, landmark_roles, depth=DEPTH):
    """§3c: rich iff >=RICH_LANDMARKS distinct landmark roles AND >=RICH_SUBTREES repeated
    (occ>=2) styled subtrees on the home route. Returns (is_rich, n_landmarks, n_repeated)."""
    by_parent = C._children(home_nodes)
    n_landmarks = len({n.get("aria_role") for n in home_nodes
                       if n.get("aria_role") in landmark_roles})
    tok = _token_of(home_nodes, 1)
    styled_roots = [n for n in home_nodes if C._is_styled(n) and by_parent.get(n["id"])]
    cnt = Counter(C.signature(n, by_parent, tok, depth, POLICY) for n in styled_roots)
    n_repeated = sum(1 for c in cnt.values() if c >= 2)
    return (n_landmarks >= RICH_LANDMARKS and n_repeated >= RICH_SUBTREES), n_landmarks, n_repeated


RICH = {
    "mui.com": ["https://mui.com/", "https://mui.com/material-ui/", "https://mui.com/material-ui/all-components/", "https://mui.com/core/"],
    "ant.design": ["https://ant.design/", "https://ant.design/components/overview/", "https://ant.design/components/button/", "https://ant.design/components/card/"],
    "getbootstrap.com": ["https://getbootstrap.com/", "https://getbootstrap.com/docs/5.3/components/buttons/", "https://getbootstrap.com/docs/5.3/components/card/", "https://getbootstrap.com/docs/5.3/components/navbar/"],
    "carbondesignsystem.com": ["https://carbondesignsystem.com/", "https://carbondesignsystem.com/components/overview/", "https://carbondesignsystem.com/components/button/usage/", "https://carbondesignsystem.com/components/tile/usage/"],
    "primer.style": ["https://primer.style/", "https://primer.style/components", "https://primer.style/foundations", "https://primer.style/guides"],
    "chakra-ui.com": ["https://chakra-ui.com/", "https://chakra-ui.com/docs/components/concepts/overview", "https://chakra-ui.com/docs/components/button", "https://chakra-ui.com/docs/components/card"],
    "stripe.com": ["https://stripe.com/", "https://stripe.com/payments", "https://stripe.com/billing", "https://stripe.com/connect"],
    "vercel.com": ["https://vercel.com/", "https://vercel.com/products/previews", "https://vercel.com/products/observability", "https://vercel.com/solutions/nextjs"],
}


def _clears(r):
    return r["gated_in"] and r["novel"] >= K_NOVEL and r["coverage"] >= COVERAGE_MIN


def verdict(control_results, rich_results):
    """Apply the pre-registered §6 bar. Returns (decision, why)."""
    controls_clearing = [r for r in control_results if _clears(r)]
    rich_gated = [r for r in rich_results if r["gated_in"]]
    rich_clearing = [r for r in rich_results if _clears(r)]
    if len(rich_gated) < MIN_RICH_GATED:
        return "DEFER", ("DEFER-as-finding: only %d/%d rich candidates gated in "
                         "(rich-but-not-recurrent)" % (len(rich_gated), MIN_RICH_GATED))
    if controls_clearing:
        return "DEFER", ("neg-control falsified: %d docs control(s) cleared the value bar "
                         "(metric does not discriminate habitat)" % len(controls_clearing))
    if len(rich_clearing) >= MIN_RICH_CLEAR:
        return "BUILD", "%d rich candidates clear (>=%d novel AND >=%.0f%% coverage); 0 controls clear" \
            % (len(rich_clearing), K_NOVEL, COVERAGE_MIN * 100)
    return "DEFER", "only %d/%d rich candidates clear the value bar" % (len(rich_clearing), MIN_RICH_CLEAR)


import shutil
import tempfile
import subprocess


def _capture_routes(urls, port):
    """site_capture a route list through the PRODUCTION path. Returns (node_lists, clean, rc).
    returncode ONLY on failure (never stderr); audits the bundle before returning."""
    out = Path(tempfile.mkdtemp(prefix="g3c_rg_"))
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


def _eval_site(netloc, urls, port, want_rich):
    """Capture, audit, gate, then (if gated-in) novelty+coverage on the BEST passing level.
    Returns a result dict or None (audit-fail / insufficient routes)."""
    lists, clean, rc = _capture_routes(urls, port)
    if not clean:
        print("  %-22s AUDIT NOT CLEAN -- excluded (firewall)" % netloc)
        return None
    if len(lists) < 2:
        print("  %-22s ok_routes=%d rc=%d -- insufficient (<2)" % (netloc, len(lists), rc))
        return None
    if len(lists) < len(urls):
        print("       NOTE: %d/%d routes ok; §3c richness scored on first ok route "
              "(home may have failed capture)" % (len(lists), len(urls)))
    rich, n_lm, n_rep = richness_predicate(lists[0], LANDMARK_ROLES)
    gated, best = gate(lists, LANDMARK_ROLES)
    level = best["level"] if gated else 1
    novel = composition_novel_components(lists, level, LANDMARK_ROLES) if gated else []
    cov = _site_coverage([coverage(nl, novel, level, LANDMARK_ROLES) for nl in lists]) \
        if gated else 0.0
    res = {"netloc": netloc, "rich": rich, "n_landmarks": n_lm, "n_repeated": n_rep,
           "gated_in": gated, "level": best["level"], "core": best["core"], "jac": best["jac"],
           "novel": len(novel), "coverage": cov}
    print("  %-22s rich=%s(lm=%d,rep=%d) gated=%s(L%s core=%d jac=%.2f) novel=%d cov=%.3f"
          % (netloc, rich, n_lm, n_rep, gated, best["level"], best["core"], best["jac"],
             len(novel), cov))
    if want_rich and not rich:
        print("       NOTE: frozen rich candidate FAILED richness predicate -- excluded from rich pool")
    return res


def _floor_a(url, port):
    """Determinism: capture one url twice -> identical level-1 landmark sig set?"""
    a, ca, _ = _capture_routes([url], port)
    b, cb, _ = _capture_routes([url], port)
    if not a or not b or not ca or not cb:
        print("FLOOR_A: capture/audit failed")
        return
    sa = _route_sig_set(a[0], 1, LANDMARK_ROLES)
    sb = _route_sig_set(b[0], 1, LANDMARK_ROLES)
    print("FLOOR_A determinism (same URL, 2 captures): identical=%s |A|=%d |B|=%d"
          % (sa == sb, len(sa), len(sb)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    ap.add_argument("--floor-a", help="capture this URL twice; assert identical sig set")
    ap.add_argument("--sites", type=int, default=0, help="cap candidates per cohort (0=all)")
    args = ap.parse_args()

    if not C._cdp_reachable(args.cdp_port):
        print("CDP_REACHABLE: False (Chrome :%d down)" % args.cdp_port)
        return 2
    print("CDP_REACHABLE: True")
    if args.floor_a:
        _floor_a(args.floor_a, args.cdp_port)
        return 0

    print("== G3c RICHNESS-GATED :: depth=%d policy=%s gate(core>=%d,jac>=%.1f) "
          "value(novel>=%d,cov>=%.2f) ==" % (DEPTH, POLICY, GATE_CORE, GATE_JAC, K_NOVEL, COVERAGE_MIN))
    ctrl_items = list(CONTROLS.items())[:args.sites or None]
    rich_items = list(RICH.items())[:args.sites or None]
    print("-- CONTROLS (expect gate-out / no value-bar clear) --")
    controls = [r for r in (_eval_site(n, u, args.cdp_port, False) for n, u in ctrl_items) if r]
    print("-- RICH CANDIDATES --")
    rich = [r for r in (_eval_site(n, u, args.cdp_port, True) for n, u in rich_items) if r]
    rich = [r for r in rich if r["rich"]]   # drop frozen candidates that failed richness

    dec, why = verdict(controls, rich)
    print("\n== VERDICT: %s ==\n   %s" % (dec, why))
    print("   controls_clearing=%d rich_gated=%d rich_clearing=%d"
          % (sum(1 for r in controls if _clears(r)),
             sum(1 for r in rich if r["gated_in"]), sum(1 for r in rich if _clears(r))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
