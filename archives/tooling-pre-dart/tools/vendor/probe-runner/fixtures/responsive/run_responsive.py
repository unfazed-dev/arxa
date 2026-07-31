#!/usr/bin/env python3
"""Host gate: web_skeleton --breakpoints captures per-node resolved-style REFLOW deltas
across viewport widths (Emulation.setDeviceMetricsOverride, NO re-navigate), and the
pipeline redacts them content-free. PROVES JOIN CORRECTNESS: the @media node gets the
RIGHT narrow-width display/flex/font-size delta; a clamp() node's font-size re-resolves;
a viewport-tracking @container node re-evals ONLY at the width where its container drops
below threshold (design §6 / probe R7); a node with NO responsive rule gets NO delta
(per-width isolation); a grid-template
change with author-named lines flows through the firewall (caught-not-silent — a SILENT
prose leak would trip audit_bundle and FAIL this gate loudly). Deterministic, offline
(local server). Runs on host CDP. bundle_writer.write_bundle runs the firewall audit and
RAISES on leak."""
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

# Base = widest (1200). @media (max-width:600px) fires at the narrow widths (400 + 280);
# @container (max-width:300px) on a viewport-tracking container fires only at 280 (the
# container is a full-width block ~= viewport, so ~280 < 300 but ~400 > 300). Fixed px
# sizes (width/height) so nodes are identifiable by bbox regardless of viewport.
_PAGE = """<!doctype html><meta charset=utf-8><title>resp-gate</title>
<style>
 #known { display:flex; flex-direction:row; font-size:24px; width:300px; height:50px; }
 @media (max-width:600px){ #known { display:block; flex-direction:column; font-size:12px; } }
 #fluid  { font-size: clamp(10px,5vw,40px); width:200px; height:30px; }
 #static { display:block; font-size:16px; width:80px; height:40px; }
 #grid   { display:grid; grid-template-columns:[a] 100px [b] 100px; width:260px; height:70px; }
 @media (max-width:600px){ #grid { grid-template-columns:[a] 1fr; } }
 #cqwrap { container-type: inline-size; }   /* block: inline size tracks the viewport */
 #cq     { font-size:18px; width:120px; height:25px; }
 @container (max-width:300px){ #cq { font-size:9px; } }
</style>
<div id=known>k</div><div id=fluid>f</div><div id=static>s</div><div id=grid>g</div>
<div id=cqwrap><div id=cq>c</div></div>"""

_SIZE = {"known": (300.0, 50.0), "fluid": (200.0, 30.0),
         "static": (80.0, 40.0), "grid": (260.0, 70.0), "cq": (120.0, 25.0)}
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
    sk = json.loads((Path(bundle_dir) / "skeleton.json").read_text())
    nodes = sk.get("nodes") or []

    # On-disk regression locks: backendNodeId is the INTERNAL join key and must NEVER
    # reach disk; the responsive carrier sidecar is internal too. The per-node
    # `responsive` field IS expected (that's the feature).
    assert "_node_responsive" not in sk, \
        "GATE FAIL: internal carrier _node_responsive leaked to disk"
    assert "_node_backend" not in sk, \
        "GATE FAIL: internal join-key sidecar _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), \
        "GATE FAIL: per-node backendNodeId leaked to disk"

    known = _node_by_size(nodes, _SIZE["known"])
    assert known is not None and known.get("responsive"), \
        "GATE FAIL: #known has no responsive delta"
    d400 = known["responsive"].get("400", {})
    assert d400.get("display") == "block", \
        f"GATE FAIL: #known @400 display delta wrong: {d400}"
    assert d400.get("flex-direction") == "column", \
        f"GATE FAIL: #known @400 flex-direction delta wrong: {d400}"
    assert d400.get("font-size") == "12px", \
        f"GATE FAIL: #known @400 font-size delta wrong: {d400}"
    assert "1200" not in known["responsive"], \
        "GATE FAIL: base width 1200 must not appear as a delta label"

    fluid = _node_by_size(nodes, _SIZE["fluid"])
    assert fluid is not None and fluid.get("responsive", {}).get("400"), \
        "GATE FAIL: #fluid clamp() font-size did not re-resolve at 400"
    # clamp(10px,5vw,40px): 5vw of 400 = 20px (within range)
    assert fluid["responsive"]["400"].get("font-size") == "20px", \
        f"GATE FAIL: #fluid @400 clamp font-size wrong: {fluid['responsive']['400']}"

    static = _node_by_size(nodes, _SIZE["static"])
    assert static is not None, "GATE FAIL: #static node missing"
    assert not static.get("responsive"), \
        f"GATE FAIL: #static got a spurious responsive delta (isolation): {static.get('responsive')}"

    grid = _node_by_size(nodes, _SIZE["grid"])
    assert grid is not None and grid.get("responsive", {}).get("400"), \
        "GATE FAIL: #grid grid-template-columns did not delta at 400"
    assert "grid-template-columns" in grid["responsive"]["400"], \
        f"GATE FAIL: #grid @400 missing grid-template-columns: {grid['responsive']['400']}"

    # @container (viewport-tracking): #cq re-evals ONLY at 280 (container ~280 < 300),
    # NOT at 400 (container ~400 > 300). Proves viewport-tracking @container rides free
    # (design §6 / probe R7) AND per-width isolation, in one node.
    cq = _node_by_size(nodes, _SIZE["cq"])
    assert cq is not None and cq.get("responsive", {}).get("280"), \
        "GATE FAIL: #cq viewport-tracking @container did not re-eval at 280"
    assert cq["responsive"]["280"].get("font-size") == "9px", \
        f"GATE FAIL: #cq @280 @container font-size wrong: {cq['responsive']['280']}"
    assert "400" not in cq.get("responsive", {}), \
        "GATE FAIL: #cq must NOT delta at 400 (container ~400 > 300; @container not fired)"

    print("GATE PASS: responsive join correct (#known carries the right narrow-width "
          "display/flex-direction/font-size reflow delta; #fluid clamp font-size "
          "re-resolved to 20px@400; #grid grid-template-columns delta flowed through the "
          "firewall; #cq viewport-tracking @container fired ONLY at 280; #static isolated "
          "— no delta); backendNodeId never on disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "responsive" / "_bundle"
    sk_json = ROOT / "fixtures" / "responsive" / "_sk.json"
    tok_json = ROOT / "fixtures" / "responsive" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--breakpoints", "1200,400,280", "--out", str(sk_json)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print("web_skeleton FAILED:\n", r.stdout, r.stderr)
        sys.exit(1)

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "bundle_writer.py"),
         "--skeleton", str(sk_json), "--tokens", str(tok_json), "--out", str(out)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=90,
    )
    if r.returncode != 0:
        print("bundle_writer FAILED (content leak?):\n", r.stdout, r.stderr)
        sys.exit(1)

    _check(out)


if __name__ == "__main__":
    main()
