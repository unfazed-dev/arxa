#!/usr/bin/env python3
"""Host gate: web_skeleton --container-queries discovers fixed-width inline-size @container
query containers by computed container-type, MUTATES each container's width to swept values,
captures the per-node restyle delta, and the pipeline redacts it content-free. PROVES, in one
deterministic offline run: (1) a fixed-width container's child re-evals @container at a swept
width that crosses its threshold but NOT at one that doesn't (per-width isolation); (2) a
NESTED container's child re-evals TRANSITIVELY when its ancestor shrinks AND when swept
directly — the composite '<container>@<width>' key keeps the two distinct; (3) a
container-type:size (2D) container is SKIPPED (its child gets no delta — documented ceiling);
(4) a non-container node gets NO delta; (5) backendNodeId / the carrier sidecar never reach
disk; (6) bundle_writer.write_bundle's firewall audit passes (RAISES on leak). Runs on host
CDP."""
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

# Fixed-width containers (independent of the viewport — the case R3c misses). box-sizing
# border-box so a child's bbox is stable for identification. Sweep widths "300,180":
#   #cqi (320, thresh 250):   @300 -> 300<320 swept but 300>250 NO fire (isolation);
#                             @180 -> 180<250 #cqc fires (11px) AND nested #cqi2 (=162<200)
#                             #cqc2 fires TRANSITIVELY under #cqi@180.
#   #cqi2 (90% => 288, thresh 200): @300 clamped (300>288); @180 -> 180<200 #cqc2 fires
#                             DIRECTLY under #cqi2@180 (distinct composite key).
#   #cqs (size, 200x100):     SKIPPED entirely (container-type:size ceiling) -> #cqsc no delta.
#   #plain:                   no container, no rule -> no delta.
_PAGE = """<!doctype html><meta charset=utf-8><title>cq-gate</title>
<style>
 * { box-sizing: border-box; }
 #cqi { container-type: inline-size; width: 320px; }
 #cqc { display:block; font-size:20px; width:100px; height:30px; }
 @container (max-width:250px){ #cqc { font-size:11px; } }
 #cqi2 { container-type: inline-size; width: 90%; }
 #cqc2 { font-size:16px; width:60px; height:20px; }
 @container (max-width:200px){ #cqc2 { font-size:8px; } }
 #cqs { container-type: size; width:200px; height:100px; }
 #cqsc { font-size:14px; width:40px; height:15px; }
 @container (max-height:50px){ #cqsc { font-size:7px; } }
 #plain { width:120px; height:44px; font-size:15px; }
</style>
<div id=cqi><div id=cqc>c</div><div id=cqi2><div id=cqc2>n</div></div></div>
<div id=cqs><div id=cqsc>s</div></div>
<div id=plain>p</div>"""

_SIZE = {"cqc": (100.0, 30.0), "cqc2": (60.0, 20.0),
         "cqsc": (40.0, 15.0), "plain": (120.0, 44.0)}
_SIZE_TOL = 2.5


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

    # On-disk regression locks: the internal carrier + join key must NEVER reach disk; the
    # per-node `container` field IS expected (that's the feature).
    assert "_node_container" not in sk, "GATE FAIL: internal carrier _node_container leaked to disk"
    assert "_node_backend" not in sk, "GATE FAIL: internal join-key _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), "GATE FAIL: per-node backendNodeId leaked to disk"

    # (1) #cqc: fires ONLY at the swept width that crosses its threshold (180), NOT at 300.
    cqc = _node_by_size(nodes, _SIZE["cqc"])
    assert cqc is not None and cqc.get("container"), "GATE FAIL: #cqc has no container delta"
    labels = list(cqc["container"].keys())
    assert len(labels) == 1 and labels[0].endswith("@180"), \
        f"GATE FAIL: #cqc should fire only @180, got {labels}"
    assert cqc["container"][labels[0]].get("font-size") == "11px", \
        f"GATE FAIL: #cqc @180 font-size wrong: {cqc['container'][labels[0]]}"

    # (2) #cqc2 (nested): TWO labels, both @180 (transitive via #cqi, direct via #cqi2),
    # distinct container node_ids -> composite key keeps them apart.
    cqc2 = _node_by_size(nodes, _SIZE["cqc2"])
    assert cqc2 is not None and cqc2.get("container"), "GATE FAIL: #cqc2 has no container delta"
    labs2 = list(cqc2["container"].keys())
    assert len(labs2) == 2, f"GATE FAIL: #cqc2 expected 2 composite labels (transitive+direct), got {labs2}"
    assert all(l.endswith("@180") for l in labs2), f"GATE FAIL: #cqc2 labels not both @180: {labs2}"
    assert len({l.split("@")[0] for l in labs2}) == 2, \
        f"GATE FAIL: #cqc2 two labels must have DISTINCT container ids: {labs2}"
    assert all(v.get("font-size") == "8px" for v in cqc2["container"].values()), \
        f"GATE FAIL: #cqc2 font-size delta wrong: {cqc2['container']}"

    # (3) #cqsc: parent is container-type:size -> SKIPPED -> no delta.
    cqsc = _node_by_size(nodes, _SIZE["cqsc"])
    assert cqsc is not None, "GATE FAIL: #cqsc node missing"
    assert not cqsc.get("container"), \
        f"GATE FAIL: #cqsc must have NO delta (size container skipped): {cqsc.get('container')}"

    # (4) #plain: no container, no rule -> isolation.
    plain = _node_by_size(nodes, _SIZE["plain"])
    assert plain is not None, "GATE FAIL: #plain node missing"
    assert not plain.get("container"), \
        f"GATE FAIL: #plain got a spurious container delta: {plain.get('container')}"

    print("GATE PASS: fixed-width @container join correct (#cqc fired ONLY @180 not @300; "
          "#cqc2 carries TWO distinct composite labels — transitive + direct nested re-eval; "
          "#cqs size-container SKIPPED; #plain isolated); backendNodeId never on disk; "
          "bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "container-query" / "_bundle"
    sk_json = ROOT / "fixtures" / "container-query" / "_sk.json"
    tok_json = ROOT / "fixtures" / "container-query" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--container-queries", "300,180", "--out", str(sk_json)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        print("web_skeleton FAILED:\n", r.stdout, r.stderr)
        sys.exit(1)

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "bundle_writer.py"),
         "--skeleton", str(sk_json), "--tokens", str(tok_json), "--out", str(out)],
        cwd=str(SCRIPTS), capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        print("bundle_writer FAILED (content leak?):\n", r.stdout, r.stderr)
        sys.exit(1)

    _check(out)


if __name__ == "__main__":
    main()
