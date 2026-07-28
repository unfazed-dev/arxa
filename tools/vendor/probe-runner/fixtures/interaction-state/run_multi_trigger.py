#!/usr/bin/env python3
"""Host harness: verify web_states' PER-TRIGGER re-baseline (the cross-attribution
fix). Two affordances; trigger A opens a ONE-WAY panel that stays open. With a
single shared REST baseline (the old bug) B's diff would re-count A's leaked-open
nodes; with per-trigger re-baselining B reports ONLY its own reveals.

Asserts: 2 states; A revealed >=3; B revealed <=4 (B alone, NOT A's ~4 + B's ~3).
MUST run on the host (host Chrome CDP at :9222 / $PROBE_RUNNER_CHROME_CDP_PORT).

  python3 fixtures/interaction-state/run_multi_trigger.py
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
    outp = os.path.join(OUT, "multi.json")
    if os.path.exists(outp):
        os.remove(outp)
    url = "http://127.0.0.1:%d/multi-trigger.html" % port
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
    counts = [s.get("n_appeared", 0) for s in states]
    print("triggers_found:", st.get("triggers_found"), "| states:", len(states),
          "| n_appeared per state:", counts)
    if len(states) != 2:
        print("FAIL — expected exactly 2 driven triggers, got", len(states))
        return 1
    a_n, b_n = states[0]["n_appeared"], states[1]["n_appeared"]
    # A reveals panelA + 3 items (~4); B alone reveals panelB + 2 items (~3). If the
    # baseline were shared (bug), B would re-count A's ~4 -> ~7. The <=4 bound is the
    # decisive cross-attribution check; >=3 on A confirms A genuinely opened.
    if a_n >= 3 and b_n <= 4:
        print("PASS — per-trigger re-baseline holds: B (%d) excludes A's leaked-open nodes" % b_n)
        return 0
    print("FAIL — cross-attribution: A=%d B=%d (B should be <=4; >4 means B re-counted A)" % (a_n, b_n))
    return 1


if __name__ == "__main__":
    sys.exit(main())
