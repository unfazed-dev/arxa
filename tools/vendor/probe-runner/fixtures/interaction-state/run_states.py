#!/usr/bin/env python3
"""Host harness: prove web_states recovers structure revealed only by a non-URL
interaction (G4). Serves a click-to-reveal fixture (3 boxes hidden at REST) and
asserts web_states reports a state whose n_appeared >= 3. MUST run on the host
(host Chrome CDP at :9222 / $PROBE_RUNNER_CHROME_CDP_PORT).

  python3 fixtures/interaction-state/run_states.py
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
OUT = "/tmp/interaction-state"
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
    outp = os.path.join(OUT, "states.json")
    if os.path.exists(outp):
        os.remove(outp)
    url = "http://127.0.0.1:%d/disclosure.html" % port
    try:
        r = subprocess.run(
            [sys.executable, os.path.join(SCRIPTS, "web_states.py"),
             "--url", url, "--out", outp],
            capture_output=True, text=True, cwd=SCRIPTS, timeout=120)
    except subprocess.TimeoutExpired:
        print("FAIL — web_states timed out")
        httpd.server_close()
        return 1
    finally:
        httpd.server_close()
    print("exit:", r.returncode, "| stderr:", (r.stderr or "").strip()[-200:])
    if not os.path.exists(outp):
        print("FAIL — no states.json written")
        return 1
    with open(outp) as fh:
        st = json.load(fh)
    states = st.get("states", [])
    best = max((s.get("n_appeared", 0) for s in states), default=0)
    print("states:", len(states), "| max n_appeared:", best,
          "| triggers:", [s["trigger"]["kind"] for s in states])
    if states and best >= 3:
        print("PASS — interaction revealed >=3 nodes (G4)")
        return 0
    print("FAIL — no state revealed the hidden panel (expected n_appeared >= 3)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
