#!/usr/bin/env python3
"""Host gate: the navigation-commit race CANNOT settle on a stale document.

Why this exists (final review, 2026-05-30): `navigate()` does an async
`location.assign` on a REUSED, already-loaded tab, then the adaptive settle polls
immediately. A reviewer flagged a plausible race — the first reads could observe
the OLD document (readyState complete, quiet, stable) and settle on the wrong page
if the new doc's TTFB exceeds min_floor (500ms). `run_settle.py` (local, ~0ms TTFB)
structurally cannot catch this. This gate can.

Empirically the settle is SAFE: CDP `Runtime.evaluate` BLOCKS through the
navigation-commit window and returns only the NEW document's context, so the old
doc is never read post-assign; min_floor + the readyState gate are belt-and-
suspenders. This gate PINS that — so a future regression (lowering MIN_FLOOR below
commit latency, dropping the readyState-complete gate) is caught.

Method: seed the reused tab with a LOW-node page (8 nodes, stable+quiet+complete —
the worst case for racing, window.__doc='seed'), then `location.assign` to /slow
(server sleeps 1.2s before the first byte, window.__doc='slow'). Tight-poll the
timeline; FAIL if the OLD seed doc is ever readable as readyState=complete in the
500-1150ms TTFB window (that is the race). Offline, deterministic.
"""
from __future__ import annotations
import json, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from _web import chrome_running, chrome_launch, cdp_target  # noqa: E402
from _web_eval import _CDPEval  # noqa: E402

SEED = ("<!doctype html><meta charset=utf-8><title>seed</title>"
        "<script>window.__doc='seed'</script><body><p>seed</p></body>")
SLOW = ("<!doctype html><meta charset=utf-8><title>slow</title>"
        "<script>window.__doc='slow'</script><body>"
        + "".join("<p>n%d</p>" % i for i in range(300)) + "</body>")


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        if self.path.startswith("/slow"):
            time.sleep(1.2)                       # TTFB > min_floor (500ms)
            body = SLOW.encode()
        else:
            body = SEED.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


READ = ("JSON.stringify({rs:document.readyState,"
        "doc:(typeof window.__doc==='undefined'?null:window.__doc),"
        "n:document.getElementsByTagName('*').length})")


def main() -> int:
    if not chrome_running():
        chrome_launch(); time.sleep(1.0)
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"

    ev = _CDPEval(cdp_target()["webSocketDebuggerUrl"])
    ev.ev("location.assign(%s)" % json.dumps(base + "/seed"))
    time.sleep(1.0)
    print("seeded:", ev.ev(READ))

    t0 = time.monotonic()
    ev.ev("location.assign(%s)" % json.dumps(base + "/slow"))
    rows = []
    while time.monotonic() - t0 < 2.6:
        try:
            r = json.loads(ev.ev(READ))
        except Exception as e:
            r = {"err": str(e)[:40]}
        rows.append((round((time.monotonic() - t0) * 1000), r))
        time.sleep(0.05)
    ev.close(); srv.shutdown()

    window = [(t, r) for t, r in rows if 500 <= t <= 1150 and "err" not in r]
    race_reads = [(t, r) for t, r in window
                  if r.get("rs") == "complete" and r.get("doc") == "seed"]
    saw_new = any(r.get("doc") == "slow" and r.get("n", 0) >= 250
                  for t, r in rows if "err" not in r)

    print("first readable post-assign read:",
          next(((t, r) for t, r in rows if "err" not in r), None))
    if race_reads:
        t, r = race_reads[0]
        print(f"GATE FAIL: race window read at t={t}ms — OLD seed doc was "
              f"readyState=complete, n={r['n']}, past min_floor. Settle could land "
              f"on the stale document.")
        return 1
    if not saw_new:
        print("GATE FAIL: never observed the new 300-node /slow doc (probe broken?).")
        return 1
    rs_seen = sorted({r["rs"] for t, r in window})
    print(f"no stale-doc read in the 500-1150ms TTFB window (readyState seen: {rs_seen}); "
          f"new doc observed. GATE PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
