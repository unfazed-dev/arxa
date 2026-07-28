#!/usr/bin/env python3
"""aria_role recurrence probe (ARIA-enrichment rung de-risk). NOT a gated CLI, NOT in the
unit suite. De-risks the ONE open axis before any core-file build: does attaching a
content-free computed ARIA role (CDP Accessibility.getFullAXTree) to each skeleton node
actually improve cross-route component-signature RECURRENCE -- or only distinctiveness
(which §C9-R-G3c-calib already showed was fine)? Recurrence was the bottleneck (py jac
0.34, iana core=1); aria_role is unproven on that axis. Measure, don't assume.

Hypothesis: semantic anchors (a few dozen navigation/article/list roots) beat the
role-only/styled anchors (thousands of unknown_box) on signal-to-noise -> higher core/jac.

Approach (advisor): capture DOMSnapshot + getFullAXTree in ONE CDP session, join the
computed role onto each node IN-MEMORY via the internal backendNodeId (`node_backend`,
dropped at emit -> can't be done post-hoc from disk bundles), then re-run the G3c
calibration's signature machinery with an aria anchor + aria-labelled token, and compare
to the styled/enriched baseline on the SAME nodes.

CONTENT-FREE: only the AX `role.value` is read (canonicalized to a fixed W3C role set;
author-custom role= -> "other"; NEVER name/description/value -> those are accessible-name =
content). aria_role is a short structural token. The probe also writes the enriched
skeletons to a tempdir and runs content_firewall.audit_bundle to PROVE the new field does
not trip the firewall. REPORT emits counts / ratios / role NAMES / role-tree strings only;
never subprocess output, never an AX name.

Run on host Bash (CDP :9222 reachable):
  --capture URLS    capture+enrich+analyse a comma list of same-host routes
  --floor-a URL     capture URL twice -> aria signatures must be identical (determinism)
"""
import argparse
import json
import shutil
import socket
import sys
import tempfile
from argparse import Namespace
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import calib_component_signature as C  # noqa: E402  reuse pure signature machinery
import web_skeleton as W  # noqa: E402  _capture_one (navigate+REST+DOMSnapshot+parse)
from _web_eval import resolve_web_eval  # noqa: E402  (engine, ev, device) transport

# Fixed standard-ARIA role allowlist. A computed role outside this set (incl. arbitrary
# author role= text) canonicalizes to "other" -- the content-safety boundary.
CANON = {
    # landmarks
    "banner", "navigation", "main", "contentinfo", "complementary", "region", "search", "form",
    # document structure
    "heading", "list", "listitem", "article", "table", "row", "cell", "columnheader",
    "rowheader", "grid", "gridcell", "rowgroup", "figure", "img", "image", "group",
    "document", "paragraph", "caption", "definition", "term", "separator", "list", "note",
    "directory", "feed", "math", "presentation", "none", "blockquote", "code", "time",
    # widgets
    "button", "link", "checkbox", "radio", "radiogroup", "textbox", "searchbox", "combobox",
    "listbox", "option", "slider", "spinbutton", "switch", "tab", "tablist", "tabpanel",
    "menu", "menubar", "menuitem", "menuitemcheckbox", "menuitemradio", "progressbar",
    "scrollbar", "tooltip", "tree", "treeitem", "treegrid", "dialog", "alertdialog",
    "alert", "status", "log", "marquee", "timer", "meter", "disclosure", "toolbar",
}


def canon(r):
    return r if r in CANON else "other"


# Landmark/region roles: the clean component-root anchor the probe unlocks (NOT all-aria
# nodes, which over-select per-link/listitem trivia that recurs on any site).
LANDMARK_ARIA = {"navigation", "banner", "main", "contentinfo", "complementary", "region",
                 "search", "form", "article", "dialog", "menubar", "tablist", "toolbar"}


# ------------------------------ aria-aware signature ------------------------------
def aria_token(n):
    """Enriched design token (reused) PREFIXED with the canonical aria role when present.
    aria_role is the semantic anchor the hypothesis rests on."""
    base = C.node_token(n, enrich=True)
    ar = n.get("aria_role")
    return ("%s@%s" % (ar, base)) if ar else base


def _plain_token(n):
    """Control token: the SAME enriched design axes WITHOUT the aria_role prefix. Isolates
    whether aria_role-as-label carries recurring-structure signal vs the anchor selecting
    trivia."""
    return C.node_token(n, enrich=True)


def _aria_roots(nodes, by_parent):
    return [n for n in nodes if n.get("aria_role") and by_parent.get(n["id"])]


def _landmark_roots(nodes, by_parent):
    return [n for n in nodes
            if n.get("aria_role") in LANDMARK_ARIA and by_parent.get(n["id"])]


def _sigs(nodes, depth, policy, roots_fn, tok_fn):
    by_parent = C._children(nodes)
    tok = {n["id"]: tok_fn(n) for n in nodes}
    roots = roots_fn(nodes, by_parent)
    return Counter(C.signature(n, by_parent, tok, depth, policy) for n in roots)


def route_aria_sigs(nodes, depth, policy):
    return _sigs(nodes, depth, policy, _aria_roots, aria_token)


# ------------------------------ capture + AX join (host CDP) ------------------------------
def _cdp_reachable(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=2):
            return True
    except OSError:
        return False


def _ax_role_by_backend(ev):
    """{backendDOMNodeId: canonical_role} from getFullAXTree, skipping ignored nodes and
    reading ONLY role.value (never name/description). Defensive against shape drift."""
    try:
        ev.sess.send("Accessibility.enable", {})
    except Exception:  # noqa: BLE001  enable is best-effort; getFullAXTree often works alone
        pass
    ax = ev.sess.send("Accessibility.getFullAXTree", {}) or {}
    out = {}
    for n in ax.get("nodes", []):
        if n.get("ignored"):
            continue
        bk = n.get("backendDOMNodeId")
        role = (n.get("role") or {}).get("value")
        if bk is not None and role:
            out[bk] = canon(role)
    return out


def _capture_enriched(ev, engine, url):
    """Capture skeleton + join aria_role onto each node in-memory. Returns the node list
    (each node gains node['aria_role'] = canonical role or None)."""
    sk, _layout, _page, node_backend = W._capture_one(ev, engine, url)
    role_by_backend = _ax_role_by_backend(ev)
    for node in sk["nodes"]:
        bk = node_backend.get(node["id"])
        node["aria_role"] = role_by_backend.get(bk)  # None if no/ignored AX node
    return sk["nodes"]


def _resolve(url, port):
    ns = Namespace(url=url, browser="chrome", cdp_port=port, ios=False, android=False,
                   serial=None)
    return resolve_web_eval(ns)  # (engine, ev, device)


def _audit_inmemory(per_route_nodes):
    """Write enriched skeletons to a tempdir + audit_bundle -> proves aria_role is
    firewall-clean. Returns (clean, violations)."""
    import content_firewall as cf
    tmp = Path(tempfile.mkdtemp(prefix="aria_audit_"))
    try:
        for i, nodes in enumerate(per_route_nodes):
            (tmp / ("r%02d_skeleton.json" % i)).write_text(
                json.dumps({"nodes": nodes}, indent=2))
        viol = cf.audit_bundle(tmp)
        return (not viol), len(viol)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ------------------------------ analysis / report ------------------------------
def _report_sweep(label, per_route_nodes, sig_fn):
    sets = [set(sig_fn(nodes)) for nodes in per_route_nodes]
    m = C.recurrence(sets)
    print("  %-22s distinct=%-4d core=%-3d shared=%-3d unique=%-4d jac=%s"
          % (label, m["distinct"], len(m["core"]), len(m["shared_ge2_not_core"]),
             len(m["unique"]), m["jac"]))
    return m


def analyse(per_route_nodes):
    n = len(per_route_nodes)
    print("  routes analysed: %d" % n)
    # (1) aria coverage + distribution (the signal-to-noise hypothesis)
    total = sum(len(nodes) for nodes in per_route_nodes)
    have = sum(1 for nodes in per_route_nodes for x in nodes if x.get("aria_role"))
    dist = Counter(x.get("aria_role") for nodes in per_route_nodes for x in nodes
                   if x.get("aria_role"))
    print("  aria_role coverage: %d/%d nodes (%.0f%%) ; distinct aria roles: %d"
          % (have, total, 100.0 * have / max(total, 1), len(dist)))
    print("  top aria roles: %s" % ", ".join("%s=%d" % (r, c) for r, c in dist.most_common(15)))
    other = dist.get("other", 0)
    print("  'other' (non-standard/author-custom, canonicalized): %d" % other)

    # (2) firewall safety of the new field
    clean, nviol = _audit_inmemory(per_route_nodes)
    print("  audit (enriched skeleton.json): %s (violations=%d)"
          % ("CLEAN" if clean else "DIRTY", nviol))

    # (3) recurrence — the CONFOUND control. Three rows per depth:
    #   aria-anchor + aria-label   : the headline (anchor + label both changed)
    #   aria-anchor + PLAIN token  : strip the aria@ prefix -> if ~unchanged, the win is
    #                                the anchor selecting trivia (links/listitems), not the label
    #   landmark-anchor + aria-label: the clean signal NOT inflated by per-link trivia
    print("  -- recurrence (distinct / core / shared / unique / jac) --")
    for depth in (1, 2):
        _report_sweep("aria-anchor  aria-tok d%d" % depth, per_route_nodes,
                      lambda nodes, d=depth: _sigs(nodes, d, "collapse", _aria_roots, aria_token))
        _report_sweep("aria-anchor  PLAIN   d%d" % depth, per_route_nodes,
                      lambda nodes, d=depth: _sigs(nodes, d, "collapse", _aria_roots, _plain_token))
        _report_sweep("landmark-anch aria   d%d" % depth, per_route_nodes,
                      lambda nodes, d=depth: _sigs(nodes, d, "collapse", _landmark_roots, aria_token))

    # (4) identity: LANDMARK anchor (the clean signal) core/shared/unique STRINGS
    sets = [set(_sigs(nodes, 2, "collapse", _landmark_roots, aria_token))
            for nodes in per_route_nodes]
    m = C.recurrence(sets)
    print("  -- identity check: LANDMARK anchor, aria-tok, collapse d2 --")
    print("  CORE (all %d routes) [up to 30]:" % n)
    for s in sorted(m["core"])[:30]:
        print("    %s" % C._trunc(s))
    print("  SHARED (>=2, not all) [sample]:")
    for s in sorted(m["shared_ge2_not_core"])[:8]:
        print("    %s" % C._trunc(s))
    print("  UNIQUE [sample]:")
    for s in sorted(m["unique"])[:5]:
        print("    %s" % C._trunc(s))


def _capture_routes(urls, port):
    if not _cdp_reachable(port):
        print("CDP_REACHABLE: False (Chrome :%d down)" % port)
        return None
    print("CDP_REACHABLE: True")
    engine, ev, _device = _resolve(urls[0], port)
    per_route = []
    for u in urls:
        try:
            per_route.append(_capture_enriched(ev, engine, u))
        except Exception as e:  # noqa: BLE001  report category only, never page bytes
            print("  capture failed for a route: %s" % type(e).__name__)
    return per_route


def cmd_capture(urls, port):
    per_route = _capture_routes(urls, port)
    if per_route:
        analyse(per_route)


def cmd_floor_a(url, port):
    per_route = _capture_routes([url, url], port)
    if not per_route or len(per_route) < 2:
        print("FLOOR_A: <2 captures")
        return
    a = set(route_aria_sigs(per_route[0], 2, "collapse"))
    b = set(route_aria_sigs(per_route[1], 2, "collapse"))
    print("FLOOR_A determinism (aria anchor, same URL x2): identical=%s |A|=%d |B|=%d jac=%s"
          % (a == b, len(a), len(b), round(C._jaccard(a, b), 3)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--capture")
    ap.add_argument("--floor-a")
    ap.add_argument("--cdp-port", type=int, default=9222)
    args = ap.parse_args()
    if args.floor_a:
        cmd_floor_a(args.floor_a, args.cdp_port)
    elif args.capture:
        cmd_capture([u.strip() for u in args.capture.split(",") if u.strip()], args.cdp_port)
    else:
        ap.error("one of --capture / --floor-a required")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
