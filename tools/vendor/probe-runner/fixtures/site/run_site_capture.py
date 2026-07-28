#!/usr/bin/env python3
"""Host CDP integration gate for multi-route site capture (G3a). Serves a synthetic
3-route mini-site from a local http.server (two real routes sharing a palette plus
one deliberately-unreachable route to force failure isolation), runs site_capture
against host Chrome, and asserts the content-free contract. NOT in the unit suite
(needs a browser). Run on host Bash with CDP reachable:

    python3 fixtures/site/run_site_capture.py --cdp-port 9222
"""
import argparse
import http.server
import json
import socketserver
import subprocess
import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"

# Two real routes share one palette; the page content is synthetic (this repo's own
# fixture markup), not third-party.
_PAGES = {
    "/": "<!doctype html><html><head><style>:root{--bg:#0b0b0b;--fg:#f5f5f5}"
         "body{background:var(--bg);color:var(--fg);font-family:system-ui}</style></head>"
         "<body><header><h1>Home</h1></header><main><p>alpha</p></main></body></html>",
    "/pricing": "<!doctype html><html><head><style>:root{--bg:#0b0b0b;--fg:#f5f5f5}"
                "body{background:var(--bg);color:var(--fg);font-family:system-ui}</style></head>"
                "<body><header><h1>Pricing</h1></header><main><p>beta</p></main></body></html>",
}


class _Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = _PAGES.get(self.path)
        if body is None:
            self.send_response(404)
            self.end_headers()
            return
        b = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", dest="cdp_port", type=int, default=9222)
    args = ap.parse_args()

    httpd = socketserver.TCPServer(("127.0.0.1", 0), _Handler)
    port = httpd.server_address[1]
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    try:
        base = "http://127.0.0.1:%d" % port
        # r00, r01 = real routes; r02 = a no-host URL. An unreachable PORT is no good:
        # Chrome renders a connection-refused interstitial (a real DOM), so web_skeleton
        # captures it ok. "http://" has no host to navigate to, so web_skeleton's navigate
        # hard-fails (exit 2) -> deterministic skeleton_failed, exercising route isolation.
        urls = [base + "/", base + "/pricing", "http://"]
        out = Path(__file__).resolve().parent / "_out"
        if out.exists():
            import shutil
            shutil.rmtree(out)

        r = subprocess.run(
            [sys.executable, str(SCRIPTS / "site_capture.py"),
             "--urls", ",".join(urls), "--out", str(out),
             "--cdp-port", str(args.cdp_port)],
            cwd=str(SCRIPTS), capture_output=True, text=True)

        # Content-free: print returncode only, never subprocess stderr.
        if r.returncode != 0:
            print("FAIL: site_capture exited rc=%d" % r.returncode)
            return 1

        site = json.loads((out / "site.json").read_text())
        ok = True

        if site.get("schema") != "probe-runner/site-manifest@1":
            print("FAIL: bad schema"); ok = False
        if site.get("route_count") != 3:
            print("FAIL: route_count != 3 (got %r)" % site.get("route_count")); ok = False
        if site.get("ok_count") != 2:
            print("FAIL: ok_count != 2 (got %r)" % site.get("ok_count")); ok = False

        routes = {r_["route_id"]: r_ for r_ in site.get("routes", [])}
        for rid in ("r00", "r01"):
            rr = routes.get(rid, {})
            if not rr.get("ok"):
                print("FAIL: %s not ok" % rid); ok = False
            bdir = out / "routes" / rid
            if not (bdir / "skeleton.json").exists() or not (bdir / "tokens.json").exists():
                print("FAIL: %s bundle incomplete" % rid); ok = False
            allowed = {"meta.json", "skeleton.json", "tokens.json",
                       "motion.json", "substrate.json", "assets"}
            extra = {p.name for p in bdir.iterdir()} - allowed
            if extra:
                print("FAIL: %s bundle dir has unexpected files %s (raw scratch must "
                      "not persist in the audited tree)" % (rid, sorted(extra))); ok = False

        r02 = routes.get("r02", {})
        if r02.get("ok") is not False or r02.get("error_kind") != "skeleton_failed":
            print("FAIL: r02 not isolated as skeleton_failed (got %r)" % r02); ok = False

        # No subprocess stderr may have reached site.json.
        if "Traceback" in (out / "site.json").read_text():
            print("FAIL: stderr/traceback leaked into site.json"); ok = False

        # site-root firewall backstop must be clean on this synthetic content.
        import importlib
        sys.path.insert(0, str(SCRIPTS))
        cf = importlib.import_module("content_firewall")
        viol = cf.audit_bundle(out)
        if viol:
            print("FAIL: site-root audit found %d violation(s)" % len(viol)); ok = False

        print("GATE PASS" if ok else "GATE FAIL")
        return 0 if ok else 1
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
