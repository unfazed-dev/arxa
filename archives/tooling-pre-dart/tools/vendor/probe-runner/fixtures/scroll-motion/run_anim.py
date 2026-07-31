#!/usr/bin/env python3
"""Measurement harness: run web_anim against the scroll-motion fixtures.

Answers the empirical question the §C canary never measured: does web_anim
already recover scroll-driven (GSAP-class) motion, and on which mechanisms does
it fail? MUST run on the host (host Chrome CDP at :9222 / $PROBE_RUNNER_CHROME_CDP_PORT;
the ctx sandbox cannot reach it).

  python3 fixtures/scroll-motion/run_anim.py

Prints a compact verdict per fixture: discovered movers, certified channels,
exit status, and the verb's note. No network — fixtures are served from disk.
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
OUT = "/tmp/scroll-motion"
os.makedirs(OUT, exist_ok=True)

FIXTURES = ["native-scrub.html", "multiseg-scrub.html", "band-localized.html",
            "late-build.html", "virtual-scroll.html", "multi-band.html"]

# Measured current behavior (2026-05-30). Flip values as a task lands.
EXPECT = {
    "native-scrub.html":  "GREEN",   # baseline; must never regress
    "multiseg-scrub.html": "GREEN",  # Task 2-3: segmentation certifies both linear runs
    "band-localized.html": "GREEN",  # Task 4: adaptive 2nd sweep certifies the band
    "late-build.html":     "GREEN",  # Task 1: readiness wait settles scrollHeight
    "virtual-scroll.html": "RED",    # G7a DEFERRED: stays RED through all of P0
    "multi-band.html":     "GREEN",  # P1 Task2: concentrate_bands gives each band its own budget (5/6 certify)
}


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    # NOTE: brief bind-race window after close() — acceptable for this local
    # single-run research harness; switch to TCPServer(("127.0.0.1", 0)) if CI-gated.
    s.close()
    return p


def serve(directory, port):
    handler = lambda *a, **k: http.server.SimpleHTTPRequestHandler(*a, directory=directory, **k)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    httpd.allow_reuse_address = True
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return httpd


def ensure_chrome():
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, "web_launch.py")],
                       capture_output=True, text=True)
    print("web_launch:", r.stdout.strip()[:200], r.stderr.strip()[:200])
    time.sleep(1.5)


def run_anim(url, name):
    outp = os.path.join(OUT, name + ".json")
    if os.path.exists(outp):
        os.remove(outp)
    try:
        r = subprocess.run(
            [sys.executable, os.path.join(SCRIPTS, "web_anim.py"),
             "--url", url, "--steps", "24", "--out", outp],
            capture_output=True, text=True, cwd=SCRIPTS, timeout=120)
    except subprocess.TimeoutExpired as exc:
        so = exc.stdout or ""
        se = (exc.stderr or "") + "\nTimeoutExpired: web_anim exceeded 120 s"
        return 1, so, se, None
    data = None
    if os.path.exists(outp):
        try:
            with open(outp) as fh:
                data = json.load(fh)
        except Exception:
            data = None
    return r.returncode, r.stdout, r.stderr, data


def _channel_certified(e):
    """A channel counts as certified if entry["certified"] is True OR
    (entry.get("segments") is truthy and every segment has certified True)."""
    if e.get("certified"):
        return True
    segs = e.get("segments")
    if segs:
        return all(s.get("certified") for s in segs)
    return False


def summarize(name, rc, so, se, data):
    """Print a verdict summary and RETURN one of 'GREEN'|'AMBER'|'RED'."""
    print("\n========== %s ==========" % name)
    print("exit:", rc)
    if data is None:
        # die() path: no --out written. Show the error line.
        err = (se or so).strip().splitlines()
        print("NO OUTPUT JSON. last err line:", err[-1] if err else "(none)")
        print("VERDICT: RED — verb bailed before measuring")
        return "RED"
    movers = data.get("movers", [])
    note = data.get("note")
    n_cert = 0
    cert_detail = []
    for m in movers:
        for ch, e in (m.get("channels") or {}).items():
            if _channel_certified(e):
                n_cert += 1
                cert_detail.append("%s/%s ease=%s amp=%s rms=%s" % (
                    m.get("sel"), ch, (e.get("easing") or {}).get("name") if isinstance(e.get("easing"), dict) else e.get("easing"),
                    e.get("range") or e.get("amp"), e.get("rms")))
    print("scrollRange:", data.get("scrollRange"), "steps:", data.get("steps"))
    print("movers discovered:", len(movers), "| certified channels:", n_cert)
    if note:
        print("note:", note)
    for c in cert_detail[:8]:
        print("   CERT", c)
    if movers and n_cert == 0:
        print("VERDICT: AMBER — mover found, NOTHING certified")
        return "AMBER"
    elif n_cert > 0:
        print("VERDICT: GREEN — scroll motion certified")
        return "GREEN"
    else:
        print("VERDICT: RED — no movers discovered")
        return "RED"


def main():
    port = free_port()
    httpd = serve(HERE, port)
    print("serving", HERE, "on", port)
    ensure_chrome()
    results = {}
    verdicts = {}
    try:
        for f in FIXTURES:
            url = "http://127.0.0.1:%d/%s" % (port, f)
            rc, so, se, data = run_anim(url, f.replace(".html", ""))
            verdict = summarize(f, rc, so, se, data)
            verdicts[f] = verdict
            results[f] = {"exit": rc, "verdict": verdict,
                          "movers": len((data or {}).get("movers", [])),
                          "note": (data or {}).get("note")}
    finally:
        # The serve thread is daemon=True, so it is reaped at process exit. Do NOT
        # call httpd.shutdown() here: it blocks until serve_forever() returns, which
        # a foreground Chrome's kept-alive connection to this server can stall
        # indefinitely (single-threaded TCPServer). Just close the listening socket.
        httpd.server_close()
    with open(os.path.join(OUT, "summary.json"), "w") as fh:
        json.dump(results, fh, indent=2)
    print("\nsummary ->", os.path.join(OUT, "summary.json"))
    bad = {f: "%s (want %s)" % (verdicts[f], EXPECT[f]) for f in FIXTURES if verdicts.get(f) != EXPECT[f]}
    if bad:
        print("\nFAIL — verdict mismatch:", json.dumps(bad, indent=2))
        return 1
    print("\nPASS — all fixtures matched expected verdicts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
