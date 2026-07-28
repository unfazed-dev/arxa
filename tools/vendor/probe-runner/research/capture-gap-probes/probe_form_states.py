#!/usr/bin/env python3
"""PROBE (throwaway diagnostic, host CDP only — run by controller with sandbox disabled).

Resolves the form-state (:checked/:disabled) design forks BEFORE the rung is designed,
mirroring the F-series discipline that grounded Regime-3b. Drives a synthetic offline page
and answers, in ONE run:

  Q1 ACCEPTANCE  — does this Chrome's CSS.forcePseudoState accept the bare strings
                   "checked" / "disabled" in forcedPseudoClasses (no exception)?
  Q2 DELTA       — forcing :checked on an UNCHECKED <input> and :disabled on an ENABLED
                   <button> overrides the match regardless of DOM state, so author
                   `input:checked{}` / `button:disabled{}` rules apply and produce a delta.
                   (This is the real gate — not string-acceptance.)
  Q3 ISOLATION   — a form control with NO state rule (#cb2) gets NO delta; a plain <div>
                   with no rule gets NO delta; a BARE `:disabled{}` rule reveals whether
                   forcePseudoState smears :disabled onto a non-disableable <div>.
  Q4 FORM_PROPS  — over a BROAD candidate prop set, report which props actually MOVED
                   (MOTION_PROPS curation discipline). FORM_PROPS := what moved.

The page is synthetic/owned (no third-party content), so prop NAMES + node ids/tags + base
vs forced value PAIRS are printed for diagnosis. Nothing here touches the shipping pipeline.

Host Bash (CDP; sandbox disabled):
    python3 research/capture-gap-probes/probe_form_states.py
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

# Broad candidate universe — let the probe CURATE which subset actually moves.
FORM_PROBE_PROPS = [
    "opacity", "cursor", "accent-color",
    "color", "background-color",
    "border-top-color", "border-top-width", "border-top-style",
    "outline-style", "outline-width", "outline-color", "outline-offset",
    "box-shadow", "filter", "transform", "visibility", "display",
    "text-decoration-line",
]

# Synthetic page:
#   #cb   unchecked checkbox WITH a self :checked rule + a COMBINATOR rule onto #sib  -> Q2/Q5
#   #sib  plain div restyled ONLY via `#cb:checked ~ #sib` (NOT forced)  -> Q5 (toggle combinator)
#   #cb2  unchecked checkbox with NO :checked rule                       -> Q3 (control isolation)
#   #txt  text input (NOT checkable) + a bare `input:checked{}` rule     -> Q3 (type-smear: must
#                                                                            NOT be forced/lit)
#   #btn  enabled button WITH a button:disabled rule                     -> Q2 (disabled delta)
#   #plain plain div, no rule                                            -> Q3 (no-rule isolation)
#   #div2  plain div; a BARE `:disabled{}` rule exists                   -> Q3 (smear onto div?)
_PAGE = """<!doctype html><meta charset=utf-8><title>form-state-probe</title>
<style>
 input#cb:checked  { opacity:.5; background-color: rgb(10,20,30); accent-color: rgb(11,22,33);
                     outline: 2px solid rgb(1,2,3); }
 #cb:checked ~ #sib { background-color: rgb(70,80,90); }   /* TOGGLE COMBINATOR -> sibling div */
 input:checked      { color: rgb(5,5,5); }                 /* bare-ish: would smear onto #txt if forced */
 button#btn:disabled { opacity:.4; cursor: not-allowed; background-color: rgb(40,50,60);
                       color: rgb(60,70,80); border-top-color: rgb(7,8,9); }
 :disabled         { outline: 3px solid rgb(9,9,9); }   /* bare — smear probe onto #div2 */
 div { width:50px; height:20px; }
</style>
<input type=checkbox id=cb>
<div id=sib></div>
<input type=checkbox id=cb2>
<input type=text id=txt>
<button id=btn>b</button>
<div id=plain></div>
<div id=div2></div>"""

# Eligibility selectors — the design's force-set (encodes the state-eligible element types).
FORM_STATE_SELECTORS = {
    "checked": "input[type=checkbox], input[type=radio], option",
    "disabled": "input, button, select, textarea, fieldset, optgroup, option",
}


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
    """backendNodeId -> TAG, straight from snapshot records (reliable; the DOM.requestNode
    round-trip returned nothing here). Element rows only."""
    out = {}
    for r in recs:
        b = r.get("backend")
        tag = r.get("tag") or ""
        if b is not None and tag and not tag.startswith("#") and not r.get("pseudo"):
            out[b] = tag
    return out


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

        sk, _layout, _page, node_backend = ws._capture_one(ev, engine, base_url,
                                                            max_wait=DEFAULT_MAX_WAIT)
        recs = ws._snapshot_recs(ev, FORM_PROBE_PROPS)
        base = _theme.styles_by_backend(recs)
        tags = _tag_by_backend(recs)

        ev.sess.send("DOM.enable", {})
        ev.sess.send("CSS.enable", {})
        doc = ev.sess.send("DOM.getDocument", {"depth": -1, "pierce": True})
        root = doc["root"]["nodeId"]

        print(f"device={device}  element-backends={len(tags)}")

        for state in ("checked", "disabled"):
            sel = FORM_STATE_SELECTORS[state]
            found = ev.sess.send("DOM.querySelectorAll", {"nodeId": root, "selector": sel})
            force_ids = [nid for nid in (found.get("nodeIds") or []) if nid]
            accept_err = None
            for nid in force_ids:
                try:
                    ev.sess.send("CSS.forcePseudoState",
                                 {"nodeId": nid, "forcedPseudoClasses": [state]})
                except Exception as e:
                    accept_err = type(e).__name__ + ": " + str(e)[:120]
                    break
            time.sleep(0.2)
            print(f"\n[:{state}] selector={sel!r}  forced-eligible-nodes={len(force_ids)}")
            if accept_err:
                print(f"[:{state}] Q1 ACCEPTANCE = REJECTED -> {accept_err}")
            else:
                cond = _theme.styles_by_backend(ws._snapshot_recs(ev, FORM_PROBE_PROPS))
                delta = _theme.diff_theme(base, cond, FORM_PROBE_PROPS)
                print(f"[:{state}] Q1 ACCEPTANCE = OK (no exception)")
                print(f"[:{state}] nodes-with-delta = {len(delta)} "
                      f"(tags: {sorted(tags.get(b, '?') for b in delta)})")
                moved_props = sorted({k for d in delta.values() for k in d})
                print(f"[:{state}] Q4 props-that-moved = {moved_props}")
                for be, d in delta.items():
                    lab = f"{tags.get(be, '?')} (backend:{be})"
                    pairs = {k: (base.get(be, {}).get(k), v) for k, v in d.items()}
                    print(f"    {lab}: {pairs}")
            for nid in force_ids:
                try:
                    ev.sess.send("CSS.forcePseudoState",
                                 {"nodeId": nid, "forcedPseudoClasses": []})
                except Exception:
                    pass
        return 0
    finally:
        ev.close()


if __name__ == "__main__":
    raise SystemExit(main())
