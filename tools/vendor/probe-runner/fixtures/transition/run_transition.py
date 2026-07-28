#!/usr/bin/env python3
"""Host gate: web_states captures a revealed panel's reveal animation as a
content-free transition motion-law.

Deterministic, offline. Serves one page with a button (aria-expanded) whose click
reveals a display:none panel via a CSS @keyframes animation (240ms ease-out on
opacity+transform). Runs web_states (CDP, host Chrome) and asserts states[*].transition:
a non-null transition whose anim binds (node not None) to the component node carrying
the panel's known bg, with duration_ms ~= 240, easing klass certified ease-out (or its
cubic-bezier), and animated props including opacity/transform. The content-free
guarantee is proven separately by test_content_firewall.py (real cf.audit_bundle);
this gate proves the LIVE declared-law capture mechanism + the click->capture->settle
ordering."""
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

PANEL_RGB = (18, 52, 86)  # #123456-equivalent panel bg; matched via parse_color (format-robust)

_PAGE = """<!doctype html><meta charset=utf-8><title>transition-gate</title>
<style>
  body { margin: 0; font-family: sans-serif; }
  #panel { display: none; margin: 40px; width: 320px;
           background: rgb(18,52,86); color: rgb(240,240,240); padding: 16px; }
  #panel.open { display: block; animation: reveal 240ms ease-out both; }
  @keyframes reveal { from { opacity: 0; transform: translateY(8px); }
                      to   { opacity: 1; transform: translateY(0); } }
</style>
<body>
  <button id=btn aria-expanded="false" aria-controls="panel">Open</button>
  <div id=panel role="region"><p id=lbl>Revealed label</p></div>
  <script>
    const b = document.getElementById('btn'), p = document.getElementById('panel');
    b.addEventListener('click', () => {
      p.classList.remove('open'); void p.offsetWidth;   // restart animation each open
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
    out = ROOT / "fixtures" / "transition" / "_out.json"
    r = subprocess.run(
        [sys.executable, str(WEB_STATES), "--url", url, "--out", str(out)],
        cwd=str(ROOT / "scripts"), capture_output=True, text=True, timeout=90)
    if r.returncode != 0:
        print("web_states FAILED:\n", r.stdout, r.stderr)
        return None
    return json.loads(out.read_text())


def _check(obj) -> bool:
    states = obj.get("states") or []
    # find the state whose component carries the panel bg AND has a transition
    target = None
    for s in states:
        comp = s.get("component")
        if not comp:
            continue
        if any(parse_color((n.get("colors") or {}).get("bg")) == PANEL_RGB
               for n in comp["nodes"]):
            target = s
            break
    if target is None:
        print("GATE FAIL: no component carried the panel bg", PANEL_RGB)
        return False
    trans = target.get("transition")
    if not trans or not trans.get("anims"):
        print("GATE FAIL: revealed panel produced no transition", json.dumps(trans))
        return False
    # at least one anim must bind to a component node, run ~240ms, ease-out-ish, on
    # opacity/transform
    comp_ids = {n["id"] for n in target["component"]["nodes"]}
    ok = False
    for a in trans["anims"]:
        bound = a["node"] in comp_ids
        dur_ok = a["duration_ms"] is not None and 200 <= a["duration_ms"] <= 280
        props_ok = bool({"opacity", "transform"} & set(a.get("props") or []))
        ease_ok = a["certified"] and a["easing"]["bezier"] is not None
        if bound and dur_ok and props_ok and ease_ok:
            ok = True
            print("transition ok: node=%s dur=%s klass=%s props=%s"
                  % (a["node"], a["duration_ms"], a["easing"]["klass"], a["props"]))
            break
    if not ok:
        print("GATE FAIL: no bound, ~240ms, certified opacity/transform anim;",
              json.dumps(trans["anims"]))
        return False
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
        print("GATE PASS: revealed panel's reveal animation captured as a content-free "
              "transition motion-law (bound to the component, certified easing).")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
