#!/usr/bin/env python3
"""Host gate: web_skeleton --form-states captures the per-node computed-style delta when form
controls are forced into :checked / :disabled, and the pipeline redacts it content-free. PROVES:
a checkbox with an input:checked rule (#cb) carries the checked delta; a CSS-toggle combinator
(`#cb:checked ~ #panel`) lands the delta on the PANEL node (FS5 — the dominant :checked use); a
button with a button:disabled rule (#btn) carries the disabled delta (opacity/cursor/bg); a plain
div + a bare `:disabled{}` rule gets NO form_state field (FS3 smear-negative — proves targeting);
a text input + a bare-ish `input:checked{}` rule gets NO checked field (type-targeting); and the
internal join keys never reach disk. Deterministic, offline (local server). bundle_writer
runs the firewall audit and RAISES on leak.

Nodes are identified by distinct rendered bbox size (the motion-gate convention). The on-disk
bbox is the BASE capture (FORM_PROPS has no geometry), so forcing a state cannot move it."""
from __future__ import annotations
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

_PAGE = """<!doctype html><meta charset=utf-8><title>form-state-gate</title>
<style>
 /* border-box: form controls render at border-box, so declared w/h == rendered bbox even with
    UA padding/border on <button>/<input> (else content-box inflates them past _SIZE_TOL and
    _node_by_size misses them). FORM_PROPS has no geometry + on-disk bbox is the unforced base
    capture, so forcing a state never moves these. */
 * { box-sizing: border-box; }
 #cb     { width:30px; height:30px; }
 #panel  { width:55px; height:25px; }             /* combinator target (NOT forced) */
 #btn    { width:90px; height:24px; }
 #txt    { width:120px; height:22px; }
 #plain  { width:44px; height:44px; }
 input#cb:checked    { opacity:.5; background-color: rgb(10,20,30); accent-color: rgb(11,22,33); }
 #cb:checked ~ #panel { background-color: rgb(70,80,90); }      /* TOGGLE COMBINATOR -> #panel */
 input:checked        { color: rgb(5,5,5); }       /* bare-ish: must NOT reach #txt (type-target) */
 button#btn:disabled  { opacity:.4; cursor: not-allowed; background-color: rgb(40,50,60); }
 :disabled            { outline: 3px solid rgb(9,9,9); }   /* bare: must NOT reach #plain */
</style>
<input type=checkbox id=cb>
<div id=panel></div>
<input type=text id=txt>
<button id=btn>b</button>
<div id=plain></div>"""

_SIZE = {"cb": (30.0, 30.0), "panel": (55.0, 25.0), "btn": (90.0, 24.0),
         "txt": (120.0, 22.0), "plain": (44.0, 44.0)}
_SIZE_TOL = 3.0


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


def _node_by_size(nodes, wh):
    tw, th = wh
    for n in nodes:
        b = n.get("bbox") or {}
        if abs(b.get("w", -1) - tw) <= _SIZE_TOL and abs(b.get("h", -1) - th) <= _SIZE_TOL:
            return n
    return None


def _check(bundle_dir):
    sk = json.loads((Path(bundle_dir) / "skeleton.json").read_text())
    nodes = sk.get("nodes") or []

    assert "_node_form_state" not in sk, "GATE FAIL: internal carrier _node_form_state leaked to disk"
    assert "_node_backend" not in sk, "GATE FAIL: internal join-key _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), "GATE FAIL: per-node backendNodeId leaked to disk"

    cb = _node_by_size(nodes, _SIZE["cb"])
    assert cb is not None and cb.get("form_state"), "GATE FAIL: #cb has no form_state delta"
    ck = cb["form_state"]["checked"]
    assert ck.get("opacity") == "0.5", f"GATE FAIL: #cb checked opacity: {ck}"
    assert ck.get("accent-color") == "rgb(11, 22, 33)", f"GATE FAIL: #cb checked accent-color: {ck}"

    panel = _node_by_size(nodes, _SIZE["panel"])
    assert panel is not None and panel.get("form_state"), \
        "GATE FAIL: combinator sibling #panel has no form_state delta (FS5 toggle-combinator)"
    assert panel["form_state"]["checked"].get("background-color") == "rgb(70, 80, 90)", \
        f"GATE FAIL: #panel combinator delta wrong: {panel['form_state']}"

    btn = _node_by_size(nodes, _SIZE["btn"])
    assert btn is not None and btn.get("form_state"), "GATE FAIL: #btn has no form_state delta"
    ds = btn["form_state"]["disabled"]
    assert ds.get("opacity") == "0.4", f"GATE FAIL: #btn disabled opacity: {ds}"
    assert ds.get("cursor") == "not-allowed", f"GATE FAIL: #btn disabled cursor: {ds}"

    plain = _node_by_size(nodes, _SIZE["plain"])
    assert plain is not None, "GATE FAIL: #plain node missing"
    assert not plain.get("form_state"), \
        f"GATE FAIL: #plain (a div) got a form_state field — bare :disabled{{}} smeared (FS3): {plain.get('form_state')}"

    txt = _node_by_size(nodes, _SIZE["txt"])
    assert txt is not None, "GATE FAIL: #txt node missing"
    assert not (txt.get("form_state") or {}).get("checked"), \
        f"GATE FAIL: #txt (text input) got a checked field — input:checked smeared (type-targeting): {txt.get('form_state')}"

    print("GATE PASS: form-state delta correct (#cb checked opacity/accent-color; #panel "
          "combinator background-color; #btn disabled opacity/cursor; #plain div NO field — "
          "no bare-rule smear; #txt no checked field — type-targeted); backendNodeId never on "
          "disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "form-state" / "_bundle"
    sk_json = ROOT / "fixtures" / "form-state" / "_sk.json"
    tok_json = ROOT / "fixtures" / "form-state" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--form-states", "--out", str(sk_json)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print(f"web_skeleton FAILED (rc={r.returncode}) — re-run manually to inspect output")
        sys.exit(1)

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "bundle_writer.py"),
         "--skeleton", str(sk_json), "--tokens", str(tok_json), "--out", str(out)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print(f"bundle_writer FAILED (rc={r.returncode}) — content leak caught by firewall audit")
        sys.exit(1)

    _check(out)


if __name__ == "__main__":
    main()
