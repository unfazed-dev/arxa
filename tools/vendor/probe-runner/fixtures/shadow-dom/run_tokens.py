#!/usr/bin/env python3
"""Host harness: prove web_tokens captures design tokens that live INSIDE an
open Web-Component shadow root (G10). Serves a deterministic fixture whose
shadow root carries #123456 / radius 13 / size 29 — none in the light DOM — and
asserts they appear in tokens.json. MUST run on the host (host Chrome CDP at
:9222 / $PROBE_RUNNER_CHROME_CDP_PORT; the ctx sandbox cannot reach it).

  python3 fixtures/shadow-dom/run_tokens.py
"""
import http.server
import json
import os
import socket
import socketserver
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPTS = os.path.join(ROOT, "scripts")
OUT = "/tmp/shadow-dom"
os.makedirs(OUT, exist_ok=True)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def serve(directory, port):
    handler = lambda *a, **k: http.server.SimpleHTTPRequestHandler(*a, directory=directory, **k)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def ensure_chrome():
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, "web_launch.py")],
                       capture_output=True, text=True)
    print("web_launch:", r.stdout.strip()[:160], r.stderr.strip()[:160])
    time.sleep(1.5)


def main():
    port = free_port()
    httpd = serve(HERE, port)
    print("serving", HERE, "on", port)
    ensure_chrome()
    outp = os.path.join(OUT, "tokens.json")
    if os.path.exists(outp):
        os.remove(outp)
    url = "http://127.0.0.1:%d/component.html" % port
    try:
        r = subprocess.run(
            [sys.executable, os.path.join(SCRIPTS, "web_tokens.py"),
             "--url", url, "--out", outp],
            capture_output=True, text=True, cwd=SCRIPTS, timeout=90)
    except subprocess.TimeoutExpired:
        print("FAIL — web_tokens timed out")
        httpd.server_close()
        return 1
    finally:
        httpd.server_close()
    print("exit:", r.returncode, "| stderr:", (r.stderr or "").strip()[-200:])
    if not os.path.exists(outp):
        print("FAIL — no tokens.json written")
        return 1
    with open(outp) as fh:
        tok = json.load(fh)
    palette = set((tok.get("palette") or {}).values())
    radii = tok.get("radii") or []
    sizes = tok.get("type_scale") or []
    print("palette:", sorted(v for v in palette if v), "| radii:", radii, "| type_scale:", sizes)
    ok = ("#123456" in palette) and (13 in radii) and (29 in sizes)
    if ok:
        print("PASS — shadow-root tokens captured (#123456 / radius 13 / size 29)")
        return 0
    print("FAIL — shadow tokens missing: ",
          {"#123456": "#123456" in palette, "radius13": 13 in radii, "size29": 29 in sizes})
    return 1


if __name__ == "__main__":
    sys.exit(main())
