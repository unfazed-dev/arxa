# fixtures/settle/run_settle.py
"""Host gate for §C9 P3-G1 adaptive settle. Offline, deterministic.

Serves two pages and runs web_skeleton against each:
  /build  a shell that PROGRESSIVELY builds its DOM over ~3s (network-driven
          batches) with a long-lived /stream open -> proves the settle WAITS the
          build out and captures the built DOM (the win vs the old flat 2.0s,
          which would have snapshotted the early shell).
  /fast   full content immediately, no stream -> proves a quiet page settles
          quickly (no latency regression vs the old 2.0s).
"""
from __future__ import annotations
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"

BUILD = """<!doctype html><html lang=en><head><meta charset=utf-8>
<title>build</title><style>html,body{margin:0}.row{height:40px}</style></head>
<body><div id=root><p>shell</p></div><script>
fetch('/stream').catch(function(){});           // long-lived: in-flight floors at 1
var batch=0;
(function step(){
  if(batch>=6)return;                            // 6 batches over ~3s
  fetch('/chunk?b='+batch).then(function(){      // network churn during build
    var f=document.createDocumentFragment();
    for(var i=0;i<100;i++){var d=document.createElement('div');
      d.className='row';d.textContent='b'+batch+'-'+i;f.appendChild(d);}
    document.getElementById('root').appendChild(f);
    batch++; setTimeout(step,500);
  });
})();
</script></body></html>"""

FAST = ("<!doctype html><html lang=en><head><meta charset=utf-8><title>fast</title>"
        "</head><body>" + "".join("<p>row%d</p>" % i for i in range(120)) +
        "</body></html>")


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        if self.path.startswith("/build"):
            self._send(BUILD.encode(), "text/html; charset=utf-8")
        elif self.path.startswith("/fast"):
            self._send(FAST.encode(), "text/html; charset=utf-8")
        elif self.path.startswith("/chunk"):
            self._send(b"{}", "application/json")
        elif self.path.startswith("/stream"):
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.end_headers()
            try:
                time.sleep(40.0)                  # never finishes within the gate
            except Exception:
                pass
        else:
            self.send_response(404); self.end_headers()
    def _send(self, body, ct):
        self.send_response(200)
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def capture(url, max_wait):
    out = Path("/tmp/p3g1_skel.json")
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", url, "--out", str(out), "--max-wait", str(max_wait)],
        capture_output=True, text=True, cwd=str(SCRIPTS))
    if r.returncode != 0:
        raise SystemExit("web_skeleton failed: " + r.stderr[-800:])
    return json.loads(out.read_text())


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"

    build = capture(base + "/build", max_wait=10.0)
    fast = capture(base + "/fast", max_wait=10.0)
    srv.shutdown()

    bs, bn = build.get("settle", {}), len(build.get("nodes", []))
    fs, fn = fast.get("settle", {}), len(fast.get("nodes", []))
    print("BUILD:", {"nodes": bn, "settle": bs})
    print("FAST :", {"nodes": fn, "settle": fs})

    ok = True
    # progressive build was waited out + captured (not the early shell)
    if not (bn > 100 and bs.get("settled") is True and 2500 <= bs.get("waited_ms", 0) <= 9500):
        print("FAIL: build not waited out / not settled in band"); ok = False
    # fast page settled quickly -> no latency regression vs old flat 2.0s
    if not (fn > 50 and fs.get("settled") is True and fs.get("waited_ms", 99999) < 2000):
        print("FAIL: fast page did not settle quickly"); ok = False

    print("GATE", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
