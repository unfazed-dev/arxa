#!/usr/bin/env python3
"""Feasibility spike: is a reveal animation observable in getAnimations() over the
ev() transport, and at what post-click delay? Serves a page whose button reveals a
display:none panel via a CSS @keyframes animation (animation runs from display:none
-> block, unlike an opacity transition which won't). Navigates, clicks, then probes
getAnimations() at several delays, printing per-delay: count, durations, the overall
getTiming().easing, and per-keyframe easings. Go/no-go before building the core.

Run on host Bash (CDP needs host Chrome): python fixtures/transition/spike_getanimations.py
"""
from __future__ import annotations
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from _web_eval import resolve_web_eval, navigate, add_transport_args  # noqa: E402

_PAGE = """<!doctype html><meta charset=utf-8><title>transition-spike</title>
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
      // force reflow so the animation restarts each open
      p.classList.remove('open'); void p.offsetWidth;
      const open = p.classList.toggle('open');
      b.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  </script>
</body>"""

_CLICK = "(() => { const el = document.querySelector('#btn'); if(!el) return false; el.click(); return true; })()"
_RESET = "(() => { const p = document.querySelector('#panel'); p.classList.remove('open'); return true; })()"
_PROBE = r"""
(() => document.getAnimations().map(a => {
  const e = a.effect, t = e && e.getTiming ? e.getTiming() : {};
  const kfs = (e && e.getKeyframes) ? e.getKeyframes() : [];
  return {duration: t.duration, delay: t.delay, easing: t.easing,
          iterations: Number.isFinite(t.iterations) ? t.iterations : null,
          kfEasings: kfs.map(k => k.easing).filter(Boolean),
          props: [...new Set(kfs.flatMap(k => Object.keys(k).filter(
                   p => !['offset','easing','composite','computedOffset'].includes(p))))],
          playState: a.playState};
}))()
"""


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


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{port}/"

    p = argparse.ArgumentParser()
    add_transport_args(p)
    args = p.parse_args(["--url", url])
    engine, ev, device = resolve_web_eval(args)
    try:
        observed = False
        for delay in (0.016, 0.05, 0.1, 0.2):
            navigate(ev, engine, url)
            ev.ev(_RESET)
            ev.ev(_CLICK)
            time.sleep(delay)
            rows = ev.ev(_PROBE) or []
            print(f"\n=== delay {int(delay*1000)}ms: {len(rows)} animation(s) ===")
            print(json.dumps(rows, indent=2))
            if rows:
                observed = True
    finally:
        ev.close()
        srv.shutdown()
    if observed:
        print("\nSPIKE PASS: reveal animation observable; pick _LIVE_WINDOW = smallest "
              "delay with a non-empty, running row carrying the easing.")
        return 0
    print("\nSPIKE FAIL: no animation observed at any delay — re-evaluate mechanism.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
