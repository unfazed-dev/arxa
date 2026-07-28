#!/usr/bin/env python3
"""Host gate: G6 occluding-overlay detection + content-blind Escape dismiss, BOTH cases.

Deterministic, offline. Serves two synthetic pages over 127.0.0.1, each with a
full-bleed position:fixed high-z overlay on a normal page behind it:
  /dismissable — the overlay removes itself on an Escape keydown  -> expect cleared:true
  /sticky      — the overlay ignores Escape (no listener)         -> expect cleared:false
Runs web_states against each (CDP, host Chrome) and asserts the `consent` State.

Why both: Escape clears few real consent walls; the honest output for those is
cleared:false. A gate that only tested /dismissable would fake coverage. This pins
the honest-ceiling direction (mirrors fixtures/settle/run_settle.py's pattern and
P3-G1's shell-trap unit pin)."""
from __future__ import annotations
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WEB_STATES = ROOT / "scripts" / "web_states.py"

# A normal page (>=120 boxes so the page-behind is real), plus a full-bleed
# position:fixed z:99999 overlay. The DISMISSABLE variant wires an Escape handler
# that removes the overlay; the STICKY variant has no handler.
_PAGE = """<!doctype html><meta charset=utf-8><title>g6</title>
<style>#ov{{position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,.6)}}
.box{{height:8px}}</style>
<body>
{boxes}
<div id=ov></div>
<script>{script}</script>
</body>"""

_BOXES = "".join("<p class=box>%d</p>" % i for i in range(150))
_DISMISS_SCRIPT = ("document.addEventListener('keydown', e => {"
                   " if (e.key === 'Escape') { const o = document.getElementById('ov');"
                   " if (o) o.remove(); } });")
_STICKY_SCRIPT = "/* no Escape handler: this overlay ignores Escape */"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        script = _DISMISS_SCRIPT if self.path.startswith("/dismissable") else _STICKY_SCRIPT
        body = _PAGE.format(boxes=_BOXES, script=script).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run(url):
    """Run web_states against url, return the parsed states.json object."""
    out = ROOT / "fixtures" / "consent" / "_out.json"
    r = subprocess.run(
        [sys.executable, str(WEB_STATES), "--url", url, "--out", str(out)],
        cwd=str(ROOT / "scripts"), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("web_states FAILED:\n", r.stdout, r.stderr)
        return None
    return json.loads(out.read_text())


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"

    ok = True

    dis = _run(base + "/dismissable")
    if not dis:
        ok = False
    else:
        c = dis.get("consent")
        print("dismissable consent:", json.dumps(c))
        if not c or c.get("kind") != "occluding_overlay":
            print("GATE FAIL: dismissable — no occluding_overlay detected"); ok = False
        elif c.get("coverage", 0) < 0.5 or (c.get("z") or 0) <= 0:
            print("GATE FAIL: dismissable — overlay geometry below threshold"); ok = False
        elif c.get("cleared") is not True:
            print("GATE FAIL: dismissable — Escape did not clear (cleared != true)"); ok = False

    stk = _run(base + "/sticky")
    if not stk:
        ok = False
    else:
        c = stk.get("consent")
        print("sticky consent:", json.dumps(c))
        if not c or c.get("kind") != "occluding_overlay":
            print("GATE FAIL: sticky — no occluding_overlay detected"); ok = False
        elif c.get("cleared") is not False:
            print("GATE FAIL: sticky — overlay should NOT clear (cleared != false)"); ok = False

    srv.shutdown()
    if ok:
        print("GATE PASS: occluding overlay detected both ways; Escape cleared the "
              "dismissable one (cleared:true) and not the sticky one (cleared:false).")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
