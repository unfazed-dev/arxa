#!/usr/bin/env python3
"""PROBE (throwaway diagnostic, host CDP only — run by controller with sandbox disabled).

Resolves the fixed-width `@container` design forks BEFORE the rung is designed, mirroring
the FS-series discipline that grounded form-state and the R-series that grounded Regime-3c.

THE GAP: Regime-3c (`capture_with_breakpoints`) re-evaluates `@container` ONLY for
viewport-TRACKING containers (a full-width block whose inline-size = the viewport, so
`Emulation.setDeviceMetricsOverride` resizes it). A FIXED-WIDTH query container
(`container-type: inline-size; width: 320px` — a sidebar, card, or grid track) does NOT
change size when the viewport resizes, so its `@container` rules never re-evaluate and
R3c misses them entirely (documented ceiling §C9-R-P11).

THE MECHANISM PROBLEM: there is NO CDP primitive to emulate CONTAINER size (unlike
`setDeviceMetricsOverride` for the viewport or `CSS.forcePseudoState` for pseudo-classes).
The ONLY content-free way to fire a fixed-width container's rules is to MUTATE the
container element's own size and let it reflow. Reading the authored `@container` rule
text would be the BLOCKED regime-4b. So mutation it is — and that is a first for this
project (every prior rung avoided DOM mutation). This probe answers, in ONE run, whether
that path is even viable:

  CQ1 DISCOVERY   — is `container-type` present in the DOMSnapshot computedStyles? (If we
                    cannot SEE which elements are query containers, we cannot target them.)
                    Expect: #cqi -> "inline-size", #cqs -> "size", plain div -> "normal".
  CQ2 JOIN       — *** THE KILL-SHOT *** does `backendNodeId` SURVIVE a non-navigate inline-
                    style mutation that reflows the page? R2's stability-across-viewport-
                    override does NOT transfer (mutation re-lays-out). If the base<->cond
                    join breaks, the whole approach is moot. Expect: descendant backendNodeIds
                    unchanged across the mutation.
  CQ3 RE-EVAL    — does width-mutation re-trigger `@container` evaluation in the CAPTURED
                    computed styles (not just the live render)? Expect: #cqi-child's font-
                    size/color/display move to the rule's values after #cqi is narrowed.
  CQ4 PROPS      — over a BROAD candidate set, which props actually MOVED -> CQ_PROPS
                    curation (the RESPONSIVE_PROPS discipline).
  CQ5 ARTIFACT   — resizing a container also reflows %-sized descendants by ordinary layout
                    (no CQ rule). Surface that (#cqi-pct) next to a real CQ restyle (#cqi-
                    child) so the design can state explicitly: isolate-CQ vs accept-whole-
                    reflow (R3c already accepts whole-reflow at viewport widths — consistent).
                    Also: a NESTED container (#cqi2) re-evals transitively when its ancestor
                    shrinks — confirm the delta lands on the nested descendant's own backend.
  CQ6 REVERT     — does clearing the inline width restore the base (so a per-container sweep
                    is reusable on ONE navigate)? Expect: empty delta after revert.
  CQ7 SIZE-2D    — does `container-type: size` (2D) fire on a height mutation, and does an
                    auto-height `size` container collapse its content? (advisor: scope the
                    rung to inline-size, treat size as a documented ceiling — confirm here.)

The page is synthetic/owned (no third-party content), so prop NAMES + node ids/tags + base-
vs-mutated value PAIRS are printed for diagnosis. Nothing here touches the shipping pipeline.

Host Bash (CDP; sandbox disabled):
    python3 research/capture-gap-probes/probe_container_query.py
"""
from __future__ import annotations
import argparse
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from _web_eval import add_transport_args, resolve_web_eval, DEFAULT_MAX_WAIT  # noqa: E402
import web_skeleton as ws  # noqa: E402
import _theme  # noqa: E402

# Broad candidate universe — let the probe CURATE which subset actually moves under a
# container query. `container-type` is INCLUDED so CQ1 can read it off the snapshot.
CQ_PROBE_PROPS = [
    "container-type", "container-name",
    "display", "flex-direction", "flex-wrap", "grid-template-columns",
    "grid-template-rows", "gap", "font-size", "line-height", "text-align",
    "padding-top", "padding-left", "margin-top", "margin-left",
    "width", "height", "color", "background-color", "visibility", "opacity",
]

# Synthetic page. FIXED-WIDTH containers (320 / 200) whose size is INDEPENDENT of the
# viewport — the exact case R3c cannot reach. box-sizing:border-box so a child's bbox is
# identifiable regardless of padding. Thresholds chosen so narrowing the container CROSSES
# them: #cqi 320 -> 200 crosses (max-width:250); nested #cqi2 (90% => 288 -> 180) crosses
# (max-width:200) TRANSITIVELY; #cqs (size) height 100 -> 40 crosses (max-height:50).
_PAGE = """<!doctype html><meta charset=utf-8><title>cq-probe</title>
<style>
 * { box-sizing: border-box; }
 #cqi { container-type: inline-size; width: 320px; }
 #cqi-child { display:block; font-size:20px; color:rgb(0,0,0); width:100px; height:30px; }
 @container (max-width:250px){ #cqi-child { display:flex; font-size:11px; color:rgb(10,20,30); } }
 #cqi-pct { width:50%; height:20px; font-size:15px; }
 #cqi2 { container-type: inline-size; width: 90%; }
 #cqi2-child { font-size:16px; width:60px; height:20px; }
 @container (max-width:200px){ #cqi2-child { font-size:8px; } }
 #cqs { container-type: size; width:200px; height:100px; }
 #cqs-child { font-size:14px; width:40px; height:15px; }
 @container (max-height:50px){ #cqs-child { font-size:7px; } }
 #vp { container-type: inline-size; }
 #vp-child { font-size:18px; width:70px; height:18px; }
 @container (max-width:600px){ #vp-child { font-size:9px; } }
 #nocq { width:120px; height:30px; font-size:15px; }
</style>
<div id=cqi><div id=cqi-child>a</div><div id=cqi-pct>p</div>
 <div id=cqi2><div id=cqi2-child>b</div></div></div>
<div id=cqs><div id=cqs-child>c</div></div>
<div id=vp><div id=vp-child>v</div></div>
<div id=nocq>n</div>"""


def _serve(page_bytes):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(page_bytes)))
            self.end_headers()
            self.wfile.write(page_bytes)

    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{srv.server_address[1]}/", srv


def _tag_by_backend(recs):
    """backendNodeId -> a 'tag#id' label, straight from snapshot records (element rows
    only). The probe page is synthetic, so the author id (when present) aids diagnosis."""
    out = {}
    for r in recs:
        b = r.get("backend")
        tag = r.get("tag") or ""
        if b is not None and tag and not tag.startswith("#") and not r.get("pseudo"):
            ident = r.get("id")
            out[b] = f"{tag}#{ident}" if ident else tag
    return out


def _snap(ev):
    """(styles_by_backend, tag_by_backend) at the page's CURRENT DOM state + REST."""
    recs = ws._snapshot_recs(ev, CQ_PROBE_PROPS)
    return _theme.styles_by_backend(recs), _tag_by_backend(recs)


def _report_delta(label, base, cond, tags, mutated_props):
    """Print which backends moved and (excluding the props we DIRECTLY mutated) which CSS
    props moved per node, with base->cond value pairs. mutated_props are flagged as
    artifacts of the mutation itself, not captured @container restyle."""
    delta = _theme.diff_theme(base, cond, CQ_PROBE_PROPS)
    print(f"  [{label}] nodes-with-delta = {len(delta)} "
          f"(tags: {sorted(tags.get(b, '?') for b in delta)})")
    moved = sorted({k for d in delta.values() for k in d})
    print(f"  [{label}] props-that-moved = {moved}")
    for be, d in sorted(delta.items()):
        lab = f"{tags.get(be, '?')} (backend:{be})"
        pairs = {k: (base.get(be, {}).get(k), v) for k, v in d.items()}
        flags = {k for k in d if k in mutated_props}
        note = f"  <-- mutated-artifact props: {sorted(flags)}" if flags else ""
        print(f"      {lab}: {pairs}{note}")
    return delta


def _set_width(ev, selector, px):
    """Force an element's inline width !important (beats author width) and return its live
    offsetWidth so we can confirm the resize took before re-snapshotting."""
    return ev.ev(
        "(function(){var e=document.querySelector(%r);"
        "e.style.setProperty('width','%dpx','important');return e.offsetWidth;})()"
        % (selector, px))


def _set_height(ev, selector, px):
    return ev.ev(
        "(function(){var e=document.querySelector(%r);"
        "e.style.setProperty('height','%dpx','important');return e.offsetHeight;})()"
        % (selector, px))


def _clear_inline(ev, selector):
    return ev.ev(
        "(function(){var e=document.querySelector(%r);"
        "e.removeAttribute('style');return e.offsetWidth;})()" % (selector,))


def main():
    p = argparse.ArgumentParser()
    add_transport_args(p)
    args = p.parse_args()

    base_url, _srv = _serve(_PAGE.encode())
    args.url = base_url
    if args.browser == "auto":
        args.browser = "chrome"

    engine, ev, device = resolve_web_eval(args)
    try:
        if not hasattr(ev, "sess"):
            print("PROBE ABORT: no CDP transport (need chrome host).")
            return 1

        ws._capture_one(ev, engine, base_url, max_wait=DEFAULT_MAX_WAIT)
        base, tags = _snap(ev)
        backset_base = set(base)
        print(f"device={device}  element-backends={len(tags)}")

        # CQ1 DISCOVERY — container-type read off the snapshot.
        print("\n=== CQ1 DISCOVERY: container-type per element (snapshot computedStyles) ===")
        for be, st in sorted(base.items()):
            ct = st.get("container-type")
            if ct and ct != "normal":
                print(f"  {tags.get(be, '?')} (backend:{be}): container-type={ct!r} "
                      f"container-name={st.get('container-name')!r}")
        any_ct = any((st.get("container-type") or "normal") != "normal"
                     for st in base.values())
        print(f"  CQ1 = {'OK (container-type visible in snapshot)' if any_ct else 'FAIL (container-type ABSENT — discovery impossible)'}")

        # CQ2/CQ3/CQ4/CQ5 — TARGETED resize of the fixed-width #cqi (320 -> 200, crosses 250).
        print("\n=== CQ2/3/4/5 TARGETED: narrow #cqi 320 -> 200px (crosses max-width:250) ===")
        live_w = _set_width(ev, "#cqi", 200)
        time.sleep(0.25)
        cond, _ = _snap(ev)
        print(f"  live #cqi offsetWidth after mutation = {live_w} (expect ~200)")

        # CQ2 KILL-SHOT: backendNodeId stability across the non-navigate mutation.
        backset_cond = set(cond)
        added = backset_cond - backset_base
        dropped = backset_base - backset_cond
        print(f"  CQ2 JOIN: base-backends={len(backset_base)} cond-backends={len(backset_cond)} "
              f"added={sorted(added)} dropped={sorted(dropped)}")
        cqi_child = next((b for b, t in tags.items() if t == "div#cqi-child"), None)
        cqi2_child = next((b for b, t in tags.items() if t == "div#cqi2-child"), None)
        print(f"  CQ2 JOIN: #cqi-child backend {cqi_child} present-in-cond="
              f"{cqi_child in backset_cond}; #cqi2-child backend {cqi2_child} present-in-cond="
              f"{cqi2_child in backset_cond}")
        print(f"  CQ2 = {'OK (no backend churn — join survives mutation)' if not added and not dropped else 'CHURN (see added/dropped — join AT RISK)'}")

        # CQ3/CQ4/CQ5: which nodes/props moved. width/height are the props we mutated.
        _report_delta("TARGETED #cqi", base, cond, tags, mutated_props={"width", "height"})
        print("  CQ3 watch: div#cqi-child font-size 20->11, color, display block->flex = REAL @container restyle")
        print("  CQ5 watch: div#cqi2-child font-size 16->8 = TRANSITIVE nested re-eval (ancestor shrank)")
        print("  CQ5 watch: div#cqi-pct width change = %-sized layout ARTIFACT (no cq rule)")

        # CQ6 REVERT — clear inline style, confirm base restored.
        print("\n=== CQ6 REVERT: clear #cqi inline style, expect empty delta vs base ===")
        _clear_inline(ev, "#cqi")
        time.sleep(0.25)
        restored, _ = _snap(ev)
        rev_delta = _theme.diff_theme(base, restored, CQ_PROBE_PROPS)
        print(f"  CQ6 = {'OK (base restored, delta empty)' if not rev_delta else 'RESIDUE: ' + str({tags.get(b,'?'): list(d) for b, d in rev_delta.items()})}")

        # CQ7 SIZE-2D — height mutation on a `container-type: size` container.
        print("\n=== CQ7 SIZE-2D: shrink #cqs height 100 -> 40px (crosses max-height:50) ===")
        live_h = _set_height(ev, "#cqs", 40)
        time.sleep(0.25)
        cond2, _ = _snap(ev)
        print(f"  live #cqs offsetHeight after mutation = {live_h} (expect ~40)")
        _report_delta("SIZE #cqs", restored, cond2, tags, mutated_props={"width", "height"})
        print("  CQ7 watch: div#cqs-child font-size 14->7 = size-container fired on HEIGHT;")
        print("             treat container-type:size as a documented ceiling per advisor (auto-dim collapse).")
        _clear_inline(ev, "#cqs")
        return 0
    finally:
        ev.close()


if __name__ == "__main__":
    raise SystemExit(main())
