#!/usr/bin/env python3
"""G2 virtualization DE-RISK probe — measures NEW content-free STRUCTURE recovered by a
bounded scroll-settle sweep vs the engine's single REST DOMSnapshot.

Bar pre-registered (BEFORE data) in docs/plans/g2-virtualization-derisk.md. This probe only
MEASURES against that bar; it builds no sweep/merge engine and modifies no shipped script.

Basis (matches what a content-free BUILD would ship): a per-step UNION over the project's
content-free shape-key (probe_g3d_dedup._node_key). The load-bearing number is `new_shapes` =
distinct shape-keys present across the sweep but ABSENT from REST — genuinely new below-fold
structure, not just more instances of already-seen structure (a content-free engine dedups
identical instances anyway). Raw node growth is reported alongside for honesty, never alone.

G2-vs-G7a gate: only natively-scrollable pages (scrollHeight > innerHeight) are in-class; a
wrapper-virtualized page (sh<=ih forever) is a G7a case and is logged + excluded.

Runs on HOST Bash (CDP :9222, dangerouslyDisableSandbox=true). Memory: :9222 needs an open tab.
Usage: python3 probe_g2_virtualization.py [--cdp-port 9222] [--steps 8] [--max-wait 30]
"""
import argparse
import json
import shutil
import sys
import tempfile
import time
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import content_firewall as cf                     # audit_bundle(dir) -> violations
from probe_g3d_dedup import _node_key             # content-free shape-key (drop=() == full key)
import web_skeleton as WK                          # parse path, to_skeleton, enrich_aria
from _web_eval import resolve_web_eval, navigate   # transport + adaptive settle

# Pre-registered cohort (docs/plans/g2-virtualization-derisk.md). class: "virt" | "neg".
SITES = [
    {"id": "S1-youtube", "class": "virt",
     "urls": ["https://www.youtube.com", "https://www.youtube.com/watch?v=aqz-KE-bpKQ"]},
    {"id": "S2-reddit", "class": "virt",
     "urls": ["https://www.reddit.com/r/popular", "https://www.reddit.com/r/all"]},
    {"id": "S3-infinitescroll", "class": "virt",
     "urls": ["https://infinite-scroll.com/demo/full-page/"]},
    {"id": "N1-wikipedia", "class": "neg",
     "urls": ["https://en.wikipedia.org/wiki/Cat",
              "https://en.wikipedia.org/wiki/Photosynthesis"]},
]

# Pre-registered thresholds (locked).
PASS_FRAC = 0.30        # new_shape_frac floor for an in-class pass-site
PASS_ABS = 25           # new_shapes absolute floor (guards against key-split noise)
REPRO_MAX = 0.20        # max |Δnew_shapes|/new_shapes across a re-run
NEG_FRAC_MAX = 0.10     # negative control must stay below this
MIN_PASS_SITES = 2      # in-class pass-sites needed


def _shapes(nodes):
    """Set of content-free shape-keys for a node list (instances collapse by design)."""
    return {_node_key(n) for n in nodes}


def _node_count(ev):
    return int(ev.ev("document.getElementsByTagName('*').length"))


def _scrollable(ev):
    return ev.ev("({sh:document.documentElement.scrollHeight,ih:innerHeight,"
                 "sy:Math.round(window.scrollY)})")


def _set_scroll(ev, y):
    ev.ev("(function(y){var d=document.documentElement;d.style.scrollBehavior='auto';"
          "document.body.style.scrollBehavior='auto';window.scrollTo(0,y);"
          "return Math.round(window.scrollY);})(%d)" % int(y))


def _settle_nodecount(ev, max_wait=4.0, poll=0.3, stable_needed=2):
    """Poll #nodes until stable between consecutive reads (lazy mount converged) or cap."""
    last, stable = -1, 0
    deadline = time.monotonic() + max_wait
    while time.monotonic() < deadline:
        n = _node_count(ev)
        if n == last:
            stable += 1
            if stable >= stable_needed:
                return n
        else:
            stable = 0
        last = n
        time.sleep(poll)
    return last


def _snap_nodes(ev, url, reset):
    """No-navigate DOMSnapshot -> skeleton node dicts at the CURRENT scroll position.

    Faithful replica of web_skeleton._snapshot_skeleton's parse path (same WANT_STYLES,
    parse_snapshot, to_skeleton, enrich_aria) so shape-keys (incl. aria_role) are identical
    to the engine's REST capture. `reset` forces scrollTo(0) (REST baseline); the sweep
    steps pass reset=False to snapshot whatever has lazily mounted at the held offset."""
    if reset:
        ev.ev(WK._REST_JS)
        time.sleep(0.15)
    layout = ev.ev("({w: innerWidth, h: innerHeight, dpr: devicePixelRatio})")
    page = ev.ev("({w: document.documentElement.scrollWidth, "
                 "h: document.documentElement.scrollHeight})")
    ev.sess.send("DOMSnapshot.enable", {})
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": WK.WANT_STYLES,
                         "includeDOMRects": True, "includePaintOrder": True})
    eff_dpr = layout["dpr"] or 1.0
    recs = WK.parse_snapshot(snap, WK.WANT_STYLES, dpr=eff_dpr)
    svg_set, parent_index = set(), None
    for doc in snap["documents"]:
        svg_set |= WK.svg_descendants(doc, snap["strings"])
        if parent_index is None:
            parent_index = doc["nodes"]["parentIndex"]
    sk, ncol, nsty, npseu, nback = WK.to_skeleton(
        recs, svg_set, parent_index=parent_index, url=url,
        viewport={"w": layout["w"], "h": layout["h"], "dpr": eff_dpr},
        page={"w": page["w"], "h": page["h"]})
    sk["_node_colors"] = {str(k): v for k, v in ncol.items()}
    sk["_node_style"] = {str(k): v for k, v in nsty.items()}
    sk["_node_pseudo"] = {str(k): v for k, v in npseu.items()}
    WK.enrich_aria(sk["nodes"], nback, ev)
    return sk


def _firewall_violations(sk):
    """Audit what a content-free BUILD would actually SHIP, not the raw capture.

    The shipped skeleton.json is written by bundle_writer, which applies cf.redact_node
    (strips CONTENT_KEYS: text/src/href/alt/...) and drops the internal _node_colors/
    _node_style/_node_pseudo raw maps (consumed at packaging, never written raw). Auditing
    the raw to_skeleton sk would false-positive on pre-redaction content the engine removes.
    So audit the redacted node list — the same content-free artifact REST and every sweep
    step pass through. A violation here is a REAL leak the redaction path cannot remove.
    redact_node touches no field _node_key reads, so this never perturbs shape-keys."""
    d = Path(tempfile.mkdtemp(prefix="g2fw_"))
    try:
        shipped = {"nodes": [cf.redact_node(n) for n in sk["nodes"]]}
        (d / "skeleton.json").write_text(json.dumps(shipped))
        return cf.audit_bundle(d)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def _sweep(ev, url, steps):
    """One bounded scroll-settle sweep. Returns (peak_nodes, union_shapes_set, violations).
    union INCLUDES the per-step snapshots only (REST is unioned by the caller)."""
    peak, union, viol = 0, set(), []
    for i in range(steps):
        s = _scrollable(ev)
        target = min(s["sh"], int((i + 1) * s["ih"] * 0.9))
        _set_scroll(ev, target)
        _settle_nodecount(ev)
        sk = _snap_nodes(ev, url, reset=False)
        nodes = sk["nodes"]
        peak = max(peak, len(nodes))
        union |= _shapes(nodes)
        viol += _firewall_violations(sk)
        # bottom reached and content stopped growing -> stop early (bounded contract intact)
        s2 = _scrollable(ev)
        if s2["sy"] + s2["ih"] >= s2["sh"] - 2:
            break
    return peak, union, viol


def _measure(ev, engine, url, steps, max_wait):
    """REST baseline + sweep + a second FRESH-LOAD sweep for reproducibility. Returns a
    result dict or {'skip': reason} when the page is out-of-class / unscrollable."""
    rest = _snap_nodes(ev, url, reset=True)
    rest_nodes = rest["nodes"]
    s = _scrollable(ev)
    if s["sh"] <= s["ih"]:
        return {"skip": "not-scrollable (sh<=ih) -> G7a/full-render, out of G2 class",
                "sh": s["sh"], "ih": s["ih"]}
    rest_shapes = _shapes(rest_nodes)
    viol = _firewall_violations(rest)

    peak1, union1, v1 = _sweep(ev, url, steps)
    new1 = len(union1 - rest_shapes)
    # Reproducibility leg: a FULL reload (navigate), NOT a scrollTo(0) reset. A reset-only
    # second sweep leaves sweep1's append content still mounted, so new2≈new1 tautologically
    # (repro_delta→0 is then an artifact, not evidence). A fresh navigate tests what the bar
    # pre-registered: does a fixed-step sweep recover a STABLE new-shape set across loads?
    # (Feeds legitimately vary load-to-load -> high repro_delta; append pages reproduce.)
    navigate(ev, engine, url, max_wait=max_wait)
    rest2 = _snap_nodes(ev, url, reset=True)
    rest_shapes2 = _shapes(rest2["nodes"])
    peak2, union2, v2 = _sweep(ev, url, steps)
    new2 = len(union2 - rest_shapes2)
    viol += v1 + v2

    new_shapes = new1
    frac = new_shapes / max(1, len(rest_shapes))
    repro_delta = abs(new1 - new2) / max(1, new1)
    return {
        "rest_nodes": len(rest_nodes), "rest_shapes": len(rest_shapes),
        "sweep_peak_nodes": peak1, "peak_over_rest": round(peak1 / max(1, len(rest_nodes)), 2),
        "new_shapes": new_shapes, "new_shape_frac": round(frac, 3),
        "new_shapes_rerun": new2, "repro_delta": round(repro_delta, 3),
        "firewall_violations": len(viol),
        "sh": s["sh"], "ih": s["ih"],
    }


def _run_site(site, port, steps, max_wait):
    out = {"id": site["id"], "class": site["class"]}
    for url in site["urls"]:
        args = SimpleNamespace(browser="auto", url=url, android=False, ios=False,
                               cdp_port=port, serial=None)
        try:
            engine, ev, _dev = resolve_web_eval(args)
        except SystemExit as e:
            out["load"] = f"transport-fail: {e}"
            continue
        try:
            navigate(ev, engine, url, max_wait=max_wait)
            res = _measure(ev, engine, url, steps, max_wait)
            res["url"] = url
            if "skip" in res:
                # out-of-class at THIS url (e.g. consent-locked sh==ih). Record it, then
                # try the next PRE-REGISTERED fallback url — a skip is not a measurement.
                out.update(res)
                out["load"] = "ok"
                continue
            return {"id": site["id"], "class": site["class"], "load": "ok", **res}
        except Exception as e:                       # noqa: BLE001 - log + try next url
            out["load"] = f"error: {type(e).__name__}: {e}"
        finally:
            try:
                ev.close()
            except Exception:
                pass
    return out


def _verdict(rows):
    pass_sites, neg_fail, fw_fail = [], [], []
    for r in rows:
        if r.get("load") != "ok" or "new_shapes" not in r:
            continue
        if r.get("firewall_violations", 0) > 0:
            fw_fail.append(r["id"])
        if r["class"] == "virt":
            if (r["new_shape_frac"] >= PASS_FRAC and r["new_shapes"] >= PASS_ABS
                    and r["repro_delta"] <= REPRO_MAX):
                pass_sites.append(r["id"])
        elif r["class"] == "neg":
            if r["new_shape_frac"] >= NEG_FRAC_MAX:
                neg_fail.append(r["id"])
    ok = (len(pass_sites) >= MIN_PASS_SITES and not neg_fail and not fw_fail)
    return {
        "pass_sites": pass_sites, "neg_control_fail": neg_fail,
        "firewall_fail": fw_fail, "MIN_PASS_SITES": MIN_PASS_SITES,
        "verdict": "BUILD-JUSTIFIED" if ok else "DEFER",
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    ap.add_argument("--steps", type=int, default=8, help="bounded sweep step count")
    ap.add_argument("--max-wait", type=float, default=30.0, help="hydration settle cap (s)")
    a = ap.parse_args()
    rows = [_run_site(s, a.cdp_port, a.steps, a.max_wait) for s in SITES]
    verdict = _verdict(rows)
    print(json.dumps({"rows": rows, "verdict": verdict,
                      "bar": {"PASS_FRAC": PASS_FRAC, "PASS_ABS": PASS_ABS,
                              "REPRO_MAX": REPRO_MAX, "NEG_FRAC_MAX": NEG_FRAC_MAX}},
                     indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
