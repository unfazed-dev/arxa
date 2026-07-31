#!/usr/bin/env python3
"""LIVE smoke (NOT a pytest; manual, headless real-site). §C9-R-CRAWL-BUILD route-expander.

Runs site_capture --crawl against a real cohort site and prints the manifest's content-free
counts (route_count, ok_count, crawl stats). NOTHING but counts is printed; no URLs, no hrefs.
Mirrors derisk_crawl_yield.py. Run: python3 scripts/crawl_expander_smoke.py
(needs Chrome). This is the human de-risk gate before declaring the feature validated; it
never runs in CI."""
from __future__ import annotations
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
from _web import chrome_binary  # noqa: E402

# One cohort seed set (4 routes, mirrors the de-risk COHORT).
SEED_URLS = [
    "https://www.djangoproject.com/",
    "https://www.djangoproject.com/start/",
    "https://www.djangoproject.com/download/",
    "https://www.djangoproject.com/weblog/",
]


def _launch(udd):
    bin_ = chrome_binary()
    if not bin_:
        print("FATAL no-chrome"); sys.exit(2)
    p = subprocess.Popen(
        [bin_, "--headless=new", "--remote-debugging-port=0", "--remote-allow-origins=*",
         "--no-first-run", "--no-default-browser-check", "--user-data-dir=" + udd, "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pf = Path(udd) / "DevToolsActivePort"
    for _ in range(100):
        if pf.exists():
            t = pf.read_text().splitlines()
            if t:
                return p, int(t[0])
        time.sleep(0.1)
    p.terminate(); print("FATAL no-port"); sys.exit(2)


def main():
    print("§C9-R-CRAWL-BUILD route-expander LIVE smoke | --crawl --crawl-max 40 T=0.5 F=20")
    udd = tempfile.mkdtemp()
    out = tempfile.mkdtemp()
    proc = None
    try:
        proc, port = _launch(udd)
        r = subprocess.run(
            [sys.executable, "site_capture.py", "--urls", ",".join(SEED_URLS),
             "--out", out, "--cdp-port", str(port), "--crawl",
             "--crawl-max", "40", "--crawl-delay", "2.0"],
            cwd=str(SCRIPTS), capture_output=True, text=True)
        if r.returncode != 0:
            print("FAIL site_capture rc=%d" % r.returncode); return 1
        payload = json.loads(r.stdout)
        print("route_count:", payload.get("route_count"))
        print("ok_count:", payload.get("ok_count"))
        print("crawl:", json.dumps(payload.get("crawl", {}), sort_keys=True))
        print("PASS" if payload.get("ok") else "FAIL")
        return 0
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait()
        shutil.rmtree(udd, ignore_errors=True)
        shutil.rmtree(out, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
