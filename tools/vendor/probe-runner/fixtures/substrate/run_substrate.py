#!/usr/bin/env python3
"""Host gate (G5/G9/G11 substrate honesty): fills parent.html (same-site src =
127.0.0.1:B, cross-site src = localhost:B), serves it, runs the full
web_skeleton -> web_tokens -> bundle_writer pipeline, and asserts the bundle's
substrate.json flags canvas + video + the cross-SITE iframe ONLY (same-origin and
same-site-cross-origin iframes are captured -> NOT flagged). MUST run on the host
(host Chrome CDP at :9222 / $PROBE_RUNNER_CHROME_CDP_PORT).

  python3 fixtures/substrate/run_substrate.py
"""
import http.server
import json
import os
import shutil
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPTS = os.path.join(ROOT, "scripts")
OUT = "/tmp/substrate-gate"


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
    print("web_launch:", (r.stdout or "").strip()[:120], (r.stderr or "").strip()[:120])
    time.sleep(1.5)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=SCRIPTS, timeout=120)
    print("  $", " ".join(os.path.basename(c) for c in cmd[1:3]),
          "| exit", r.returncode, "|", (r.stderr or "").strip()[-160:])
    return r


def main():
    a, b = free_port(), free_port()
    tmp = tempfile.mkdtemp(prefix="substrate-gate-")
    shutil.copy(os.path.join(HERE, "child.html"), os.path.join(tmp, "child.html"))
    tpl = open(os.path.join(HERE, "parent.html")).read()
    filled = (tpl.replace("__SAMESITE_SRC__", "http://127.0.0.1:%d/child.html" % b)
                 .replace("__XSITE_SRC__", "http://localhost:%d/child.html" % b))
    open(os.path.join(tmp, "parent.html"), "w").write(filled)
    hA, hB = serve(tmp, a), serve(tmp, b)
    print("parent port:", a, "| child port:", b)
    ensure_chrome()
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT, exist_ok=True)
    sk, tok = os.path.join(OUT, "skeleton.json"), os.path.join(OUT, "tokens.json")
    bundle = os.path.join(OUT, "bundle")
    url = "http://127.0.0.1:%d/parent.html" % a
    try:
        run([sys.executable, os.path.join(SCRIPTS, "web_skeleton.py"), "--url", url, "--out", sk])
        run([sys.executable, os.path.join(SCRIPTS, "web_tokens.py"), "--url", url, "--out", tok])
        run([sys.executable, os.path.join(SCRIPTS, "bundle_writer.py"),
             "--skeleton", sk, "--tokens", tok, "--out", bundle])
    finally:
        hA.server_close()
        hB.server_close()
        shutil.rmtree(tmp, ignore_errors=True)

    subp = os.path.join(bundle, "substrate.json")
    if not os.path.exists(subp):
        print("FAIL — no substrate.json (bundle_writer failed or firewall raised)")
        return 1
    man = json.loads(open(subp).read())
    kinds = man.get("kinds", {})
    print("substrate kinds:", kinds, "| n_regions:", man.get("n_regions"))
    # canvas (G5) + video (G9) + exactly ONE uncaptured iframe (G11, the localhost one).
    ok = (kinds.get("canvas", 0) >= 1 and kinds.get("video", 0) >= 1
          and kinds.get("iframe_uncaptured", 0) == 1)
    if ok:
        print("PASS — canvas+video flagged; cross-SITE iframe flagged; "
              "same-origin/same-site iframes NOT flagged (exactly 1 uncaptured)")
        return 0
    print("FAIL — expected canvas>=1, video>=1, iframe_uncaptured==1; got", kinds)
    return 1


if __name__ == "__main__":
    sys.exit(main())
