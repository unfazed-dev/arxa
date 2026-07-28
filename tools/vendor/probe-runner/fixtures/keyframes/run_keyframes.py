#!/usr/bin/env python3
"""Host gate: web_skeleton --keyframes captures per-node CSS @keyframes timelines via
CSS.getMatchedStylesForNode (authored path), and the pipeline redacts them content-free.
PROVES: an INFINITE anim (#spin) + a multi-stop anim (#pulse) are captured with correct
offsets/props; a FINISHED fill:none one-shot (#oneshot, absent from getAnimations) IS
captured (the authored-path coverage win, probe PR2); a NOT-YET-STARTED long-delay anim
(#delayed) IS captured; a node with NO animation (#static) gets NO keyframes field
(isolation); and the @keyframes NAME ('spin'/'pulse') NEVER reaches disk. Deterministic,
offline (local server). bundle_writer.write_bundle runs the firewall audit and RAISES on
leak."""
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

# Fixed px sizes so nodes are identifiable by bbox. #oneshot finishes (~0.3s, fill:none)
# and #delayed never starts (5s delay) within the capture window — both MUST still be
# captured because cssKeyframesRules is keyed off the computed animation-name (set in
# every play state), unlike getAnimations.
_PAGE = """<!doctype html><meta charset=utf-8><title>kf-gate</title>
<style>
 /* translate-based transforms: an axis-aligned move leaves the rendered w/h unchanged, so
    each animating node stays identifiable by its authored bbox even mid-animation (a
    rotate/scale would grow the AABB non-deterministically and defeat _node_by_size).
    Capture itself is shape-agnostic — it records whatever transform the @keyframes drive. */
 @keyframes spin { from { transform: translateX(0);} to { transform: translateX(60px);} }
 @keyframes pulse { 0% { opacity:1; transform:translateX(0);} 50% { opacity:.4; transform:translateX(20px);} 100% { opacity:1; transform:translateX(0);} }
 #spin    { animation: spin 2s linear infinite; width:40px; height:40px; }
 #pulse   { animation: pulse 3s ease-in-out infinite; width:50px; height:50px; }
 #oneshot { animation: spin 0.3s linear 1; width:20px; height:20px; }
 #delayed { animation: spin 2s linear 5s 1; width:30px; height:30px; }
 #static  { width:80px; height:40px; }
</style>
<div id=spin></div><div id=pulse></div><div id=oneshot></div>
<div id=delayed></div><div id=static></div>"""

_SIZE = {"spin": (40.0, 40.0), "pulse": (50.0, 50.0), "oneshot": (20.0, 20.0),
         "delayed": (30.0, 30.0), "static": (80.0, 40.0)}
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


def _offsets(kf_entry):
    return [round(fr.get("offset"), 3) for fr in kf_entry["frames"]]


def _check(bundle_dir):
    raw = (Path(bundle_dir) / "skeleton.json").read_text()
    sk = json.loads(raw)
    nodes = sk.get("nodes") or []

    assert "_node_keyframes" not in sk, "GATE FAIL: internal carrier _node_keyframes leaked to disk"
    assert "_node_backend" not in sk, "GATE FAIL: internal join-key _node_backend leaked to disk"
    assert all("backend" not in n for n in nodes), "GATE FAIL: per-node backendNodeId leaked to disk"
    # the @keyframes author NAME must never reach disk (the core content-free invariant).
    assert "spin" not in raw and "pulse" not in raw, \
        "GATE FAIL: @keyframes author name leaked into the on-disk skeleton"

    spin = _node_by_size(nodes, _SIZE["spin"])
    assert spin is not None and spin.get("keyframes"), "GATE FAIL: #spin has no keyframes"
    a = spin["keyframes"][0]
    assert _offsets(a) == [0.0, 1.0], f"GATE FAIL: #spin offsets wrong: {_offsets(a)}"
    assert "transform" in a["frames"][0]["props"], f"GATE FAIL: #spin missing transform: {a['frames'][0]}"
    assert a["timing"]["iterations"] == "infinite", f"GATE FAIL: #spin iterations wrong: {a['timing']}"

    pulse = _node_by_size(nodes, _SIZE["pulse"])
    assert pulse is not None and pulse.get("keyframes"), "GATE FAIL: #pulse has no keyframes"
    pa = pulse["keyframes"][0]
    assert _offsets(pa) == [0.0, 0.5, 1.0], f"GATE FAIL: #pulse offsets wrong: {_offsets(pa)}"
    assert "opacity" in pa["frames"][1]["props"], f"GATE FAIL: #pulse @50% missing opacity: {pa['frames'][1]}"

    oneshot = _node_by_size(nodes, _SIZE["oneshot"])
    assert oneshot is not None and oneshot.get("keyframes"), \
        "GATE FAIL: #oneshot (finished fill:none) not captured — authored-path coverage broken (probe PR2)"

    delayed = _node_by_size(nodes, _SIZE["delayed"])
    assert delayed is not None and delayed.get("keyframes"), \
        "GATE FAIL: #delayed (not-yet-started) not captured — authored-path coverage broken"

    static = _node_by_size(nodes, _SIZE["static"])
    assert static is not None, "GATE FAIL: #static node missing"
    assert not static.get("keyframes"), \
        f"GATE FAIL: #static got a spurious keyframes field (isolation): {static.get('keyframes')}"

    print("GATE PASS: keyframes capture correct (#spin offsets [0,1]+transform+infinite; "
          "#pulse offsets [0,0.5,1]+opacity; #oneshot finished one-shot CAPTURED; #delayed "
          "not-started CAPTURED; #static isolated — no field); @keyframes name never on "
          "disk; backendNodeId never on disk; bundle audit CLEAN")


def main():
    base_url, _srv = _serve(_PAGE.encode())
    out = ROOT / "fixtures" / "keyframes" / "_bundle"
    sk_json = ROOT / "fixtures" / "keyframes" / "_sk.json"
    tok_json = ROOT / "fixtures" / "keyframes" / "_tokens.json"
    tok_json.write_text(json.dumps({"palette": {}}))

    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", base_url, "--keyframes", "--out", str(sk_json)],
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
