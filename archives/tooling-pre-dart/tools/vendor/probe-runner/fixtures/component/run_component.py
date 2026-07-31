#!/usr/bin/env python3
"""Host gate: web_states captures a revealed panel as a reproducible component.

Deterministic, offline. Serves one page with a button (aria-expanded) whose
click reveals a hidden styled panel (known background color + a text child). Runs
web_states (CDP, host Chrome) and asserts states[*].component: the revealed
subtree is re-rooted (parent links resolve to valid component-local ids or null),
the panel's known bg color is carried (parsed -> spacing/format robust), n_nodes
matches len(nodes), and a root records a mount. The content-free guarantee is
proven separately by test_content_firewall.py (real cf.audit_bundle); this gate
proves the LIVE capture mechanism."""
from __future__ import annotations
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WEB_STATES = ROOT / "scripts" / "web_states.py"
sys.path.insert(0, str(ROOT / "scripts"))
from web_tokens import parse_color  # noqa: E402

PANEL_RGB = (18, 52, 86)  # #123456 — distinctive; matched via parse_color (format-robust)

# A button with aria-expanded=false (a drivable disclosure trigger) reveals a
# styled panel containing a label + an item. The panel is display:none at REST
# (genuinely revealed by the click, not present at baseline). The marker color
# #123456 lives on the .item LEAF div (explicit size + bg -> certain to survive
# classify); the role=region wrapper may not be emitted as a distinct node, so the
# gate must not depend on it carrying the marker.
_PAGE = """<!doctype html><meta charset=utf-8><title>component-gate</title>
<style>
  body { margin: 0; font-family: sans-serif; }
  #panel { display: none; margin: 40px; width: 320px;
           background: rgb(33,33,40); color: rgb(240,240,240); padding: 16px; }
  #panel.open { display: block; }
  .item { height: 48px; background: #123456; margin-top: 12px; }   /* marker on a sized leaf */
</style>
<body>
  <button id=btn aria-expanded="false" aria-controls="panel">Open</button>
  <div id=panel role="region">
    <p id=lbl>Revealed label</p>
    <div class=item></div>
  </div>
  <script>
    const b = document.getElementById('btn'), p = document.getElementById('panel');
    b.addEventListener('click', () => {
      const open = p.classList.toggle('open');
      b.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  </script>
</body>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        body = _PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run(url):
    out = ROOT / "fixtures" / "component" / "_out.json"
    r = subprocess.run(
        [sys.executable, str(WEB_STATES), "--url", url, "--out", str(out)],
        cwd=str(ROOT / "scripts"), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("web_states FAILED:\n", r.stdout, r.stderr)
        return None
    return json.loads(out.read_text())


def _check(obj) -> bool:
    states = obj.get("states") or []
    comps = [s["component"] for s in states if s.get("component")]
    print("states:", len(states), "components:", len(comps))
    if not comps:
        print("GATE FAIL: no state produced a component (panel not revealed?)")
        return False
    # the component that carries the panel's known bg (parse_color -> format-robust)
    target = None
    for c in comps:
        if any(parse_color((n.get("colors") or {}).get("bg")) == PANEL_RGB for n in c["nodes"]):
            target = c
            break
    if target is None:
        print("GATE FAIL: no component carried the panel bg", PANEL_RGB)
        return False
    n_ids = {n["id"] for n in target["nodes"]}
    for n in target["nodes"]:
        if n["parent"] is not None and n["parent"] not in n_ids:
            print("GATE FAIL: dangling parent id", n["parent"], "not in", n_ids)
            return False
    if not any(n["parent"] is None and n.get("mount") for n in target["nodes"]):
        print("GATE FAIL: no root records a mount point")
        return False
    if target["n_nodes"] != len(target["nodes"]):
        print("GATE FAIL: n_nodes != len(nodes)")
        return False
    print("component ok: n_nodes=%d, carried bg=%s, parents resolve, root mounted"
          % (target["n_nodes"], PANEL_RGB))
    return True


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"

    obj = _run(base + "/")
    ok = bool(obj) and _check(obj)

    srv.shutdown()
    if ok:
        print("GATE PASS: revealed panel captured as a reproducible component "
              "(structure + colors + mount), parents resolve.")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
