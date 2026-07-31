#!/usr/bin/env python3
"""Host gate: web_skeleton --reduced-motion captures the per-node computed-style delta under
emulated prefers-reduced-motion:reduce, and the pipeline redacts it content-free. PROVES: a
node that declares an animation + transition + scroll-behavior (#known) carries the reduce
delta (animation-name->none, animation-duration->0s, transition-duration->0s,
scroll-behavior->auto); a node with no motion declarations (#static) gets NO reduced_motion
field (isolation); and the internal join keys never reach disk. Deterministic, offline (local
server). bundle_writer.write_bundle runs the firewall audit and RAISES on leak.

Two fixture facts: #known animates via translateX (NOT rotate/scale) so its rendered w/h stays
40x40 and it is identifiable by bbox even mid-animation; scroll-behavior is declared ON #known
(not an ancestor) because scroll-behavior is not inherited — the delta lands on the declaring
node."""
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

_PAGE = """<!doctype html><meta charset=utf-8><title>rm-gate</title>
<style>
 /* translateX (NOT rotate/scale): axis-aligned move keeps rendered w/h at 40x40 so #known
    is bbox-identifiable mid-animation. scroll-behavior declared ON #known (not inherited). */
 @keyframes drift { from { transform: translateX(0);} to { transform: translateX(60px);} }
 #known  { animation: drift 2s linear infinite; transition: opacity .5s ease;
           scroll-behavior: smooth; width:40px; height:40px; }
 #static { width:80px; height:40px; }
 @media (prefers-reduced-motion: reduce) {
   #known { animation: none; transition: none; scroll-behavior: auto; }
 }
</style>
<div id=known></div><div id=static></div>"""

_SIZE = {"known": (40.0, 40.0), "static": (80.0, 40.0)}
_SIZE_TOL = 2.0


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
    raw = (Path(bundle_dir) / "skeleton.json").read_text()
    sk = json.loads(raw)
    nodes = sk.get("nodes") or []

    assert "_node_reduced_motion" not in sk, "GATE FAIL: internal carrier _node_reduced_motion leaked to disk"
    assert "_node_backend" not in sk, "GATE FAIL: internal join-key _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), "GATE FAIL: per-node backendNodeId leaked to disk"

    known = _node_by_size(nodes, _SIZE["known"])
    assert known is not None and known.get("reduced_motion"), "GATE FAIL: #known has no reduced_motion delta"
    rd = known["reduced_motion"]["reduce"]
    assert rd.get("animation-name") == "none", f"GATE FAIL: #known animation-name not suppressed: {rd}"
    assert rd.get("animation-duration") == "0s", f"GATE FAIL: #known animation-duration not 0s: {rd}"
    assert rd.get("scroll-behavior") == "auto", f"GATE FAIL: #known scroll-behavior not auto: {rd}"
    assert rd.get("transition-duration") == "0s", f"GATE FAIL: #known transition-duration not 0s: {rd}"

    static = _node_by_size(nodes, _SIZE["static"])
    assert static is not None, "GATE FAIL: #static node missing"
    assert not static.get("reduced_motion"), \
        f"GATE FAIL: #static got a spurious reduced_motion field (isolation): {static.get('reduced_motion')}"

    print("GATE PASS: reduced-motion delta correct (#known: animation-name->none, "
          "animation-duration->0s, transition-duration->0s, scroll-behavior->auto; #static "
          "isolated — no field); backendNodeId never on disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "reduced-motion" / "_bundle"
    sk_json = ROOT / "fixtures" / "reduced-motion" / "_sk.json"
    tok_json = ROOT / "fixtures" / "reduced-motion" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--reduced-motion", "--out", str(sk_json)],
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
