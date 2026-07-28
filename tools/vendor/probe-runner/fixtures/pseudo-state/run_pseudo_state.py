#!/usr/bin/env python3
"""Host gate: web_skeleton --pseudo-states captures per-node resolved style deltas
under forced :hover / :focus / :active (CSS.forcePseudoState), and the pipeline redacts
them content-free. PROVES JOIN CORRECTNESS: the :hover node gets the RIGHT hover delta;
a :focus node gets an outline delta; the #menu:hover .child descendant gets the
combinator delta; a node with NO interactive rule gets NO delta (per-state isolation).
Deterministic, offline (local server). Runs on host CDP. bundle_writer.write_bundle
runs the firewall audit and RAISES on leak."""
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
from web_tokens import parse_color  # noqa: E402  (format-robust rgb compare)

# #known restyles under hover (color/bg) + focus (outline) + active (color).
# #static has NO interactive rule -> MUST get no pseudo_state delta.
# #menu:hover .child -> descendant-combinator restyle of #child.
_PAGE = """<!doctype html><meta charset=utf-8><title>pstate-gate</title>
<style>
 #known { width:120px; height:60px; color: rgb(10,20,30);
          background-color: rgb(200,200,200); outline-style: none; }
 #known:hover { color: rgb(0,128,0); background-color: rgb(17,17,17); }
 #known:focus { outline-style: solid; outline-color: rgb(255,0,0); outline-width: 3px; }
 #known:active { color: rgb(0,0,255); }
 #static { width:80px; height:40px; color: rgb(50,60,70);
           background-color: rgb(123,124,125); }
 #menu { width:200px; height:100px; }   /* explicit size, distinct from the three
           target bboxes below — the wrapper can never collide in _node_by_size */
 #menu:hover .child { color: rgb(123,45,67); }
 #child { width:40px; height:20px; color: rgb(1,2,3); }
</style>
<div id=known tabindex="0">k</div>
<div id=menu><div id=child class=child>c</div></div>
<div id=static>s</div>"""

# Identify emitted nodes by their fixed rendered bbox size (deterministic for this page;
# background-color lives in a stripped sidecar, not node["style"], so size is the key).
_SIZE = {"known": (120.0, 60.0), "static": (80.0, 40.0), "child": (40.0, 20.0)}
_SIZE_TOL = 2.0  # px


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

    # On-disk regression locks: backendNodeId is the INTERNAL join key (session-scoped +
    # mild fingerprint) and must NEVER reach disk. It is a bare int, so it trips NO
    # firewall content-pattern — these asserts over the real serialized bundle are the
    # only backstop. The per-node `pseudo_state` field IS expected (that's the feature).
    assert "_node_backend" not in sk, \
        "GATE FAIL: internal join-key sidecar _node_backend leaked to disk"
    assert "_node_pseudo_state" not in sk, \
        "GATE FAIL: internal carrier _node_pseudo_state leaked to disk"
    assert all("backend" not in n for n in nodes), \
        "GATE FAIL: per-node backendNodeId leaked to disk"

    known = _node_by_size(nodes, _SIZE["known"])
    assert known is not None and known.get("pseudo_state"), \
        "GATE FAIL: #known has no pseudo_state"
    ps = known["pseudo_state"]
    hov = ps.get("hover", {})
    assert parse_color(hov.get("color")) == (0, 128, 0), \
        f"GATE FAIL: wrong hover color delta: {hov.get('color')}"
    assert parse_color(hov.get("background-color")) == (17, 17, 17), \
        f"GATE FAIL: wrong hover bg delta: {hov.get('background-color')}"
    foc = ps.get("focus", {})
    assert foc.get("outline-style") == "solid", \
        f"GATE FAIL: focus outline-style not captured: {foc}"
    assert parse_color(foc.get("outline-color")) == (255, 0, 0), \
        f"GATE FAIL: wrong focus outline-color: {foc.get('outline-color')}"
    act = ps.get("active", {})
    assert parse_color(act.get("color")) == (0, 0, 255), \
        f"GATE FAIL: wrong active color delta: {act.get('color')}"

    child = _node_by_size(nodes, _SIZE["child"])
    assert child is not None and child.get("pseudo_state"), \
        "GATE FAIL: #child has no pseudo_state (descendant-combinator delta missing)"
    cps = child["pseudo_state"]
    assert parse_color(cps.get("hover", {}).get("color")) == (123, 45, 67), \
        f"GATE FAIL: wrong #child hover delta: {cps.get('hover')}"
    # Combinator specificity: #menu:hover .child fires ONLY under hover. #child has no
    # :focus/:active rule and forced :focus does not paint a UA outline on a non-tabindex
    # div (confirmed: #static stays clean), so #child must carry hover and nothing else.
    assert "focus" not in cps and "active" not in cps, \
        f"GATE FAIL: #child should restyle ONLY under hover (combinator specificity): {sorted(cps)}"

    static = _node_by_size(nodes, _SIZE["static"])
    assert static is not None, "GATE FAIL: #static node missing"
    assert not static.get("pseudo_state"), \
        f"GATE FAIL: #static got a spurious pseudo_state: {static.get('pseudo_state')}"

    print("GATE PASS: pseudo-state join correct (#known carries right hover/focus/"
          "active deltas; #child carries the descendant-combinator hover delta; #static "
          "isolated — no delta); backendNodeId never on disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "pseudo-state" / "_bundle"
    sk_json = ROOT / "fixtures" / "pseudo-state" / "_sk.json"
    tok_json = ROOT / "fixtures" / "pseudo-state" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url,
         "--pseudo-states", "hover,focus,active",
         "--out", str(sk_json)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print("web_skeleton FAILED:\n", r.stdout, r.stderr)
        sys.exit(1)

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "bundle_writer.py"),
         "--skeleton", str(sk_json),
         "--tokens", str(tok_json),
         "--out", str(out)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print("bundle_writer FAILED (content leak?):\n", r.stdout, r.stderr)
        sys.exit(1)

    _check(out)


if __name__ == "__main__":
    main()
