#!/usr/bin/env python3
"""PROBE (throwaway): what is the EXACT serialized shape of a computed cursor/background-image
url() value, both as Chrome returns it and after json.dumps (the on-disk skeleton.json form)?
Decides the firewall url() regex (quoted? escaped-quote? absolute?). Host CDP."""
from __future__ import annotations
import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
from _web_eval import add_transport_args, resolve_web_eval  # noqa: E402

_PAGE = """<!doctype html><meta charset=utf-8><title>url-shape</title>
<style>
 #x { cursor: url(https://example.com/path/c.cur), auto;
      background-image: url(https://example.com/img/i.png); }
 #y { cursor: url("https://example.com/q/c2.cur"), pointer; }
</style>
<div id=x>x</div><div id=y>y</div>"""


def _serve(b):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{srv.server_address[1]}/", srv


def main():
    p = argparse.ArgumentParser()
    add_transport_args(p)
    args = p.parse_args()
    base_url, _ = _serve(_PAGE.encode())
    args.url = base_url
    if args.browser == "auto":
        args.browser = "chrome"
    engine, ev, device = resolve_web_eval(args)
    try:
        if not hasattr(ev, "sess"):
            print("ABORT: no CDP"); return 1
        ev.sess.send("Page.enable", {})
        ev.sess.send("Runtime.enable", {})
        ev.sess.send("Page.navigate", {"url": base_url})
        import time
        time.sleep(1.0)
        js = ("JSON.stringify({"
              "x_cursor: getComputedStyle(document.getElementById('x')).cursor,"
              "x_bg: getComputedStyle(document.getElementById('x')).backgroundImage,"
              "y_cursor: getComputedStyle(document.getElementById('y')).cursor})")
        r = ev.sess.send("Runtime.evaluate", {"expression": js, "returnByValue": True})
        vals = json.loads(r["result"]["value"])
        for k, v in vals.items():
            print(f"{k}:")
            print(f"    raw computed (repr): {v!r}")
            print(f"    json.dumps (on-disk text): {json.dumps(v)}")
        return 0
    finally:
        ev.close()


if __name__ == "__main__":
    raise SystemExit(main())
